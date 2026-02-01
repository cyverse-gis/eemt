---
title: Installation Troubleshooting
---

# Installation Troubleshooting Guide

**Updated January 2025** - Version 2.0.0

## Overview

This guide helps resolve common installation issues for both Docker and manual installations of EEMT. Each section includes symptoms, diagnosis steps, and solutions. Many critical issues have been fixed in version 2.0.0.

## 🎉 Recently Fixed Issues (v2.0.0)

The following issues have been resolved and should no longer occur:

### Web Interface Workflow Submission
**Previous Issue**: JSON parsing errors, container preparation hanging at 25%
**Status**: ✅ FIXED
**Solution Implemented**: Enhanced error handling with proper content-type checking

### System Resource Detection
**Previous Issue**: Displayed "unknown (subprocess mode)" instead of actual resources
**Status**: ✅ FIXED
**Solution Implemented**: Added psutil-based CPU and memory detection

### Job Monitoring
**Previous Issue**: Jobs not appearing, progress bars stuck
**Status**: ✅ FIXED
**Solution Implemented**: Enhanced progress parsing and job persistence

### System Status Updates
**Previous Issue**: Timestamp stuck at "Updating..."
**Status**: ✅ FIXED
**Solution Implemented**: Fixed API error handling and response processing

## Docker Installation Issues

### Docker Daemon Not Running

**Symptoms**:
```
Cannot connect to the Docker daemon at unix:///var/run/docker.sock
```

**Solution**:
```bash
# Linux
sudo systemctl start docker
sudo systemctl enable docker

# macOS - Start Docker Desktop from Applications

# Windows - Start Docker Desktop from Start Menu

# Verify Docker is running
docker ps
```

### Permission Denied Errors

**Symptoms**:
```
permission denied while trying to connect to the Docker daemon socket
```

**Solution**:
```bash
# Add user to docker group (Linux)
sudo usermod -aG docker $USER

# Log out and back in, then verify
groups | grep docker

# Alternative: use sudo (not recommended)
sudo docker-compose up
```

### Container Build Failures

**Symptoms**:
```
ERROR: failed to solve: process "/bin/sh -c apt-get update" did not complete successfully
```

**Current Container Versions (v2.0.0)**:
- eemt:ubuntu24.04 - Image ID: e3a84eb59c8e
- eemt-web:latest - Image ID: e8e8fa0d382d

**Solutions**:

1. **Network Issues**:
```bash
# Check DNS settings
docker run --rm busybox nslookup google.com

# Use alternative DNS
echo '{"dns": ["8.8.8.8", "8.8.4.4"]}' | sudo tee /etc/docker/daemon.json
sudo systemctl restart docker
```

2. **Proxy Configuration**:
```bash
# Set Docker proxy
mkdir -p ~/.docker
cat > ~/.docker/config.json << EOF
{
  "proxies": {
    "default": {
      "httpProxy": "http://proxy.example.com:8080",
      "httpsProxy": "http://proxy.example.com:8080",
      "noProxy": "localhost,127.0.0.1"
    }
  }
}
EOF
```

3. **Disk Space**:
```bash
# Check available space
df -h /var/lib/docker

# Clean up Docker resources
docker system prune -a --volumes

# Remove unused images
docker image prune -a
```

### Port Already in Use

**Symptoms**:
```
Error: bind: address already in use
```

**Solution**:
```bash
# Find process using port 5000
sudo lsof -i :5000  # Linux/macOS
netstat -ano | findstr :5000  # Windows

# Kill the process or use different port
# Edit docker-compose.yml
ports:
  - "5001:5000"  # Change host port to 5001
```

### Volume Mount Issues

**Symptoms**:
```
Error: invalid mount config for type "bind"
```

**Solutions**:

1. **Path Format (Windows)**:
```bash
# Use forward slashes or escaped backslashes
-v C:/Users/username/data:/data  # Correct
-v C:\Users\username\data:/data  # Incorrect
```

2. **Permissions**:
```bash
# Ensure directory exists and has correct permissions
mkdir -p ./data
chmod 755 ./data

# For SELinux systems
chcon -Rt svirt_sandbox_file_t ./data
```

## Manual Installation Issues

### Python Version Conflicts

**Symptoms**:
```
ERROR: This package requires Python >=3.12
```

**Solutions**:

1. **Install Python 3.12**:
```bash
# Ubuntu/Debian
sudo apt install python3.12 python3.12-venv

# macOS
brew install python@3.12

# From source
wget https://www.python.org/ftp/python/3.12.0/Python-3.12.0.tgz
tar -xf Python-3.12.0.tgz
cd Python-3.12.0
./configure --enable-optimizations
make -j $(nproc)
sudo make altinstall
```

2. **Use pyenv**:
```bash
# Install pyenv
curl https://pyenv.run | bash

# Install Python 3.12
pyenv install 3.12.0
pyenv local 3.12.0
```

### GRASS GIS Not Found

**Symptoms**:
```
grass: command not found
ERROR: GRASS GIS not installed
```

**Solutions**:

1. **Verify Installation**:
```bash
# Check if installed
which grass
apt list --installed | grep grass  # Debian/Ubuntu
rpm -qa | grep grass  # RHEL/CentOS
```

2. **Add to PATH**:
```bash
# Find GRASS installation
find /usr -name "grass*" -type f -executable 2>/dev/null

# Add to PATH in ~/.bashrc
export PATH=/usr/lib/grass84/bin:$PATH
export GISBASE=/usr/lib/grass84
source ~/.bashrc
```

3. **Install Missing Dependencies**:
```bash
# Ubuntu/Debian
sudo apt install grass-core grass-dev

# Fix library issues
sudo ldconfig
```

### GDAL Import Errors

**Symptoms**:
```python
ImportError: cannot import name 'gdal' from 'osgeo'
```

**Solutions**:

1. **Version Mismatch**:
```bash
# Check system GDAL version
gdalinfo --version

# Install matching Python bindings
pip install GDAL==$(gdal-config --version)
```

2. **Missing Libraries**:
```bash
# Ubuntu/Debian
sudo apt install gdal-bin libgdal-dev

# Set environment variables
export CPLUS_INCLUDE_PATH=/usr/include/gdal
export C_INCLUDE_PATH=/usr/include/gdal
pip install --no-binary GDAL GDAL
```

### CCTools/Makeflow Issues

**Symptoms**:
```
makeflow: command not found
work_queue_worker: error while loading shared libraries
```

**Solutions**:

1. **Compilation Errors**:
```bash
# Install build dependencies
sudo apt install build-essential zlib1g-dev

# Recompile with debugging
cd cctools-source
make clean
./configure --prefix=$HOME/cctools --debug
make
make install
```

2. **Library Path Issues**:
```bash
# Add to LD_LIBRARY_PATH
export LD_LIBRARY_PATH=$HOME/cctools/lib:$LD_LIBRARY_PATH
echo 'export LD_LIBRARY_PATH=$HOME/cctools/lib:$LD_LIBRARY_PATH' >> ~/.bashrc
```

### NumPy/SciPy Installation Failures

**Symptoms**:
```
ERROR: Failed building wheel for numpy
```

**Solutions**:

1. **Install System Dependencies**:
```bash
# Ubuntu/Debian
sudo apt install python3-dev libblas-dev liblapack-dev gfortran

# CentOS/RHEL
sudo yum install python3-devel blas-devel lapack-devel gcc-gfortran

# macOS
brew install openblas gfortran
```

2. **Use Pre-built Wheels**:
```bash
# Upgrade pip
pip install --upgrade pip wheel setuptools

# Install with pre-built wheels
pip install --only-binary :all: numpy scipy
```

## Platform-Specific Issues

### WSL2 (Windows)

**GPU Access**:
```bash
# Install CUDA support for WSL2
# Download from: https://developer.nvidia.com/cuda/wsl

# Verify GPU access
nvidia-smi

# Enable in Docker
docker run --gpus all nvidia/cuda:11.8.0-base-ubuntu22.04 nvidia-smi
```

**File System Performance**:
```bash
# Use native Linux filesystem for better performance
cd /home/username  # Good performance
# Avoid /mnt/c/    # Poor performance

# Move data to WSL filesystem
cp -r /mnt/c/Users/username/data ~/data
```

### macOS Apple Silicon

**Architecture Issues**:
```bash
# Install Rosetta 2
softwareupdate --install-rosetta

# Run with specific architecture
arch -x86_64 python script.py  # Intel
arch -arm64 python script.py   # ARM

# Check binary architecture
file $(which python)
```

**Homebrew Paths**:
```bash
# M1/M2 Homebrew location
export PATH=/opt/homebrew/bin:$PATH

# Intel Homebrew location  
export PATH=/usr/local/bin:$PATH
```

### SELinux (CentOS/RHEL)

**Permission Denials**:
```bash
# Check SELinux status
getenforce

# Temporary disable (testing only)
sudo setenforce 0

# Proper fix - set context
sudo chcon -Rt svirt_sandbox_file_t /path/to/data

# Or add SELinux rule
sudo setsebool -P container_manage_cgroup on
```

## Web Interface Specific Issues

### Resource Detection Shows Incorrect Values

**Symptoms**:
```
System shows incorrect CPU/memory values
```

**Solution**:
```bash
# Ensure psutil is installed
pip install psutil

# Restart web interface
python app.py

# Verify detection is working
curl http://localhost:5000/api/system/status
```

### Docker Subprocess Mode Issues

**Symptoms**:
```
Docker commands fail in subprocess mode
```

**Solution**:
```bash
# Ensure user has Docker permissions
sudo usermod -aG docker $USER
# Log out and back in

# Test Docker access
docker ps

# For Docker Compose deployments
docker-compose up --build
```

### Container Orchestration Problems

**Symptoms**:
```
Containers start but workflows don't execute
```

**Solution**:
```bash
# Check container logs
docker logs <container_id>

# Verify volume mounts
docker inspect <container_id> | grep -A 10 Mounts

# Ensure workflow scripts are accessible
docker run --rm eemt:ubuntu24.04 ls /opt/eemt/
```

## Diagnostic Commands

### Enhanced System Information (v2.0.0)

```bash
#!/bin/bash
# Save as diagnose.sh

echo "System Diagnostics for EEMT"
echo "============================"
echo ""

# OS Information
echo "Operating System:"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo "  $NAME $VERSION"
else
    echo "  $(uname -s) $(uname -r)"
fi

# Architecture
echo "  Architecture: $(uname -m)"
echo ""

# Python
echo "Python Environment:"
echo "  Python: $(python3 --version 2>&1)"
echo "  Pip: $(pip --version 2>&1)"
echo "  Virtual Env: ${VIRTUAL_ENV:-Not activated}"
echo ""

# Docker
echo "Docker Status:"
if command -v docker &> /dev/null; then
    echo "  $(docker --version)"
    echo "  Daemon: $(docker ps &> /dev/null && echo 'Running' || echo 'Not running')"
    # Check EEMT images
    echo "  EEMT Images:"
    docker images | grep eemt | sed 's/^/    /'
    # Check running containers
    echo "  Running Containers:"
    docker ps --filter "ancestor=eemt:ubuntu24.04" --filter "ancestor=eemt-web:latest" | sed 's/^/    /'
else
    echo "  Docker: Not installed"
fi
echo ""

# GRASS GIS
echo "GRASS GIS:"
if command -v grass &> /dev/null; then
    grass --version 2>&1 | head -1 | sed 's/^/  /'
else
    echo "  Not found in PATH"
fi
echo ""

# GDAL
echo "GDAL:"
if command -v gdalinfo &> /dev/null; then
    gdalinfo --version | sed 's/^/  /'
else
    echo "  Not found in PATH"
fi
echo ""

# Disk Space
echo "Disk Space:"
df -h . | tail -1 | awk '{print "  Available: "$4" of "$2}'
echo ""

# Memory
echo "Memory:"
if command -v free &> /dev/null; then
    free -h | grep Mem | awk '{print "  Total: "$2", Available: "$7}'
else
    echo "  Unable to determine"
fi
```

### Dependency Check

```python
#!/usr/bin/env python3
# Save as check_deps.py

import sys
import subprocess

def check_import(module):
    """Check if a Python module can be imported."""
    try:
        __import__(module)
        return True, None
    except ImportError as e:
        return False, str(e)

def check_command(cmd):
    """Check if a system command exists."""
    try:
        subprocess.run([cmd, '--version'], 
                      capture_output=True, 
                      check=False)
        return True
    except FileNotFoundError:
        return False

# Python modules to check (updated for v2.0.0)
modules = [
    'numpy', 'pandas', 'xarray', 'rasterio', 
    'geopandas', 'dask', 'scipy', 'matplotlib',
    'fastapi', 'uvicorn', 'psutil', 'docker'
]

# System commands to check
commands = ['grass', 'gdalinfo', 'docker', 'makeflow']

print("EEMT Dependency Check")
print("=" * 40)

print("\nPython Modules:")
for module in modules:
    success, error = check_import(module)
    status = "✓" if success else "✗"
    print(f"  {status} {module:20} {'OK' if success else error}")

print("\nSystem Commands:")
for cmd in commands:
    success = check_command(cmd)
    status = "✓" if success else "✗"
    print(f"  {status} {cmd:20} {'Found' if success else 'Not found'}")

print("\nPython Version:", sys.version)
```

## Getting Help

If these solutions don't resolve your issue:

1. **Collect Diagnostic Information**:
   ```bash
   ./diagnose.sh > diagnostics.txt
   python check_deps.py >> diagnostics.txt
   ```

2. **Search Existing Issues**:
   - [GitHub Issues](https://github.com/cyverse-gis/eemt/issues)
   - [Stack Overflow](https://stackoverflow.com/questions/tagged/grass-gis)

3. **Create New Issue** with:
   - Diagnostic output
   - Complete error messages
   - Steps to reproduce
   - Installation method attempted

4. **Community Support**:
   - [GitHub Discussions](https://github.com/cyverse-gis/eemt/discussions)
   - [GRASS GIS Mailing List](https://lists.osgeo.org/mailman/listinfo/grass-user)

---

*Return to [Installation Overview](index.md) or proceed to [Quick Start Guide](../workflows/quick-start.md).*