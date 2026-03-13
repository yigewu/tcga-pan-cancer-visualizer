#!/bin/bash

# ==============================================================================
# CONFIGURATION - Update the path below to your local data directory
# ==============================================================================
HOST_DATA_PATH="/home/ubuntu/tcga_data"

# Define your list of target genes and their Ensembl IDs
# Format -> "GENE_SYMBOL:ENSEMBL_ID"
GENES=(
    "GAPDH:ENSG00000111640"
    "MYC:ENSG00000136997"
    "ESR1:ENSG00000091831"
    "PTEN:ENSG00000171862"
)

# ==============================================================================
# EXECUTION LOGIC
# ==============================================================================
# Create the figures directory relative to the host data path
mkdir -p "$HOST_DATA_PATH/figures"

echo "Starting TCGA Pan-Cancer Visualization Pipeline..."
echo "Starting batch processing for ${#GENES[@]} genes..."

# Loop through each gene in the list
for entry in "${GENES[@]}"; do
    # Split the pair into two variables: SYMBOL and ID
    IFS=":" read -r SYMBOL ID <<< "$entry"
    
    echo "================================================="
    echo "▶ Generating plot for $SYMBOL ($ID)..."
    echo "================================================="
    
    # Run the Docker container for the current gene
    docker run --rm \
        -v "$HOST_DATA_PATH":/data \
        tcga-tool \
	Rscript /app/scripts/plot_tcga_gene.R \
        --expr /data/CPM.log2.RDS \
        --meta /data/RNAseq_Meta_Data.tsv \
        --gene_symbol "$SYMBOL" \
        --gene_id "$ID" \
        --outdir /data/figures
        
    echo "✔ Finished $SYMBOL"
    echo ""
done

echo "================================================="
echo "🎉 Done! Plots saved to: $HOST_DATA_PATH/figures/"
