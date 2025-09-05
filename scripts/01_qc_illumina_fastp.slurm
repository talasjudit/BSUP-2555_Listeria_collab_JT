#!/bin/bash -e
#SBATCH -p qib-short
#SBATCH --mem 16G
#SBATCH -c 6
#SBATCH --job-name=qc-illumina-fastp

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

# Parse sample information (6 fields: biosample,nanopore_srr,nanopore_path,illumina_srr,illumina_r1_path,illumina_r2_path)
IFS=',' read -r current_sample nanopore_srr nanopore_path illumina_srr illumina_r1_path illumina_r2_path <<< "${sample_line}"

echo "Processing sample: ${current_sample}"
echo "Illumina SRR: ${illumina_srr}"

# Use full paths from samplesheet
r1_path="${illumina_r1_path}"
r2_path="${illumina_r2_path}"

echo "R1 path: ${r1_path}"
echo "R2 path: ${r2_path}"

# Verify input files exist
if [[ ! -f "${r1_path}" ]]; then
    echo "ERROR: Cannot find R1 file: ${r1_path}"
    exit 1
fi

if [[ ! -f "${r2_path}" ]]; then
    echo "ERROR: Cannot find R2 file: ${r2_path}"
    exit 1
fi

# Create output directory using config variables
output_dir="${work_dir}/${output_name}/01_qc_illumina"
mkdir -p ${output_dir}
tool_log_dir="${log_dir}/fastp"
mkdir -p ${tool_log_dir}

# Set up singularity binding for input files
input_dir_R1=$(dirname "${r1_path}")
input_dir_R2=$(dirname "${r2_path}")

if [[ "$input_dir_R1" == "$input_dir_R2" ]]; then
    input_bind_args="--bind ${input_dir_R1}:${input_dir_R1}"
else
    input_bind_args="--bind ${input_dir_R1}:${input_dir_R1} --bind ${input_dir_R2}:${input_dir_R2}"
fi

singularity_image="${singularity_dir}/fastp-1.0.1.sif"

singularity exec \
    --bind ${work_dir}:${work_dir} \
    ${input_bind_args} \
    ${singularity_image} \
    fastp \
        -i ${r1_path} \
        -I ${r2_path} \
        -o ${output_dir}/${current_sample}_R1_trimmed.fastq.gz \
        -O ${output_dir}/${current_sample}_R2_trimmed.fastq.gz \
        --detect_adapter_for_pe \
        --correction \
        --qualified_quality_phred 20 \
        --thread ${SLURM_CPUS_PER_TASK} \
        --json ${tool_log_dir}/${current_sample}.json \
        --html ${tool_log_dir}/${current_sample}.html

echo "Fastp completed for ${current_sample}"