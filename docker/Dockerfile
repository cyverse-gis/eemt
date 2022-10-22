FROM harbor.cyverse.org/vice/jupyter/datascience:latest

# Build-time metadata as defined at http://label-schema.org
ARG BUILD_DATE
ARG VCS_REF
ARG VERSION
LABEL org.label-schema.build-date=$BUILD_DATE \
      org.label-schema.name="EEMT Jupyter" \
      org.label-schema.description="PROJ GDAL SAGA-GIS with Makeflow" \
      org.label-schema.url="https://tyson-swetnam.github.io/eemt" \
      org.label-schema.vcs-ref=$VCS_REF \
      org.label-schema.vcs-url="e.g. https://github.com/tyson-swetnam/eemt" \
      org.label-schema.vendor="CyVerse" \
      org.label-schema.version=$VERSION \
      org.label-schema.schema-version="1.0.0"

USER root
ENV DEBIAN_FRONTEND noninteractive

# Install CCTOOLS from GitHub
RUN apt-get install -y git libperl-dev ca-certificates
RUN cd /tmp && git clone https://github.com/cooperative-computing-lab/cctools.git -v
RUN cd /tmp/cctools && \
    ./configure --prefix=/opt/eemt --with-zlib-path=/usr/lib/x86_64-linux-gnu && \
    make clean && \
    make install && \
    export PATH=$PATH:/opt/eemt

#remove build to reduce contianer size
RUN rm -rf /tmp/cctools

COPY /docker/gis_dependency.makefile /tmp/

ENV GISBASE=/opt/osgeo/grass-7.2.2
ENV LOCATION=/usr/local/share/grassdata/eemt/PERMANENT
ENV GRASS_PROJSHARE=/usr/share/proj
ENV LD_LIBRARY_PATH=/opt/osgeo/lib:/opt/osgeo/grass-7.2.2/lib
ENV PATH=/opt/osgeo/bin:/opt/osgeo/grass-7.2.2/bin:$PATH
ENV PYTHONPATH=/opt/osgeo/lib/python3.6/site-packages
ENV export GISBASE LOCATION GRASS_PROJSHARE LD_LIBRARY_PATH PATH PYTHONPATH

# data directory - not using the base images volume because then the permissions cannot be adapted
ENV DATA_DIR /data

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

# Run the Makefile for PROJ GEOS, GDAL-OGR, GRASS, SAGA-GIS - this will take a long time
# https://github.com/OSGeo/grass/blob/main/INSTALL.md 
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
    	export PATH=/opt/osgeo/bin:/opt/osgeo/grass-7.2.2/bin:/opt/osgeo/grass-7.2.2/scripts/:$PATH && \
    	export GISBASE=/opt/osgeo/grass-7.2.2 && \
    	rm -rf mytmp_wgs84 && \
    	grass72 -text -c epsg:3857 ${PWD}/mytmp_wgs84 -e && \
    	echo "g.extension -s extension=r.sun.mp ; g.extension -s extension=r.sun.hourly ; g.extension -s extension=r.sun.daily" | grass72 -text ${PWD}/mytmp_wgs84/PERMANENT

# add /cvmfs and /work directory for OSG integration
RUN mkdir /cvmfs /work 