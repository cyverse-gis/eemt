# EEMT Algorithm Suite

[![License](https://img.shields.io/badge/license-BSD%203--Clause-blue.svg)](LICENSE)
[![Docker](https://img.shields.io/badge/docker-supported-blue.svg)](docker/)
[![Documentation](https://img.shields.io/badge/docs-mkdocs-blue.svg)](docs/)
[![Version](https://img.shields.io/badge/version-2.0.0-green.svg)](.)

The **Effective Energy and Mass Transfer (EEMT) Algorithm Suite** is a comprehensive geospatial modeling toolkit for calculating energy flux in the Critical Zone using topographic solar radiation modeling and climate data integration.

## Recent Modernization (2026)

- Migrated from deprecated `r.sun.mp` to GRASS GIS core `r.sun` with `nprocs` parameter
- Standardized on Python 3.11 for CCTools compatibility
- Removed legacy Singularity container definitions and deprecated workflow launchers
- Docker-based deployment with FastAPI web interface and real-time monitoring
- Automated job cleanup system with configurable retention policies

## 🚀 Quick Start

### Docker Compose (Fastest Setup)
Get up and running in under 5 minutes:

```bash
# 1. Clone repository
git clone https://github.com/tyson-swetnam/eemt.git
cd eemt

# 2. Start with Docker Compose (auto-builds containers)
docker-compose up

# 3. Access web interface
open http://127.0.0.1:5000  # Main interface
open http://127.0.0.1:5000/monitor  # Job monitoring
```

### Manual Setup
For development or custom configurations:

```bash
# 1. Build container (one-time setup)
cd docker/ubuntu/24.04/
./build.sh

# 2. Start web interface  
cd ../../web-interface/
pip install -r requirements.txt  # Includes psutil for resource detection
python app.py

# 3. Access via browser
firefox http://127.0.0.1:5000
```

### Key Features
- 🌐 **Web-based Interface**: Upload DEMs and configure workflows through responsive browser interface
- 🐳 **Containerized Execution**: Docker containers with all dependencies included (GRASS 8.4+, CCTools 7.8.2)
- 📊 **Real-time Monitoring**: Track progress with live updates, accurate system resource detection
- 🔄 **Multi-Workflow Support**: Solar radiation modeling and full EEMT analysis
- 💾 **Easy Results**: Download processed data as ZIP archives
- 🖥️ **System Awareness**: Automatic detection of available CPU cores and memory for optimal configuration

## 📋 What is EEMT?

EEMT quantifies energy flux in the Critical Zone by combining:
- **Solar Radiation**: Topographically-modified energy input using GRASS GIS r.sun
- **Climate Data**: DAYMET temperature, precipitation, and vapor pressure
- **Topographic Analysis**: Slope, aspect, and wetness index calculations
- **Energy Balance**: Comprehensive energy transfer modeling

### Scientific Applications
- Soil formation rate prediction
- Landscape evolution modeling  
- Critical Zone Observatory analysis
- Climate change impact assessment

## 🏗️ Architecture

### Execution Modes

1. **Local Container Mode**
   - FastAPI web interface on localhost:5000
   - Docker containers with GRASS GIS 8.4+ and CCTools 7.8.2
   - Direct job submission via HTML interface

2. **Distributed Mode**
   - Master-worker architecture across VMs, HPC, HTC systems
   - Work Queue coordination with automatic load balancing
   - Support for SLURM, PBS, LSF batch schedulers

3. **OSG Mode** (Planned)  
   - HTCondor integration for Open Science Grid
   - Auto-scaling worker provisioning

### Workflow Types

#### Solar Radiation Modeling
- Calculates daily solar irradiation for entire year (365 tasks)
- Uses GRASS GIS r.sun for topographic solar modeling
- Generates monthly aggregated products
- Runtime: 5-30 minutes depending on DEM resolution

#### Full EEMT Analysis  
- Complete energy-mass transfer calculation
- Integrates solar radiation with DAYMET climate data
- Calculates topographic and traditional EEMT values
- Runtime: 1-4 hours depending on time period and resolution

## 📖 Documentation

- **[User Guide](docs/)**: Complete documentation with MkDocs
- **[Web Interface Guide](web-interface/README.md)**: FastAPI interface documentation  
- **[Algorithm Details](EEMT.md)**: Scientific background and methodology
- **[Distributed Deployment](docs/distributed-deployment/)**: Multi-node setup guide
## 🔧 Installation

### Prerequisites
- **Docker**: Version 20.0+ with daemon running
- **Python 3.11+**: For web interface dependencies
- **4GB+ RAM**: 8GB+ recommended for larger DEMs
- **20GB+ Disk**: For container images and workflow outputs

### Container Setup
```bash
# Build EEMT container with all dependencies
cd docker/ubuntu/24.04/
./build.sh

# Verify installation
docker run --rm eemt:ubuntu24.04 grass --version
docker run --rm eemt:ubuntu24.04 makeflow --version
```

### Web Interface Setup
```bash
cd web-interface/
pip install -r requirements.txt
python app.py
# Access at http://127.0.0.1:5000
```

## 🎯 Usage Examples

### Web Interface
1. Navigate to http://127.0.0.1:5000
2. Upload DEM file (GeoTIFF format)
3. Configure parameters (time step, atmospheric conditions, CPU threads)
4. Submit job and monitor progress
5. Download results when complete

### Distributed Execution
```bash
# Start master node with web interface
python scripts/start-master.py \
    --work-dir /data/eemt-master \
    --web-interface --web-port 5000

# Start workers on remote machines
python scripts/start-worker.py \
    --master-host master-node-ip \
    --master-port 9123 \
    --cores 8 --memory 16G
```

### Direct Container Execution
```bash
# Solar radiation workflow
docker run --rm \
  -v $(pwd)/data:/data/input:ro \
  -v $(pwd)/results:/data/output:rw \
  eemt:ubuntu24.04 \
  python /opt/eemt/bin/run-solar-workflow.py \
  --dem /data/input/your_dem.tif \
  --output /data/output \
  --step 15 --num-threads 4 --job-id solar-001
```

### REST API
```bash
# Submit job programmatically
curl -X POST "http://127.0.0.1:5000/api/submit-job" \
  -F "workflow_type=sol" \
  -F "dem_file=@your_dem.tif" \
  -F "step=15" \
  -F "num_threads=4"
```

## 📊 Data Sources

- **DAYMET v4**: 1km daily meteorological data (1980-present)
- **User DEMs**: Any GDAL-supported elevation data
- **3DEP (USGS)**: 1m lidar coverage (recommended)
- **SRTM/ASTER**: Global coverage options

## 🤝 Contributing

1. Fork the repository
2. Create feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open Pull Request

## 📄 License

This project is licensed under the BSD 3-Clause License - see the [LICENSE](LICENSE) file for details.

## 📚 Citations

If you use EEMT in your research, please cite:
- Pelletier, J.D., et al. (2017). *Journal of Geophysical Research*, [DOI](https://doi.org/xxx)
- Rasmussen, C., et al. (2015). *Earth Surface Processes and Landforms*, [DOI](https://doi.org/xxx)

## 🆘 Support

- 📖 [Documentation](docs/)
- 🐛 [Issue Tracker](https://github.com/tyson-swetnam/eemt/issues)
- 💬 [Discussions](https://github.com/tyson-swetnam/eemt/discussions)
- 📧 Email: [tswetnam@cyverse.org](mailto:tswetnam@cyverse.org)

---

*Part of the CyVerse geospatial analysis ecosystem*
