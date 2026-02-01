---
title: Installation
---

# Installation Guide

## Overview

The EEMT (Effective Energy and Mass Transfer) suite can be deployed through multiple methods, each suited to different use cases and environments. This guide provides comprehensive installation instructions for all deployment options.

## Installation Methods

### 🐳 [Docker Deployment](docker.md) (Recommended)
The containerized approach provides the most reliable and reproducible installation method:
- **Advantages**: No dependency conflicts, consistent environment, easy updates
- **Best for**: Most users, production deployments, cloud environments
- **Requirements**: Docker Engine 20.10+ and Docker Compose v2.0+

### 🔧 [Manual Installation](manual.md)
Direct installation on your system for development or customization:
- **Advantages**: Full control, easier debugging, native performance
- **Best for**: Developers, HPC environments, custom integrations
- **Requirements**: Python 3.12+, GRASS GIS 8.4+, GDAL 3.8+

### 📋 [Requirements & Dependencies](requirements.md)
Detailed list of all software dependencies and system requirements:
- Hardware specifications
- Software prerequisites
- Python package requirements
- Optional components

### 🔍 [Troubleshooting](troubleshooting.md)
Common installation issues and their solutions:
- Docker-specific problems
- Dependency conflicts
- Permission issues
- Platform-specific considerations

## Quick Start

For most users, we recommend the Docker deployment:

```bash
# Clone the repository
git clone https://github.com/cyverse-gis/eemt.git
cd eemt

# Start with Docker Compose
docker-compose up

# Access web interface
# Open browser to http://localhost:5000
```

## System Requirements

### Minimum Hardware
- **CPU**: 4 cores (8+ recommended for parallel processing)
- **RAM**: 8 GB (16+ GB recommended for large datasets)
- **Storage**: 50 GB free space (more for large study areas)
- **GPU**: Optional but recommended for r.sun calculations

### Operating Systems
- **Linux**: Ubuntu 20.04+, CentOS 7+, Debian 10+
- **macOS**: 11.0+ (Big Sur or later)
- **Windows**: Windows 10+ with WSL2 or Docker Desktop

## Verification

After installation, verify your setup:

```bash
# Docker installation
docker run --rm eemt:ubuntu24.04 python -c "import eemt; print('EEMT installed successfully')"

# Manual installation  
python -c "import eemt; print('EEMT installed successfully')"
grass --version
makeflow --version
```

## Next Steps

After successful installation:

1. Review the [Quick Start Guide](../workflows/quick-start.md) for your first analysis
2. Explore [Example Workflows](../examples/index.md) for real-world applications
3. Check the [API Documentation](../api/index.md) for detailed usage
4. Join our [community forum](https://github.com/cyverse-gis/eemt/discussions) for support

## Support

If you encounter issues during installation:

1. Check the [Troubleshooting Guide](troubleshooting.md)
2. Search [existing issues](https://github.com/cyverse-gis/eemt/issues)
3. Create a [new issue](https://github.com/cyverse-gis/eemt/issues/new) with:
   - Your operating system and version
   - Installation method attempted
   - Complete error messages
   - Output of diagnostic commands

---

*For development setup and contribution guidelines, see the [Development Guide](../development/index.md).*