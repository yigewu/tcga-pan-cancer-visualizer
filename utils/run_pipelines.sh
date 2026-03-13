#!/bin/bash

# ==============================================================================
# TCGA AUTOMATED PIPELINE ORCHESTRATOR
# ==============================================================================
HOST_DATA_PATH="${1:-/home/ubuntu/tcga_data}"
MAX_RETRIES=5
RETRY_COUNT=0
DOWNLOAD_SUCCESS=false

echo "================================================="
echo "▶ STARTING TCGA PIPELINE: DOWNLOAD PHASE"
echo "================================================="
echo "Tracking Directory: $HOST_DATA_PATH"

# The Self-Healing Loop
while [ "$DOWNLOAD_SUCCESS" = false ] && [ "$RETRY_COUNT" -lt "$MAX_RETRIES" ]; do
    echo "Running download script (Attempt $((RETRY_COUNT + 1)) of $MAX_RETRIES)..."

    docker run --rm -v "$HOST_DATA_PATH":/data tcga-tool \
        Rscript /app/scripts/01_download_data.R --outdir /data

    # Capture the exact exit code from the Docker container
    EXIT_CODE=$?

    if [ $EXIT_CODE -eq 0 ]; then
        echo "✔ Download phase completed successfully with full MD5 verification!"
        DOWNLOAD_SUCCESS=true
    else
        echo "⚠️ Download interrupted or failed (Exit code: $EXIT_CODE)."
        ((RETRY_COUNT++))
        if [ "$RETRY_COUNT" -lt "$MAX_RETRIES" ]; then
            echo "⏳ Network drop detected. Retrying in 30 seconds to resume partials..."
            sleep 30
        fi
    fi
done

# Gatekeeper Check
if [ "$DOWNLOAD_SUCCESS" = false ]; then
    echo "❌ CRITICAL ERROR: Download failed after $MAX_RETRIES attempts. Halting pipeline to prevent corrupted normalization."
    exit 1
fi

echo ""
echo "================================================="
echo "▶ STARTING TCGA PIPELINE: NORMALIZATION PHASE"
echo "================================================="

docker run --rm -v "$HOST_DATA_PATH":/data tcga-tool \
    Rscript /app/scripts/02_normalize_data.R --outdir /data

NORM_EXIT_CODE=$?

if [ $NORM_EXIT_CODE -eq 0 ]; then
    echo "🎉 Pipeline completely finished! Data is merged, normalized, and ready for plotting."
else
    echo "❌ ERROR: Normalization failed (Exit code: $NORM_EXIT_CODE)."
    exit 1
fi
