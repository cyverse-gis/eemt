##!/usr/bin/make

TARGET := /opt/osgeo

SHELL := /bin/bash

export PATH := $(TARGET)/bin:$(PATH)
export CPPFLAGS := -I$(TARGET)/include
export CFLAGS := -fPIC
export CXXFLAGS := -fPIC
export LDFLAGS := -L$(TARGET)/lib
export LD_LIBRARY_PATH := $(TARGET)/lib:$(TARGET)/grass/lib

WGET_FLAGS := -nv --no-check-certificate

.PHONY: all setup

# list base packages as well as top level goals
all: setup $(TARGET)/lib/gdalplugins/gdal_GRASS.so $(TARGET)/bin/saga-gis

setup:
	@rm -rf build-dir
	@mkdir build-dir

##proj


##geos 

$(TARGET)/lib/libgeos.so:
	(cd build-dir \
	 && wget $(WGET_FLAGS) http://download.osgeo.org/geos/geos-3.6.3.tar.bz2 \
	 && tar -xjf geos-3.6.3.tar.bz2 \
	 && cd geos-3.6.3 \
	 && ./configure --prefix=$(TARGET) --enable-python \
	 && make -j 12 \
	 && make install)

##gdal
$(TARGET)/bin/gdalinfo: $(TARGET)/lib/libgeos.so
	(cd build-dir \
	 && wget $(WGET_FLAGS) http://download.osgeo.org/gdal/2.2.1/gdal-2.2.1.tar.gz \
	 && tar xzf gdal-2.2.1.tar.gz \
	 && cd gdal-2.2.1 \
	 && ./configure --prefix=$(TARGET) --without-grass --with-netcdf --with-python --with-hdf5 --with-geos=$(TARGET)/bin/geos-config \
	 && make -j 12 \
	 && make install)

##GRASS
$(TARGET)/bin/grass72: $(TARGET)/bin/gdalinfo
	(cd build-dir \
	 && wget $(WGET_FLAGS) https://grass.osgeo.org/grass72/source/grass-7.2.2.tar.gz \
	 && tar xzf grass-7.2.2.tar.gz \
	 && cd grass-7.2.2 \
	 && export LDFLAGS="-Wl,-rpath,$(TARGET)/lib -lpthread" \
	 && ./configure --enable-64bit \
	 --enable-largefile \
	 --with-nls \
	 --with-readline \
	 --with-bzlib \
         --with-zstd \
	 --with-cairo --with-cairo-ldflags=-lfontconfig \
	 --with-fftw \
	 --with-liblas --with-liblas-config=/user/bin/liblas-config \
         --without-pdal \
	 --prefix=$(TARGET) \
	 --with-libs=$(TARGET)/lib \
	 --with-proj --with-proj-share=/usr/share/proj \
	 --with-gdal=$(TARGET) \
	 --with-cxx \
	 --without-fftw \
	 --without-python \
	 --with-geos=$(TARGET)/bin \
	 --with-libs=$(TARGET)/lib \
	 --with-postgres --with-postgres-includes="/usr/include/postgresql" \
	 --with-opengl-libs=/usr/include/GL \
	 --with-netcdf \
	 --without-tcltk \
	 --with-sqlite \
	 --with-freetype --with-freetype-includes="/usr/include/freetype2/" \
	 --with-openmp \
	 && (make -j 12 || make -j 12 || make -j 12) \
	 && make install && ldconfig)

##GDAL_GRASS 
$(TARGET)/lib/gdalplugins/gdal_GRASS.so: $(TARGET)/bin/grass72 $(TARGET)/bin/gdalinfo
        (cd build-dir \
         && wget $(WGET_FLAGS) http://download.osgeo.org/gdal/2.2.1/gdal-grass-2.2.1.tar.gz \
         && tar xzf gdal-grass-2.2.1.tar.gz \
         && cd gdal-grass-2.2.1 \
         && export LDFLAGS="-L$(TARGET)/grass-7.2.2/lib" \
         && ./configure --with-gdal=$(TARGET)/bin/gdal-config --with-grass=$(TARGET)/grass-7.2.2 --prefix=$(TARGET) \
         && make -j 12 \
         && make install)

 ##SAGA-GIS
 $(TARGET)/bin/saga-gis: $(TARGET)/bin/grass72 $(TARGET)/lib/gdalplugins/gdal_GRASS.so
        (cd build-dir \
        && wget $(WGET_FLAGS) 'https://superb-sea2.dl.sourceforge.net/project/saga-gis/SAGA%20-%207/SAGA%20-%203.0.0/saga-3.0.0.tar.gz' \
        && tar xzf saga-3.0.0.tar.gz \
        && cd saga-3.0.0 \
        && ./configure --prefix=$(TARGET) --disable-odbc \
        && make -j 12 \
        && make install)
