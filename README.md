# BSUP-2555: Collaborative Listeria Hybrid Assembly Pipeline

## Table of Contents

- [Pipeline Overview](#pipeline-overview)
- [Requirements](#requirements)
- [Installation](#installation)
  - [1. Clone the repository](#1-clone-the-repository)
  - [2. Set up Singularity images](#2-set-up-singularity-images)
  - [3. Configure the pipeline](#3-configure-the-pipeline)
  - [4. Create samplesheet](#4-create-samplesheet)
- [Quick Start](#quick-start)
- [Output Structure](#output-structure)
- [Pipeline Steps](#pipeline-steps)
  - [Step 1: Illumina Read QC (fastp)](#step-1-illumina-read-qc-fastp)
  - [Step 2: Illumina QC Report (MultiQC)](#step-2-illumina-qc-report-multiqc)
  - [Step 3: Nanopore Read QC (Porechop ABI)](#step-3-nanopore-read-qc-porechop-abi)
  - [Step 4: Nanopore Read Filtering (Filtlong)](#step-4-nanopore-read-filtering-filtlong)
  - [Step 5: Long-Read Assembly (Flye)](#step-5-long-read-assembly-flye---optional)
  - [Step 6: Hybrid Assembly (Unicycler)](#step-6-hybrid-assembly-unicycler)
  - [Step 7: Assembly Completeness (CheckM2)](#step-7-assembly-completeness-checkm2)
  - [Step 8: Assembly Statistics (QUAST)](#step-8-assembly-statistics-quast)

## Pipeline overview

``` mermaid
---
config:
  theme: mc
  themeVariables:
    fontSize: 40px
    width: 100%
    height: 1200px
    secondaryColor: '#ffffff'
    tertiaryColor: '#ffffff'
    background: '#ffffff'
  background: '#ffffff'
  layout: elk
---
flowchart LR
    n3["Illumina FastQ files"] --> n7["fastp"]
    n7 --> n8["Trimmed/filtered reads"]
    n5["porechop_ABI"] --> n9["Trimmed reads"]
    n9 --> n6["filtlong"]
    n6 --> n10["Filtered reads"]
    n1["Nanopore FastQ files"] --> n5
    n11["flye"] --> n12["Long read assembly"]
    n12 --> n13["unicycler <br>(existing_long_read_assembly)"]
    n15["Skip <br>Flye?"] -- Yes --> n22["unicycler <br>(hybrid mode)"]
    n22 --> n23["Hybrid assembly"]
    n23 --> n27["checkm2"] & n28["QUAST"]
    n13 --> n23
    n27 --> n30["Assembly stat reports"]
    n28 --> n30
    n15 -- No --> n11
    n8 --> n31(["30-40X coverage checkpoint"])
    n31 --> n13
    n10 --> n32(["Minimum data checkpoint"])
    n32 --> n15
    n3@{ shape: in-out}
    n7@{ shape: proc}
    n8@{ shape: lean-r}
    n5@{ shape: proc}
    n9@{ shape: lean-r}
    n6@{ shape: proc}
    n10@{ shape: lean-r}
    n1@{ shape: in-out}
    n11@{ shape: proc}
    n12@{ shape: lean-r}
    n13@{ shape: proc}
    n15@{ shape: diam}
    n22@{ shape: proc}
    n23@{ shape: lean-r}
    n27@{ shape: proc}
    n28@{ shape: proc}
    n30@{ shape: lean-r}
     n3:::data
     n7:::process
     n8:::data
     n5:::process
     n9:::data
     n6:::process
     n10:::data
     n1:::data
     n11:::process
     n12:::data
     n13:::process
     n15:::decision
     n22:::process
     n23:::data
     n27:::process
     n28:::process
     n30:::data
     n31:::checkpoint
     n32:::Peach
     n32:::checkpoint
    classDef process fill:#bbdefb,stroke:#1976d2,color:black
    classDef data fill:#c8e6c9,stroke:#388e3c,color:black
    classDef decision fill:#d3d3d3,stroke:#666666,color:black
    classDef Peach stroke-width:1px, stroke-dasharray:none, stroke:#FBB35A, fill:#FFEFDB, color:#8F632D
    classDef checkpoint fill:#f6cf92, stroke-width:1px, stroke-dasharray: 0, color:black
```

## Requirements

- **SLURM** job scheduler
- **Singularity** (containerization)


## Installation

### 1. Clone the repository
```bash
git clone https://github.com/talasjudit/BSUP-2555_Listeria_collab_JT.git
cd BSUP-2555_Listeria_collab_JT
```
### 2. Set up Singularity images

Most images are hosted on GitHub Container Registry (ghcr.io). Unicycler is pulled from Biocontainers on Quay.io.

```bash
mkdir -p singularity/sif

singularity pull singularity/sif/fastp-1.0.1.sif oras://ghcr.io/talasjudit/bsup-2555/fastp:1.0.1-1
singularity pull singularity/sif/multiqc-1.31.sif oras://ghcr.io/talasjudit/bsup-2555/multiqc:1.31-1
singularity pull singularity/sif/porechop-0.2.4.sif oras://ghcr.io/talasjudit/bsup-2555/porechop:0.2.4-1
singularity pull singularity/sif/porechop_abi-0.5.0.sif oras://ghcr.io/talasjudit/bsup-2555/porechop_abi:0.5.0-1
singularity pull singularity/sif/filtlong-0.3.0.sif oras://ghcr.io/talasjudit/bsup-2555/filtlong:0.3.0-1
singularity pull singularity/sif/flye-2.9.6.sif oras://ghcr.io/talasjudit/bsup-2555/flye:2.9.6-1
singularity pull singularity/sif/unicycler-0.5.1.sif docker://quay.io/biocontainers/unicycler:0.5.1--py39h746d604_5
singularity pull singularity/sif/checkm2-1.1.0.sif oras://ghcr.io/talasjudit/bsup-2555/checkm2:1.1.0-1
singularity pull singularity/sif/quast-5.3.0.sif oras://ghcr.io/talasjudit/bsup-2555/quast:5.3.0-1
```

### 3. Configure the pipeline

Rename config.conf.template to config.conf and set your working directory

```bash
work_dir="/path/to/work/dir"                    # Main working directory
singularity_dir="${work_dir}/singularity/sif"   # Container location
output_name="output"                            # Output subdirectory name
log_dir="${work_dir}/logs"                      # Log files location
```

### 4. Create samplesheet

Create a CSV file named `samplesheet.csv` with the following structure:

**Header (first line - required):**
```csv
biosample,nanopore_srr,nanopore_path,illumina_srr,illumina_r1_path,illumina_r2_path
```

**Column descriptions:**
- `biosample`: Unique sample identifier - no spaces allowed
- `nanopore_srr`: Nanopore run ID (can be blank if not from SRA)
- `nanopore_path`: Full absolute path to Nanopore FASTQ file
- `illumina_srr`: Illumina run ID (can be blank if not from SRA)
- `illumina_r1_path`: Full absolute path to Illumina R1 reads
- `illumina_r2_path`: Full absolute path to Illumina R2 reads

**Example with 3 samples:**
```csv
biosample,nanopore_srr,nanopore_path,illumina_srr,illumina_r1_path,illumina_r2_path
Sample_001,SRR19183897,/data/nanopore/SRR19183897.fastq.gz,SRR19183925,/data/illumina/SRR19183925_1.fastq.gz,/data/illumina/SRR19183925_2.fastq.gz
Sample_002,SRR19183898,/data/nanopore/SRR19183898.fastq.gz,SRR19183926,/data/illumina/SRR19183926_1.fastq.gz,/data/illumina/SRR19183926_2.fastq.gz
```

## Quick Start

Please edit the names of the partitions of your system in each of the *slurm scripts (currently these are set to qib-short, or qib-medium to run on the HPC at NBI).

To run the pipeline:

```bash
# 1. Illumina QC
./submit_jobs.sh samplesheet.csv array 01_qc_illumina_fastp.slurm
./submit_jobs.sh samplesheet.csv single 02_qc_illumina_multiqc.slurm

# 2. Nanopore QC
./submit_jobs.sh samplesheet.csv array 03_qc_nanopore_porechop_abi.slurm
./submit_jobs.sh samplesheet.csv array 04_qc_nanopore_filtlong.slurm

# 3. Assembly (choose one of two options)

## Option A: Direct hybrid assembly
./submit_jobs.sh samplesheet.csv array 06_assembly_unicycler.slurm

## Option B: Long-read first, then hybrid 
./submit_jobs.sh samplesheet.csv array 05_assembly_flye.slurm
# Wait for Flye to complete, then:
./submit_jobs.sh samplesheet.csv array 06_assembly_unicycler.slurm

# 4. Assembly QC
./submit_jobs.sh samplesheet.csv array 07_assembly_qc_checkm2.slurm
./submit_jobs.sh samplesheet.csv array 08_assembly_qc_quast.slurm
```


## Output structure

```
work_dir/
├── output/
│   ├── 01_qc_illumina/          # Trimmed Illumina reads
│   ├── 02_qc_multiqc/           # MultiQC report
│   ├── 03_qc_nanopore_porechop_abi/  # Trimmed Nanopore reads
│   ├── 04_qc_nanopore_filtlong/ # Filtered Nanopore reads
│   ├── 05_assembly_flye/        # Flye assemblies (optional)
│   ├── 06_assembly_unicycler/   # Final hybrid assemblies
│   ├── 07_qc_checkm2/          # CheckM2 results
│   └── 08_qc_quast/            # QUAST results
└── logs/
    ├── slurm_logs/             # SLURM stdout/stderr
    ├── fastp/                  # Tool-specific logs
    ├── porechop_abi/
    ├── filtlong/
    ├── flye/
    ├── unicycler/
    ├── checkm2/
    └── quast/
```

## Pipeline Steps
### Step 1: Illumina Read QC (fastp)

Input: Raw Illumina paired-end FASTQ files
Output: Trimmed and filtered reads
Script: 01_qc_illumina_fastp.slurm

Performs adapter trimming, quality filtering (Q20).

### Step 2: Illumina QC Report (MultiQC)

Input: fastp JSON/HTML reports
Output: Aggregated QC report
Script: 02_qc_illumina_multiqc.slurm

Generates a single HTML report summarizing QC metrics for all samples.

### Step 3: Nanopore Read QC (Porechop ABI)

- Input: Raw Nanopore FASTQ files
- Output: Adapter-trimmed reads
- Script: 03_qc_nanopore_porechop_abi.slurm

Removes adapters and barcodes from Nanopore reads using ab initio detection.

### Step 4: Nanopore Read Filtering (Filtlong)

- Input: Adapter-trimmed Nanopore reads
- Output: Length and quality-filtered reads
- Script: 04_qc_nanopore_filtlong.slurm


**Filters reads by:**

- Minimum length: 6000 bp
- Keep top 95% by quality

### Step 5: Long-Read Assembly (Flye) - Optional

- Input: Filtered Nanopore reads
- Output: Draft long-read assembly
- Script: 05_assembly_flye.slurm

Assembles long reads using Flye. This step is optional - Unicycler can assemble directly from reads.

### Step 6: Hybrid Assembly (Unicycler)

- Input: Trimmed Illumina reads + (Filtered Nanopore reads OR Flye assembly)
- Output: Final hybrid assembly
- Script: 06_assembly_unicycler.slurm

**Two assembly modes:**

- Standard hybrid: Assembles from Illumina + Nanopore reads directly
- With existing assembly: If existing Flye assembly, uses Flye assembly as scaffold, polished with Illumina reads

The script automatically detects which mode to use based on available inputs.

### Step 7: Assembly Completeness (CheckM2)

- Input: Assembly FASTA
- Output: Completeness and contamination estimates
- Script: 07_assembly_qc_checkm2.slurm

Assesses assembly quality using single-copy marker genes.

### Step 8: Assembly Statistics (QUAST)

- Input: Assembly FASTA(s)
- Output: Assembly statistics and comparison
- Script: 08_assembly_qc_quast.slurm

Generates statistics including N50, L50, number of contigs, and total assembly size.
