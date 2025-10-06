#!/bin/bash -e
#SBATCH -p qib-medium
#SBATCH --mem 16G
#SBATCH -c 8
#SBATCH --time 6:00:00
#SBATCH --job-name=qc-checkm2

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

# Find assembly files - prioritize Unicycler, then Medaka, then Flye
unicycler_assembly="${work_dir}/${output_name}/07_assembly_unicycler/${current_sample}_unicycler.fasta"
medaka_assembly="${work_dir}/${output_name}/06_polish_medaka/${current_sample}_medaka.fasta"
flye_assembly="${work_dir}/${output_name}/05_assembly_flye/${current_sample}_flye.fasta"

if [[ -f "${unicycler_assembly}" ]]; then
    input_assembly="${unicycler_assembly}"
    assembly_type="unicycler"
    echo "Using Unicycler assembly: ${input_assembly}"
elif [[ -f "${medaka_assembly}" ]]; then
    input_assembly="${medaka_assembly}"
    assembly_type="medaka"
    echo "Using Medaka assembly: ${input_assembly}"
elif [[ -f "${flye_assembly}" ]]; then
    input_assembly="${flye_assembly}"
    assembly_type="flye"
    echo "Using Flye assembly: ${input_assembly}"
else
    echo "ERROR: No assembly found for sample ${current_sample}"
    echo "Checked: ${unicycler_assembly}"
    echo "Checked: ${medaka_assembly}"
    echo "Checked: ${flye_assembly}"
    echo "Please run at least one assembly step first"
    exit 1
fi

# Create output directory using config variables
output_dir="${work_dir}/${output_name}/08_qc_checkm2"
mkdir -p ${output_dir}
tool_log_dir="${log_dir}/checkm2"
mkdir -p ${tool_log_dir}

# Create temporary directory for this sample
temp_dir="${output_dir}/${current_sample}_temp"
mkdir -p ${temp_dir}

# Copy assembly to temp directory (CheckM2 expects input directory with fasta files)
cp ${input_assembly} ${temp_dir}/${current_sample}.fasta

# Set up singularity binding
assembly_dir=$(dirname "${input_assembly}")
input_bind_args="--bind ${assembly_dir}:${assembly_dir}"

singularity_image="${singularity_dir}/checkm2-1.1.0.sif"

# Run CheckM2
echo "Starting CheckM2 analysis for ${current_sample} (${assembly_type} assembly)"
singularity exec \
    --bind ${work_dir}:${work_dir} \
    ${input_bind_args} \
    ${singularity_image} \
    checkm2 predict \
        --threads ${SLURM_CPUS_PER_TASK} \
        --input ${temp_dir} \
        --output-directory ${output_dir}/${current_sample} \
        --extension fasta \
        --force \
        > ${tool_log_dir}/${current_sample}_checkm2.log 2>&1

# Check if CheckM2 succeeded and create summary
if [[ -f "${output_dir}/${current_sample}/quality_report.tsv" ]]; then
    # Add sample name and assembly type to the report for easier tracking
    echo -e "sample\tassembly_type\t$(head -n1 ${output_dir}/${current_sample}/quality_report.tsv)" > ${output_dir}/${current_sample}_checkm2_summary.tsv
    tail -n+2 ${output_dir}/${current_sample}/quality_report.tsv | \
        sed "s/^/${current_sample}\t${assembly_type}\t/" >> ${output_dir}/${current_sample}_checkm2_summary.tsv
    
    echo "CheckM2 analysis completed successfully for ${current_sample}"
    echo "Results: ${output_dir}/${current_sample}_checkm2_summary.tsv"
else
    echo "ERROR: CheckM2 analysis failed for ${current_sample} - no quality_report.tsv found"
    exit 1
fi

# Clean up temporary directory
rm -rf ${temp_dir}