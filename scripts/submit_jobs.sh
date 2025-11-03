#!/bin/bash

usage() {
    echo "Usage: $0 <samplesheet.csv> <job_type> <slurm_script>"
    echo "  job_type: array|single"
    echo ""
    echo "Samplesheet format (CSV with header):"
    echo "  sample,nanopore_run,illumina_run"
    echo "  SAMN28229381,SRR19183897,SRR19183925"
    echo ""
    echo "Array jobs process each sample individually:"
    echo "  $0 samplesheet.csv array 01_qc_illumina_fastp.slurm"
    echo ""
    echo "Single jobs process all samples together:"
    echo "  $0 samplesheet.csv single 02_qc_multiqc.slurm"
    exit 1
}

if [[ $# -ne 3 ]]; then
    usage
fi

SAMPLESHEET="$1"
JOB_TYPE="$2"
SLURM_SCRIPT="$3"

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
    
    # Check header
    local header=$(head -n1 "$samplesheet")
    if [[ "$header" != "biosample,nanopore_srr,nanopore_path,illumina_srr,illumina_r1_path,illumina_r2_path" ]]; then
        echo "ERROR: Invalid samplesheet header."
        echo "Expected: biosample,nanopore_srr,nanopore_path,illumina_srr,illumina_r1_path,illumina_r2_path"
        echo "Got: $header"
        return 1
    fi
    
    # Count valid hybrid samples
    local sample_count=0
    local line_num=1
    
    while IFS=',' read -r biosample nanopore_srr nanopore_path illumina_srr illumina_r1_path illumina_r2_path; do
        ((line_num++))
        
        # Validate required fields are present
        if [[ -z "$biosample" || -z "$nanopore_srr" || -z "$illumina_srr" ]]; then
            echo "ERROR: Line $line_num missing required fields"
            return 1
        fi
        
        # Check for spaces in biosample names
        if [[ "$biosample" =~ [[:space:]] ]]; then
            echo "ERROR: Line $line_num biosample contains spaces: '$biosample'"
            echo "Please use underscores or hyphens instead"
            return 1
        fi
        
        ((sample_count++))
    done < <(tail -n+2 "$samplesheet")
    
    echo "$sample_count"
    return 0
}

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
            echo "ERROR: No valid hybrid samples found in samplesheet"
            echo "Each sample must have both nanopore_run and illumina_run"
            exit 1
        fi
        
        echo "Submitting array job: $script_name"
        echo "Processing $SAMPLE_COUNT hybrid samples"
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
        
    *)
        echo "ERROR: Invalid job_type. Use: array|single"
        exit 1
        ;;
esac