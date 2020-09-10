FROM centos:7

LABEL authors="Tyson L Swetnam"
LABEL maintainer="tswetnam@cyverse.org"

# system environment
ENV DEBIAN_FRONTEND noninteractive

# data directory - not using the base images volume because then the permissions cannot be adapted
ENV DATA_DIR /data

RUN yum update && yum install epel-release -y
RUN yum install flex bison make zlib-devel gcc-c++ gettext \
             sqlite-devel mesa-libGL-devel mesa-libGLU-devel \
             libXmu-devel libX11-devel fftw-devel libtiff-devel \
             lesstif-devel python-devel numpy wxPython wxGTK-devel \
             proj proj-devel proj-epsg proj-nad libxml2 gdal gdal-devel geos geos-devel \
             netcdf netcdf-devel blas-devel lapack-devel atlas-devel \
             python python-dateutil python-imaging python-matplotlib python-sphinx \
             doxygen subversion wget libiodbc -y

RUN echo LANG="en_US.UTF-8" > /etc/default/locale
ENV LANG en_US.UTF-8
ENV LC_ALL C

# Download the GRASS Github Repo
RUN mkdir -p /code/grass

# add GRASS source repository files to the image
RUN wget -nv --no-check-certificate https://grass.osgeo.org/grass78/source/grass-7.8.3.tar.gz \
	 && tar xzf grass-7.8.3.tar.gz -C /code/grass --strip-components=1


# Set gcc/g++ environmental variables for GRASS GIS compilation, without debug symbols
ENV MYCFLAGS "-O2 -std=gnu99 -m64"
ENV MYLDFLAGS "-s"
# CXX stuff:
ENV LD_LIBRARY_PATH "/usr/local/lib"
ENV LDFLAGS "$MYLDFLAGS"
ENV CFLAGS "$MYCFLAGS"
ENV CXXFLAGS "$MYCXXFLAGS"

# Configure, compile and install GRASS GIS
ENV NUMTHREADS=4
RUN cd /code/grass && ./configure \
  --with-cxx \
  --enable-largefile \
  --with-proj --with-proj-share=/usr/share/proj \
  --with-gdal=/usr/bin/gdal-config \
  --without-python \
  --with-geos \
  --without-sqlite \
  --with-nls \
  --without-zstd \
  --without-liblas \
  --without-pdal \
  --with-cairo --with-cairo-ldflags=-lfontconfig \
  --with-freetype=yes --with-freetype-includes="/usr/include/freetype2/" \
  --with-wxwidgets \
  --without-fftw \
  --without-motif \
  --with-opengl-libs=/usr/include/GL \
  --without-postgresql \
#  --with-postgres=yes --with-postgres-includes="/usr/include/postgresql" \
  --with-netcdf \
  --without-mysql \
  --without-odbc \
  --with-openmp \
  --without-ffmpeg \
  --enable-64bit \
    && make -j $NUMTHREADS && make install && ldconfig
   
# enable simple grass command regardless of version number
RUN ln -s /usr/local/bin/grass* /usr/local/bin/grass

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
RUN grass78 -text -c epsg:3857 ${PWD}/mytmp_wgs84 -e && \
    echo "g.extension -s extension=r.sun.mp ; g.extension -s extension=r.sun.hourly ; g.extension -s extension=r.sun.daily" | grass78 -text ${PWD}/mytmp_wgs84/PERMANENT

RUN echo "Updating library paths" && \
    cd /etc/ld.so.conf.d && \
    echo "/opt/eemt/lib" >eemt.conf && \
    echo "/opt/eemt/lib64" >>eemt.conf && \
    echo "/opt/eemt/grass-7.8.3/lib" >grass.conf && \
    ldconfig

# Install CC Tools
RUN cd && wget http://ccl.cse.nd.edu/software/files/cctools-7.1.7-source.tar.gz && \
    tar xvzf cctools-7.1.7-source.tar.gz && cd cctools-7.1.7-source && \
    ./configure --prefix /opt/eemt && \
    make && \
    make install

USER grass

CMD ["/usr/local/bin/grass", "--version"]
