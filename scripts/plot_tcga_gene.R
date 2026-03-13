#!/usr/bin/env Rscript

# --- 1. Setup and Library Loading ---
# Load libraries required for data reshaping, statistical testing, and visualization.
suppressPackageStartupMessages({
  library(optparse)
  library(data.table)
  library(dplyr)
  library(ggplot2)
  library(ggpubr)
  library(rstatix)
  library(gginnards)
  library(reshape2)
})

# Workaround for compatibility between specific versions of ggpubr and ggplot2
`%||%` <- function(a, b) if (!is.null(a)) a else b

# --- 2. Command Line Arguments ---
# Define required inputs including paths to data and target gene identifiers.
option_list = list(
  make_option(c("-e", "--expr"), type="character", default=NULL, help="Path to CPM.log2.RDS"),
  make_option(c("-m", "--meta"), type="character", default=NULL, help="Path to RNAseq_Meta_Data.tsv"),
  make_option(c("-g", "--gene_symbol"), type="character", default="GAPDH"),
  make_option(c("-i", "--gene_id"), type="character", default="ENSG00000111640"),
  make_option(c("-o", "--outdir"), type="character", default="./figures/")
)
opt = parse_args(OptionParser(option_list=option_list))

# --- 3. Data Loading and Formatting ---
# Load the normalized expression matrix and merge it with sample metadata.
cat(sprintf("Generating Pan-Cancer expression plot for %s...\n", opt$gene_symbol))
meta_df <- fread(data.table = FALSE, input = opt$meta)
log2cpm_df <- readRDS(file = opt$expr)

# Directly create a data frame using column names (Barcodes) from the matrix
exp_gene_df <- data.frame(
  sample_id = colnames(log2cpm_df),
  value = as.numeric(log2cpm_df[opt$gene_id, ]),
  stringsAsFactors = FALSE
)

# Merge using the barcodes
exp_gene_df <- merge(x = exp_gene_df, y = meta_df, by.x = "sample_id", by.y = "sample", all.x = TRUE)

# Final check before moving to projects filtering
if (sum(!is.na(exp_gene_df$project_id)) == 0) {
  stop("CRITICAL ERROR: Zero matches found between expression IDs and Metadata. Check for dots vs dashes.", call. = FALSE)
}

# --- 4. Filtering and Level Management ---
# Identify projects with at least 3 samples in both Normal and Tumor for stability
valid_projects <- exp_gene_df %>%
  group_by(project_id) %>%
  summarise(
    n_normal = sum(sample_type == "SolidTissueNormal"),
    n_tumor = sum(sample_type != "SolidTissueNormal"),
    .groups = "drop"
  ) %>%
  filter(n_normal >= 1 & n_tumor >= 1) %>%
  pull(project_id)

plot_data_df <- exp_gene_df %>%
  filter(project_id %in% valid_projects) %>%
  mutate(cancer_type = gsub("TCGA-", "", project_id)) %>%
  mutate(sample_group = factor(ifelse(sample_type == "SolidTissueNormal", "Normal", "Tumor"), 
                               levels = c("Normal", "Tumor"))) %>%
  mutate(x_plot = paste0(cancer_type, ".", sample_group)) %>%
  droplevels()

# Sort facets by median Tumor expression
sort_levels <- plot_data_df %>%
  filter(sample_group == "Tumor") %>%
  group_by(cancer_type) %>%
  summarise(value_median = median(value, na.rm = TRUE), .groups = "drop") %>%
  arrange(value_median) %>%
  pull(cancer_type)

plot_data_df$cancer_type <- factor(plot_data_df$cancer_type, levels = sort_levels)

# Labels for X-axis
label_data_df <- plot_data_df %>%
  group_by(x_plot, sample_group) %>%
  summarise(count = n(), .groups = "drop") %>%
  mutate(x_label = paste0(sample_group, " (n=", count, ")"))

if (nrow(plot_data_df) == 0) {
  stop("CRITICAL ERROR: plot_data_df is empty. Check your merge keys and project filters.", call. = FALSE)
}

# --- 5. Statistics ---
# Perform Wilcoxon rank-sum tests to compare tumor vs normal expression across all valid cohorts.
cat("Calculating statistics for", length(unique(plot_data_df$cancer_type)), "cancer types...\n")
stat.test <- plot_data_df %>%
  group_by(cancer_type) %>%
  wilcox_test(value ~ sample_group, ref.group = "Normal") %>%
  adjust_pvalue(method = "bonferroni") %>%
  add_significance("p.adj") %>%
  add_xy_position(x = "sample_group")

# Highlighting significant facets
highlight_data_df <- plot_data_df %>%
  filter(cancer_type %in% stat.test$cancer_type[stat.test$p.adj.signif != "ns"]) %>%
  group_by(cancer_type) %>%
  slice(1) %>%
  ungroup()

# --- 6. Plot Rendering ---
# Generate the final boxplot with significance brackets and facet highlighting.
cat("Rendering plot...\n")
p <- ggboxplot(plot_data_df, x = "x_plot", y = "value", fill = "sample_group",
              facet.by = "cancer_type", nrow = 1, scales = "free_x")

if (nrow(highlight_data_df) > 0) {
  p <- p + geom_rect(data = highlight_data_df,
                    fill = "coral1", xmin = -Inf, xmax = Inf, ymin = -Inf, ymax = Inf, alpha = 0.2)
}

p <- p + stat_pvalue_manual(stat.test, label = "p.adj.signif", tip.length = 0.01) +
  scale_x_discrete(breaks = label_data_df$x_plot, labels = label_data_df$x_label) +
  scale_fill_manual(values = c("Tumor" = "coral2", "Normal" = "darkgray")) +
  labs(y = paste0(opt$gene_symbol, " expression (log2CPM)")) +
  theme_bw() + 
  theme(axis.text.x = element_text(angle = 90, vjust = 0.5, hjust = 1), 
        axis.title.x = element_blank(),
        panel.spacing = unit(0, "cm"),
        strip.background = element_rect(fill = "white"),
        legend.position = "none")

p <- gginnards::move_layers(p, "GeomBoxplot", position = "top")

final_outdir <- normalizePath(opt$outdir, mustWork = FALSE)
output_file <- file.path(final_outdir, paste0(opt$gene_symbol, ".tumor_vs_normal.png"))

png(output_file, width = 1500, height = 600, res = 150)
print(p)
invisible(dev.off())

cat("Success! Plot saved to:", output_file, "\n")
