#!/bin/bash -e
#SBATCH -p qib-medium
#SBATCH --mem 32G
#SBATCH -c 12
#SBATCH --time 24:00:00
#SBATCH --job-name=assembly-unicycler

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

# Find Illumina reads (required for both modes)
illumina_r1="${work_dir}/${output_name}/01_qc_illumina/${current_sample}_R1_trimmed.fastq.gz"
illumina_r2="${work_dir}/${output_name}/01_qc_illumina/${current_sample}_R2_trimmed.fastq.gz"

if [[ ! -f "${illumina_r1}" ]] || [[ ! -f "${illumina_r2}" ]]; then
    echo "ERROR: Cannot find Illumina reads for sample ${current_sample}"
    echo "R1: ${illumina_r1}"
    echo "R2: ${illumina_r2}"
    echo "Please run 01_qc_illumina_fastp.slurm first"
    exit 1
fi

echo "Illumina R1: ${illumina_r1}"
echo "Illumina R2: ${illumina_r2}"

# Determine assembly mode and find inputs
unicycler_args="-1 ${illumina_r1} -2 ${illumina_r2}"

# Check for existing Flye assembly first
flye_assembly="${work_dir}/${output_name}/05_assembly_flye/${current_sample}_flye.fasta"
nanopore_input="${work_dir}/${output_name}/04_qc_nanopore_filtlong/${current_sample}_filtlong.fastq.gz"

if [[ -f "${flye_assembly}" ]] && [[ -f "${nanopore_input}" ]]; then
    # Hybrid mode with existing assembly - requires BOTH assembly AND reads
    unicycler_args="${unicycler_args} -l ${nanopore_input} --existing_long_read_assembly ${flye_assembly}"
    assembly_mode="hybrid with existing long-read assembly (flye)"
    echo "Using Flye assembly: ${flye_assembly}"
    echo "Using nanopore reads: ${nanopore_input}"
elif [[ -f "${nanopore_input}" ]]; then
    # Standard hybrid mode with nanopore reads only
    unicycler_args="${unicycler_args} -l ${nanopore_input}"
    assembly_mode="standard hybrid assembly"
    echo "Using nanopore reads for hybrid assembly: ${nanopore_input}"
else
    echo "ERROR: Cannot find nanopore reads for sample ${current_sample}: ${nanopore_input}"
    echo "Please run 04_qc_nanopore_filtlong.slurm first"
    exit 1
fi

echo "Assembly mode: ${assembly_mode}"

# Create output directory using config variables
output_dir="${work_dir}/${output_name}/06_assembly_unicycler"
mkdir -p ${output_dir}
tool_log_dir="${log_dir}/unicycler"
mkdir -p ${tool_log_dir}

# Set up singularity binding for input directories
bind_dirs=()
bind_dirs+=("$(dirname "${illumina_r1}")")
bind_dirs+=("$(dirname "${nanopore_input}")")

if [[ "${assembly_mode}" == "hybrid with existing long-read assembly (flye)" ]]; then
    bind_dirs+=("$(dirname "${flye_assembly}")")
fi

# Create unique bind arguments
unique_dirs=$(printf '%s\n' "${bind_dirs[@]}" | sort -u)
input_bind_args=""
for dir in ${unique_dirs}; do
    input_bind_args="${input_bind_args} --bind ${dir}:${dir}"
done

singularity_image="${singularity_dir}/unicycler-0.5.1.sif"

# Run Unicycler assembly
echo "Starting Unicycler assembly (${assembly_mode}) for ${current_sample}"
singularity exec \
    --bind ${work_dir}:${work_dir} \
    ${input_bind_args} \
    ${singularity_image} \
    unicycler \
        ${unicycler_args} \
        -o ${output_dir}/${current_sample} \
        --threads ${SLURM_CPUS_PER_TASK} \
        --verbosity 2 \
        > ${tool_log_dir}/${current_sample}_unicycler.log 2>&1

# Check if assembly succeeded and create standardized output
if [[ -f "${output_dir}/${current_sample}/assembly.fasta" ]]; then
    # Create standardized output name for downstream tools
    cp "${output_dir}/${current_sample}/assembly.fasta" "${output_dir}/${current_sample}_unicycler.fasta"
    echo "Unicycler assembly completed successfully for ${current_sample}"
    echo "Assembly: ${output_dir}/${current_sample}_unicycler.fasta"
else
    echo "ERROR: Unicycler assembly failed for ${current_sample} - no assembly.fasta found"
    exit 1
fi