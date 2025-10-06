#!/bin/bash -e
#SBATCH -p qib-medium
#SBATCH --mem 32G
#SBATCH -c 12
#SBATCH --time 24:00:00
#SBATCH --job-name=assembly-flye

source ./config.conf

if [[ -z "$SAMPLESHEET_FILE" ]]; then
    echo "ERROR: Must be run via submit_jobs.sh with SAMPLESHEET_FILE"
    exit 1
fi

if [[ ! -f "$SAMPLESHEET_FILE" ]]; then
    echo "ERROR: Samplesheet file not found: $SAMPLESHEET_FILE"
    exit 1
fi

# Get sample information from samplesheet (skip header, so +2)
sample_line=$(sed -n "$((SLURM_ARRAY_TASK_ID + 2))p" "$SAMPLESHEET_FILE")

if [[ -z "$sample_line" ]]; then
    echo "ERROR: No sample at index $SLURM_ARRAY_TASK_ID"
    exit 1
fi

# Parse sample information  (6 fields)
IFS=',' read -r current_sample nanopore_srr nanopore_path illumina_srr illumina_r1_path illumina_r2_path <<< "${sample_line}"

echo "Processing sample: ${current_sample}"

# Find nanopore input file (from filtlong output)
nanopore_input="${work_dir}/${output_name}/04_qc_nanopore_filtlong/${current_sample}_filtlong.fastq.gz"

if [[ ! -f "${nanopore_input}" ]]; then
    echo "ERROR: Cannot find filtlong output for sample ${current_sample}: ${nanopore_input}"
    echo "Please run the nanopore QC steps (porechop + filtlong) first"
    exit 1
fi

echo "Nanopore input: ${nanopore_input}"

# Create output directory using config variables
output_dir="${work_dir}/${output_name}/05_assembly_flye"
mkdir -p ${output_dir}
tool_log_dir="${log_dir}/flye"
mkdir -p ${tool_log_dir}

# Set up singularity binding
input_dir=$(dirname "${nanopore_input}")
input_bind_args="--bind ${input_dir}:${input_dir}"

singularity_image="${singularity_dir}/flye-2.9.6.sif"

# Run Flye assembly
echo "Starting Flye assembly for ${current_sample}"
singularity exec \
    --bind ${work_dir}:${work_dir} \
    ${input_bind_args} \
    ${singularity_image} \
    flye \
        --nano-hq ${nanopore_input} \
        --out-dir ${output_dir}/${current_sample} \
        --threads ${SLURM_CPUS_PER_TASK} \
        --genome-size ${genome_size} \
        --meta \
        > ${tool_log_dir}/${current_sample}_flye.log 2>&1

# Check if assembly succeeded
if [[ -f "${output_dir}/${current_sample}/assembly.fasta" ]]; then
    # Create standardized output name for downstream tools
    cp "${output_dir}/${current_sample}/assembly.fasta" "${output_dir}/${current_sample}_flye.fasta"
    echo "Flye assembly completed successfully for ${current_sample}"
    echo "Assembly: ${output_dir}/${current_sample}_flye.fasta"
else
    echo "ERROR: Flye assembly failed for ${current_sample} - no assembly.fasta found"
    exit 1
fi