---
title: Manual Installation
---

# Manual Installation Guide

## Overview

This guide provides instructions for manually installing EEMT and its dependencies directly on your system. Manual installation offers full control over the environment and is suitable for development, customization, or integration with existing HPC systems.

## Prerequisites

### System Requirements

**Minimum Hardware**:
- CPU: 4 cores (8+ recommended for parallel processing)
- RAM: 8 GB (16+ GB recommended for large datasets)  
- Storage: 50 GB free space
- GPU: Optional but recommended for r.sun calculations

**Operating Systems**:
- Linux: Ubuntu 20.04+, CentOS 7+, Debian 10+
- macOS: 11.0+ (Big Sur or later)
- Windows: Windows 10+ with WSL2

## Core Dependencies

### 1. Python Environment

EEMT requires Python 3.12 or later:

```bash
# Check Python version
python3 --version

# Ubuntu/Debian
sudo apt update
sudo apt install python3.12 python3.12-venv python3.12-dev

# macOS (via Homebrew)
brew install python@3.12

# CentOS/RHEL
sudo yum install python3.12 python3.12-devel
```

### 2. GRASS GIS Installation

GRASS GIS 8.4+ is required for geospatial processing:

#### Ubuntu/Debian
```bash
# Add GRASS GIS repository
sudo add-apt-repository ppa:ubuntugis/ppa
sudo apt update

# Install GRASS GIS
sudo apt install grass grass-dev grass-doc

# Verify installation
grass --version
```

#### macOS
```bash
# Install via Homebrew
brew tap OSGeo/osgeo4mac
brew install grass

# Or download from official site
# https://grass.osgeo.org/download/mac/
```

#### CentOS/RHEL
```bash
# Enable EPEL repository
sudo yum install epel-release

# Install GRASS GIS
sudo yum install grass grass-libs grass-devel

# Verify installation
grass --version
```

### 3. GDAL Installation

GDAL 3.8+ is required for raster data handling:

```bash
# Ubuntu/Debian
sudo apt install gdal-bin python3-gdal libgdal-dev

# macOS
brew install gdal

# CentOS/RHEL  
sudo yum install gdal gdal-devel gdal-python

# Verify installation
gdalinfo --version
```

### 4. CCTools Installation (Makeflow + Work Queue)

CCTools provides workflow management capabilities:

```bash
# Download latest CCTools
wget https://github.com/cooperative-computing-lab/cctools/releases/download/release/7.8.2/cctools-7.8.2-source.tar.gz
tar -xzf cctools-7.8.2-source.tar.gz
cd cctools-7.8.2-source

# Configure and compile
./configure --prefix=$HOME/cctools
make
make install

# Add to PATH
echo 'export PATH=$HOME/cctools/bin:$PATH' >> ~/.bashrc
source ~/.bashrc

# Verify installation
makeflow --version
work_queue_status --version
```

## EEMT Installation

### 1. Clone Repository

```bash
git clone https://github.com/cyverse-gis/eemt.git
cd eemt
```

### 2. Create Python Virtual Environment

```bash
# Create virtual environment
python3 -m venv eemt-env

# Activate environment
source eemt-env/bin/activate  # Linux/macOS
# eemt-env\Scripts\activate   # Windows

# Upgrade pip
pip install --upgrade pip
```

### 3. Install Python Dependencies

```bash
# Install required packages
pip install -r requirements.txt

# Core dependencies include:
# numpy>=1.26
# pandas>=2.1
# xarray>=2024.1
# rasterio>=1.3
# geopandas>=0.14
# dask>=2024.1
# scipy>=1.11
# matplotlib>=3.8
# requests>=2.31
```

### 4. Install EEMT Package

```bash
# Install in development mode
pip install -e .

# Or for production installation
pip install .
```

### 5. Configure CCTools Password

```bash
# Create password file for Makeflow authentication
echo "your_secure_password" > ~/.eemt-makeflow-password
chmod 600 ~/.eemt-makeflow-password
```

## Verification

### Test Core Components

```bash
# Test Python installation
python -c "import numpy, pandas, rasterio, xarray; print('Python packages OK')"

# Test GRASS GIS
grass --exec r.info --help

# Test GDAL
gdalinfo --formats | grep -i "GTiff"

# Test CCTools
makeflow --version
work_queue_worker --version
```

### Run Test Workflow

```bash
# Navigate to solar workflow directory
cd sol/sol/

# Run test with example DEM
python run-workflow --step 15 --num_threads 2 ../examples/mcn_10m.tif

# Check output
ls sol_data/global/daily/total_sun_day_*.tif | wc -l  # Should be 365
```

## Platform-Specific Notes

### Ubuntu/Debian

Additional packages for optimal performance:

```bash
sudo apt install \
  build-essential \
  libproj-dev \
  libgeos-dev \
  libspatialindex-dev \
  libnetcdf-dev \
  libhdf5-dev
```

### macOS

Ensure Xcode Command Line Tools are installed:

```bash
xcode-select --install
```

For M1/M2 Macs, use arch-specific builds:

```bash
# Install Rosetta 2 if needed
softwareupdate --install-rosetta

# Use arch flag for compilation
arch -arm64 make
```

### CentOS/RHEL

Enable additional repositories:

```bash
# Enable PowerTools/CodeReady
sudo yum config-manager --set-enabled powertools  # CentOS 8
# or
sudo subscription-manager repos --enable codeready-builder-for-rhel-8-x86_64-rpms  # RHEL 8

# Install development tools
sudo yum groupinstall "Development Tools"
```

### Windows (WSL2)

Install WSL2 and use Ubuntu distribution:

```powershell
# Install WSL2
wsl --install

# Set WSL2 as default
wsl --set-default-version 2

# Install Ubuntu
wsl --install -d Ubuntu-22.04

# Follow Ubuntu installation instructions within WSL2
```

## Environment Variables

Set required environment variables:

```bash
# Add to ~/.bashrc or ~/.zshrc
export EEMT_HOME=/path/to/eemt
export GRASSBIN=$(which grass)
export GISBASE=$(grass --config path)
export PATH=$EEMT_HOME/bin:$PATH
export PYTHONPATH=$EEMT_HOME:$PYTHONPATH

# Optional performance tuning
export GRASS_NPROCS=8  # Number of parallel processes
export OMP_NUM_THREADS=4  # OpenMP threads
```

## Troubleshooting

### Common Issues

#### GRASS GIS Not Found
```bash
# Check GRASS installation
which grass
grass --config path

# Set GISBASE manually if needed
export GISBASE=/usr/lib/grass84
```

#### Python Import Errors
```bash
# Ensure virtual environment is activated
which python  # Should show path within eemt-env

# Reinstall dependencies
pip install --force-reinstall -r requirements.txt
```

#### GDAL Version Conflicts
```bash
# Check GDAL versions
gdalinfo --version
python -c "from osgeo import gdal; print(gdal.__version__)"

# Ensure versions match
pip install GDAL==$(gdal-config --version)
```

#### Permission Denied Errors
```bash
# Check file permissions
ls -la ~/.eemt-makeflow-password

# Fix permissions
chmod 600 ~/.eemt-makeflow-password
chmod +x sol/sol/run-workflow
chmod +x eemt/eemt/run-workflow
```

### Getting Help

If you encounter issues:

1. Check the [FAQ](../about/index.md#faq)
2. Search [GitHub Issues](https://github.com/cyverse-gis/eemt/issues)
3. Post on [Discussions](https://github.com/cyverse-gis/eemt/discussions)
4. Create a [new issue](https://github.com/cyverse-gis/eemt/issues/new) with:
   - System information (OS, versions)
   - Complete error messages
   - Steps to reproduce

## Next Steps

After successful installation:

1. Review [Workflow Documentation](../workflows/index.md)
2. Try [Example Datasets](../examples/index.md)
3. Explore [API Reference](../api/index.md)
4. Configure for [Distributed Computing](../distributed-deployment/index.md)

---

*For containerized deployment (recommended), see the [Docker Installation Guide](docker.md).*