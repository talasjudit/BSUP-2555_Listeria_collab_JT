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

# Parse sample information  (6 fields)
IFS=',' read -r current_sample nanopore_srr nanopore_path illumina_srr illumina_r1_path illumina_r2_path <<< "${sample_line}"

echo "Processing sample: ${current_sample}"

# Find all available assemblies for this sample
assemblies=()
assembly_labels=()

unicycler_assembly="${work_dir}/${output_name}/06_assembly_unicycler/${current_sample}_unicycler.fasta"
flye_assembly="${work_dir}/${output_name}/05_assembly_flye/${current_sample}_flye.fasta"

if [[ -f "${unicycler_assembly}" ]]; then
    assemblies+=("${unicycler_assembly}")
    assembly_labels+=("${current_sample}_unicycler")
fi

if [[ -f "${flye_assembly}" ]]; then
    assemblies+=("${flye_assembly}")
    assembly_labels+=("${current_sample}_flye")
fi

if [[ ${#assemblies[@]} -eq 0 ]]; then
    echo "ERROR: No assemblies found for sample ${current_sample}"
    echo "Checked: ${unicycler_assembly}"
    echo "Checked: ${flye_assembly}"
    echo "Please run at least one assembly step first"
    exit 1
fi

echo "Found ${#assemblies[@]} assemblies for ${current_sample}:"
for i in "${!assemblies[@]}"; do
    echo "  ${assembly_labels[$i]}: ${assemblies[$i]}"
done

# Create output directory using config variables
output_dir="${work_dir}/${output_name}/08_qc_quast"
mkdir -p ${output_dir}
tool_log_dir="${log_dir}/quast"
mkdir -p ${tool_log_dir}

# Set up singularity binding for all input files
bind_dirs=()
for assembly in "${assemblies[@]}"; do
    bind_dirs+=("$(dirname "${assembly}")")
done

# Create unique bind arguments
unique_dirs=$(printf '%s\n' "${bind_dirs[@]}" | sort -u)
input_bind_args=""
for dir in ${unique_dirs}; do
    input_bind_args="${input_bind_args} --bind ${dir}:${dir}"
done

singularity_image="${singularity_dir}/quast-5.3.0.sif"

# Create QUAST arguments
quast_args=""
for i in "${!assemblies[@]}"; do
    quast_args="${quast_args} --label ${assembly_labels[$i]} ${assemblies[$i]}"
done

# Run QUAST
echo "Starting QUAST analysis for ${current_sample}"
singularity exec \
    --bind ${work_dir}:${work_dir} \
    ${input_bind_args} \
    ${singularity_image} \
    quast.py \
        ${quast_args} \
        --output-dir ${output_dir}/${current_sample} \
        --threads ${SLURM_CPUS_PER_TASK} \
        --min-contig 500 \
        --est-ref-size ${genome_size} \
        --bacterium \
        --plots-format png,pdf \
        --no-html \
        > ${tool_log_dir}/${current_sample}_quast.log 2>&1

# Check if QUAST succeeded
if [[ -f "${output_dir}/${current_sample}/report.tsv" ]]; then
    # Create a simplified summary with sample name
    echo -e "sample\t$(head -n1 ${output_dir}/${current_sample}/transposed_report.tsv | cut -f2-)" > ${output_dir}/${current_sample}_quast_summary.tsv
    tail -n+2 ${output_dir}/${current_sample}/transposed_report.tsv | \
        sed "s/^/${current_sample}\t/" >> ${output_dir}/${current_sample}_quast_summary.tsv
    
    echo "QUAST analysis completed successfully for ${current_sample}"
    echo "Results: ${output_dir}/${current_sample}_quast_summary.tsv"
    echo "Full report: ${output_dir}/${current_sample}/report.html"
else
    echo "ERROR: QUAST analysis failed for ${current_sample} - no report.tsv found"
    exit 1
fi