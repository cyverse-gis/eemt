FROM ubuntu:18.04

LABEL authors="Tyson L Swetnam, Mats Rynge"
LABEL maintainer="tswetnam@cyverse.org"

# Dont forget to copy the gis_dependency.makefile into the directory
USER root
COPY /docker/gis_dependency.makefile /tmp/

ENV DEBIAN_FRONTEND noninteractive
ENV GISBASE=/opt/osgeo/grass-7.2.2
ENV LOCATION=/usr/local/share/grassdata/eemt/PERMANENT
ENV GRASS_PROJSHARE=/usr/share/proj
ENV LD_LIBRARY_PATH=/opt/osgeo/lib:/opt/osgeo/grass-7.2.2/lib
ENV PATH=/opt/osgeo/bin:/opt/osgeo/grass-7.2.2/bin:$PATH
ENV PYTHONPATH=/opt/osgeo/lib/python3.6/site-packages
ENV export GISBASE LOCATION GRASS_PROJSHARE LD_LIBRARY_PATH PATH PYTHONPATH

# data directory - not using the base images volume because then the permissions cannot be adapted
ENV DATA_DIR /data

CMD echo 'deb http://us.archive.ubuntu.com/ubuntu/ bionic main restricted universe multiverse' >> /etc/apt/sources.list

# GRASS GIS compile dependencies
RUN apt-get update \
	&& apt-get install -y --no-install-recommends --no-install-suggests \
	apt-utils \
	bash-completion \
	build-essential \
	libblas-dev \
	libbz2-dev \
	libcairo2-dev \
	libfftw3-dev \
	libfreetype6-dev \
	libgdal-dev \
	libgeos-dev \
	libglu1-mesa-dev \
	libgsl0-dev \
	libjpeg-dev \
	liblapack-dev \
	liblas-dev \
	liblas-c-dev \
	libncurses5-dev \
	libnetcdf-dev \
	libopenjp2-7 \
	libopenjp2-7-dev \
	libpdal-dev pdal \
	libpdal-plugin-python \
	libpng-dev \
	libpq-dev \
	libproj-dev \
	libreadline-dev \
	libsqlite3-dev \
	libtiff-dev \
	libxmu-dev \
	libzstd-dev \
	bison \
	flex \
	g++ \
	gettext \
	gdal-bin \
	libfftw3-bin \
	make \
	ncurses-bin \
	netcdf-bin \
	postgresql \
	proj-bin \
	proj-data \
	python \
	python-dev \
	python-numpy \
	python-pil \
	python-ply \
	sqlite3 \
	subversion \
	swig \
	unixodbc-dev \
	wget \
	zlib1g-dev \
	&& apt-get autoremove \
	&& apt-get clean

RUN echo LANG="en_US.UTF-8" > /etc/default/locale
ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8

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
    echo "/opt/osgeo/grass-7.2.2/lib" >> grass.conf && \
    ldconfig

# Run the Makefile for GEOS, GDAL, GRASS, SAGA-GIS - this will take a long time
RUN cd /tmp && make -f gis_dependency.makefile

# Reduce the image size
RUN apt-get autoremove -y
RUN apt-get clean -y

# set SHELL var to avoid /bin/sh fallback in interactive GRASS GIS sessions in docker
ENV SHELL /bin/bash

# declare data volume late so permissions apply
VOLUME $DATA_DIR
WORKDIR $DATA_DIR

# Install CCTOOLS from Github
RUN apt-get install -y git libperl-dev ca-certificates
RUN cd /tmp && git clone https://github.com/cooperative-computing-lab/cctools.git -v
RUN cd /tmp/cctools && \
    ./configure --prefix=/opt/eemt --with-zlib-path=/usr/lib/x86_64-linux-gnu && \
    make clean && \
    make install && \
    export PATH=$PATH:/opt/eemt
#remove build to reduce contianer size
RUN rm -rf /tmp/cctools

# once everything is built, we can install the GRASS extensions
RUN export LC_ALL=en_US.UTF-8 && \
    	export LANG=en_US.UTF-8 && \
    	export PATH=/opt/osgeo/bin:/opt/osgeo/grass-7.2.2/bin:/opt/osgeo/grass-7.2.2/scripts/:$PATH && \
    	export GISBASE=/opt/osgeo/grass-7.2.2 && \
    	rm -rf mytmp_wgs84 && \
    	grass72 -text -c epsg:3857 ${PWD}/mytmp_wgs84 -e && \
    	echo "g.extension -s extension=r.sun.mp ; g.extension -s extension=r.sun.hourly ; g.extension -s extension=r.sun.daily" | grass72 -text ${PWD}/mytmp_wgs84/PERMANENT

# add /cvmfs and /work directory for OSG integration
RUN mkdir /cvmfs /work 

# Add a few dependecies for installing iCommands
RUN apt-get update \
    && apt-get install -y lsb libfuse2 libssl1.0 wget

# Install iCommands
RUN wget https://files.renci.org/pub/irods/releases/4.1.12/ubuntu14/irods-icommands-4.1.12-ubuntu14-x86_64.deb && \
    dpkg -i irods-icommands-4.1.12-ubuntu14-x86_64.deb && \
    rm irods-icommands-4.1.12-ubuntu14-x86_64.deb
# Add the iRODS environment
RUN mkdir -p /home/${USER}/.irods
ADD irods_environment.json /home/${USER}/.irods/irods_environment.json
