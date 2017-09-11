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


##PKD-Config
$(TARGET)/bin/pkg-config:
	(cd build-dir \
	 && wget $(WGET_FLAGS) https://pkg-config.freedesktop.org/releases/pkg-config-0.29.1.tar.gz \
	 && tar xzf pkg-config-0.29.1.tar.gz \
	 && cd pkg-config-0.29.1 \
	 && ./configure --with-internal-glib --prefix=$(TARGET) \
	 && make install)

##mesa
$(TARGET)/bin/mesa:
	(cd build-dir \
	 && wget ftp://ftp.freedesktop.org/pub/mesa/mesa-17.0.0.tar.gz \
	 && tar xf mesa-17.0.0.tar.gz \
	 && cd mesa-17.0.0\
	 && ./configure --prefix=$(TARGET) \
	 && make install)

##python 3.5
#$(TARGET)/bin/python3: $(TARGET)/bin/pkg-config $(TARGET)/lib/libsqlite3.a
#	(cd build-dir \
#	 && wget https://www.python.org/ftp/python/3.5.2/Python-3.5.2.tgz \
#	 && tar xzf Python-3.5.2.tgz \
#	 && cd Python-3.5.2 \
#	 && ./configure --prefix=$(TARGET) \
#	 && make \
#	 && make install \
#	 && cd $(TARGET)/bin \
#	 && rm -f python \
#	 && ln -s pip3 pip \
#	 && ln -s python3 python)


$(TARGET)/bin/python: $(TARGET)/bin/pkg-config $(TARGET)/lib/libsqlite3.a
	(cd build-dir \
	 && wget $(WGET_FLAGS) https://www.python.org/ftp/python/2.7.9/Python-2.7.9.tgz \
	 && tar xzf Python-2.7.9.tgz \
	 && cd Python-2.7.9 \
	 && ./configure --prefix=$(TARGET) \
	 && make \
	 && make install \
	 && cd $(TARGET)/bin \
	 && ls -l python*)


##python packages
$(TARGET)/lib/python-packages.stamp: $(TARGET)/bin/python
	(cd build-dir \
	 && wget $(WGET_FLAGS) https://bootstrap.pypa.io/get-pip.py \
	 && python get-pip.py \
	 && pip install --upgrade pip \
	 && pip install --upgrade db \
	 && pip install --upgrade numpy \
	 && pip install --upgrade HTMLParser \
	 && touch $(TARGET)/lib/python-packages.stamp)
	
#python3 problem:
#&& pip3 install --upgrade ctypesgencore \

##swig
$(TARGET)/bin/swig: $(TARGET)/bin/python $(TARGET)/lib/libz.so
	(cd build-dir \
	 && wget http://prdownloads.sourceforge.net/swig/swig-3.0.12.tar.gz \
	 && tar xzf swig-3.0.12.tar.gz \
	 && cd swig-3.0.12 \
	 && wget ftp://ftp.csx.cam.ac.uk/pub/software/programming/pcre/pcre-8.40.tar.gz \
	 && ./Tools/pcre-build.sh \
	 && ./configure --prefix=$(TARGET) \
	 && make \
	 && make install)


##zlib
$(TARGET)/lib/libz.so:
	(cd build-dir \
	 && wget ftp://ftp.unidata.ucar.edu/pub/netcdf/netcdf-4/zlib-1.2.8.tar.gz \
	 && tar xzf zlib-1.2.8.tar.gz \
	 && cd zlib-1.2.8 \
	 && ./configure --prefix=$(TARGET) \
	 && make install)


##hdf5
$(TARGET)/lib/libhdf5.so: $(TARGET)/lib/libz.so
	(cd build-dir \
		&& wget https://support.hdfgroup.org/ftp/HDF5/releases/hdf5-1.10/hdf5-1.10.1/src/hdf5-1.10.1.tar.gz \
	 && tar xzf hdf5-1.10.1.tar.gz \
	 && cd hdf5-1.10.1 \
	 && ./configure --with-zlib=$(TARGET) --prefix=$(TARGET) \
	 && make install)


##netcdf
$(TARGET)/lib/libnetcdf.so:
	(cd build-dir \
	 && wget ftp://ftp.unidata.ucar.edu/pub/netcdf/netcdf-4.4.1.1.tar.gz \
	 && tar xzf netcdf-4.4.1.1.tar.gz \
	 && cd netcdf-4.4.1.1 \
	 && ./configure --prefix=$(TARGET) \
	 && make \
	 && make install)


##PROJ.4
$(TARGET)/bin/proj:
	(cd build-dir \
	 && wget http://download.osgeo.org/proj/proj-4.9.3.tar.gz \
	 && wget http://download.osgeo.org/proj/proj-datumgrid-1.5.tar.gz \
	 && tar xzf proj-4.9.3.tar.gz \
	 && cd proj-4.9.3/nad \
	 && tar xzf ../../proj-datumgrid-1.5.tar.gz \
	 && cd .. \
	 && ./configure --prefix=$(TARGET) \
	 && make \
	 && make install)


##gdal
$(TARGET)/bin/gdalinfo: $(TARGET)/lib/libhdf5.so $(TARGET)/lib/libnetcdf.so $(TARGET)/bin/proj
	(cd build-dir \
	 && wget http://download.osgeo.org/gdal/2.1.3/gdal-2.1.3.tar.gz \
	 && tar xzf gdal-2.1.3.tar.gz \
	 && cd gdal-2.1.3 \
	 && ./configure --without-grass --with-netcdf=$(TARGET) --with-python --prefix=$(TARGET) --with-hdf5=$(TARGET) \
	 && make \
	 && make install)


##geos
$(TARGET)/lib/libgeos.so: $(TARGET)/bin/swig $(TARGET)/bin/python
	(cd build-dir \
	 && wget http://download.osgeo.org/geos/geos-3.5.0.tar.bz2 \
	 && tar -xjf geos-3.5.0.tar.bz2 \
	 && cd geos-3.5.0 \
	 && ./configure --prefix=$(TARGET) --enable-python \
	 && make \
	 && make install)
	# does not work with python3 - https://trac.osgeo.org/geos/ticket/774
	#&& ./configure --prefix=$(TARGET) --enable-python \

##Flex
$(TARGET)/bin/flex:
	(cd build-dir \
	 && wget http://downloads.sourceforge.net/project/flex/flex-2.6.0.tar.gz \
	 && tar xzf flex-2.6.0.tar.gz \
	 && cd flex-2.6.0 \
	 && ./configure --prefix=$(TARGET) \
	 && make install)


##Bison
$(TARGET)/bin/bison:
	(cd build-dir \
	 && wget http://ftp.gnu.org/gnu/bison/bison-3.0.4.tar.gz \
	 && tar xzf bison-3.0.4.tar.gz \
	 && cd bison-3.0.4 \
	 && ./configure --prefix=$(TARGET) \
	 && make install)


##libtiff
$(TARGET)/lib/libtiff.a:
	(cd build-dir \
	 && wget ftp://download.osgeo.org/libtiff/tiff-4.0.6.tar.gz \
	 && tar xzf tiff-4.0.6.tar.gz \
	 && cd tiff-4.0.6 \
	 && ./configure --prefix=$(TARGET) \
	 && make install)
#
##libjasper
$(TARGET)/lib/libjasper.a:
	(cd build-dir \
	 && wget https://www.ece.uvic.ca/~frodo/jasper/software/jasper-1.900.1.zip \
	 && unzip jasper-1.900.1.zip \
	 && cd jasper-1.900.1 \
	 && ./configure --prefix=$(TARGET) \
	 && make install)

##libpng
$(TARGET)/lib/libpng.a:
	(cd build-dir \
	 && wget http://downloads.sourceforge.net/project/libpng/libpng16/1.6.28/libpng-1.6.28.tar.gz \
	 && tar xzf libpng-1.6.28.tar.gz \
	 && cd libpng-1.6.28 \
	 && ./configure --prefix=$(TARGET) \
	 && make install)

##SQLite
$(TARGET)/lib/libsqlite3.a:
	(cd build-dir \
	 && wget https://www.sqlite.org/2016/sqlite-autoconf-3140200.tar.gz \
	 && tar xzf sqlite-autoconf-3140200.tar.gz \
	 && cd sqlite-autoconf-3140200 \
	 && ./configure --prefix=$(TARGET) --enable-static --disable-shared \
	 && make install)


##FreeType
$(TARGET)/bin/freetype-config: $(TARGET)/bin/pkg-config $(TARGET)/lib/libpng.a $(TARGET)/lib/libjasper.a $(TARGET)/lib/libtiff.a
	(cd build-dir \
	 && wget http://download.savannah.gnu.org/releases/freetype/freetype-2.7.tar.gz \
	 && tar xzf freetype-2.7.tar.gz \
	 && cd freetype-2.7 \
	 && ./configure --prefix=$(TARGET) \
	 && make \
	 && make install)


##expat
$(TARGET)/lib/libexpat.a: $(TARGET)/bin/pkg-config $(TARGET)/bin/flex $(TARGET)/bin/bison
	(cd build-dir \
	 && wget http://downloads.sourceforge.net/expat/expat-2.1.0.tar.gz \
	 && tar xzf expat-2.1.0.tar.gz \
	 && cd expat-2.1.0 \
	 && ./configure --prefix=$(TARGET) \
	 && make install)



##FontConfig
$(TARGET)/lib/libfontconfig.so: $(TARGET)/bin/pkg-config $(TARGET)/lib/libexpat.a $(TARGET)/bin/freetype-config
	(cd build-dir \
	 && wget http://www.freedesktop.org/software/fontconfig/release/fontconfig-2.12.1.tar.gz \
	 && tar xf fontconfig-2.12.1.tar.gz \
	 && cd fontconfig-2.12.1 \
	 && ./configure --prefix=$(TARGET) --disable-docs \
	 && make install)


##Pixman
$(TARGET)/lib/libpixman-1.a: $(TARGET)/bin/pkg-config $(TARGET)/lib/libpng.a $(TARGET)/lib/libjasper.a $(TARGET)/lib/libtiff.a
	(cd build-dir \
	 && wget http://cairographics.org/releases/pixman-0.34.0.tar.gz \
	 && tar xzf pixman-0.34.0.tar.gz \
	 && cd pixman-0.34.0 \
	 && CPPFLAGS="-I$(TARGET)/include" LDFLAGS="-L$(TARGET)/lib" ./configure --prefix=$(TARGET) \
	 && make install)


##GLib
$(TARGET)/lib/libglib-2.0.so: $(TARGET)/lib/libpcre.so $(TARGET)/lib/libffi.so
	(cd build-dir \
	 && wget ftp://ftp.gnome.org/pub/gnome/sources/glib/2.50/glib-2.50.1.tar.xz \
	 && tar xf glib-2.50.1.tar.xz \
	 && cd glib-2.50.1 \
	 && ./configure --prefix=$(TARGET) --disable-libmount \
	 && make install)


##harfbuzz
$(TARGET)/lib/libharfbuzz.so: $(TARGET)/lib/libglib-2.0.so $(TARGET)/bin/freetype-config
	(cd build-dir \
	 && wget http://www.freedesktop.org/software/harfbuzz/release/harfbuzz-1.3.2.tar.bz2 \
	 && tar xjf harfbuzz-1.3.2.tar.bz2 \
	 && cd harfbuzz-1.3.2 \
	 && ./configure --prefix=$(TARGET) --with-freetype=yes \
	 && make install)


##Cairo
$(TARGET)/lib/libcairo.so: $(TARGET)/bin/pkg-config $(TARGET)/lib/libglib-2.0.so $(TARGET)/lib/libpng.a $(TARGET)/lib/libjasper.a $(TARGET)/lib/libtiff.a $(TARGET)/lib/libpixman-1.a $(TARGET)/lib/libfontconfig.so $(TARGET)/lib/libharfbuzz.so
	(cd build-dir \
	 && wget http://cairographics.org/releases/cairo-1.14.6.tar.xz \
	 && tar xf cairo-1.14.6.tar.xz \
	 && cd cairo-1.14.6 \
	 && ./configure --prefix=$(TARGET) --with-glib \
	 && make install)


##libffi
$(TARGET)/lib/libffi.so: $(TARGET)/bin/pkg-config
	(cd build-dir \
	 && if [ ! -e $(TARGET)/lib64 ]; then (cd $(TARGET) && ln -s lib lib64); fi \
	 && wget ftp://sourceware.org/pub/libffi/libffi-3.2.1.tar.gz \
	 && tar xf libffi-3.2.1.tar.gz \
	 && cd libffi-3.2.1 \
	 && CPPFLAGS="-I$(TARGET)/include" LDFLAGS="-L$(TARGET)/lib" ./configure --prefix=$(TARGET) --libdir=$(TARGET)/lib \
	 && make install)


##pcre
$(TARGET)/lib/libpcre.so:
	(cd build-dir \
	 && wget ftp://ftp.csx.cam.ac.uk/pub/software/programming/pcre/pcre-8.39.tar.gz \
	 && tar xzf pcre-8.39.tar.gz \
	 && cd pcre-8.39 \
	 &&  ./configure --prefix=$(TARGET) --enable-unicode-properties \
	 && make install)


##ATK
$(TARGET)/lib/libatk-1.0.so:
	(cd build-dir \
	 && wget http://ftp.gnome.org/pub/gnome/sources/atk/2.22/atk-2.22.0.tar.xz \
	 && tar xf atk-2.22.0.tar.xz \
	 && cd atk-2.22.0 \
	 && ./configure --prefix=$(TARGET) \
	 && make install)


##Pango
$(TARGET)/lib/libpango-1.0.so: $(TARGET)/bin/pkg-config $(TARGET)/lib/libglib-2.0.so $(TARGET)/lib/libharfbuzz.so $(TARGET)/lib/libcairo.so
	(cd build-dir \
	 && wget ftp://ftp.gnome.org/pub/gnome/sources/pango/1.40/pango-1.40.3.tar.xz \
	 && tar xf pango-1.40.3.tar.xz \
	 && cd pango-1.40.3 \
	 && ./configure --prefix=$(TARGET) \
	 && make install)


##gdk-pixbuf
$(TARGET)/lib/libgdk_pixbuf-2.0.so: $(TARGET)/bin/pkg-config $(TARGET)/lib/libpango-1.0.so
	(cd build-dir \
	 && wget ftp://ftp.gnome.org/pub/gnome/sources/gdk-pixbuf/2.36/gdk-pixbuf-2.36.0.tar.xz \
	 && tar xf gdk-pixbuf-2.36.0.tar.xz \
	 && cd gdk-pixbuf-2.36.0 \
	 && ./configure --prefix=$(TARGET) --without-libjpeg \
	 && make install)


##epoxy
$(TARGET)/lib/libepoxy.so: $(TARGET)/bin/pkg-config
	(cd build-dir \
	 && wget https://github.com/anholt/libepoxy/releases/download/v1.4/libepoxy-1.4.0.tar.xz \
	 && tar xf libepoxy-1.4.0.tar.xz \
	 && cd libepoxy-1.4.0 \
	 && export PKG_CONFIG_PATH="$(TARGET)/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig/" \
	 && ./configure --prefix=$(TARGET) \
	 && make install)


##GTK+
$(TARGET)/lib/libgtk-3.so: $(TARGET)/lib/libglib-2.0.so $(TARGET)/lib/libatk-1.0.so $(TARGET)/lib/libpango-1.0.so $(TARGET)/lib/libcairo.so $(TARGET)/lib/libgdk_pixbuf-2.0.so $(TARGET)/lib/libepoxy.so
	(cd build-dir \
	 && wget http://ftp.gnome.org/pub/gnome/sources/gtk+/3.5/gtk+-3.5.4.tar.xz \
	 && tar xf gtk+-3.5.4.tar.xz \
	 && cd gtk+-3.5.4 \
	 && export PKG_CONFIG_PATH="$(TARGET)/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig/" \
	 && ./configure --prefix=$(TARGET) --disable-xinput --without-atk-bridge \
	 && make install)


##wxPython
$(TARGET)/bin/wx-config:
	(cd build-dir \
	 && wget http://downloads.sourceforge.net/wxpython/wxPython-src-3.0.2.0.tar.bz2 \
	 && tar xjf wxPython-src-3.0.2.0.tar.bz2 \
	 && cd wxPython-src-3.0.2.0 \
	 && export PKG_CONFIG_PATH="$(TARGET)/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig/" \
	 && ./configure --prefix=$(TARGET) \
	 && make install)


##GRASS
$(TARGET)/bin/grass72: $(TARGET)/lib/libgtk-3.so $(TARGET)/lib/libgeos.so $(TARGET)/bin/freetype-config $(TARGET)/bin/gdalinfo $(TARGET)/bin/proj $(TARGET)/lib/libnetcdf.so $(TARGET)/bin/wx-config $(TARGET)/lib/python-packages.stamp
	(cd build-dir \
	 && wget $(WGET_FLAGS) https://grass.osgeo.org/grass72/source/grass-7.2.1.tar.gz \
	 && tar xzf grass-7.2.1.tar.gz \
	 && cd grass-7.2.1 \
	 && export LDFLAGS="-Wl,-rpath,$(TARGET)/lib -lpthread" \
	 && ./configure --enable-64bit --prefix=$(TARGET) --with-libs=$(TARGET)/lib --with-proj-lib=$(TARGET)/lib --with-proj-share=$(TARGET)/share/proj/ --with-proj-includes=$(TARGET)/include --with-gdal=$(TARGET)  --with-cxx --without-fftw --without-python --with-geos=$(TARGET)/bin --with-libs=$(TARGET)/lib -with-opengl=no --with-freetype-includes=$(TARGET)/include/freetype2 --with-netcdf --without-tcltk --with-png-libs=$(TARGET)/lib \
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

