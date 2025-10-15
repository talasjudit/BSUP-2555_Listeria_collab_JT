#!/bin/bash -e
#SBATCH -p qib-short
#SBATCH --mem 16G
#SBATCH -c 6
#SBATCH --job-name=qc-nanopore-filtlong

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

# Auto-detect input file from previous porechop step
# Check for porechop_abi output first, then standard porechop
porechop_abi_input="${work_dir}/${output_name}/03_qc_nanopore_porechop_abi/${current_sample}_porechop_abi.fastq.gz"
porechop_input="${work_dir}/${output_name}/03_qc_nanopore_porechop/${current_sample}_porechop.fastq.gz"

if [[ -f "${porechop_abi_input}" ]]; then
    input_file="${porechop_abi_input}"
    echo "Using Porechop ABI output: ${input_file}"
elif [[ -f "${porechop_input}" ]]; then
    input_file="${porechop_input}"
    echo "Using standard Porechop output: ${input_file}"
else
    echo "ERROR: Cannot find porechop output for sample ${current_sample}"
    echo "Checked: ${porechop_abi_input}"
    echo "Checked: ${porechop_input}"
    exit 1
fi

# Create output directory using config variables
output_dir="${work_dir}/${output_name}/04_qc_nanopore_filtlong"
mkdir -p ${output_dir}
tool_log_dir="${log_dir}/filtlong"
mkdir -p ${tool_log_dir}

# Set up singularity binding for input files
input_dir=$(dirname "${input_file}")
input_bind_args="--bind ${input_dir}:${input_dir}"

singularity_image="${singularity_dir}/filtlong-0.3.0.sif"

# Run Filtlong with quality-based filtering
singularity exec \
    --bind ${work_dir}:${work_dir} \
    ${input_bind_args} \
    --env LC_ALL=C \
    ${singularity_image} \
    filtlong \
        --min_length 6000 \
        --keep_percent 95 \
        --verbose \
        ${input_file} \
        2> ${tool_log_dir}/${current_sample}_filtlong.log \
        | gzip > ${output_dir}/${current_sample}_filtlong.fastq.gz

echo "Filtlong completed for ${current_sample}"