#!/bin/bash
# QGIS Installation Script for EEMT
# Installing QGIS LTR 3.34+ from official repositories

set -e

# Configuration
QGIS_VERSION="ltr"  # Use Long Term Release
INSTALL_METHOD="repo"  # repo, flatpak, or source

echo "Installing QGIS ${QGIS_VERSION} for EEMT..."

# Function to install via official repositories
install_qgis_repo() {
    # Ubuntu/Debian installation
    if command -v apt-get >/dev/null 2>&1; then
        echo "Installing QGIS on Ubuntu/Debian..."
        
        # Install required packages
        apt-get update
        apt-get install -y gnupg software-properties-common wget
        
        # Add QGIS repository key
        wget -qO - https://qgis.org/downloads/qgis-2022.gpg.key | gpg --no-default-keyring --keyring gnupg-ring:/etc/apt/trusted.gpg.d/qgis-archive.gpg --import
        chmod a+r /etc/apt/trusted.gpg.d/qgis-archive.gpg
        
        # Detect Ubuntu version
        UBUNTU_VERSION=$(lsb_release -cs)
        echo "Detected Ubuntu version: $UBUNTU_VERSION"
        
        # Add QGIS repository
        add-apt-repository "deb https://qgis.org/ubuntu ${UBUNTU_VERSION} main"
        
        # Update and install QGIS
        apt-get update
        apt-get install -y qgis qgis-plugin-grass python3-qgis
        
        echo "QGIS installed via APT repository"
    
    # CentOS/RHEL/Rocky/Fedora installation
    elif command -v dnf >/dev/null 2>&1; then
        echo "Installing QGIS on Fedora/RHEL 9+..."
        dnf install -y qgis python3-qgis qgis-grass
        
    elif command -v yum >/dev/null 2>&1; then
        echo "Installing QGIS on CentOS/RHEL..."
        
        # Enable EPEL repository
        yum install -y epel-release
        
        # Install QGIS
        yum install -y qgis python3-qgis qgis-grass
        
    else
        echo "Package manager not supported for repository installation"
        return 1
    fi
}

# Function to install via Flatpak (universal)
install_qgis_flatpak() {
    echo "Installing QGIS via Flatpak..."
    
    # Install flatpak if not present
    if ! command -v flatpak >/dev/null 2>&1; then
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update && apt-get install -y flatpak
        elif command -v dnf >/dev/null 2>&1; then
            dnf install -y flatpak
        elif command -v yum >/dev/null 2>&1; then
            yum install -y flatpak
        else
            echo "Cannot install flatpak on this system"
            return 1
        fi
    fi
    
    # Add Flathub repository
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    
    # Install QGIS
    flatpak install -y flathub org.qgis.qgis
    
    echo "QGIS installed via Flatpak"
    echo "Run with: flatpak run org.qgis.qgis"
}

# Function to build from source (advanced)
install_qgis_source() {
    echo "Building QGIS from source..."
    echo "WARNING: This is complex and may take several hours"
    
    TEMP_DIR="/tmp/qgis_build"
    QGIS_INSTALL_PREFIX="/usr/local"
    CORES=$(nproc)
    
    # Install build dependencies
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update
        apt-get install -y \
            build-essential \
            cmake \
            git \
            libqt5svg5-dev \
            libqt5xmlpatterns5-dev \
            qtbase5-dev \
            qttools5-dev \
            qttools5-dev-tools \
            libqt5sql5-sqlite \
            qt5-default \
            libgdal-dev \
            libproj-dev \
            libgeos-dev \
            libexpat1-dev \
            libsqlite3-dev \
            libspatialite-dev \
            libqt5webkit5-dev \
            libqca-qt5-2-dev \
            libqt5scintilla2-dev \
            libqwt-qt5-dev \
            libqt5opengl5-dev \
            libzip-dev \
            python3-dev \
            python3-sip-dev \
            python3-pyqt5-dev \
            pyqt5-dev-tools
    else
        echo "Source build dependencies not defined for this distribution"
        return 1
    fi
    
    # Create build directory
    mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR"
    
    # Clone QGIS source
    if [ ! -d "QGIS" ]; then
        git clone --depth 1 --branch release-3_34 https://github.com/qgis/QGIS.git
    fi
    cd QGIS
    
    # Create build directory
    mkdir -p build
    cd build
    
    # Configure with CMake
    cmake -DCMAKE_INSTALL_PREFIX="$QGIS_INSTALL_PREFIX" \
          -DCMAKE_BUILD_TYPE=Release \
          -DWITH_DESKTOP=ON \
          -DWITH_SERVER=ON \
          -DWITH_3D=ON \
          -DWITH_BINDINGS=ON \
          -DBINDINGS_GLOBAL_INSTALL=ON \
          ..
    
    # Build
    make -j"$CORES"
    
    # Install
    make install
    
    # Cleanup
    cd /
    rm -rf "$TEMP_DIR"
    
    echo "QGIS built and installed from source"
}

# Main installation logic
case "$INSTALL_METHOD" in
    "repo")
        if ! install_qgis_repo; then
            echo "Repository installation failed, trying Flatpak..."
            install_qgis_flatpak
        fi
        ;;
    "flatpak")
        install_qgis_flatpak
        ;;
    "source")
        install_qgis_source
        ;;
    *)
        echo "Invalid installation method: $INSTALL_METHOD"
        echo "Valid options: repo, flatpak, source"
        exit 1
        ;;
esac

# Verify installation
echo ""
echo "Verifying QGIS installation..."
if command -v qgis >/dev/null 2>&1; then
    echo "QGIS installed successfully!"
    qgis --version
elif flatpak list | grep -q org.qgis.qgis; then
    echo "QGIS installed via Flatpak!"
    echo "Run with: flatpak run org.qgis.qgis"
else
    echo "QGIS installation verification failed"
    exit 1
fi

echo ""
echo "QGIS installation complete!"
echo "For EEMT workflows, ensure QGIS can access:"
echo "  - GRASS GIS integration"
echo "  - GDAL/OGR drivers"
echo "  - Python processing plugins"