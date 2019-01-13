FROM ubuntu:bionic

# Dont forget to copy the gis_dependency.makefile into the directory
USER root
COPY gis_dependency.makefile /tmp/

ENV GISBASE=/opt/osgeo/grass-7.4.0
ENV GRASS_PROJSHARE=/usr/share/proj
ENV LD_LIBRARY_PATH=/opt/osgeo/lib:/opt/osgeo/grass-7.4.0/lib
ENV PATH=/opt/osgeo/bin:/opt/osgeo/grass-7.4.0/bin:$PATH
ENV PYTHONPATH=/opt/osgeo/lib/python3.6/site-packages
ENV export GISBASE GRASS_PROJSHARE LD_LIBRARY_PATH PATH PYTHONPATH

CMD echo 'deb http://us.archive.ubuntu.com/ubuntu/ bionic main restricted universe multiverse' >> /etc/apt/sources.list

# be sure to have an updated system
RUN apt-get -y update && apt-get -y upgrade

# install Ubuntu dependencies and Python
RUN apt-get install -f -y software-properties-common \
        apt-utils \
        bison \
        build-essential \
        flex \
        g++ \
        gcc \
        gettext \
        libcairo2 \
        libcairo2-dev \
        libcanberra-gtk-module \
        libcanberra-gtk3-module \
        libwxbase3.0-dev \
        libwxgtk3.0-dev \
        python-dev \
        python3-dev \
        python3-distutils \
        texlive-extra-utils \
        wget \
        wx3.0-headers \
        zlib1g-dev

# Install OSGEO dependencies
RUN apt-get install -f -y \
        gdal-bin \
        libgdal-dev \
        libgdal-doc \
        libgeos-dev \
        libproj-dev \
        netcdf-bin \
        proj-data \
        proj-bin \
        python-gdal 

# set locale (this fixes an error we had in GRASS environment on startup)
CMD locale-gen en_GB en_GB.UTF-8
CMD dpkg-reconfigure locales
CMD echo "LC_ALL=en_GB.UTF-8" >> /etc/environment
CMD echo "LANG=en_GB.UTF-8" >> /etc/environment

# Run the Makefile for GEOS, GDAL, GRASS, SAGA-GIS
RUN cd /tmp && make -f gis_dependency.makefile

CMD echo "Updating library paths"
CMD cd /etc/ld.so.conf.d
CMD echo "/opt/osgeo/lib" >> osgeo.conf
CMD echo "/opt/osgeo/lib64" >> osgeo.conf
CMD echo "/opt/osgeo/grass-7.4.0/lib" >> grass.conf
CMD ldconfig

# once everything is built, we can install the GRASS extensions
RUN export LC_ALL=en_US.UTF-8 && \
    export LANG=en_US.UTF-8 && \
    export PATH=/opt/osgeo/bin:/opt/osgeo/grass-7.4.0/bin:/opt/osgeo/grass-7.4.0/scripts/:$PATH && \
    export GISBASE=/opt/osgeo/grass-7.4.0 && \
    rm -rf mytmp_wgs84 && \
    grass74 -text -c epsg:3857 ${PWD}/mytmp_wgs84 -e && \
    echo "g.extension -s extension=r.sun.mp ; g.extension -s extension=r.sun.hourly ; g.extension -s extension=r.sun.daily" | grass74 -text ${PWD}/mytmp_wgs84/PERMANENT

# Install CCTOOLS from Github
RUN apt-get install -y git libperl-dev zlib1g-dev
RUN cd /tmp && git clone https://github.com/cooperative-computing-lab/cctools/
RUN cd /tmp/cctools && \
    ./configure --prefix=/opt/eemt --with-zlib-path=/usr/lib/x86_64-linux-gnu && \
    make clean && \
    make install && \
    export PATH=$PATH:/opt/eemt
