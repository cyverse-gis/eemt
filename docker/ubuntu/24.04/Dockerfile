FROM ubuntu:24.04

LABEL authors="Tyson L Swetnam"
LABEL maintainer="tswetnam@cyverse.org"
LABEL description="EEMT Algorithm Suite with GRASS GIS 8.4+, GDAL 3.11, Python 3.11"
LABEL version="2.0"

# System environment
ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV SHELL=/bin/bash

# Data directory
ENV DATA_DIR=/data
ENV CONDA_DIR=/opt/conda
ENV PATH=$CONDA_DIR/bin:$PATH

# Update system and install base dependencies
RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y \
        software-properties-common \
        build-essential \
        curl \
        wget \
        git \
        ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install Miniforge for Python environment management (conda-forge by default, no TOS issues)
RUN wget --quiet https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh -O /tmp/miniforge.sh && \
    bash /tmp/miniforge.sh -b -p $CONDA_DIR && \
    rm /tmp/miniforge.sh && \
    $CONDA_DIR/bin/conda clean -ya

# Copy environment files
COPY docker/ubuntu/24.04/environment.yml /tmp/environment.yml
COPY docker/ubuntu/24.04/install_grass.sh /tmp/install_grass.sh
COPY docker/ubuntu/24.04/install_qgis.sh /tmp/install_qgis.sh

# Make installation scripts executable
RUN chmod +x /tmp/install_grass.sh /tmp/install_qgis.sh

# Create conda environment from environment.yml (using mamba for speed)
RUN mamba env create -f /tmp/environment.yml && \
    conda clean -ya

# Activate environment by default
ENV CONDA_DEFAULT_ENV=eemt-gis
ENV PATH=$CONDA_DIR/envs/eemt-gis/bin:$PATH

# Install GRASS GIS from source
RUN /tmp/install_grass.sh

# Set GRASS environment variables (using package installation paths)
ENV GISBASE=/usr/lib/grass84
ENV GRASS_PYTHON=$CONDA_DIR/envs/eemt-gis/bin/python
ENV PYTHONPATH=$GISBASE/etc/python:$PYTHONPATH
ENV LD_LIBRARY_PATH=$GISBASE/lib:$LD_LIBRARY_PATH

# Install QGIS using official installation guide
RUN apt-get update && \
    apt-get install -y gnupg software-properties-common && \
    mkdir -m755 -p /etc/apt/keyrings && \
    wget -O /etc/apt/keyrings/qgis-archive-keyring.gpg https://download.qgis.org/downloads/qgis-archive-keyring.gpg && \
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/qgis-archive-keyring.gpg] https://qgis.org/ubuntu noble main" > /etc/apt/sources.list.d/qgis.list && \
    apt-get update && \
    apt-get install -y qgis qgis-plugin-grass python3-qgis && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Set up GRASS environment and install extensions for EEMT
RUN echo 'export PATH=/usr/lib/grass84/bin:$PATH' >> /etc/bash.bashrc && \
    echo 'export GISBASE=/usr/lib/grass84' >> /etc/bash.bashrc && \
    echo 'export PYTHONPATH=/usr/lib/grass84/etc/python:$PYTHONPATH' >> /etc/bash.bashrc && \
    echo 'Installing GRASS extensions for EEMT solar radiation modeling...' && \
    bash -c "source $CONDA_DIR/etc/profile.d/conda.sh && conda activate eemt-gis && \
    export GISBASE=/usr/lib/grass84 && \
    export PYTHONPATH=/usr/lib/grass84/etc/python:$PYTHONPATH && \
    grass --tmp-location EPSG:4326 --exec 'g.extension extension=r.sun.mp operation=add' || echo 'r.sun.mp extension install attempted' && \
    grass --tmp-location EPSG:4326 --exec 'g.extension extension=r.sun.hourly operation=add' || echo 'r.sun.hourly extension install attempted' && \
    grass --tmp-location EPSG:4326 --exec 'g.extension extension=r.sun.daily operation=add' || echo 'r.sun.daily extension install attempted'"

# Install CCTools (Makeflow + Work Queue) for distributed workflow management
RUN apt-get update && \
    apt-get install -y \
        build-essential \
        gcc \
        g++ \
        swig \
        python3-dev \
        perl \
        libssl-dev \
        zlib1g-dev \
        cron \
        systemd && \
    cd /tmp && \
    wget https://github.com/cooperative-computing-lab/cctools/archive/refs/tags/release/7.15.14.tar.gz && \
    tar xzf 7.15.14.tar.gz && \
    cd cctools-release-7.15.14 && \
    ./configure \
        --prefix /opt/eemt \
        --with-python-path $CONDA_DIR/envs/eemt-gis/bin/python \
        --with-python3-path $CONDA_DIR/envs/eemt-gis/bin/python \
        --with-swig-path $(which swig) && \
    make -j$(nproc) && \
    make install && \
    cd / && \
    rm -rf /tmp/cctools-* /tmp/7.15.14.tar.gz && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Update library paths and environment variables for CCTools
RUN echo "/opt/eemt/lib" > /etc/ld.so.conf.d/eemt.conf && \
    echo "/opt/eemt/lib64" >> /etc/ld.so.conf.d/eemt.conf && \
    echo "/usr/local/grass84/lib" > /etc/ld.so.conf.d/grass.conf && \
    ldconfig

# Set CCTools environment variables
ENV PATH="/opt/eemt/bin:$PATH"
ENV PYTHONPATH="/opt/eemt/lib/python3.11/site-packages:$PYTHONPATH"
ENV PERL5LIB="/opt/eemt/lib/perl5/site_perl:$PERL5LIB"

# Create data directory and set permissions
RUN mkdir -p $DATA_DIR && \
    chmod -R a+rwx $DATA_DIR

# Create user
RUN useradd -m -U -s /bin/bash eemt && \
    chown -R eemt:eemt $DATA_DIR

# Copy EEMT source code (relative to Docker context)
COPY sol/ /opt/eemt/sol/
COPY eemt/ /opt/eemt/eemt/

# Copy container workflow scripts
COPY docker/ubuntu/24.04/container-scripts/ /opt/eemt/bin/
RUN chmod +x /opt/eemt/bin/*.py

# Copy cleanup scripts from web interface for worker nodes
COPY web-interface/cleanup_jobs.py /opt/eemt/bin/
COPY web-interface/setup_cleanup_cron.sh /opt/eemt/bin/
RUN chmod +x /opt/eemt/bin/cleanup_jobs.py /opt/eemt/bin/setup_cleanup_cron.sh

# Create logs directory for cleanup scripts
RUN mkdir -p /opt/eemt/logs

# Set ownership
RUN chown -R eemt:eemt /opt/eemt/

# Cleanup installation files
RUN rm -f /tmp/environment.yml /tmp/install_grass.sh /tmp/install_qgis.sh

# Declare data volume
VOLUME $DATA_DIR
WORKDIR $DATA_DIR

# Switch to non-root user
USER eemt

# Activate conda environment and test installation
RUN echo "conda activate eemt-gis" >> ~/.bashrc

# Health check - Test GRASS, CCTools, and Python integrations
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD grass --version && \
        makeflow --version && \
        work_queue_worker --version && \
        python -c "import grass.script as gs; print('GRASS Python interface OK')" || exit 1

# Default command
CMD ["/bin/bash", "-l"]