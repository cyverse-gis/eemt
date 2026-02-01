# EEMT Modernization Plan (2025)

## Overview

This plan outlines the modernization of the Effective Energy and Mass Transfer (EEMT) algorithm suite, transitioning from 2016-era implementations to leverage contemporary geospatial software advances and cloud-native computing paradigms.

## Current State Assessment

### Legacy System (2016)
- **GRASS GIS**: Version 6.x/7.x (current: 8.x available)
- **GDAL**: Version 1.x (current: 3.8+)
- **PROJ**: Version 4.x (current: 9.x with enhanced datum transformations)
- **Workflow Engine**: CCTools Makeflow + Work Queue
- **Computing Environment**: OpenScienceGrid, XSEDE HPC clusters
- **Container Technology**: Docker (basic implementation)
- **Language**: Python 2.x, Bash scripts

### Technical Debt Identified
1. **Python 2.x deprecation**: End-of-life compatibility issues
2. **Hardcoded OpenScienceGrid URLs**: Broken data access endpoints
3. **SAGA-GIS dependencies**: Planned deprecation in favor of GRASS-native tools
4. **Legacy projection handling**: Pre-PROJ 6.x datum transformations
5. **Manual DAYMET downloads**: No API integration for automated data access

## Modernization Objectives

### Phase 1: Foundation Modernization (Q1 2025)

#### Software Stack Updates
- **Python 3.12+**: Full migration with type hints and async support
- **GRASS GIS 8.4+**: Latest LTS with enhanced parallelization
- **GDAL 3.8+**: Modern format support and cloud-optimized GeoTIFF
- **PROJ 9.x**: Enhanced coordinate reference system handling
- **QGIS 3.34+ LTR**: Integration for processing algorithm development

#### Container Modernization
- **Apptainer/Singularity**: Replace Docker for HPC compatibility
- **Multi-stage builds**: Optimize container size and security
- **Base images**: Official OSGEO/GDAL containers as foundation

#### Code Quality Improvements
- **Type annotations**: Full Python typing for better maintainability
- **Error handling**: Comprehensive exception management
- **Logging**: Structured logging with configurable levels
- **Testing**: Unit and integration test suites
- **Documentation**: API docs with Sphinx

### Phase 2: Data Infrastructure Modernization (Q2 2025)

#### Cloud-Optimized Data Access
- **STAC (SpatioTemporal Asset Catalog)**: Standardized metadata
- **Cloud-Optimized GeoTIFF (COG)**: Efficient remote data access
- **Zarr arrays**: Chunked, compressed multi-dimensional data
- **Dask integration**: Parallel processing of large datasets

#### DAYMET API Integration
- **ORNL DAAC API**: Direct programmatic access to DAYMET v4
- **Temporal subsetting**: On-demand date range queries
- **Spatial subsetting**: Bounding box and geometry-based filtering
- **Format optimization**: NetCDF4/Zarr for time series analysis

#### Alternative Climate Datasets
- **PRISM**: High-resolution precipitation and temperature (US)
- **ERA5**: Global reanalysis data via Climate Data Store
- **CHIRPS**: Global precipitation (focus on data-sparse regions)
- **TerraClimate**: Monthly global climate data

### Phase 3: Algorithm Enhancement (Q3 2025)

#### GRASS GIS 8.x Features
- **r.sun.mp**: Enhanced multi-core solar radiation modeling
- **r.sim.water**: Improved overland flow simulation
- **r.stream.extract**: Modern drainage network delineation
- **r.slope.aspect**: Vectorized slope/aspect calculations
- **Temporal framework**: Built-in time series management

#### GPU Acceleration
- **RAPIDS cuSpatial**: GPU-accelerated geospatial operations
- **r.sun OpenCL**: GPU solar radiation calculations
- **CuPy arrays**: NumPy-compatible GPU computations
- **Numba CUDA**: Just-in-time GPU kernel compilation

#### Advanced Topographic Analysis
- **Multiscale terrain analysis**: Automated scale-dependent metrics
- **Geomorphons**: Landform classification integration
- **Flow accumulation algorithms**: Multiple flow direction methods
- **Landscape connectivity**: Graph-based terrain analysis

### Phase 4: Multi-Mode Execution Architecture (Q4 2025)

#### Execution Modes
The modernized EEMT system supports three distinct execution modes to accommodate different computational environments and use cases:

##### 1. Local Mode
- **Web Service**: FastAPI-based REST API on localhost:`<port>`
- **Job Submission**: HTML interface for DEM upload and parameter configuration
- **Execution Engine**: Direct local execution with progress monitoring
- **Resource Management**: Automatic CPU/memory detection and allocation
- **Use Cases**: Development, small-scale analysis, educational environments

##### 2. Distributed Mode
- **Master-Worker Architecture**: Central coordinator with remote compute nodes
- **Worker Types**: VMs, HPC login nodes, container clusters
- **Load Balancing**: Dynamic task distribution based on resource availability
- **Fault Tolerance**: Automatic retry and worker replacement mechanisms
- **Communication**: Work Queue protocol with encrypted connections
- **Use Cases**: Multi-institutional collaboration, hybrid cloud-HPC deployments

##### 3. OSG Mode
- **HTCondor Integration**: Native OSG job submission and management
- **Container Support**: Singularity/Apptainer containers for reproducibility
- **Auto-Scaling**: Dynamic worker provisioning based on queue depth
- **Resource Classes**: Different resource profiles (standard, high-memory, GPU)
- **Monitoring**: Integration with OSG monitoring infrastructure
- **Use Cases**: Large-scale continental analysis, parameter sweeps, ensemble runs

#### Workflow Engines
- **Nextflow**: Primary workflow engine with container and cloud support
- **Legacy Makeflow**: Backward compatibility for existing deployments
- **Apache Airflow**: Alternative for complex data pipeline orchestration
- **CWL (Common Workflow Language)**: Portable workflow descriptions

#### Web Service Architecture
```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   HTML Client  │    │   FastAPI Core   │    │ Execution Modes │
│                 │    │                  │    │                 │
│ • Job Submit   ◄────► • REST Endpoints  ◄────► • Local         │
│ • Monitor      │    │ • Authentication │    │ • Distributed   │
│ • Results      │    │ • Job Queue      │    │ • OSG           │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                              │
                              ▼
                      ┌──────────────────┐
                      │ Workflow Engines │
                      │                  │
                      │ • Nextflow       │
                      │ • Makeflow       │
                      │ • Task Scheduler │
                      └──────────────────┘
```

#### Cloud-Native Computing
- **Kubernetes**: Container orchestration for scalable deployments
- **Dask Gateway**: Distributed computing on cloud infrastructure
- **JupyterHub**: Collaborative notebook environments
- **Pangeo ecosystem**: Cloud-based earth science computing stack

#### HPC Integration
- **SLURM**: Modern batch scheduler integration
- **LSF/PBS**: Legacy HPC system compatibility
- **Flux Framework**: Next-generation resource management
- **Charliecloud**: HPC-friendly container runtime

## New Capabilities and Features

### Enhanced Spatial Analysis
1. **Multi-resolution processing**: Adaptive grid refinement
2. **Uncertainty quantification**: Monte Carlo error propagation
3. **Machine learning integration**: RF/XGBoost for parameter estimation
4. **Change detection**: Temporal trend analysis capabilities

### Improved Climate Integration
1. **Climate scenarios**: RCP/SSP future projections
2. **Bias correction**: Statistical downscaling methods
3. **Extreme events**: Return period analysis
4. **Seasonal decomposition**: Trend/seasonal/residual components

### Advanced Visualization
1. **Interactive dashboards**: Streamlit/Dash applications
2. **Time series visualization**: Plotly/Bokeh temporal plots
3. **3D terrain rendering**: PyVista/Mayavi landscape views
4. **Web mapping**: Folium/Leaflet interactive maps

## Public Dataset Integration

### High-Resolution Topography
- **3DEP (USGS)**: 1-meter resolution US-wide lidar coverage
- **FABDEM**: Forest-corrected global 30m elevation
- **COP-DEM**: Copernicus 30/90m global elevation
- **OpenTopography**: On-demand lidar data access

### Climate and Environmental Data
- **GridMET**: High-resolution meteorological data (US)
- **Landsat Collection 2**: 50-year earth observation archive
- **Sentinel-2**: High-resolution multispectral imagery (5-day revisit)
- **MODIS**: Long-term vegetation and land surface datasets

### Derived Products
- **Global Forest Change**: Annual forest loss/gain (2000-present)
- **ESA WorldCover**: 10m global land cover classification
- **USGS GAP**: Vegetation and species distribution (US)
- **SoilGrids**: Global soil property predictions

## CLAUDE.md Implementation

### Purpose
A configuration file to guide Claude Code assistant in understanding the modernized EEMT codebase structure and computational requirements.

### Key Contents
```yaml
project_type: geospatial_modeling
language: python
version: "3.12+"
dependencies:
  - grass-gis>=8.4
  - gdal>=3.8
  - rasterio>=1.3
  - xarray>=2024.1
  - dask>=2024.1
  - geopandas>=0.14
  
test_commands:
  - "pytest tests/"
  - "grass --version"
  - "gdalinfo --version"
  
compute_requirements:
  memory_per_thread: "2GB"
  threads_default: 4
  gpu_optional: true
  
data_sources:
  - "ORNL DAAC DAYMET API"
  - "USGS 3DEP elevation"
  - "User-provided DEM files"
  
workflow_engines:
  - "Nextflow (preferred)"
  - "Apache Airflow"
  - "Dask Distributed"
```

## Multi-Mode Implementation Roadmap

### Phase A: Local Mode Development (Weeks 1-4)
1. **FastAPI Service Setup**
   - REST API endpoints for job submission and monitoring
   - File upload handling for DEM and configuration
   - SQLite database for job queue management
   - Basic authentication and session management

2. **HTML Interface Development**
   - Responsive web interface for job submission
   - Real-time progress monitoring with WebSocket connections
   - Results visualization and download capabilities
   - Parameter validation and input sanitization

3. **Workflow Integration**
   - Adaptation of existing sol/ and eemt/ workflows
   - Python subprocess management for local execution
   - Resource monitoring and allocation
   - Error handling and logging improvements

### Phase B: Distributed Mode Implementation (Weeks 5-8)
1. **Master Node Architecture**
   - Work Queue master integration with FastAPI
   - Worker registration and heartbeat monitoring
   - Dynamic load balancing algorithms
   - Fault tolerance and task retry mechanisms

2. **Worker Node Deployment**
   - Containerized worker images (Docker/Singularity)
   - Auto-discovery and registration protocols
   - Resource profiling and capability advertisement
   - Secure communication channels

3. **Management Interface**
   - Worker status dashboard
   - Resource utilization monitoring
   - Job distribution visualization
   - Administrative controls for worker management

### Phase C: OSG Mode Development (Weeks 9-12)
1. **HTCondor Integration**
   - Job submission template generation
   - Resource requirement specification
   - Singularity container job execution
   - OSG-specific monitoring integration

2. **Auto-Scaling Implementation**
   - Queue depth monitoring
   - Dynamic worker provisioning
   - Cost optimization algorithms
   - Resource class selection logic

3. **OSG-Specific Features**
   - Site blacklisting and resource preferences
   - Data staging and output collection
   - Integration with existing OSG infrastructure
   - Compliance with OSG usage policies

## Implementation Timeline

### 2025 Milestones
- **Q1**: Foundation modernization and Local Mode deployment
- **Q2**: Cloud data infrastructure and Distributed Mode operational  
- **Q3**: Enhanced algorithms and OSG Mode integration
- **Q4**: Production deployment across all execution modes

### Success Metrics
- **Performance**: 5x speedup through GPU acceleration and parallel execution
- **Scalability**: Process continental-scale datasets across execution modes
- **Reliability**: 99%+ workflow success rate with automatic fault recovery
- **Accessibility**: Web interface reduces barrier to entry for new users
- **Flexibility**: Seamless switching between local, distributed, and OSG modes
- **Sustainability**: Active community contribution model with modern tooling

## Risk Mitigation

### Technical Risks
1. **GPU availability**: Fallback to CPU implementations
2. **Data access failures**: Local caching and alternative sources
3. **Version compatibility**: Comprehensive testing matrix
4. **Performance regression**: Benchmark-driven development

### Resource Risks  
1. **Compute costs**: Efficient algorithms and resource monitoring
2. **Storage requirements**: Compression and data lifecycle policies
3. **Network bandwidth**: Edge computing and data locality

## Community Engagement

### Open Source Strategy
- **GitHub**: Public development with issue tracking
- **Documentation**: Comprehensive user guides and tutorials
- **Examples**: Jupyter notebooks for common use cases
- **Workshops**: Virtual training sessions

### Academic Partnerships
- **CZO Network**: Critical Zone Observatory collaboration
- **OpenTopography**: Processing pipeline integration
- **CUAHSI**: Hydrology informatics community engagement
- **AGU/ESA**: Conference presentations and workshops

This modernization plan positions EEMT for the next decade of geospatial computing while maintaining scientific rigor and expanding accessibility to the broader earth science community.