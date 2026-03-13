# 1. Base Image: Use the official Bioconductor Docker image
FROM bioconductor/bioconductor_docker:RELEASE_3_18

# 2. Package Manager Configuration: Set R mirror to use pre-compiled binaries for speed
# This prevents R from compiling everything from source
RUN echo "options(repos = c(CRAN = 'https://packagemanager.posit.co/cran/__linux__/jammy/latest'))" >> /usr/local/lib/R/etc/Rprofile.site

# 3. System Dependencies: Install core utilities and the GDC Data Transfer Tool in a single layer
RUN apt-get update && apt-get install -y --no-install-recommends \
    libcurl4-openssl-dev libxml2-dev libssl-dev unzip wget \
    && wget https://gdc.cancer.gov/files/public/file/gdc-client_v1.6.1_Ubuntu_x64.zip \
    && unzip gdc-client_v1.6.1_Ubuntu_x64.zip \
    && mv gdc-client /usr/local/bin/ \
    && rm gdc-client_v1.6.1_Ubuntu_x64.zip \
    && apt-get purge -y --auto-remove wget unzip \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# 4. R Package Installation: Combine installations to optimize Docker layer caching
# Combining these prevents multiple "layers" of package data
RUN Rscript -e "install.packages(c('optparse', 'data.table', 'plyr', 'dplyr', 'reshape2', 'ggpubr', 'gginnards', 'rstatix'))" \
    && Rscript -e "BiocManager::install(c('GDCRNATools', 'edgeR', 'limma'))"

# 5. Application Setup
WORKDIR /app
# Copy everything into /app; our scripts will live in /app/scripts/
COPY . /app/
