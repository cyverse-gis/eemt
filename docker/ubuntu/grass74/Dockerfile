FROM ubuntu:18.04

LABEL authors="Tyson L Swetnam"
LABEL maintainer="tswetnam@cyverse.org"

# system environment
ENV DEBIAN_FRONTEND noninteractive

# data directory - not using the base images volume because then the permissions cannot be adapted
ENV DATA_DIR /data

# GRASS GIS compile dependencies
RUN apt-get update \
    && apt-get install -y --no-install-recommends --no-install-suggests \
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
	git \
        libfftw3-bin \
        make \
        ncurses-bin \
        netcdf-bin \
        proj-bin \
        proj-data \
        python \
        python-dev \
        python-numpy \
        python-pil \
        python-ply \
        python-requests \
        sqlite3 \
        subversion \
        wget \
	unixodbc-dev \
        zlib1g-dev \
    && apt-get autoremove \
    && apt-get clean && \
    mkdir -p $DATA_DIR

RUN echo LANG="en_US.UTF-8" > /etc/default/locale
ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8

# Download the GRASS Github Repo
RUN mkdir -p /code/grass

# add GRASS source repository files to the image
RUN wget -nv --no-check-certificate https://grass.osgeo.org/grass74/source/grass-7.4.4.tar.gz \
	 && tar xzf grass-7.4.4.tar.gz -C /code/grass --strip-components=1

WORKDIR /code/grass

# Set gcc/g++ environmental variables for GRASS GIS compilation, without debug symbols
ENV MYCFLAGS "-O2 -std=gnu99 -m64"
ENV MYLDFLAGS "-s"
# CXX stuff:
ENV LD_LIBRARY_PATH "/usr/local/lib"
ENV LDFLAGS "$MYLDFLAGS"
ENV CFLAGS "$MYCFLAGS"
ENV CXXFLAGS "$MYCXXFLAGS"

# Configure, compile and install GRASS GIS
ENV NUMTHREADS=14
RUN cd /code/grass && ./configure \
    --enable-largefile \
    --with-cxx \
    --with-nls \
    --with-readline \
    --with-sqlite \
    --with-bzlib \
    --with-zstd \
    --with-cairo --with-cairo-ldflags=-lfontconfig \
    --with-freetype --with-freetype-includes="/usr/include/freetype2/" \
    --with-fftw \
    --with-netcdf \
    --with-pdal \
    --with-proj --with-proj-share=/usr/share/proj \
    --with-geos=/usr/bin/geos-config \
    --with-postgres --with-postgres-includes="/usr/include/postgresql" \
    --with-opengl-libs=/usr/include/GL \
    --with-openmp \
    --enable-64bit \
    && make -j $NUMTHREADS && make install && ldconfig
   
# enable simple grass command regardless of version number
RUN ln -s /usr/local/bin/grass* /usr/local/bin/grass

# Reduce the image size
RUN apt-get autoremove -y
RUN apt-get clean -y

# set SHELL var to avoid /bin/sh fallback in interactive GRASS GIS sessions in docker
ENV SHELL /bin/bash

# Fix permissions
RUN chmod -R a+rwx $DATA_DIR

# create a user
RUN useradd -m -U grass

# declare data volume late so permissions apply
VOLUME $DATA_DIR
WORKDIR $DATA_DIR

# Further reduce the docker image size 
RUN rm -rf /code/grass

# once everything is built, we can install the GRASS extensions
RUN grass74 -text -c epsg:3857 ${PWD}/mytmp_wgs84 -e && \
    echo "g.extension -s extension=r.sun.mp ; g.extension -s extension=r.sun.hourly ; g.extension -s extension=r.sun.daily" | grass74 -text ${PWD}/mytmp_wgs84/PERMANENT

# Install CCTOOLS from Github
RUN apt-get install -y git libperl-dev ca-certificates
RUN cd /tmp && git clone https://github.com/cooperative-computing-lab/cctools.git -v
RUN cd /tmp/cctools && \
    ./configure --prefix=/opt/eemt --with-zlib-path=/usr/lib/x86_64-linux-gnu && \
    make clean && \
    make install && \
    export PATH=$PATH:/opt/eemt

#remove build dir to reduce contianer size
RUN rm -rf /tmp/cctools

# Install SAGA-GIS
RUN apt-get install -y software-properties-common && \
    add-apt-repository ppa:ubuntugis/ubuntugis-unstable && \
    apt-get -y update && \
    apt-get install -y saga
#Switch User
USER grass

CMD ["/usr/local/bin/grass", "--version"]
