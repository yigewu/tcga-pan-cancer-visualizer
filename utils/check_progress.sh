#!/bin/bash

# ==============================================================================
# CONFIGURATION
# Set your default path here, OR pass it as an argument when running the script:
# Example: ./utils/check_progress.sh /my/custom/data/path
# ==============================================================================
HOST_DATA_PATH="${1:-/home/ubuntu/tcga_data}"

# Define the projects we are looking for
PROJECTS=("TCGA-BRCA" "TCGA-GBM" "TCGA-OV" "TCGA-LUAD" "TCGA-UCEC" "TCGA-KIRC" \
"TCGA-HNSC" "TCGA-LGG" "TCGA-THCA" "TCGA-LUSC" "TCGA-PRAD" "TCGA-SKCM" \
"TCGA-COAD" "TCGA-STAD" "TCGA-BLCA" "TCGA-LIHC" "TCGA-CESC" "TCGA-KIRP" \
"TCGA-SARC" "TCGA-LAML" "TCGA-ESCA" "TCGA-PAAD" "TCGA-PCPG" "TCGA-READ" \
"TCGA-TGCT" "TCGA-THYM" "TCGA-KICH" "TCGA-ACC" "TCGA-MESO" "TCGA-UVM" \
"TCGA-DLBC" "TCGA-UCS" "TCGA-CHOL")

echo "------------------------------------------"
echo "TCGA Download Progress Tracker"
echo "Tracking Directory: $HOST_DATA_PATH"
echo "Checked at: $(date)"
echo "------------------------------------------"

DONE=0
PENDING=0
NOT_STARTED=0

for PROJ in "${PROJECTS[@]}"; do
    MANIFEST="$HOST_DATA_PATH/${PROJ}_manifest.txt"
    PROJ_DIR="$HOST_DATA_PATH/$PROJ"

    # 1. Check if manifest exists to know the target count
    if [ -f "$MANIFEST" ]; then
        # Subtract 1 for the header 'id'
        EXPECTED_FILES=$(($(wc -l < "$MANIFEST") - 1))
        
        # 2. Check how many UUID folders gdc-client has successfully created
        if [ -d "$PROJ_DIR" ]; then
            DOWNLOADED_FILES=$(find "$PROJ_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l)
            
            if [ "$DOWNLOADED_FILES" -eq 0 ]; then
                echo "[...] $PROJ: Started (0 / $EXPECTED_FILES files)"
                ((PENDING++))
            elif [ "$DOWNLOADED_FILES" -ge "$EXPECTED_FILES" ]; then
                echo "[✓] $PROJ: Complete ($DOWNLOADED_FILES / $EXPECTED_FILES files)"
                ((DONE++))
            else
                echo "[...] $PROJ: In Progress ($DOWNLOADED_FILES / $EXPECTED_FILES files)"
                ((PENDING++))
            fi
        else
            echo "[ ] $PROJ: Manifest ready, download not started"
            ((NOT_STARTED++))
        fi
    else
        echo "[ ] $PROJ: Not Started (No manifest generated yet)"
        ((NOT_STARTED++))
    fi
done

echo "------------------------------------------"
echo "SUMMARY: $DONE Complete | $INCOMPLETE Incomplete | $NOT_STARTED Not Started"
echo "------------------------------------------"

if [ "$INCOMPLETE" -gt 0 ] || [ "$NOT_STARTED" -gt 0 ]; then
    echo "⚠️  ACTION REQUIRED: Some projects are missing data."
    echo "   Please re-run the download script: docker run ... Rscript /app/scripts/01_download_data.R"
    echo "   NOTE: The gdc-client will securely verify existing files before resuming."
    echo "   This verification can take 10-20 minutes, but it prevents duplicate downloads."
    echo "   DO NOT proceed to step 02 (Normalization) until all projects show [✓] Complete."
else
    echo "✅ All downloads complete! You are cleared to run 02_normalize_data.R"
fi
echo "------------------------------------------"
