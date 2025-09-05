#!/bin/bash -e
#SBATCH -p qib-short
#SBATCH --mem 16G
#SBATCH -c 6
#SBATCH --job-name=qc-multiqc

source ./config.conf

# Create output directory
output_dir="${work_dir}/${output_name}/02_qc_multiqc"
mkdir -p ${output_dir}

singularity_image="${singularity_dir}/multiqc-1.31.sif"

echo "Running MultiQC on FastP reports"
echo "Input directory: ${log_dir}/fastp"
echo "Output directory: ${output_dir}"

# Run multiqc
singularity exec \
    --bind ${work_dir}:${work_dir} \
    ${singularity_image} \
    multiqc \
        -o ${output_dir} \
        ${log_dir}/fastp

echo "MultiQC completed"