#!/bin/bash -e
#SBATCH -p qib-short
#SBATCH --mem 8G
#SBATCH -c 4
#SBATCH --time 2:00:00
#SBATCH --job-name=qc-quast

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

# Parse sample information (4 fields: sample,nanopore_path,illumina_r1_path,illumina_r2_path)
IFS=',' read -r current_sample nanopore_path illumina_r1_path illumina_r2_path <<< "${sample_line}"

# Remove any trailing carriage returns
current_sample=$(echo "$current_sample" | tr -d '\r')

echo "Processing sample: ${current_sample}"

# Find assembly files - prioritize Unicycler, then Flye
unicycler_assembly="${work_dir}/${output_name}/06_assembly_unicycler/${current_sample}_unicycler.fasta"
flye_assembly="${work_dir}/${output_name}/05_assembly_flye/${current_sample}_flye.fasta"

if [[ -f "${unicycler_assembly}" ]]; then
    input_assembly="${unicycler_assembly}"
    assembly_type="unicycler"
    echo "Using Unicycler assembly: ${input_assembly}"
elif [[ -f "${flye_assembly}" ]]; then
    input_assembly="${flye_assembly}"
    assembly_type="flye"
    echo "Using Flye assembly: ${input_assembly}"
else
    echo "ERROR: No assembly found for sample ${current_sample}"
    echo "Checked: ${unicycler_assembly}"
    echo "Checked: ${flye_assembly}"
    echo "Please run at least one assembly step first"
    exit 1
fi

# Create output directory using config variables
output_dir="${work_dir}/${output_name}/08_qc_quast"
mkdir -p ${output_dir}
tool_log_dir="${log_dir}/quast"
mkdir -p ${tool_log_dir}

# Set up singularity binding
assembly_dir=$(dirname "${input_assembly}")
input_bind_args="--bind ${assembly_dir}:${assembly_dir}"

singularity_image="${singularity_dir}/quast-5.3.0.sif"

# Run QUAST
echo "Starting QUAST analysis for ${current_sample} (${assembly_type} assembly)"
singularity exec \
    --bind ${work_dir}:${work_dir} \
    ${input_bind_args} \
    ${singularity_image} \
    quast.py \
        ${input_assembly} \
        --output-dir ${output_dir}/${current_sample} \
        --threads ${SLURM_CPUS_PER_TASK} \
        --min-contig 500 \
        > ${tool_log_dir}/${current_sample}_quast.log 2>&1

# Check if QUAST succeeded
if [[ -f "${output_dir}/${current_sample}/report.tsv" ]]; then
    # Create a simplified summary with sample name and assembly type
    echo -e "sample\tassembly_type\t$(head -n1 ${output_dir}/${current_sample}/transposed_report.tsv | cut -f2-)" > ${output_dir}/${current_sample}_quast_summary.tsv
    tail -n+2 ${output_dir}/${current_sample}/transposed_report.tsv | \
        sed "s/^/${current_sample}\t${assembly_type}\t/" >> ${output_dir}/${current_sample}_quast_summary.tsv
    
    echo "QUAST analysis completed successfully for ${current_sample}"
    echo "Results: ${output_dir}/${current_sample}_quast_summary.tsv"
    echo "Full report: ${output_dir}/${current_sample}/report.html"
else
    echo "ERROR: QUAST analysis failed for ${current_sample} - no report.tsv found"
    exit 1
fi