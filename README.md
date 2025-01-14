<img src="png/tourmaline_banner.png" alt="png/tourmaline_banner" width="100%"/>

# Tourmaline 2  

## Major changes in v2 vs. v1  

### tourmaline.sh script  

Instead of interacting with Snakemake rules directly, the main way to run Tourmaline 2 is through the `tourmaline.sh` script. This script allows you to run one or more of the workflow steps at a time, specify specific config files, and set the maximum number of cores. You must be located in the tourmaline directory when running it, however you can set the output file destinations to anywhere. Usage:  

```bash
conda activate snakemake-tour
./tourmaline.sh --step [qaqc,repseqs,taxonomy] --configfile [config1,config2,config3] --cores N
```

You can still run individual snakemake rules as before. Each of the three steps (explained more below) has its own Snakefile, so you must specify the correct snakefile when running an individual rule.

#### Providing externally-generated data  

Unlike Tourmaline 1, you can start any of the 3 workflow steps with data from an external program, so long as it is formatted correctly. For example, if you already have ASV sequences and just want to assign taxonomy with Tourmaline, you can format them for QIIME 2 (code to help with this below) and just provide the file path in your config file.

## Overview

Tourmaline 2 is a modular Snakemake pipeline for processing DNA metabarcoding data. The pipeline consists of three main steps:

1. Sequence QA/QC (Quality Assessment/Quality Control)

    * Provide sequence quality plots for demultiplexed raw and/or trimmed reads.
    * Create a QIIME2 sequence artifact
    * Optionally trim primer sequences from raw reads.  

2. Representative Sequences (ASV Generation)

    * Generates ASVs using specified method (DADA2 or Deblur)
    * Optional filtering based on length, abundance, and prevalence
    * Produces feature table and representative sequences

3. Taxonomy Assignment

    * Assigns taxonomy using one of 4 methods:

        1. [naive-bayes classifier as implemented in QIIME2](https://docs.qiime2.org/2024.10/plugins/available/feature-classifier/classify-sklearn/) 
        2. [Consensus blast as implemented in QIIME2](https://docs.qiime2.org/2024.10/plugins/available/feature-classifier/classify-consensus-blast/)
        3. [Consensus vsearch as implemented in QIIME2](https://docs.qiime2.org/2024.10/plugins/available/feature-classifier/classify-consensus-vsearch/)
        4. [Anacapa's Bowtie2 and BLCA method](https://github.com/limey-bean/Anacapa?tab=readme-ov-file#step-3-taxonomic-assignment-using-bowtie-2-and-blca)

    * Supports multiple classification methods
    * Generates taxonomy assignments and visualization
  
4. Generate bioinformatics metadata

    * Creates a file with metadata about the analysis using FAIR eDNA terms
    * File can be read into NODE

## Setup Requirements

* [Conda (Miniconda works well)](https://docs.conda.io/projects/conda/en/latest/user-guide/install/index.html)
* [QIIME 2 (2024.10) amplicon workflow](https://docs.qiime2.org/2024.10/install/)
* [Snakemake conda environment, with extra packages installed](https://snakemake.readthedocs.io/en/stable/getting_started/installation.html)

  * ```bash
     conda create -c conda-forge -c bioconda -n snakemake-tour snakemake biopython yq parallel
     ```

* [Development branch of Tourmaline](https://github.com/aomlomics/tourmaline/tree/develop)
* bowtie2-blca conda env, only if running BLCA taxa assignment

  * ```bash
     conda create -c conda-forge -c bioconda -n bt2-blca biopython muscle=3.8 bowtie2
     ```  

### Running Requirements
* Snakemake environment must be activated
* Required configuration files for each step
* Input data files (vary depending on starting step)

## Configuration Files

The pipeline uses three main configuration files, one for each step. These files can have any name, and example files are provided.

### 1. Sample/QA/QC Configuration (config-01-qaqc.yaml)

Key parameters:
```yaml
run_name: [your_run_name]              # Name for this qaqc run, will be a prefix for outputs
output_dir: [path]                     # Output directory path
raw_fastq_path: [path]                 # Path to raw fastq files
paired_end: [True/False]               # Whether data is paired-end
to_trim: [True/False]                  # Whether to trim sequences

# Trimming parameters
fwd_primer: [sequence]                 # Forward primer sequence
rev_primer: [sequence]                 # Reverse primer sequence
discard_untrimmed: [True/False]        # Whether to discard sequences without the primer
minimum_length: [int]                  # Minimum sequence length to keep after trimming
```

#### QA/QC Input Files
There are three options for input files in the QA/QC step. You must choose one and leave the others blank in the config file:

```yaml
raw_fastq_path: [path]                 
# Full path to raw demultiplexed fastq files. Sample names will be the prefix of the file names.
trimmed_fastq_path: [path]
# Full path to pre-trimmed fastq files. Sample names will be the prefix of the file names.
sample_manifest_file: [path/filename] 
# relative path and file name of a QIIME2 manifest file. It can point to trimmed or untrimmed reads. 
```

##### Sample Manifest Format
Can provide either the current QIIME2 tab-separated file format, or the legacy comma-separated format. Much have the correct headers: 

**Tab-separated**  
Paired-end:
```
sample-id	forward-absolute-filepath	reverse-absolute-filepath
sample1	/path/to/sample1_R1.fastq.gz	/path/to/sample1_R2.fastq.gz
```

Single-end:
```
sample-id	absolute-filepath
sample1	/path/to/sample1_R1.fastq.gz
```

**CSV (Legacy)**  
Paired-end:
```
sample-id,absolute-filepath,direction
sample1,/path/to/sample1_R1.fastq.gz,forward
sample1,/path/to/sample1_R2.fastq.gz,reverse
```

Single-end:
```
sample-id,absolute-filepath
sample1,/path/to/sample1_R1.fastq.gz
```

### FASTQ Files without a manifest file
* Paired-end naming: `{sample}_R1.fastq.gz` and `{sample}_R2.fastq.gz`
* Alternative format: `{sample}_R1_001.fastq.gz` and `{sample}_R2_001.fastq.gz`
* Single-end naming: `{sample}_R1.fastq.gz` or `{sample}_R1_001.fastq.gz`

### 2. Representative Sequences Configuration (config-02-repseqs.yaml)

Key parameters:
```yaml
run_name: [your_run_name]              
# Name for this repseqs run, can be the same or different than qaqc step
output_dir: [path]                     
# Output directory path
asv_method: [method]                   
# ASV method (dada2pe, dada2se, deblur)

# DADA2 parameters (if using dada2pe/dada2se)
dada2_trunc_len_f: [int]              
# Forward read truncation length
dada2pe_trunc_len_r: [int]            
# Reverse read truncation length (Paired end only)
dada2_trim_left_f: [int]              
# Number of bases to trim from start of forward reads
dada2pe_trim_left_r: [int]              
# Number of bases to trim from start of reverse reads (paired end only)

# Filtering options
to_filter: [True/False]                # Whether to apply filtering
repseq_min_length: [int]              # Minimum ASV length 
repseq_max_length: [int]              # Maximum ASV length
repseq_min_abundance: [float]          # Minimum abundance threshold
repseq_min_prevalence: [float]         # Minimum prevalence threshold
```

#### Repseqs Input Files

You have two options for providing files to the repseqs step:  

**1) Provide an existing Tourmaline QA/QC run**  
    a) Either use the same ```run_name``` and ```output_dir``` for both steps, or  
    b) Use a different ```run_name``` for the repseqs step, and provide the ```sample_run_name``` you want to use. Can be helpfulif you are testing out different trimming parameters.  
**2) Provide an externally generated QIIME2 sequence archive (.qza)**    


To generate a QIIME2 sequence archive, you need a manifest file linking sample names with the absolute file path of the fastq.gz files (see the [TSV format above](https://github.com/aomlomics/tourmaline/blob/develop/README.md#sample-manifest-format). 

Activate ```qiime2-amplicon-2024.10``` environment.  
```
conda activate qiime2-amplicon-2024.10
```
Import to a QIIME2 artifact. Change code to match your manifest file name and desired output .qza file name and path.     
**Paired-end data**  
```
qiime tools import \
   --type 'SampleData[PairedEndSequencesWithQuality]' \
   --input-path my_pe.manifest \
   --output-path output-file_pe_fastq.qza \
   --input-format PairedEndFastqManifestPhred33V2
```
**Single-end data**  
```
qiime tools import \
   --type 'SampleData[SequencesWithQuality]' \
   --input-path my_se.manifest \
   --output-path output-file_se_fastq.qza \
   --input-format SingleEndFastqManifestPhred33V2
``` 

### 3. Taxonomy Configuration (config-03-taxonomy.yaml)

Key parameters:
```yaml
run_name: [your_run_name]              # Name for this pipeline run
output_dir: [path]                     # Output directory path
classify_method: [method]              # Classification method (naive-bayes, consensus-blast, consensus-vsearch, bt2-blca)
collapse_taxalevel: [int] 
# Creates an additional table where ASV counts are collapsed to the provided taxonomic level
classify_threads: [int]                
# Number of threads for classification
```

#### Taxonomy Input Files

You have two options for providing files to the taxonomy step:  

**1) Provide an existing Tourmaline repseqs run**  
    a) Either use the same ```run_name``` and ```output_dir``` for both steps, or  
    b) Use a different ```run_name``` for the taxonomy step, and provide the ```repseqs_run_name``` you want to use. Can be helpful if you are testing out different ASV parameters.  
**2) Provide externally generated QIIME2 sequence archive and table (.qza)**   
    * Must provide paths for both ```repseqs_qza_file``` and ```table_qza_file```  

**ASV sequences**  
If you have a fasta file of ASV/OTU sequences, you can use the following code to generate a QIIME2 repseqs archive. 

Activate ```qiime2-amplicon-2024.10``` environment.  
```
conda activate qiime2-amplicon-2024.10
```
Import to a QIIME2 artifact. Change code to match your fasta file name and desired output .qza file name and path.
```
qiime tools import \
   --type 'FeatureData[Sequence]' \
   --input-path my-asvs.fasta \
   --output-path output-asvs.qza 
```
**Read count table**  

If you have a biom formatted table, you can [follow the QIIME2 guidance and check the format prior to importing](https://docs.qiime2.org/2024.10/tutorials/importing/#feature-table-data). Example for a BIOM v1.0.o formatted file:  
 
```
conda activate qiime2-amplicon-2024.10

qiime tools import \
  --input-path feature-table-v100.biom \
  --type 'FeatureTable[Frequency]' \
  --input-format BIOMV100Format \
  --output-path feature-table.qza
```

If you have a .tsv file with rows as unique sequences and columns as sample read counts, you can first [convert to BIOM](https://biom-format.org/documentation/biom_conversion.html) then convert to .qza. Example: 
```
conda activate qiime2-amplicon-2024.10

biom convert -i otu_table.txt -o new_otu_table.biom --to-hdf5 --table-type="OTU table"

qiime tools import \
  --input-path new_otu_table.biom \
  --type 'FeatureTable[Frequency]' \
  --input-format BIOMV210Format \
  --output-path feature-table.qza
```

Key parameters for reference database:
```yaml
database_name: [name]                  
# Reference database name, just used for metadata
refseqs_file: [path]                   
# Reference sequences file, 
taxa_file: [path]                      
# Reference taxonomy file
classify_method: [method]              
# Classification method (naive-bayes, consensus-blast, consensus-vsearch)
taxa_ranks: [comma-separated list of ranks]                    
# Taxonomy rank levels that match the reference database
pretrained_classifier: [full path] 
# Optional for naive-bayes method, if provided will ignore refseqs_file and taxa_file
bowtie_database: [path] # optional for bt2-blca, folder with bowtie index database, refseqs and taxa files also required
```

Method-specific parameters:
```yaml
# naive-bayes
skl_confidence: 0.7
# Confidence threshold for limiting taxonomic depth
# SEQ SIMILARITY (consensus-blast or consensus-vsearch)
perc_identity: 0.8
# Percent identity threshold for matches
query_cov: 0.8
# Query alignment coverage threshold for matches
min_consensus: 0.51
# Minimum fraction of assignments must match top hit to be accepted as consensus assignment
# bt2-blca
confidence_thres: 0.8
# Bootstrap confidence threshold for limiting taxonomic depth
```

## Running the Pipeline

The pipeline can be run using the `tourmaline.sh` script. You can run all steps at once or run them modularly.

### (FIRST TIME) Clone Tourmaline develop branch

If this is your first time running Tourmaline, you'll need to set up your directory.

Start by cloning the Tourmaline directory and files OF THE DEVELOP BRANCH!:

```bash
git clone --branch develop https://github.com/aomlomics/tourmaline.git

```

### Activate snakemake conda env

```
conda activate snakemake
```

Also make sure you have the ```qiime2-amplicon-2024.10``` environment installed, with that name. You do not need to install anything else in that environment.

### Basic Usage

```bash
./tourmaline.sh --step/-s [step] --configfile/-c [config_file] --cores/-n [num_cores]
```

#### Examples

1. Run a single step (taxonomy):
```bash
./tourmaline.sh -s taxonomy -c config-03-taxonomy.yaml -n 6
```

2. Run all steps with one command:
```bash
./tourmaline.sh -s qaqc,repseqs,taxonomy -c config-01-sample.yaml,config-02-repseqs.yaml,config-03-taxonomy.yaml -n 6
```

#### Important Notes

* The number of steps must match the number of config files provided
* Each step corresponds to its respective config file
* Config files must be provided in the same order as the steps

### Generate bioinformaticsa metadata  

To generate a report file with metadata on the bioinformatics, provide your three config files to the ```scripts/format_analysisMetadata.py``` along with the tourmaline metadata file.

```bash
python scripts/format_analysisMetadata.py -s config-01-sample.yaml -r config-02-repseqs.yaml -t config-03-taxonomy.yaml -o my-tourmaline-metadata.tsv
```

## Pipeline Steps

### 1. QA/QC Step
* Processes raw fastq files
* Handles both paired-end and single-end data
* Optional primer trimming
* Quality filtering

### 2. Representative Sequences Step
* Generates ASVs using specified method (DADA2 or Deblur)
* Optional filtering based on length, abundance, and prevalence
* Produces feature table and representative sequences

### 3. Taxonomy Step
* Assigns taxonomy using specified method
* Supports multiple classification methods
* Generates taxonomy assignments and visualization

### 4. Bioinformatics Metadata
* Generate bioinformatics metadata 

## Directory Structure

The pipeline creates the following directory structure for outputs:

```
output_dir/
├── [run_name]-samples/    # QA/QC outputs
├── [run_name]-repseqs/    # Representative sequences outputs
└── [run_name]-taxonomy/   # Taxonomy assignment outputs
```

Each directory contains the relevant outputs for that step of the pipeline.
