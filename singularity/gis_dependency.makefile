##!/usr/bin/make


TARGET := /opt/eemt

SHELL := /bin/bash

export PATH := $(TARGET)/bin:$(PATH)
export CPPFLAGS := -I$(TARGET)/include
export CFLAGS := -fPIC
export CXXFLAGS := -fPIC
export LDFLAGS := -L$(TARGET)/lib
export LD_LIBRARY_PATH := $(TARGET)/lib:$(TARGET)/grass-7.2.1/lib

WGET_FLAGS := -nv --no-check-certificate

.PHONY: all setup


# list base packages as well as top level goals
all: setup $(TARGET)/lib/gdalplugins/gdal_GRASS.so $(TARGET)/bin/saga-gis


setup:
	@rm -rf build-dir
	@mkdir build-dir

##geos
$(TARGET)/lib/libgeos.so:
	(cd build-dir \
	 && wget $(WGET_FLAGS) http://download.osgeo.org/geos/geos-3.5.0.tar.bz2 \
	 && tar -xjf geos-3.5.0.tar.bz2 \
	 && cd geos-3.5.0 \
	 && ./configure --prefix=$(TARGET) --enable-python \
	 && make \
	 && make install)

##gdal
$(TARGET)/bin/gdalinfo: $(TARGET)/lib/libgeos.so
	(cd build-dir \
	 && wget $(WGET_FLAGS) http://download.osgeo.org/gdal/2.2.1/gdal-2.2.1.tar.gz \
	 && tar xzf gdal-2.2.1.tar.gz \
	 && cd gdal-2.2.1 \
	 && ./configure --prefix=$(TARGET) --without-grass --with-netcdf --with-python --with-hdf5 --with-geos=$(TARGET)/bin/geos-config \
	 && make \
	 && make install)


##GRASS
$(TARGET)/bin/grass72: $(TARGET)/bin/gdalinfo
	(cd build-dir \
	 && wget $(WGET_FLAGS) https://grass.osgeo.org/grass72/source/grass-7.2.1.tar.gz \
	 && tar xzf grass-7.2.1.tar.gz \
	 && cd grass-7.2.1 \
	 && export LDFLAGS="-Wl,-rpath,$(TARGET)/lib -lpthread" \
	 && ./configure --enable-64bit --prefix=$(TARGET) --with-libs=$(TARGET)/lib --with-proj-share=/usr/share/proj --with-gdal=$(TARGET)  --with-cxx --without-fftw --without-python --with-geos=$(TARGET)/bin --with-libs=$(TARGET)/lib -with-opengl=no --with-netcdf --without-tcltk --with-sqlite=yes --with-freetype=yes --with-freetype-includes="/usr/include/freetype2/" \
	 && (make || make || make) \
	 && make install)


##GDAL_GRASS
$(TARGET)/lib/gdalplugins/gdal_GRASS.so: $(TARGET)/bin/grass72 $(TARGET)/bin/gdalinfo
	(cd build-dir \
	 && wget $(WGET_FLAGS) http://download.osgeo.org/gdal/2.1.3/gdal-grass-2.1.3.tar.gz \
	 && tar xzf gdal-grass-2.1.3.tar.gz \
	 && cd gdal-grass-2.1.3 \
	 && export LDFLAGS="-L$(TARGET)/grass-7.2.1/lib" \
	 && ./configure --with-gdal=$(TARGET)/bin/gdal-config --with-grass=$(TARGET)/grass-7.2.1 --prefix=$(TARGET) \
	 && make \
	 && make install)


##Saga
$(TARGET)/bin/saga-gis: $(TARGET)/bin/grass72 $(TARGET)/lib/gdalplugins/gdal_GRASS.so
	(cd build-dir \
	 && wget $(WGET_FLAGS) 'http://downloads.sourceforge.net/project/saga-gis/SAGA%20-%203/SAGA%20-%203.0.0/saga_3.0.0.tar.gz' \
	 && tar xzf saga_3.0.0.tar.gz \
	 && cd saga-3.0.0 \
	 && ./configure --prefix=$(TARGET) --disable-odbc \
	 && make \
	 && make install)

