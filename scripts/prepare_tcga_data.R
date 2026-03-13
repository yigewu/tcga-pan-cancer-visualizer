#!/usr/bin/env Rscript

# --- 1. Setup and Library Loading ---
# Load required bioinformatics and data manipulation packages silently.
suppressPackageStartupMessages({
	  library(optparse)
	    library(data.table)
	    library(dplyr)
	      library(GDCRNATools)
	      library(edgeR)
	        library(limma)
})

# 1. Command Line Arguments
# Define input flags for output directory and metadata skipping.
option_list = list(
		   make_option(c("-o", "--outdir"), type="character", default="/data", help="Output directory"),
                   make_option(c("-s", "--skip_meta"), action="store_true", default=FALSE, help="Skip metadata parsing if TSV exists")
		     )
opt = parse_args(OptionParser(option_list=option_list))

dir.create(opt$outdir, showWarnings = FALSE, recursive = TRUE)
setwd(opt$outdir)

# --- 3. Project Configuration ---
# Define the target TCGA and NCICCR cohorts for download.
tcga_projects <- c(
		     "TCGA-BRCA", "TCGA-GBM", "TCGA-OV", "TCGA-LUAD", "TCGA-UCEC", "TCGA-KIRC", 
		       "TCGA-HNSC", "TCGA-LGG", "TCGA-THCA", "TCGA-LUSC", "TCGA-PRAD", "TCGA-SKCM", 
		       "TCGA-COAD", "TCGA-STAD", "TCGA-BLCA", "TCGA-LIHC", "TCGA-CESC", "TCGA-KIRP", 
		         "TCGA-SARC", "TCGA-LAML", "TCGA-ESCA", "TCGA-PAAD", "TCGA-PCPG", "TCGA-READ", 
		         "TCGA-TGCT", "TCGA-THYM", "TCGA-KICH", "TCGA-ACC", "TCGA-MESO", "TCGA-UVM", 
			   "TCGA-DLBC", "TCGA-UCS", "TCGA-CHOL")

# --- 4. Metadata Parsing ---
# Fetch or load sample metadata from GDC and filter for primary tumors and normal solid tissues.
meta_file <- file.path(opt$outdir, "RNAseq_Meta_Data.tsv")

if (opt$skip_meta && file.exists(meta_file)) {
  cat("Skipping metadata parsing. Loading existing file...\n")
  meta.rna_df <- fread(meta_file, data.table = FALSE)
} else {
  cat("Parsing metadata from GDC...\n")
  meta.rna_df <- NULL
  for (project in tcga_projects) {
	  cat("Checking project:", project, "\n")
          meta.rna <- gdcParseMetadata(project.id = project, data.type = 'RNAseq', write.meta = FALSE)
	  cat("Running gdcFilterDuplicate:")
	  meta.rna <- gdcFilterDuplicate(meta.rna)
          meta.rna <- meta.rna[meta.rna$sample_type %in% c("PrimaryTumor", "SolidTissueNormal", "PrimaryBloodDerivedCancer-PeripheralBlood"),]
          meta.rna_df <- rbind(meta.rna_df, meta.rna)
	  
	  # Write individual project manifests for the download client
	  manifest_path <- file.path(opt$outdir, paste0(project, "_manifest.txt"))
	  write.table(meta.rna[, "file_id", drop=FALSE],
              file = manifest_path, quote = FALSE, sep = "\t", row.names = FALSE, col.names = "id")
  }

  meta.rna_df <- gdcFilterDuplicate(meta.rna_df)
  write.table(meta.rna_df, file = meta_file, quote = FALSE, sep = "\t", row.names = FALSE)
}

# --- 5. Data Download Phase ---
# Trigger the external GDC client to download raw RNA-seq files in parallel.
cat("Starting data download (this will take significant time)...\n")
# Determine which projects we actually have metadata for (after filtering)
download_projects <- unique(meta.rna_df$project_id)

for (project in download_projects) {
	  dir_download <- file.path(opt$outdir, project)
# Only create the directory if it doesn't exist
  if (!dir.exists(dir_download)) {
	      dir.create(dir_download, recursive = TRUE)
    }
    
    cat("Downloading project:", project, "\n")
    manifest_path <- file.path(opt$outdir, paste0(project, "_manifest.txt"))

    # Call gdc-client directly via the system to use --n-parallel 10
    # Using absolute paths ensures Docker volume mapping is respected
    download_cmd <- paste0("gdc-client download -m ", manifest_path,
                         " -d ", dir_download,
                         " -n 10 --retry-amount 5 2>&1")

    system(download_cmd, intern = FALSE, wait = TRUE)
}

# --- 6. Data Merge and Normalization ---
# Consolidate raw files into a single matrix and apply TMM normalization to generate final log2CPM values.
cat("Merging RNAseq counts...\n")
meta.rna_new_df <- meta.rna_df %>% mutate(file_id = paste0(project_id, "/", file_id))

rnaCounts <- gdcRNAMerge(metadata  = meta.rna_new_df, 
			                          path      = opt$outdir, 
						                           organized = FALSE, 
						                           data.type = 'RNAseq')

cat("Performing TMM Normalization...\n")
dge <- DGEList(counts = rnaCounts)
dge <- calcNormFactors(dge, method = 'TMM')
saveRDS(dge, file=file.path(opt$outdir, 'DGEList.RDS'), compress = TRUE)

exprData <- edgeR::cpm(dge, log = TRUE, prior.count = 2)
saveRDS(exprData, file=file.path(opt$outdir, 'CPM.log2.RDS'), compress = TRUE)

cat("Data preparation complete!\n")
