FROM ubuntu:20.04

LABEL authors="Tyson L Swetnam"
LABEL maintainer="tswetnam@cyverse.org"

# system environment
ENV DEBIAN_FRONTEND noninteractive

# data directory - not using the base images volume because then the permissions cannot be adapted
ENV DATA_DIR /data

# GRASS GIS compile dependencies

RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y software-properties-common build-essential

# be sure to have an updated system
RUN apt-get update && apt-get upgrade -y

# install PROJ
RUN apt-get install libproj-dev proj-data proj-bin -y

# install GEOS
RUN apt-get install libgeos-dev -y

# install GDAL
RUN apt-get install libgdal-dev python3-gdal gdal-bin -y

# install PDAL (optional)
RUN apt-get install libpdal-dev pdal libpdal-plugin-python -y

# recommended to give Python3 precedence over Python2 (which is end-of-life since 2019)
RUN update-alternatives --install /usr/bin/python python /usr/bin/python3.8 1

RUN apt-get install \
  flex make bison gcc libgcc1 g++ cmake ccache \
  python3 python3-dev \
  python3-opengl \
  python-wxversion python-wxtools python3-wxgtk4.0 \
  python3-dateutil libgsl-dev python3-numpy \
  wx3.0-headers wx-common  libwxgtk3.0-gtk3-dev \
  libwxbase3.0-dev   \
  libncurses5-dev \
  libbz2-dev \
  zlib1g-dev gettext \
  libtiff5-dev libpnglite-dev \
  libcairo2 libcairo2-dev \
  sqlite3 libsqlite3-dev \
  libpq-dev \
  libreadline6-dev libfreetype6-dev \
  libfftw3-3 libfftw3-dev \
  libboost-thread-dev libboost-program-options-dev  libpdal-dev\
  subversion libzstd-dev \
  checkinstall \
  libglu1-mesa-dev libxmu-dev \
  ghostscript wget -y

RUN apt-get autoremove \
    && apt-get clean && \
    mkdir -p $DATA_DIR

RUN echo LANG="en_US.UTF-8" > /etc/default/locale
ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8

# Download the GRASS Github Repo
RUN mkdir -p /code/grass

# add GRASS source repository files to the image
RUN wget -nv --no-check-certificate https://grass.osgeo.org/grass78/source/grass-7.8.3.tar.gz \
	 && tar xzf grass-7.8.3.tar.gz -C /code/grass --strip-components=1

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
ENV NUMTHREADS=4
RUN cd /code/grass && ./configure \
  --with-cxx \
  --enable-largefile \
  --with-proj --with-proj-share=/usr/share/proj \
  --with-gdal=/usr/bin/gdal-config \
  --with-python \
  --with-geos \
  --with-sqlite \
  --with-nls \
  --with-zstd \
#  --with-liblas \
  --with-pdal \
  --with-cairo --with-cairo-ldflags=-lfontconfig \
  --with-freetype=yes --with-freetype-includes="/usr/include/freetype2/" \
  --with-wxwidgets \
  --with-fftw \
  --with-motif \
  --with-opengl-libs=/usr/include/GL \
  --with-postgres=yes --with-postgres-includes="/usr/include/postgresql" \
  --with-netcdf \
  --without-mysql \
  --with-odbc \
  --with-openmp \
  --without-ffmpeg \
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
RUN grass78 -text -c epsg:3857 ${PWD}/mytmp_wgs84 -e && \
    echo "g.extension -s extension=r.sun.mp ; g.extension -s extension=r.sun.hourly ; g.extension -s extension=r.sun.daily" | grass78 -text ${PWD}/mytmp_wgs84/PERMANENT

# Install SAGA-GIS
RUN apt-get install -y software-properties-common && \
    add-apt-repository ppa:ubuntugis/ubuntugis-unstable && \
    apt-get -y update && \
    apt-get install -y saga

RUN echo "Updating library paths" && \
    cd /etc/ld.so.conf.d && \
    echo "/opt/eemt/lib" >eemt.conf && \
    echo "/opt/eemt/lib64" >>eemt.conf && \
    echo "/opt/eemt/grass-7.8.3/lib" >grass.conf && \
    ldconfig

# Install CC Tools
RUN apt-get install -y swig gcc 
RUN cd && wget http://ccl.cse.nd.edu/software/files/cctools-7.1.7-source.tar.gz && \
    tar xvzf cctools-7.1.7-source.tar.gz && cd cctools-7.1.7-source && \
    ./configure --prefix /opt/eemt && \
    make && \
    make install

USER grass

CMD ["/usr/local/bin/grass", "--version"]
