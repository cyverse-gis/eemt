FROM ubuntu:22.04

# Build-time metadata as defined at http://label-schema.org
ARG BUILD_DATE
ARG VCS_REF
ARG VERSION
LABEL org.label-schema.build-date=$BUILD_DATE \
      org.label-schema.name="EEMT" \
      org.label-schema.description="Conda CCTOOLS Python PROJ GDAL GRASS SAGA-GIS" \
      org.label-schema.url="https://tyson-swetnam.github.io/eemt" \
      org.label-schema.vcs-ref=$VCS_REF \
      org.label-schema.vcs-url="e.g. https://github.com/tyson-swetnam/eemt" \
      org.label-schema.vendor="CyVerse" \
      org.label-schema.version=$VERSION \
      org.label-schema.schema-version="1.0.0"

USER root
ENV DEBIAN_FRONTEND noninteractive

# Add sudo
RUN apt-get update && \
    apt-get install -y sudo && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
    
ARG LOCAL_USER=jovyan
ARG PRIV_CMDS='/bin/ch*,/bin/cat,/bin/gunzip,/bin/tar,/bin/mkdir,/bin/ps,/bin/mv,/bin/cp,/usr/bin/apt*,/usr/bin/pip*,/bin/yum'

RUN adduser --disabled-password --gecos "Jovyan" --uid 1000 jovyan  && \
    usermod -aG sudo jovyan && \
    echo "$LOCAL_USER ALL=NOPASSWD: $PRIV_CMDS" >> /etc/sudoers

# Install MiniConda and Tini
ENV TZ America/Phoenix
ENV LANG=C.UTF-8 
ENV LC_ALL "en_US.UTF-8"
RUN echo LANG="en_US.UTF-8" > /etc/default/locale
ENV PATH /opt/conda/bin:$PATH

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && \
    echo $TZ > /etc/timezone

# MiniConda dependencies
RUN apt-get update && \
    apt-get install -y wget bzip2 ca-certificates \
    libglib2.0-0 libxext6 libsm6 libxrender1 \
    gettext-base git mercurial subversion \
    tmux && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN wget --quiet https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O ~/miniconda.sh && \
    /bin/bash ~/miniconda.sh -b -p /opt/conda && \
    rm ~/miniconda.sh && \
    ln -s /opt/conda/etc/profile.d/conda.sh /etc/profile.d/conda.sh && \
    echo ". /opt/conda/etc/profile.d/conda.sh" >> /home/jovyan/.bashrc && \
    echo ". /opt/conda/etc/profile.d/conda.sh" >> /home/jovyan/.zshrc && \
    chown -R jovyan:jovyan /opt/conda

RUN apt-get update && \
    apt-get install -y curl grep sed dpkg && \
    curl -L "https://github.com/krallin/tini/releases/download/v0.19.0/tini_0.19.0-amd64.deb" > tini.deb && \
    dpkg -i tini.deb && \
    rm tini.deb && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install a few dependencies for iCommands, text editing, and monitoring instances
RUN apt update && \
    apt install -y lsb-release apt-transport-https curl libfreetype6-dev pkg-config libx11-dev gcc less software-properties-common apt-utils glances htop nano rclone

RUN wget -qO - https://packages.irods.org/irods-signing-key.asc | apt-key add - && \
    echo "deb [arch=amd64] https://packages.irods.org/apt/ focal main" >> /etc/apt/sources.list.d/renci-irods.list && \
    apt-get update && \
    apt install -y irods-icommands 

# add iRODS iCommands to user profile as JSON
RUN mkdir /home/jovyan/.irods     

# Create Conda environment for CCTOOLS & Jupyter Notebooks
RUN conda update conda 
RUN conda config --remove channels conda-forge
RUN conda config --add channels conda-forge
RUN conda config --set channel_priority strict
RUN conda install -c conda-forge mamba
COPY environment.yml /home/jovyan/ 
RUN mamba env create -f /home/jovyan/environment.yml
RUN echo ". /opt/conda/etc/profile.d/conda.sh" >> /home/jovyan/.bashrc && \
    echo "conda deactivate" >> /home/jovyan/.bashrc && \
    echo "conda activate EEMT" >> /home/jovyan/.bashrc
RUN . /opt/conda/etc/profile.d/conda.sh && conda activate EEMT && python -m ipykernel install --user --name EEMT  
RUN source /home/jovyan/.bashrc

# Install JupyterLab widget extensions
RUN sudo chown -R 1000:100 /opt/conda/share
RUN jupyter labextension install \
    ipyvolume \
    itkwidgets \    
    jupyterlab_iframe \ 
    jupyter-leaflet \
    jupyter-threejs \
 && npm cache clean --force

RUN jupyter lab build

############## Getting ready to build GIS packages ##############

COPY /docker/gis_dependency.makefile /tmp/

ENV GISBASE=/opt/osgeo/grass-8.2.0
ENV LOCATION=/usr/local/share/grassdata/eemt/PERMANENT
ENV GRASS_PROJSHARE=/usr/share/proj
ENV LD_LIBRARY_PATH=/opt/osgeo/lib:/opt/osgeo/grass-8.2.0/lib
ENV PATH=/opt/osgeo/bin:/opt/osgeo/grass-8.2.0/bin:$PATH
ENV PYTHONPATH=/opt/osgeo/lib/python3.7/site-packages
ENV export GISBASE LOCATION GRASS_PROJSHARE LD_LIBRARY_PATH PATH PYTHONPATH

# data directory - not using the base images volume because then the permissions cannot be adapted
ENV DATA_DIR /data

# Set gcc/g++ environmental variables for GRASS GIS compilation, without debug symbols
ENV MYCFLAGS "-O2 -std=gnu99 -m64"
ENV MYLDFLAGS "-s"
# CXX stuff:
ENV LD_LIBRARY_PATH "/usr/local/lib"
ENV LDFLAGS "$MYLDFLAGS"
ENV CFLAGS "$MYCFLAGS"
ENV CXXFLAGS "$MYCXXFLAGS"

# Update library paths
RUN echo "Updating library paths" && \
    cd /etc/ld.so.conf.d && \
    echo "/opt/osgeo/lib" >> osgeo.conf && \
    echo "/opt/osgeo/lib64" >> osgeo.conf && \
    echo "/opt/osgeo/grass-8.2.0/lib" >> grass.conf && \
    ldconfig

# SAGA-GIS dependencies
RUN apt-get install ibwxgtk3.0-gtk3-dev libtiff5-dev \
    libexpat1-dev wx-common libogdi-dev unixodbc-dev

# Run the Makefile for PROJ GEOS, GDAL-OGR, GRASS, SAGA-GIS - this will take a long time
RUN cd /tmp && make -f gis_dependency.makefile

# Reduce the image size
RUN apt-get autoremove -y
RUN apt-get clean -y

# set SHELL var to avoid /bin/sh fallback in interactive GRASS GIS sessions in docker
ENV SHELL /bin/bash

# declare data volume late so permissions apply
VOLUME $DATA_DIR
WORKDIR $DATA_DIR

# once everything is built, we can install the GRASS extensions
RUN export LC_ALL=en_US.UTF-8 && \
    	export LANG=en_US.UTF-8 && \
    	export PATH=/opt/osgeo/bin:/opt/osgeo/grass-8.2.0/bin:/opt/osgeo/grass-8.2.0/scripts/:$PATH && \
    	export GISBASE=/opt/osgeo/grass-8.2.0 && \
    	rm -rf mytmp_wgs84 && \
    	grass72 -text -c epsg:3857 ${PWD}/mytmp_wgs84 -e && \
    	echo "g.extension -s extension=r.sun.mp ; g.extension -s extension=r.sun.hourly ; g.extension -s extension=r.sun.daily" | grass72 -text ${PWD}/mytmp_wgs84/PERMANENT

############## GIS Build Finished ##############

# add /cvmfs and /work directory for later OSG reintegration
RUN mkdir /cvmfs /work 

RUN addgroup jovyan
RUN usermod -aG jovyan jovyan

USER jovyan
WORKDIR /home/jovyan
EXPOSE 8888

COPY entry.sh /bin
RUN mkdir -p /home/jovyan/.irods

ENTRYPOINT ["bash", "/bin/entry.sh"]