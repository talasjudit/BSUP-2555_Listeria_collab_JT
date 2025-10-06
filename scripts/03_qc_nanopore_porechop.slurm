#!/bin/bash -e
#SBATCH -p qib-short
#SBATCH --mem 16G
#SBATCH -c 6
#SBATCH --job-name=qc-nanopore-porechop

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

# Parse sample information (6 fields)
IFS=',' read -r current_sample nanopore_srr nanopore_path illumina_srr illumina_r1_path illumina_r2_path <<< "${sample_line}"

echo "Processing sample: ${current_sample}"
echo "Nanopore SRR: ${nanopore_srr}"

# Use full path from samplesheet
nanopore_path="${nanopore_path}"

echo "Nanopore path: ${nanopore_path}"

# Verify input file exists
if [[ ! -f "${nanopore_path}" ]]; then
    echo "ERROR: Cannot find nanopore file: ${nanopore_path}"
    exit 1
fi

# Create output directory using config variables
output_dir="${work_dir}/${output_name}/03_qc_nanopore_porechop"
mkdir -p ${output_dir}
tool_log_dir="${log_dir}/porechop"
mkdir -p ${tool_log_dir}

# Set up singularity binding for input files
input_dir=$(dirname "${nanopore_path}")
input_bind_args="--bind ${input_dir}:${input_dir}"

singularity_image="${singularity_dir}/porechop-0.2.4.sif"

# Run Porechop
singularity exec \
    --bind ${work_dir}:${work_dir} \
    ${input_bind_args} \
    ${singularity_image} \
    porechop \
        -i ${nanopore_path} \
        -o ${output_dir}/${current_sample}_porechop.fastq.gz \
        --threads ${SLURM_CPUS_PER_TASK} \
        --verbosity 2 \
        > ${tool_log_dir}/${current_sample}_porechop.log 2>&1

echo "Porechop completed for ${current_sample}"