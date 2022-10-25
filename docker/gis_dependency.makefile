##!/usr/bin/make

## Latest update 2022-10-25

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
$(TARGET)/lib/libproj.so:
	(cd build-dir \
	 && wget $(WGET_FLAGS) http://download.osgeo.org/proj/proj-9.1.0.tar.gz \
	 && tar -xjf proj-9.1.0.tar.gz \
	 && cd proj-9.1.0 \
	 && ./configure --prefix=$(TARGET) --enable-python \
	 && make -j 2 \
	 && make install)

##geos 
$(TARGET)/lib/libgeos.so:
	(cd build-dir \
	 && wget $(WGET_FLAGS) http://download.osgeo.org/geos/geos-3.9.3.tar.bz2 \
	 && tar -xjf geos-3.9.3.tar.bz2 \
	 && cd geos-3.9.3 \
	 && ./configure --prefix=$(TARGET) --enable-python \
	 && make -j 2 \
	 && make install)

##gdal
$(TARGET)/bin/gdalinfo: $(TARGET)/lib/libgeos.so
	(cd build-dir \
	 && wget $(WGET_FLAGS) http://download.osgeo.org/gdal/3.4.3/gdal-3.4.3.tar.gz \
	 && tar xzf gdal-3.4.3.tar.gz \
	 && cd gdal-3.4.3 \
	 && ./configure --prefix=$(TARGET) --without-grass --with-netcdf --with-python --with-hdf5 --with-geos=$(TARGET)/bin/geos-config \
	 && make -j 2 \
	 && make install)

##GRASS-GIS
$(TARGET)/bin/grass82: $(TARGET)/bin/gdalinfo
	(cd build-dir \
	 && wget $(WGET_FLAGS) https://grass.osgeo.org/grass82/source/grass-8.2.0.tar.gz \
	 && tar xzf grass-8.2.0.tar.gz \
	 && cd grass-8.2.0 \
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
	 && (make -j 2 || make -j 2 || make -j 2) \
	 && make install && ldconfig)

##GDAL_GRASS 
$(TARGET)/lib/gdalplugins/gdal_GRASS.so: $(TARGET)/bin/grass82 $(TARGET)/bin/gdalinfo
        (cd build-dir \
         && wget $(WGET_FLAGS) http://download.osgeo.org/gdal/3.4.3/gdal-grass-3.4.3.tar.gz \
         && tar xzf gdal-grass-3.4.3.tar.gz \
         && cd gdal-grass-3.4.3 \
         && export LDFLAGS="-L$(TARGET)/grass-8.2.0/lib" \
         && ./configure --with-gdal=$(TARGET)/bin/gdal-config --with-grass=$(TARGET)/grass-8.2.0 --prefix=$(TARGET) \
         && make -j 2 \
         && make install)

 ##SAGA-GIS
 $(TARGET)/bin/saga-gis: $(TARGET)/bin/grass82 $(TARGET)/lib/gdalplugins/gdal_GRASS.so
        (cd build-dir \
        && wget $(WGET_FLAGS) 'https://master.dl.sourceforge.net/project/saga-gis/SAGA%20-%208/SAGA%20-%208.4.0/saga-8.4.0.tar.gz' \
        && tar xzf saga-8.4.0.tar.gz \
        && cd saga-8.4.0 \
        && ./configure --prefix=$(TARGET) --disable-odbc \
        && make -j 2 \
        && make install)
