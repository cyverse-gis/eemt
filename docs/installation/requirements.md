---
title: Requirements & Dependencies
---

# Requirements & Dependencies

## Overview

This document provides comprehensive details about all hardware requirements, software dependencies, and optional components for running EEMT workflows at various scales.

## Hardware Requirements

### Minimum Specifications

| Component | Minimum | Recommended | Notes |
|-----------|---------|-------------|-------|
| **CPU** | 4 cores | 8-16 cores | More cores enable parallel processing |
| **RAM** | 8 GB | 16-32 GB | Scales with DEM resolution |
| **Storage** | 50 GB | 200+ GB | Depends on study area size |
| **GPU** | Optional | NVIDIA with 4+ GB VRAM | Accelerates r.sun calculations |
| **Network** | 10 Mbps | 100+ Mbps | For climate data downloads |

### Performance Scaling

#### By Dataset Size
- **Small (< 100 km²)**: 4 cores, 8 GB RAM
- **Medium (100-1000 km²)**: 8 cores, 16 GB RAM
- **Large (1000-10000 km²)**: 16 cores, 32 GB RAM
- **Continental (> 10000 km²)**: 32+ cores, 64+ GB RAM, distributed computing

#### By Resolution
- **30m DEM**: Base requirements
- **10m DEM**: 2x memory requirement
- **1m LiDAR**: 10x memory requirement, tiling recommended

## Software Dependencies

### Core Geospatial Stack

| Software | Minimum Version | Recommended | Purpose |
|----------|----------------|-------------|---------|
| **GRASS GIS** | 8.0 | 8.4+ | Geospatial processing engine |
| **GDAL** | 3.0 | 3.8+ | Raster data I/O |
| **PROJ** | 7.0 | 9.0+ | Coordinate transformations |
| **GEOS** | 3.8 | 3.12+ | Geometric operations |

### Python Environment

| Package | Minimum Version | Purpose |
|---------|----------------|---------|
| **Python** | 3.10 | 3.12+ recommended |
| **numpy** | 1.22 | Numerical arrays |
| **pandas** | 1.5 | Data manipulation |
| **xarray** | 2023.1 | NetCDF/climate data |
| **rasterio** | 1.3 | Raster I/O |
| **geopandas** | 0.12 | Vector data |
| **dask** | 2023.1 | Parallel computing |
| **scipy** | 1.10 | Scientific computing |
| **matplotlib** | 3.6 | Visualization |
| **requests** | 2.28 | HTTP/API access |

### Workflow Management

| Software | Version | Purpose | Required |
|----------|---------|---------|----------|
| **CCTools** | 7.8+ | Makeflow + Work Queue | Yes |
| **Docker** | 20.10+ | Container runtime | Recommended |
| **Docker Compose** | 2.0+ | Multi-container orchestration | Recommended |
| **Nextflow** | 23.10+ | Alternative workflow engine | Optional |

### Web Interface Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| **FastAPI** | 0.104+ | REST API framework |
| **Uvicorn** | 0.24+ | ASGI server |
| **Pydantic** | 2.5+ | Data validation |
| **Jinja2** | 3.1+ | Template engine |
| **python-multipart** | 0.0.6+ | File uploads |
| **aiofiles** | 23.2+ | Async file operations |

## Operating System Support

### Linux (Primary Platform)

**Supported Distributions**:
- Ubuntu 20.04 LTS, 22.04 LTS, 24.04 LTS
- Debian 10 (Buster), 11 (Bullseye), 12 (Bookworm)
- CentOS 7, CentOS Stream 8/9
- RHEL 7, 8, 9
- Rocky Linux 8, 9
- AlmaLinux 8, 9
- Fedora 36+

**Package Managers**:
```bash
# APT (Ubuntu/Debian)
sudo apt update && sudo apt install [packages]

# YUM/DNF (RHEL/CentOS/Fedora)
sudo yum install [packages]  # or
sudo dnf install [packages]
```

### macOS

**Supported Versions**:
- macOS 11 (Big Sur)
- macOS 12 (Monterey)
- macOS 13 (Ventura)
- macOS 14 (Sonoma)

**Architecture Support**:
- Intel x86_64
- Apple Silicon (M1/M2/M3) with Rosetta 2

**Package Manager**:
```bash
# Homebrew installation
brew install grass gdal python@3.12
```

### Windows

**Supported Versions**:
- Windows 10 (version 2004+)
- Windows 11
- Windows Server 2019, 2022

**Installation Methods**:
1. **WSL2** (Recommended):
   ```powershell
   wsl --install
   # Then follow Linux instructions
   ```

2. **Docker Desktop**:
   - Native Windows containers
   - WSL2 backend for Linux containers

3. **Native** (Limited support):
   - OSGeo4W installer
   - Conda/Mamba environments

## Optional Components

### Performance Enhancements

| Component | Purpose | Impact |
|-----------|---------|--------|
| **NVIDIA CUDA** | GPU acceleration for r.sun | 10-50x speedup |
| **Intel MKL** | Optimized linear algebra | 2-5x speedup |
| **OpenMP** | Multi-threading support | Scales with cores |
| **HDF5** | Efficient data storage | Reduced I/O overhead |
| **NetCDF** | Climate data format | Direct DAYMET access |

### Development Tools

| Tool | Purpose | Required For |
|------|---------|--------------|
| **Git** | Version control | Development |
| **Make** | Build automation | Compiling from source |
| **GCC/Clang** | C/C++ compiler | Building extensions |
| **pytest** | Testing framework | Running tests |
| **mkdocs** | Documentation | Building docs |
| **Jupyter** | Interactive notebooks | Data exploration |

### Monitoring & Debugging

| Tool | Purpose |
|------|---------|
| **htop** | Process monitoring |
| **nvidia-smi** | GPU monitoring |
| **gdalinfo** | Raster metadata inspection |
| **grass --exec** | GRASS command testing |
| **docker stats** | Container resource usage |

## Container Requirements

### Docker Installation

**Minimum Docker Version**: 20.10+

```bash
# Check Docker version
docker --version

# Required features
- Buildkit support
- Multi-stage builds
- Volume mounts
- Network creation
```

### Container Resources

**Default Limits**:
```yaml
# docker-compose.yml
services:
  eemt-web:
    deploy:
      resources:
        limits:
          cpus: '4'
          memory: 8G
        reservations:
          cpus: '2'
          memory: 4G
```

### Storage Requirements

**Container Images**:
- Base Ubuntu: ~500 MB
- EEMT with dependencies: ~2.5 GB
- With cached climate data: ~10 GB

**Volume Mounts**:
- Input data: `/data/input`
- Results: `/data/output`
- Cache: `/data/cache`

## Network Requirements

### Internet Connectivity

**Required for**:
- Climate data downloads (DAYMET)
- Container image pulls
- Package installations
- Updates

**Bandwidth Requirements**:
- Minimum: 10 Mbps for basic operations
- Recommended: 100+ Mbps for large datasets
- DAYMET downloads: ~1 GB per year of data

### Firewall Ports

| Port | Service | Protocol | Direction |
|------|---------|----------|-----------|
| 5000 | Web Interface | TCP | Inbound |
| 8000 | Documentation | TCP | Inbound |
| 9123 | Work Queue Master | TCP | Inbound |
| 9124-9200 | Work Queue Workers | TCP | Bidirectional |

## Cloud Platform Requirements

### AWS

**EC2 Instance Types**:
- Development: t3.large (2 vCPU, 8 GB)
- Production: c5.4xlarge (16 vCPU, 32 GB)
- GPU-enabled: p3.2xlarge (8 vCPU, 61 GB, V100 GPU)

**Storage**:
- EBS: gp3 volumes, 100+ GB
- S3: For input/output data

### Google Cloud

**Compute Engine**:
- Development: e2-standard-4
- Production: c2-standard-16
- GPU-enabled: n1-standard-8 with T4 GPU

### Azure

**Virtual Machines**:
- Development: Standard_D4s_v3
- Production: Standard_F16s_v2
- GPU-enabled: Standard_NC6s_v3

### HPC Systems

**SLURM Requirements**:
```bash
#SBATCH --nodes=1
#SBATCH --ntasks=16
#SBATCH --mem=32GB
#SBATCH --time=24:00:00
#SBATCH --partition=standard
```

**Modules**:
```bash
module load grass/8.4
module load gdal/3.8
module load python/3.12
```

## Verification Commands

### Check All Dependencies

```bash
#!/bin/bash
# Save as check_requirements.sh

echo "Checking EEMT Requirements..."
echo "=============================="

# Python
echo -n "Python: "
python3 --version 2>/dev/null || echo "NOT FOUND"

# GRASS GIS
echo -n "GRASS GIS: "
grass --version 2>/dev/null | head -1 || echo "NOT FOUND"

# GDAL
echo -n "GDAL: "
gdalinfo --version 2>/dev/null || echo "NOT FOUND"

# Docker
echo -n "Docker: "
docker --version 2>/dev/null || echo "NOT FOUND"

# CCTools
echo -n "Makeflow: "
makeflow --version 2>/dev/null | head -1 || echo "NOT FOUND"

# Python packages
echo -e "\nPython Packages:"
python3 -c "
import importlib
packages = ['numpy', 'pandas', 'rasterio', 'xarray', 'geopandas']
for pkg in packages:
    try:
        mod = importlib.import_module(pkg)
        print(f'  {pkg}: {mod.__version__}')
    except ImportError:
        print(f'  {pkg}: NOT INSTALLED')
" 2>/dev/null

# System resources
echo -e "\nSystem Resources:"
echo "  CPU Cores: $(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 'Unknown')"
echo "  Total RAM: $(free -h 2>/dev/null | awk '/^Mem:/{print $2}' || echo 'Unknown')"
echo "  Available Disk: $(df -h . | awk 'NR==2{print $4}')"
```

## Troubleshooting Dependencies

### Version Conflicts

```bash
# Check for conflicts
pip check

# Force reinstall with specific versions
pip install --force-reinstall numpy==1.26.0 pandas==2.1.0
```

### Missing Libraries

```bash
# Find missing libraries (Linux)
ldd $(which grass) | grep "not found"

# Install missing libraries
sudo apt install libgdal-dev libproj-dev  # Ubuntu/Debian
sudo yum install gdal-devel proj-devel     # CentOS/RHEL
```

### Permission Issues

```bash
# Fix permission problems
sudo chown -R $USER:$USER ~/.grass8
chmod 755 ~/grassdata
chmod 600 ~/.eemt-makeflow-password
```

---

*For installation instructions, see the [Installation Overview](index.md).*