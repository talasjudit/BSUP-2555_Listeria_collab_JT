#!/bin/bash -e
#SBATCH -p qib-medium
#SBATCH --mem 16G
#SBATCH -c 8
#SBATCH --time 12:00:00
#SBATCH --job-name=polish-medaka

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

# Find required inputs
flye_assembly="${work_dir}/${output_name}/05_assembly_flye/${current_sample}_flye.fasta"
nanopore_reads="${work_dir}/${output_name}/04_qc_nanopore_filtlong/${current_sample}_filtlong.fastq.gz"

# Verify inputs exist
if [[ ! -f "${flye_assembly}" ]]; then
    echo "ERROR: Cannot find Flye assembly for sample ${current_sample}: ${flye_assembly}"
    echo "Please run 05_assembly_flye.slurm first"
    exit 1
fi

if [[ ! -f "${nanopore_reads}" ]]; then
    echo "ERROR: Cannot find nanopore reads for sample ${current_sample}: ${nanopore_reads}"
    echo "Please run the nanopore QC steps (porechop + filtlong) first"
    exit 1
fi

echo "Flye assembly: ${flye_assembly}"
echo "Nanopore reads: ${nanopore_reads}"

# Create output directory using config variables
output_dir="${work_dir}/${output_name}/06_polish_medaka"
mkdir -p ${output_dir}
tool_log_dir="${log_dir}/medaka"
mkdir -p ${tool_log_dir}

# Set up singularity binding for input files
assembly_dir=$(dirname "${flye_assembly}")
reads_dir=$(dirname "${nanopore_reads}")

# Create unique bind arguments
bind_dirs=("${assembly_dir}" "${reads_dir}")
unique_dirs=$(printf '%s\n' "${bind_dirs[@]}" | sort -u)
input_bind_args=""
for dir in ${unique_dirs}; do
    input_bind_args="${input_bind_args} --bind ${dir}:${dir}"
done

singularity_image="${singularity_dir}/medaka-2.1.1.sif"

# Run Medaka polishing (1 iteration - best practice)
echo "Starting Medaka polishing for ${current_sample}"
singularity exec \
    --bind ${work_dir}:${work_dir} \
    ${input_bind_args} \
    ${singularity_image} \
    medaka_consensus \
        -i ${nanopore_reads} \
        -d ${flye_assembly} \
        -o ${output_dir}/${current_sample} \
        -t ${SLURM_CPUS_PER_TASK} \
        -m auto \
        > ${tool_log_dir}/${current_sample}_medaka.log 2>&1

# Check if polishing succeeded
if [[ -f "${output_dir}/${current_sample}/consensus.fasta" ]]; then
    # Create standardized output name for downstream tools
    cp "${output_dir}/${current_sample}/consensus.fasta" "${output_dir}/${current_sample}_medaka.fasta"
    echo "Medaka polishing completed successfully for ${current_sample}"
    echo "Polished assembly: ${output_dir}/${current_sample}_medaka.fasta"
else
    echo "ERROR: Medaka polishing failed for ${current_sample} - no consensus.fasta found"
    exit 1
fi