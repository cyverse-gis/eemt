# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Claude Code Assistant Configuration for EEMT

## Project Overview
**Project Name**: Effective Energy and Mass Transfer (EEMT) Algorithm Suite  
**Type**: Geospatial modeling and Critical Zone science  
**Primary Language**: Python 3.12+  
**Secondary Languages**: Bash, R (for analysis)  
**Domain**: Earth System Science, Geomorphology, Hydrology  

## Specialized Agent Configuration

This project utilizes specialized Claude Code agents located in `.claude/agents/` to handle domain-specific tasks with expert knowledge. These agents provide specialized assistance for different aspects of EEMT development and deployment.

### Available Specialized Agents

#### 1. **python-gis-expert** (`.claude/agents/python-gis-expert.md`)
**Use for**: Geospatial data processing, GIS workflows, and spatial analysis tasks
- **Expertise**: GDAL, PDAL, PROJ, GRASS GIS, PyQGIS, raster/vector processing
- **EEMT Applications**: DEM processing, coordinate transformations, spatial data validation
- **When to use**: Working with GeoTIFF files, projection handling, topographic analysis

#### 2. **workflow-debug-agent** (`.claude/agents/workflow-debug-agent.md`)
**Use for**: Makeflow/Work Queue debugging and distributed computing optimization
- **Expertise**: CCTools, foreman-worker architectures, task distribution, performance tuning
- **EEMT Applications**: Solar radiation workflow optimization, distributed EEMT calculations
- **When to use**: Workflow execution failures, task timeout issues, resource allocation problems

#### 3. **container-orchestrator** (`.claude/agents/container-orchestrator.md`)
**Use for**: Docker, Kubernetes, and container deployment management
- **Expertise**: Container orchestration, Docker Compose, deployment strategies
- **EEMT Applications**: EEMT container builds, web interface deployment, scaling strategies
- **When to use**: Container configuration, deployment issues, scaling requirements

#### 4. **fastapi-html-frontend** (`.claude/agents/fastapi-html-frontend.md`)
**Use for**: Web interface development and FastAPI backend integration
- **Expertise**: FastAPI development, HTML frontends, REST API design, job management
- **EEMT Applications**: Web-based workflow submission, job monitoring, results visualization
- **When to use**: Web interface issues, API endpoints, frontend-backend integration

#### 5. **mkdocs-documentation-writer** (`.claude/agents/mkdocs-documentation-writer.md`)
**Use for**: Documentation creation and maintenance using MkDocs
- **Expertise**: Technical writing, MkDocs configuration, documentation workflows
- **EEMT Applications**: User guides, API documentation, algorithm explanations, tutorials
- **When to use**: Creating documentation, updating guides, writing technical content

#### 6. **agent-architect** (`.claude/agents/agent-architect.md`)
**Use for**: Complex multi-domain tasks requiring coordination between specialized agents
- **Expertise**: Task orchestration, agent coordination, workflow planning
- **EEMT Applications**: Large-scale refactoring, multi-component feature development
- **When to use**: Complex tasks spanning multiple domains (GIS + containers + docs)

### Agent Usage Guidelines

#### Automatic Agent Selection
Claude Code will automatically select appropriate specialized agents based on task context:

```python
# GIS data processing task → python-gis-expert
"I need to reproject this DEM and calculate slope"

# Workflow performance issue → workflow-debug-agent  
"My Makeflow is timing out on large datasets"

# Container deployment → container-orchestrator
"Help me scale the EEMT containers across multiple nodes"

# Web interface bug → fastapi-html-frontend
"The job submission form isn't validating parameters correctly"

# Documentation request → mkdocs-documentation-writer
"Create user documentation for the new GPU acceleration feature"

# Multi-domain task → agent-architect
"Refactor the entire workflow system to use Nextflow instead of Makeflow"
```

#### Manual Agent Invocation
You can explicitly request specific agents when needed:

```bash
# Request specific agent for specialized knowledge
"Use the python-gis-expert agent to help optimize this raster processing pipeline"

# Coordinate multiple agents for complex tasks
"Use the agent-architect to plan refactoring the web interface and container system"
```

### Agent Integration with EEMT Workflows

The specialized agents are pre-configured with EEMT domain knowledge:

- **python-gis-expert**: Understands DEM processing, GRASS GIS integration, DAYMET data handling
- **workflow-debug-agent**: Familiar with solar radiation task distribution, EEMT pipeline optimization
- **container-orchestrator**: Configured for EEMT Docker builds, web interface deployment
- **fastapi-html-frontend**: Knows EEMT job submission patterns, monitoring requirements
- **mkdocs-documentation-writer**: Understands EEMT algorithms, usage patterns, scientific context
- **agent-architect**: Coordinates complex EEMT modernization tasks across domains

## Software Dependencies

### Core Geospatial Stack
```yaml
gdal: ">=3.8"
proj: ">=9.0"
grass-gis: ">=8.4"
qgis: ">=3.34"  # LTR version
```

### Python Scientific Stack
```yaml
python: ">=3.12"
numpy: ">=1.26"
pandas: ">=2.1"
xarray: ">=2024.1"
rasterio: ">=1.3"
geopandas: ">=0.14"
dask: ">=2024.1"
scipy: ">=1.11"
matplotlib: ">=3.8"
```

### Workflow and HPC
```yaml
nextflow: ">=23.10"  # Preferred workflow engine
makeflow: ">=7.0"    # Legacy support
dask-distributed: ">=2024.1"
```

## Computational Requirements

### Default Resource Allocation
- **Threads**: 4 (configurable via `--num_threads`, supports up to 512)
- **Memory per thread**: 2GB minimum
- **Disk space**: 50GB for typical regional analysis
- **GPU**: Optional but recommended for large datasets

### Current System Capabilities (gpu06.cyverse.org)
- **CPU Cores**: 255 (automatically detected)
- **Memory**: 1007.7 GB (~1TB RAM) (automatically detected)
- **Docker Containers**: 14+ running simultaneously
- **System Detection**: Accurate resource reporting via psutil

### Scaling Characteristics
- **Daily solar calculations**: 365 parallel tasks
- **EEMT calculations**: 816 tasks for 34-year analysis
- **Memory scaling**: Linear with DEM resolution
- **I/O bottleneck**: Large raster operations
- **Resource Detection**: Automatic CPU/memory detection for optimal configuration

## Build and Development Commands

### Docker Deployment (Recommended)
```bash
# Quick start with Docker Compose
git clone https://github.com/cyverse-gis/eemt.git
cd eemt

# Local mode (single-node)
docker-compose up

# Distributed mode (master + workers)  
docker-compose --profile distributed up

# Access web interface
firefox http://127.0.0.1:5000        # Job submission interface
firefox http://127.0.0.1:5000/monitor # Job monitoring dashboard
firefox http://127.0.0.1:8000        # Documentation (with --profile docs)
```

### Manual Docker Build
```bash
# Build containers manually
cd docker/ubuntu/24.04/
./build.sh                           # Build eemt:ubuntu24.04 base container

# Build web interface container
docker build -t eemt-web -f docker/web-interface/Dockerfile .

# Start web interface container
docker run -p 5000:5000 -v $(pwd)/data:/app/data eemt-web
```

### Documentation Website
```bash
# Build and serve documentation locally
mkdocs serve                    # Local development server on localhost:8000
mkdocs build                    # Build static site

# Documentation dependencies are in requirements.txt
pip install -r requirements.txt
```

### Container Development
```bash
# Build Docker images with EEMT workflows
cd docker/ubuntu/24.04/
./build.sh                            # Ubuntu 24.04 with GRASS 8.4+, CCTools 7.8.2

# Alternative container builds
docker build -t eemt docker/centos/7  # CentOS 7 container (legacy)

# Manual container testing
docker run -it --rm -v $(pwd):/data eemt:ubuntu24.04
```

### Environment Verification
```bash
# Verify Docker and container image
docker --version
docker images | grep eemt            # Should show eemt:ubuntu24.04

# Test container workflow execution
docker run --rm \
  -v $(pwd)/web-interface/uploads:/data/input:ro \
  -v $(pwd)/web-interface/results:/data/output:rw \
  eemt:ubuntu24.04 \
  python /opt/eemt/bin/run-solar-workflow.py --help

# Check container dependencies
docker run --rm eemt:ubuntu24.04 grass --version
docker run --rm eemt:ubuntu24.04 makeflow --version
```

### Workflow Testing

#### Web Interface Testing (Recommended)
```bash
# Start web interface and submit jobs via browser
cd web-interface/ && python app.py
# Navigate to http://127.0.0.1:5000
# Upload DEM file and submit job through web interface
```

#### Direct Container Testing
```bash
# Test solar radiation workflow with container
docker run --rm \
  -v $(pwd)/sol/examples:/data/input:ro \
  -v $(pwd)/test-output:/data/output:rw \
  eemt:ubuntu24.04 \
  python /opt/eemt/bin/run-solar-workflow.py \
  --dem /data/input/mcn_10m.tif \
  --output /data/output \
  --step 15 --num-threads 2 --job-id test-001

# Verify workflow outputs
ls test-output/global/daily/total_sun_day_*.tif | wc -l  # Should be 365 files
ls test-output/global/monthly/total_sun_*_sum.tif | wc -l  # Should be 12 files
```

#### Legacy Direct Execution (Requires Host Dependencies)
```bash
# Note: Requires GRASS GIS, CCTools, and Python dependencies on host
# Use containerized execution instead for reliable results

cd sol/sol/
python run-workflow --step 15 --num_threads 2 ../examples/mcn_10m.tif

cd ../../eemt/eemt/
python run-workflow --start-year 2020 --end-year 2020 --step 15 ../examples/mcn_10m.tif
```

## Key Algorithms and Scripts

### Solar Radiation Modeling (`/sol/sol/`)
- **run-workflow** (Python): Main orchestrator for 365-day solar radiation calculations
- **rsun.sh** (Bash): GRASS GIS r.sun wrapper for daily solar calculations
- **rsum.sh** (Bash): Monthly aggregation using GRASS r.series
- **Tiff.py**: GeoTIFF metadata parsing utilities
- **parser.py**: Projection and coordinate system handling

### EEMT Calculations (`/eemt/eemt/`)  
- **run-workflow** (Python): Full EEMT pipeline with climate data integration
- **reemt.sh** (Bash): Core EEMT calculation combining solar and climate data
- **metget.sh** (Bash): Climate data download and preprocessing
- **twi.sh** (Bash): Topographic wetness index calculation
- **parser.py**: Enhanced GeoTIFF processing with DAYMET projection alignment
- **Tiff.py**: Shared utilities for raster data manipulation

### Key Parameters
- **step**: Solar calculation time interval (3-15 minutes)
- **linke_value**: Atmospheric turbidity (1.0-8.0)
- **albedo_value**: Surface reflectance (0.0-1.0)
- **start_year/end_year**: DAYMET temporal range

## Data Sources and APIs

### Primary Climate Data
- **DAYMET v4**: 1km daily meteorological data (1980-present)
- **ORNL DAAC API**: `https://daac.ornl.gov/daac/DAYMET`
- **Variables**: tmin, tmax, prcp, vp (vapor pressure)

### Topographic Data
- **User-provided DEM**: GeoTIFF format required
- **3DEP (USGS)**: 1m lidar coverage (recommended)
- **SRTM/ASTER**: Global coverage options

### Output Products
- **Global radiation**: `global/monthly/total_sun_*.tif`
- **EEMT results**: `eemt/EEMT_Topo_*.tif`
- **Processing logs**: `task_output.log`, `sys.err`

## Common Issues and Solutions

### Memory Management
- **Large DEMs**: Use `gdal_translate` to tile processing
- **Time series**: Implement chunked processing with Dask
- **GRASS location**: Temporary directories cleaned automatically

### Projection Handling
- **Input CRS**: Any GDAL-supported projection
- **Internal processing**: GRASS locations created per task
- **DAYMET alignment**: Automatic reprojection to match climate data

### Workflow Dependencies
- **GRASS database**: Temporary locations created automatically
- **Password file**: `~/.eemt-makeflow-password` required for Makeflow execution
- **CCTools (Makeflow + Work Queue)**: Distributed task execution system
- **Binary copies**: Shell scripts copied to output directory for task isolation
- **Legacy data URLs**: Hardcoded OpenScienceGrid URLs (may be broken - see PLAN.md)

## Development Guidelines

### Code Style
- **Python**: Follow PEP 8, use type hints
- **Bash**: Use `set -e` for error handling
- **Comments**: Explain scientific concepts, not just implementation

### Git Workflow Requirements
**CRITICAL**: After every successful prompt completion that modifies code, you MUST commit changes using detailed commit messages to enable future rollbacks.

#### Docker Container Rebuild Requirements
**MANDATORY**: Rebuild Docker containers after major changes to ensure consistency between codebase and deployed environments.

**Rebuild containers when changes affect:**
- Core workflow scripts (`sol/sol/`, `eemt/eemt/`)
- Docker configuration files (`docker/*/Dockerfile`, `docker-compose.yml`)
- System dependencies or GRASS GIS integration
- Web interface components (`web-interface/`)
- Python requirements or dependency changes
- Container entry points or workflow orchestration

**Container Rebuild Commands:**
```bash
# After major changes, rebuild base container
cd docker/ubuntu/24.04/
./build.sh

# Verify container build success
docker images | grep eemt:ubuntu24.04

# Rebuild web interface container if web components changed
docker build -t eemt-web -f docker/web-interface/Dockerfile .

# Test container functionality after rebuild
docker run --rm eemt:ubuntu24.04 grass --version
docker run --rm eemt:ubuntu24.04 makeflow --version
docker run --rm eemt:ubuntu24.04 python /opt/eemt/bin/run-solar-workflow.py --help

# For Docker Compose deployments, rebuild and restart services
docker-compose down
docker-compose build
docker-compose up -d

# Verify web interface is accessible
curl -f http://127.0.0.1:5000/health || echo "Web interface rebuild required"
```

**When NOT to rebuild:**
- Documentation-only changes (`docs/`, `*.md` files)
- Configuration file updates that don't affect container internals
- Minor bug fixes that don't change dependencies or system integration
- Git workflow or project management file changes

#### Required Git Commands After Each Successful Change
```bash
# Stage all modified files
git add .

# Commit with detailed message following this format:
git commit -m "[TASK]: Brief description

Detailed changes:
- List specific files modified
- Describe functional changes made
- Note any new features added
- Document any breaking changes
- Include rationale for changes

Files affected:
- path/to/file1.py: description of changes
- path/to/file2.sh: description of changes

Testing: [describe any testing performed]
Impact: [describe potential impact on system]
Container Status: [REBUILT/NO_REBUILD_NEEDED - specify if containers were rebuilt]

🤖 Generated with Claude Code (claude.ai/code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

#### Commit Message Examples
```bash
# Example 1: Bug fix
git commit -m "FIX: Correct memory leak in solar radiation calculations

Detailed changes:
- Fixed buffer overflow in rsun.sh when processing large DEMs
- Added bounds checking in parser.py coordinate transformations
- Improved error handling for malformed GeoTIFF inputs

Files affected:
- sol/sol/rsun.sh: Added memory cleanup and bounds checking
- sol/sol/parser.py: Enhanced coordinate validation
- eemt/eemt/parser.py: Synchronized validation logic

Testing: Tested with 10GB DEM file, memory usage stable
Impact: Prevents crashes on large datasets, improves stability
Container Status: REBUILT - Core workflow scripts modified, containers rebuilt and tested

🤖 Generated with Claude Code (claude.ai/code)

Co-Authored-By: Claude <noreply@anthropic.com>"

# Example 2: Feature addition
git commit -m "FEATURE: Add GPU acceleration support for r.sun calculations

Detailed changes:
- Implemented CUDA-accelerated solar radiation modeling
- Added GPU memory management and fallback to CPU
- Enhanced configuration options for GPU utilization
- Updated Docker containers with NVIDIA runtime support

Files affected:
- sol/sol/run-workflow: Added GPU detection and configuration
- sol/sol/rsun.sh: Integrated r.sun GPU mode
- docker/ubuntu/24.04/Dockerfile: Added CUDA runtime dependencies
- web-interface/containers/workflow_manager.py: GPU container orchestration

Testing: Validated 5x speedup on RTX 4090, fallback tested
Impact: Significant performance improvement for large-scale analyses
Container Status: REBUILT - CUDA dependencies added, containers rebuilt with NVIDIA runtime

🤖 Generated with Claude Code (claude.ai/code)

Co-Authored-By: Claude <noreply@anthropic.com>"

# Example 3: Refactoring
git commit -m "REFACTOR: Consolidate GeoTIFF parsing utilities

Detailed changes:
- Merged duplicate Tiff.py implementations
- Created shared geospatial utilities module
- Standardized coordinate system handling across workflows
- Eliminated code duplication between sol/ and eemt/ modules

Files affected:
- sol/sol/Tiff.py: Moved to shared/geospatial/tiff_utils.py
- eemt/eemt/Tiff.py: Moved to shared/geospatial/tiff_utils.py
- shared/geospatial/tiff_utils.py: Consolidated implementation
- sol/sol/parser.py: Updated imports
- eemt/eemt/parser.py: Updated imports

Testing: All existing tests pass, no functional changes
Impact: Improved maintainability, reduced technical debt
Container Status: NO_REBUILD_NEEDED - Code refactoring only, no container changes required

🤖 Generated with Claude Code (claude.ai/code)

Co-Authored-By: Claude <noreply@anthropic.com>"

# Example 4: Container rebuild scenario
git commit -m "UPDATE: Upgrade GRASS GIS to version 8.4 with enhanced r.sun performance

Detailed changes:
- Updated Docker base image to Ubuntu 24.04 LTS
- Upgraded GRASS GIS from 8.2 to 8.4 for improved GPU support
- Modified workflow scripts to use new GRASS API features
- Updated container entry points for compatibility
- Enhanced error handling for GRASS session management

Files affected:
- docker/ubuntu/24.04/Dockerfile: Updated GRASS GIS installation
- docker/ubuntu/24.04/build.sh: Modified build process
- sol/sol/rsun.sh: Updated GRASS API calls
- eemt/eemt/reemt.sh: Updated GRASS session handling
- web-interface/containers/workflow_manager.py: Updated container configuration

Testing: Rebuilt containers successfully, validated solar workflow execution
Impact: Improved performance and GPU acceleration compatibility
Container Status: REBUILT - Major GRASS GIS upgrade, full container rebuild completed

🤖 Generated with Claude Code (claude.ai/code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

#### Git Workflow Enforcement
- **MANDATORY**: Every code modification must be committed immediately after completion
- **NO BATCHING**: Do not accumulate multiple changes before committing
- **DESCRIPTIVE MESSAGES**: Include enough detail to understand and revert changes
- **FILE LISTING**: Always list specific files and their changes
- **TESTING NOTES**: Document any validation or testing performed
- **IMPACT ASSESSMENT**: Describe potential system impact
- **CONTAINER STATUS**: Always specify if containers were rebuilt or why rebuild was not needed
- **CONTAINER TESTING**: If containers were rebuilt, verify functionality before committing

#### Rollback Strategy
When issues are discovered:
```bash
# View recent commits with detailed info
git log --oneline -10

# Revert specific commit (creates new commit)
git revert [commit-hash]

# Reset to previous working state (destructive)
git reset --hard [commit-hash]

# Create branch from known good state
git checkout -b hotfix-[issue] [known-good-commit]
```

### Testing Strategy
- **Unit tests**: Individual function validation
- **Integration tests**: End-to-end workflow verification
- **Performance tests**: Scaling and resource usage benchmarks

### Error Handling
- **Graceful degradation**: Fallback to CPU if GPU unavailable
- **Checkpoint/restart**: Workflow resumption capabilities
- **Validation**: Input data quality checks

## Performance Optimization

### Computational Hotspots
1. **r.sun**: GPU acceleration available in GRASS 8.x
2. **Monthly aggregation**: Parallel r.series operations
3. **DAYMET downloads**: Concurrent API requests
4. **GeoTIFF I/O**: Cloud-optimized formats preferred

### Scaling Recommendations
- **Spatial**: Process by tiles for continental datasets
- **Temporal**: Parallelize year-wise calculations  
- **Resource**: Monitor memory usage per thread
- **I/O**: Use local SSD for temporary data

## Scientific Context

### Physical Basis
EEMT quantifies energy flux in the Critical Zone using:
- **Solar radiation**: Topographically-modified energy input
- **Climate variables**: Temperature and precipitation energy content
- **Biological processes**: NPP energy conversion
- **Landscape evolution**: Denudation and soil formation rates

### Validation Approaches
- **Field measurements**: Eddy covariance tower data
- **Literature comparison**: Published EEMT values
- **Sensitivity analysis**: Parameter uncertainty quantification
- **Cross-validation**: Independent climate datasets

### Applications
- Soil formation rate prediction
- Landscape evolution modeling  
- Critical Zone Observatory analysis
- Climate change impact assessment

## Architecture Overview

### Multi-Mode Execution Architecture
The EEMT system supports three distinct execution modes:

1. **Local Container Mode** (Current Implementation)
   - FastAPI web interface on localhost:5000
   - Docker containers for workflow execution
   - Direct job submission via HTML interface
   
2. **Distributed Mode** (Future)
   - Master-worker architecture with remote containers
   - Cross-host distributed execution
   - Load balancing and fault tolerance

3. **OSG Mode** (Future)
   - HTCondor integration for Open Science Grid
   - Auto-scaling worker provisioning
   - Singularity container support

### Workflow Execution System

#### Current: Containerized Local Execution
- **Interface**: FastAPI REST API with HTML frontend
- **Engine**: Docker containers with CCTools Makeflow + Work Queue
- **Tasks**: 365 daily solar calculations + monthly aggregations + EEMT computations
- **Parallelization**: Container-based (configurable CPU limits)
- **Monitoring**: Real-time progress via container log streaming
- **Output Management**: Volume-mounted results directory

#### Legacy: Direct Host Execution
- **Engine**: Direct CCTools Makeflow + Work Queue execution
- **Requirements**: GRASS GIS, CCTools, Python dependencies on host
- **Status**: Deprecated due to dependency complexity

### Key File Structure

```
/eemt/
├── web-interface/              # FastAPI web application (NEW)
│   ├── app.py                 # Main FastAPI application
│   ├── containers/            # Docker workflow management
│   │   └── workflow_manager.py # Container orchestration
│   ├── templates/             # HTML interface templates
│   │   ├── index.html         # Job submission page
│   │   └── monitor.html       # Job monitoring dashboard
│   ├── static/                # CSS, JavaScript, assets
│   ├── uploads/               # DEM file uploads (auto-created)
│   ├── results/               # Job output directories (auto-created)
│   └── requirements.txt       # FastAPI dependencies
├── sol/sol/                    # Solar radiation workflow components
│   ├── run-workflow           # Python orchestrator (365-day solar modeling)
│   ├── rsun.sh               # GRASS r.sun wrapper
│   ├── rsum.sh               # Monthly aggregation via r.series
│   ├── Tiff.py               # GeoTIFF utilities
│   ├── parser.py             # Projection handling
│   └── examples/             # Test datasets (mcn_10m.tif)
├── eemt/eemt/                  # Full EEMT pipeline
│   ├── run-workflow          # Python orchestrator (climate + solar integration) 
│   ├── reemt.sh             # Core EEMT calculations
│   ├── metget.sh            # Climate data retrieval
│   ├── twi.sh               # Topographic wetness index
│   ├── parser.py            # Enhanced GeoTIFF + DAYMET projection
│   └── Tiff.py              # Shared utilities
├── docker/                     # Container environments
│   ├── ubuntu/24.04/          # Primary container with GRASS 8.4+ & CCTools
│   │   ├── Dockerfile         # Container definition
│   │   ├── build.sh          # Container build script
│   │   └── container-scripts/ # Container workflow wrappers (NEW)
│   │       ├── run-solar-workflow.py   # Solar container entry point
│   │       └── run-eemt-workflow.py    # EEMT container entry point
│   ├── centos/7/              # Legacy HPC compatibility
│   └── grass*/                # GRASS GIS specific builds (legacy)
├── docs/                       # MkDocs documentation source
│   └── web-interface/         # Web interface documentation (NEW)
├── notebooks/                  # Jupyter analysis examples
├── requirements.txt            # Main project Python dependencies
├── EEMT.md                    # Algorithm documentation  
├── PLAN.md                    # Modernization roadmap
├── WORKFLOW_PLAN.md           # Containerized execution plan (NEW)
└── CLAUDE.md                  # This assistant guide
```

## Usage Examples

### Docker Deployment (Recommended)
```bash
# Quick start - one command deployment
git clone https://github.com/cyverse-gis/eemt.git
cd eemt && docker-compose up

# Access web interface at http://127.0.0.1:5000
# - Upload DEM file through browser interface
# - Configure workflow parameters
# - Monitor progress in real-time  
# - Download results when complete

# Distributed cluster deployment
docker-compose --profile distributed up --scale eemt-worker-2=5

# Master + workers on separate hosts
# On master host:
docker run -p 5000:5000 -p 9123:9123 eemt-web

# On worker hosts:
docker run -e MASTER_HOST=MASTER_IP eemt:ubuntu24.04
```

### Direct Container Execution
```bash
# Solar radiation modeling with container
docker run --rm \
  -v $(pwd)/uploads:/data/input:ro \
  -v $(pwd)/results:/data/output:rw \
  eemt:ubuntu24.04 \
  python /opt/eemt/bin/run-solar-workflow.py \
  --dem /data/input/your_dem.tif \
  --output /data/output \
  --step 15 --num-threads 4 --job-id solar-001

# Full EEMT analysis with container
docker run --rm \
  -v $(pwd)/uploads:/data/input:ro \
  -v $(pwd)/results:/data/output:rw \
  eemt:ubuntu24.04 \
  python /opt/eemt/bin/run-eemt-workflow.py \
  --dem /data/input/your_dem.tif \
  --output /data/output \
  --start-year 2020 --end-year 2020 \
  --step 15 --num-threads 8 --job-id eemt-001
```

### REST API Usage
```bash
# Submit job via API
curl -X POST "http://127.0.0.1:5000/api/submit-job" \
  -F "workflow_type=sol" \
  -F "dem_file=@your_dem.tif" \
  -F "step=15" \
  -F "num_threads=4"

# Check job status  
curl "http://127.0.0.1:5000/api/jobs/JOB_ID"

# Download results
curl -O "http://127.0.0.1:5000/api/jobs/JOB_ID/results"
```

### Custom Atmospheric Parameters
```bash
# High-resolution forest canopy analysis (via web interface)
# - Upload high_resolution_lidar_dem.tif
# - Set: step=3, linke_value=2.5, albedo_value=0.15, threads=16

# Arid region analysis (via container)
docker run --rm \
  -v $(pwd)/data:/data/input:ro \
  -v $(pwd)/results:/data/output:rw \
  eemt:ubuntu24.04 \
  python /opt/eemt/bin/run-solar-workflow.py \
  --dem /data/input/desert_dem.tif \
  --output /data/output \
  --step 15 --linke-value 1.5 --albedo-value 0.25 \
  --num-threads 8 --job-id desert-001
```

### Legacy Direct Execution (Deprecated)
```bash
# Note: Requires GRASS GIS, CCTools on host (complex setup)
# Use containerized execution instead

# Create required password file
echo "your_secure_password" > ~/.eemt-makeflow-password

# Navigate to workflow directory
cd sol/sol/
python run-workflow --step 15 --num_threads 4 /path/to/dem.tif

# Monitor workflow execution (if using Makeflow)
work_queue_status -M $(whoami)_SOL
```

This configuration enables Claude Code to effectively assist with EEMT algorithm development, debugging, and modernization tasks.