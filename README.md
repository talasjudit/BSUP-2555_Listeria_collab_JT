# BSUP-2555_Listeria_collab_JT
Nextflow pipeline for Listeria hybrid assembly

## Table of Contents

- [Pipeline Overview](#pipeline-overview)

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
    n3["Illumina FastQ files"] --> n7["trimmomatic"]
    n7 --> n8["Trimmed/filtered reads"]
    n5["porechop_ABI"] --> n9["Trimmed reads"]
    n9 --> n6["filtlong"]
    n6 --> n10["Filtered reads"]
    n1["Nanopore FastQ files"] --> n5
    n11["flye"] --> n12["Long read assembly"]
    n12 --> n26["medaka"]
    n26 --> n33["Polished long read assembly"]
    n33 --> n13["unicycler <br>(existing_long_read_assembly)"]
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
    n26@{ shape: proc}
    n33@{ shape: lean-r}
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
     n26:::process
     n33:::data
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