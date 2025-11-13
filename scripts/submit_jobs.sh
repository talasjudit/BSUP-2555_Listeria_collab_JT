#!/bin/bash

usage() {
    echo "Usage: $0 <samplesheet.csv> <slurm_script>"
    echo ""
    echo "Samplesheet format (CSV with header):"
    echo "  sample,nanopore_path,illumina_r1_path,illumina_r2_path"
    echo "  Sample_001,/data/nanopore/sample1.fastq.gz,/data/illumina/sample1_R1.fastq.gz,/data/illumina/sample1_R2.fastq.gz"
    echo ""
    echo "Examples:"
    echo "  $0 samplesheet.csv 01_qc_illumina_fastp.slurm"
    echo "  $0 samplesheet.csv 02_qc_illumina_multiqc.slurm"
    echo ""
    echo "Job type (array vs single) is automatically detected:"
    echo "  - Scripts containing 'multiqc' run as single jobs (aggregate all samples)"
    echo "  - All other scripts run as array jobs (one job per sample)"
    exit 1
}

if [[ $# -ne 2 ]]; then
    usage
fi

SAMPLESHEET="$1"
SLURM_SCRIPT="$2"

if [[ ! -f "$SAMPLESHEET" ]]; then
    echo "ERROR: Samplesheet not found: $SAMPLESHEET"
    exit 1
fi

if [[ ! -f "$SLURM_SCRIPT" ]]; then
    echo "ERROR: SLURM script not found: $SLURM_SCRIPT"
    exit 1
fi

# Load config and set up logging
source ./config.conf
script_name=$(basename "$SLURM_SCRIPT" .slurm)
slurm_log_dir="${log_dir}/slurm_logs/${script_name}"
mkdir -p "$slurm_log_dir"

# Validate samplesheet format
validate_samplesheet() {
    local samplesheet="$1"
    
    # Read and normalize header (remove BOM, CR, whitespace)
    local header=$(head -n1 "$samplesheet" | sed 's/^\xEF\xBB\xBF//' | tr -d '\r' | tr -d ' \t')
    
    if [[ "$header" != "sample,nanopore_path,illumina_r1_path,illumina_r2_path" ]]; then
        echo "ERROR: Invalid samplesheet header."
        echo "Expected: sample,nanopore_path,illumina_r1_path,illumina_r2_path"
        echo "Got: $header"
        return 1
    fi
    
    # Count valid samples
    local sample_count=0
    local line_num=1
    
    while IFS=',' read -r sample nanopore_path illumina_r1_path illumina_r2_path; do
        ((line_num++))
        
        # Remove any carriage returns from fields
        sample=$(echo "$sample" | tr -d '\r')
        nanopore_path=$(echo "$nanopore_path" | tr -d '\r')
        illumina_r1_path=$(echo "$illumina_r1_path" | tr -d '\r')
        illumina_r2_path=$(echo "$illumina_r2_path" | tr -d '\r')
        
        # Validate required fields are present
        if [[ -z "$sample" || -z "$nanopore_path" || -z "$illumina_r1_path" || -z "$illumina_r2_path" ]]; then
            echo "ERROR: Line $line_num has missing required fields"
            echo "Sample: '$sample', Nanopore: '$nanopore_path', R1: '$illumina_r1_path', R2: '$illumina_r2_path'"
            return 1
        fi
        
        # Check for spaces in sample names
        if [[ "$sample" =~ [[:space:]] ]]; then
            echo "ERROR: Line $line_num - sample name contains spaces: '$sample'"
            echo "Please use underscores or hyphens instead"
            return 1
        fi
        
        ((sample_count++))
    done < <(tail -n+2 "$samplesheet")
    
    if [[ $sample_count -eq 0 ]]; then
        echo "ERROR: No samples found in samplesheet"
        return 1
    fi
    
    echo "$sample_count"
    return 0
}

# Auto-detect job type based on script name
if [[ "$script_name" == *"multiqc"* ]]; then
    JOB_TYPE="single"
else
    JOB_TYPE="array"
fi

# Handle job types
case "$JOB_TYPE" in
    single)
        echo "Submitting single job: $script_name"
        echo "SLURM logs: $slurm_log_dir"
        
        sbatch \
            --output="${slurm_log_dir}/${script_name}-%j.out" \
            --error="${slurm_log_dir}/${script_name}-%j.err" \
            "$SLURM_SCRIPT"
        ;;
        
    array)
        echo "Validating samplesheet format..."
        if ! SAMPLE_COUNT=$(validate_samplesheet "$SAMPLESHEET"); then
            echo "ERROR: Samplesheet validation failed"
            exit 1
        fi
        
        if [[ $SAMPLE_COUNT -eq 0 ]]; then
            echo "ERROR: No valid samples found in samplesheet"
            exit 1
        fi
        
        echo "Submitting array job: $script_name"
        echo "Processing $SAMPLE_COUNT samples"
        echo "Samplesheet: $SAMPLESHEET" 
        echo "SLURM logs: $slurm_log_dir"
        
        # Export samplesheet for scripts to use
        export SAMPLESHEET_FILE="$(realpath "$SAMPLESHEET")"
        
        sbatch --array=0-$((SAMPLE_COUNT-1)) \
            --export=SAMPLESHEET_FILE \
            --output="${slurm_log_dir}/${script_name}-%A_%a.out" \
            --error="${slurm_log_dir}/${script_name}-%A_%a.err" \
            "$SLURM_SCRIPT"
        ;;
esac