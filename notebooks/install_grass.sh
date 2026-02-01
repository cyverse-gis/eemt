#!/bin/bash
# GRASS GIS Installation Script for EEMT
# Based on https://grasswiki.osgeo.org/wiki/Compile_and_Install

set -e

# Configuration
GRASS_VERSION="8.4.1"
INSTALL_PREFIX="/usr/local"
TEMP_DIR="/tmp/grass_install"
CORES=$(nproc)

echo "Installing GRASS GIS ${GRASS_VERSION} for EEMT..."
echo "Installation prefix: ${INSTALL_PREFIX}"
echo "Using ${CORES} cores for compilation"

# Check if running as root for system install
if [[ "$EUID" -ne 0 && "$INSTALL_PREFIX" == "/usr/local" ]]; then
    echo "Error: System installation requires root privileges"
    echo "Run with sudo or set INSTALL_PREFIX to user directory"
    exit 1
fi

# Install system dependencies (Ubuntu/Debian)
if command -v apt-get >/dev/null 2>&1; then
    echo "Installing Ubuntu/Debian dependencies..."
    apt-get update
    apt-get install -y \
        build-essential \
        cmake \
        git \
        libgdal-dev \
        libproj-dev \
        libgeos-dev \
        libsqlite3-dev \
        libpng-dev \
        libjpeg-dev \
        libtiff-dev \
        libfftw3-dev \
        libcairo2-dev \
        libfreetype6-dev \
        libreadline-dev \
        libncurses5-dev \
        zlib1g-dev \
        libbz2-dev \
        libxmu-dev \
        libgl1-mesa-dev \
        libglu1-mesa-dev \
        python3-dev \
        python3-numpy \
        python3-six \
        python3-pil \
        flex \
        bison \
        pkg-config

# Install system dependencies (CentOS/RHEL/Rocky)
elif command -v yum >/dev/null 2>&1; then
    echo "Installing CentOS/RHEL dependencies..."
    yum groupinstall -y "Development Tools"
    yum install -y \
        cmake \
        git \
        gdal-devel \
        proj-devel \
        geos-devel \
        sqlite-devel \
        libpng-devel \
        libjpeg-turbo-devel \
        libtiff-devel \
        fftw-devel \
        cairo-devel \
        freetype-devel \
        readline-devel \
        ncurses-devel \
        zlib-devel \
        bzip2-devel \
        libXmu-devel \
        mesa-libGL-devel \
        mesa-libGLU-devel \
        python3-devel \
        python3-numpy \
        python3-six \
        python3-pillow \
        flex \
        bison \
        pkgconfig

else
    echo "Unsupported package manager. Please install dependencies manually."
    echo "Required: GDAL, PROJ, GEOS, SQLite, PNG, JPEG, TIFF, FFTW, Cairo, etc."
    exit 1
fi

# Create temporary build directory
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR"

# Download GRASS source
echo "Downloading GRASS GIS source code..."
if [ ! -d "grass" ]; then
    git clone https://github.com/OSGeo/grass.git
fi
cd grass
git checkout releasebranch_8_4

# Configure build
echo "Configuring GRASS build..."
./configure \
    --prefix="$INSTALL_PREFIX" \
    --enable-largefile \
    --with-cxx \
    --with-gdal \
    --with-proj \
    --with-geos \
    --with-sqlite \
    --with-cairo \
    --with-freetype \
    --with-readline \
    --with-python \
    --with-openmp \
    --with-pthread

# Build
echo "Building GRASS GIS (this may take 20-30 minutes)..."
make -j"$CORES"

# Install
echo "Installing GRASS GIS..."
make install

# Create symbolic links for easy access
if [[ "$INSTALL_PREFIX" == "/usr/local" ]]; then
    ln -sf "$INSTALL_PREFIX/bin/grass84" /usr/local/bin/grass
    echo "Created symlink: grass -> $INSTALL_PREFIX/bin/grass84"
fi

# Cleanup
echo "Cleaning up build directory..."
cd /
rm -rf "$TEMP_DIR"

echo "GRASS GIS installation complete!"
echo "Executable: $INSTALL_PREFIX/bin/grass84"
echo ""
echo "To use GRASS GIS with Python:"
echo "  export GISBASE=$INSTALL_PREFIX/grass84"
echo "  export PATH=\$GISBASE/bin:\$PATH"
echo "  export LD_LIBRARY_PATH=\$GISBASE/lib:\$LD_LIBRARY_PATH"
echo "  export PYTHONPATH=\$GISBASE/etc/python:\$PYTHONPATH"
echo ""
echo "Test installation with: grass84 --version"