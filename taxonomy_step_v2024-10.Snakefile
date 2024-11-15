## Snakefile for taxonomy step of Tourmaline V2 pipeline
import os

output_dir = config["output_dir"]+"/"

if config["sample_metadata_file"] != None:
    print("yes metadata\n")
    use_metadata="yes"
else:
    print("no metadata\n")
    use_metadata="no"

# set input repseqs file
input_table=output_dir+config["run_name"]+"-repseqs/"+config["run_name"]+"-table.qza"
if config["repseqs_run_name"] != None:
    repseqs_run_name=config["repseqs_run_name"]
    input_repseqs=output_dir+repseqs_run_name+"-repseqs/"+repseqs_run_name+"-repseqs.qza"
    input_table=output_dir+repseqs_run_name+"-repseqs/"+repseqs_run_name+"-table.qza"
elif config["repseqs_qza_file"] != None:
    input_repseqs=config["repseqs_qza_file"]
    input_table=config["table_qza_file"]
else:
    input_repseqs=output_dir+config["run_name"]+"-repseqs/"+config["run_name"]+"-repseqs.qza"
    input_table=output_dir+config["run_name"]+"-repseqs/"+config["run_name"]+"-table.qza"

# set classifier files
# Check the suffix of config["refseqs_file"]
fasta_suffixes = [".fna", ".fa",".fasta"]

# Function to check if the file has a valid suffix
def has_fa_suffix(file, suffixes):
    return any(file.endswith(suffix) for suffix in suffixes)

# Function to change the suffix of a file
def change_suffix(file, new_suffix):
    base_name = os.path.basename(file)
    file_name = os.path.splitext(base_name)[0]
    return file_name + new_suffix

print("check out classifier")
if config["pretrained_classifier"] != None:
    use_classifier="yes"
    #os.makedirs(config["run_name"] + "-taxonomy/", exist_ok=True)
    #os.symlink(config["pretrained_classifier"], config["run_name"]+"-taxonomy/classifier.qza")
else:
    use_classifier="no"
    print("No pretrained classifier provided, using refseqs and reftax files")


## MASTER RULE
rule run_taxonomy:
    """Run taxonomy"""
    input:
        output_dir+config["run_name"]+"-taxonomy/"+config["run_name"]+"-taxonomy.tsv",
        output_dir+config["run_name"]+"-taxonomy/figures/"+config["run_name"]+"-taxa_barplot.qzv",
        output_dir+config["run_name"]+"-taxonomy/"+config["run_name"]+"-taxa_sample_table_"+"l"+str(config["classify_taxalevel"])+".tsv",
        output_dir+config["run_name"]+"-taxonomy/"+config["run_name"]+"-asv_taxa_features.tsv"

        # add figures here

if config["refseqs_file"] == None or config["taxa_file"] == None:
    print("refseqs_file and taxa_file must be provided if pretrained_classifier is not used")
elif has_fa_suffix(config["refseqs_file"], fasta_suffixes) and config["classify_method"] != "bt2-blca":
    output_seq = output_dir+config["run_name"]+"-taxonomy/"+change_suffix(config["refseqs_file"], ".qza")
    output_tax = output_dir+config["run_name"]+"-taxonomy/"+change_suffix(config["taxa_file"], ".qza")
    rule import_ref_seqs:
        input:
            config["refseqs_file"]
        output:
            output_seq
        conda:
            "qiime2-amplicon-2024.10"
        shell:
            "qiime tools import "
            "--type 'FeatureData[Sequence]' "
            "--input-path {input} "
            "--output-path {output}"
        
    rule import_ref_tax:
        input:
            config["taxa_file"]
        output:
            output_tax
        conda:
            "qiime2-amplicon-2024.10"
        shell:
            "qiime tools import "
            "--type 'FeatureData[Taxonomy]' "
            "--input-format HeaderlessTSVTaxonomyFormat "
            "--input-path {input} "
            "--output-path {output}"
elif has_fa_suffix(config["refseqs_file"], [".qza"]):
    output_seq = config["refseqs_file"]
    output_tax = config["taxa_file"]
elif has_fa_suffix(config["refseqs_file"], fasta_suffixes) and config["classify_method"] == "bt2-blca":
    output_seq = config["refseqs_file"]
    output_tax = config["taxa_file"]
elif use_classifier == "no":
    raise ValueError("refseqs_file must have one of the following extensions: .qza, .fna, .fa, .fasta")
else:
    print("Using pretrained classifier")

if config["classify_method"] == "naive-bayes":
    if use_classifier != "yes":
        rule fit_classifier:
            input:
                refseq=output_seq,
                reftax=output_tax
            output:
                output_dir+config["run_name"]+"-taxonomy/classifier.qza"
            conda:
                "qiime2-amplicon-2024.10"
            threads: config["classify_threads"]
            shell:
                "qiime feature-classifier fit-classifier-naive-bayes "
                "--i-reference-reads {input.refseq} "
                "--i-reference-taxonomy {input.reftax} "
                "--o-classifier {output};"
    else:
        rule import_classifier:
            input:
                config["pretrained_classifier"]
            output:
                output_dir+config["run_name"]+"-taxonomy/classifier.qza"
            conda:
                "qiime2-amplicon-2024.10"
            shell:
                "ln -s {input} {output}" 
    rule feature_classifier_nb:
        input:
            repseqs=input_repseqs,
            classifier=output_dir+config["run_name"]+"-taxonomy/classifier.qza"
        output:
            output_dir+config["run_name"]+"-taxonomy/"+config["run_name"]+"-taxonomy.qza",
        params:
            classifyparams=config["classify_params"],
        conda:
            "qiime2-amplicon-2024.10"
        threads: config["classify_threads"]
        shell:
            """
            qiime feature-classifier classify-sklearn \
            --i-classifier {input.classifier} \
            --i-reads {input.repseqs} \
            --o-classification {output} \
            --p-n-jobs {threads} \
            {params.classifyparams};
            """

# elif config["classify_method"] == "bt2-blca":
#     bt2_index_path = output_dir+config["run_name"] + "-taxonomy/bowtie2_index/bowtie2_index.1.bt2"
#     if not os.path.exists(bt2_index_path):
#         rule bt2-index:
#             input:
#                 refseq=output_seq,
#             output:
#                 directory(output_dir+config["run_name"] + "-taxonomy/bowtie2_index/")
#             params:
#                 prefix={output}+"bowtie2_index"
#             conda:
#                 "bt2"
#             threads: config["classify_threads"]
#             shell:
#                 "bowtie2-build "
#                 "--threads {threads} "
#                 "-f {input.refseq} "
#                 "{params.prefix}; "
#     rule bt2:
#         input:
#             repseqs=input_repseqs,
#             index=output_dir+config["run_name"] + "-taxonomy/bowtie2_index/"
#         output:
#             sam=output_dir+config["run_name"]+"-taxonomy/"+config["run_name"]+"_bowtie2_all.sam",
#             temp_dir=output_dir+config["run_name"]+"-taxonomy/temp/"
#         params:
#             prefix={input.index}+"bowtie2_index",
#             classifyparams=config["classify_params"],
#         conda:
#             "qiime2-amplicon-2024.10"
#         threads: config["classify_threads"]
#         shell:
#             """
#             qiime feature-classifier classify-sklearn \
#             --i-classifier {input.classifier} \
#             --i-reads {input.repseqs} \
#             --o-classification {output} \
#             --p-n-jobs {threads} \
#             {params.classifyparams};
#             """

elif config["classify_method"] == "consensus-blast":
    rule feature_classifier_cb:
        input:
            repseqs=input_repseqs,
            refseq=output_seq,
            reftax=output_tax
        output:
            output_dir+config["run_name"]+"-taxonomy/"+config["run_name"]+"-taxonomy.qza",
        params:
            classifyparams=config["classify_params"],
            searchout=output_dir+config["run_name"]+"-taxonomy/search_results.qza"
        conda:
            "qiime2-amplicon-2024.10"
        threads: config["classify_threads"]
        shell:
            """
            qiime feature-classifier classify-consensus-blast \
            --i-reference-reads {input.refseq} \
            --i-reference-taxonomy {input.reftax} \
            --i-query {input.repseqs} \
            --o-classification {output} \
            --o-search-results {params.searchout} \
            {params.classifyparams};
            """
elif config["classify_method"] == "consensus-vsearch":
    rule feature_classifier_cv:
        input:
            repseqs=input_repseqs,
            refseq=output_seq,
            reftax=output_tax,
        output:
            output_dir+config["run_name"]+"-taxonomy/"+config["run_name"]+"-taxonomy.qza",
        params:
            classifyparams=config["classify_params"],
            searchout=output_dir+config["run_name"]+"-taxonomy/search_results.qza"
        conda:
            "qiime2-amplicon-2024.10"
        threads: config["classify_threads"]
        shell:
            """
            qiime feature-classifier classify-consensus-vsearch \
            --i-reference-reads {input.refseq} \
            --i-reference-taxonomy {input.reftax} \
            --i-query {input.repseqs} \
            --o-classification {output} \
            --o-search-results {params.searchout} \
            --p-threads {threads} \
            {params.classifyparams};
            """
else:
    print("classify_method must be one of the following: naive-bayes, consensus-blast, consensus-vsearch")


rule export_taxa_biom:
    input:
        table=input_table,
        taxonomy=output_dir+config["run_name"]+"-taxonomy/"+config["run_name"]+"-taxonomy.qza",
    output:
        taxa_table=output_dir+config["run_name"]+"-taxonomy/"+config["run_name"]+"-taxa_sample_table_"+"l"+str(config["classify_taxalevel"])+".tsv",
    params:
        taxalevel=config["classify_taxalevel"]
    conda:
        "qiime2-amplicon-2024.10"
    shell:
        "qiime taxa collapse "
        "--i-table {input.table} "
        "--i-taxonomy {input.taxonomy} "
        "--p-level {params.taxalevel} "
        "--o-collapsed-table tempfile_collapsed.qza;"
        "qiime tools export "
        "--input-path tempfile_collapsed.qza "
        "--output-path temp_export;"
        "biom convert "
        "-i temp_export/feature-table.biom "
        "-o {output.taxa_table} "
        "--to-tsv;"
        "/bin/rm -r tempfile_collapsed.qza temp_export/"

rule export_asv_taxa_features:
    input:
        taxonomy=output_dir+config["run_name"]+"-taxonomy/"+config["run_name"]+"-taxonomy.qza",
        repseqs=input_repseqs
    output:
        output_dir+config["run_name"]+"-taxonomy/"+config["run_name"]+"-asv_taxa_features.tsv"
    params:
        taxaranks=config["taxa_ranks"]
    conda:
        "qiime2-amplicon-2024.10"
    shell:
        "python scripts/create_asv_seq_taxa_output.py --input_repseqs {input.repseqs} --input_taxonomy {input.taxonomy} --output {output} --taxaranks {params.taxaranks}"

rule export_taxonomy_to_tsv:
    input:
        output_dir+config["run_name"]+"-taxonomy/"+config["run_name"]+"-taxonomy.qza"
    output:
        output_dir+config["run_name"]+"-taxonomy/"+config["run_name"]+"-taxonomy.tsv"
    conda:
        "qiime2-amplicon-2024.10"
    shell:
        "qiime tools export "
        "--input-path {input} "
        "--output-path {output} "
        "--output-format TSVTaxonomyFormat"

rule taxa_barplot:
    input:
        table=input_table,
        taxonomy=output_dir+config["run_name"]+"-taxonomy/"+config["run_name"]+"-taxonomy.qza",
    output:
        output_dir+config["run_name"]+"-taxonomy/figures/"+config["run_name"]+"-taxa_barplot.qzv"
    params:
        metadata=config["sample_metadata_file"]
    conda:
        "qiime2-amplicon-2024.10"
    shell:
        """
        if [ {use_metadata} = yes ]; then 
            qiime taxa barplot \
            --i-table {input.table} \
            --i-taxonomy {input.taxonomy} \
            --m-metadata-file {params.metadata} \
            --o-visualization {output};
        else
            qiime taxa barplot \
            --i-table {input.table} \
            --i-taxonomy {input.taxonomy} \
            --o-visualization {output};
        fi;
        """
