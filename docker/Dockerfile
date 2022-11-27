FROM mundialis/grass-py3-pdal:releasebranch_8_2-ubuntu
# image from https://github.com/OSGeo/grass/tree/main/docker
# THANK YOU 4 EVER OSGEO!

# Set the SH shell to use BASH
RUN rm /bin/sh && ln -s /bin/bash /bin/sh

# Build-time metadata as defined at http://label-schema.org
ARG BUILD_DATE
ARG VCS_REF
ARG VERSION
LABEL org.label-schema.build-date=$BUILD_DATE \
      org.label-schema.name="EEMT" \
      org.label-schema.description="GRASS PY3 with PDAL CCTOOLS Conda" \
      org.label-schema.url="https://tyson-swetnam.github.io/eemt" \
      org.label-schema.vcs-ref=$VCS_REF \
      org.label-schema.vcs-url="e.g. https://github.com/tyson-swetnam/eemt" \
      org.label-schema.vendor="CyVerse" \
      org.label-schema.version=$VERSION \
      org.label-schema.schema-version="1.0.0"

USER root
ENV DEBIAN_FRONTEND noninteractive

# data directory - not using the base images volume because then the permissions cannot be adapted
ENV DATA_DIR /data

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
RUN apt update && apt install locales && \
    locale-gen en_US.UTF-8 && \
    dpkg-reconfigure locales
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

# Reduce the image size
RUN apt-get autoremove -y
RUN apt-get clean -y

# set SHELL var to avoid /bin/sh fallback in interactive GRASS GIS sessions in docker
ENV SHELL /bin/bash

# declare data volume late so permissions apply
VOLUME $DATA_DIR
WORKDIR $DATA_DIR

# once everything is built, we can install the GRASS extensions
RUN grass --text -c epsg:3857 /home/jovyan/mytmp_wgs84 -e && \
    	echo "g.extension -s extension=r.sun.mp ; g.extension -s extension=r.sun.hourly ; g.extension -s extension=r.sun.daily" | grass --text /home/jovyan/mytmp_wgs84/PERMANENT

############## GIS Build Finished ##############

RUN usermod -aG jovyan jovyan

# Create Conda environment for CCTOOLS & Jupyter Notebooks
RUN apt-get update && apt-get install -y nodejs npm
USER jovyan
RUN conda update conda 
RUN conda config --add channels conda-forge
RUN conda config --set channel_priority strict
RUN conda install mamba
RUN mamba install -c conda-forge jupyterlab

COPY environment.yml /home/jovyan/ 
RUN mamba env create -f /home/jovyan/environment.yml
RUN echo ". /opt/conda/etc/profile.d/conda.sh" >> /home/jovyan/.bashrc && \
    echo "conda deactivate" >> /home/jovyan/.bashrc && \
    echo "conda activate eemt" >> /home/jovyan/.bashrc
RUN . /opt/conda/etc/profile.d/conda.sh && conda activate eemt && python -m ipykernel install --user --name eemt 
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

# add /cvmfs and /work directory for later OSG reintegration
RUN sudo mkdir /cvmfs /work 
RUN sudo chown -R jovyan:jovyan /cvmfs
RUN sudo chown -R jovyan:jovyan /work

USER jovyan
WORKDIR /home/jovyan
EXPOSE 8888

COPY entry.sh /bin
RUN mkdir -p /home/jovyan/.irods

ENTRYPOINT ["bash", "/bin/entry.sh"]