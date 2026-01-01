# EEMT Web Interface - Local Mode

A modern web-based interface for submitting and monitoring EEMT (Effective Energy and Mass Transfer) and solar radiation workflows in local execution mode.

## Features

- 🌐 **Web-based Job Submission**: Upload DEM files and configure parameters through a responsive interface
- 📊 **Real-time Monitoring**: Track job progress with live updates and status monitoring
- 🔄 **Multi-Workflow Support**: Choose between solar radiation modeling and full EEMT analysis
- 💾 **Result Management**: Download completed results as ZIP archives
- 📱 **Responsive Design**: Works on desktop, tablet, and mobile devices
- ⚡ **Fast API Backend**: High-performance REST API built with FastAPI
- 🐳 **Containerized Execution**: Docker containers with all dependencies included
- 🔄 **Progress Streaming**: Real-time log monitoring via container output parsing
- 🛠️ **Resource Management**: Automatic container lifecycle and cleanup

## Prerequisites

### System Requirements
- **Docker**: Version 20.0+ with daemon running
- **Python 3.8+**: For web interface dependencies
- **4GB+ RAM**: 8GB+ recommended for larger DEMs
- **20GB+ Disk**: For container images and workflow outputs

### Container Setup (Required)
The web interface uses Docker containers for workflow execution:

```bash
# 1. Verify Docker installation
docker --version
docker info

# 2. Build EEMT container (one-time setup)
cd ../docker/ubuntu/24.04/
./build.sh

# 3. Verify container image
docker images | grep eemt
# Should show: eemt:ubuntu24.04

# 4. Test container functionality
docker run --rm eemt:ubuntu24.04 grass --version
docker run --rm eemt:ubuntu24.04 makeflow --version
```

### Legacy Direct Execution (Not Recommended)
If you prefer direct execution without containers (not recommended):
- GRASS GIS 8.4+ (with r.sun.mp support)
- CCTools 7.8+ (Makeflow + Work Queue)
- GDAL 3.8+
- Complete Python geospatial environment

## Quick Start

### 1. Build Container (One-time Setup)
```bash
# Navigate to container directory and build
cd ../docker/ubuntu/24.04/
./build.sh

# This creates the eemt:ubuntu24.04 image with:
# - GRASS GIS 8.4+ with r.sun extensions
# - CCTools 7.8.2 (Makeflow + Work Queue)  
# - Python 3.12 geospatial environment
# - EEMT workflow scripts
```

### 2. Install Web Interface Dependencies
```bash
cd ../../web-interface/
pip install -r requirements.txt
```

### 3. Start the Web Service
```bash
python app.py
```

The service will start on `http://127.0.0.1:5000` and automatically:
- Check Docker availability
- Verify container image exists
- Display system status in web interface

### 4. Access the Interface
Open your web browser and navigate to:
- **Main Interface**: http://127.0.0.1:5000
- **Job Monitor**: http://127.0.0.1:5000/monitor
- **API Documentation**: http://127.0.0.1:5000/docs (auto-generated)

## Usage Guide

### Submitting a Workflow

1. **Choose Workflow Type**:
   - **Solar Radiation**: Calculate daily and monthly solar irradiation (365 tasks)
   - **Full EEMT**: Complete energy-mass transfer analysis with climate data

2. **Upload DEM File**:
   - Format: GeoTIFF (.tif or .tiff)
   - Projection: Any GDAL-supported coordinate system
   - Size: Tested up to 100MB+ files

3. **Configure Parameters**:
   - **Time Step**: Solar calculation interval (3-15 minutes)
   - **Linke Turbidity**: Atmospheric clarity (1.0-8.0)
   - **Surface Albedo**: Ground reflectance (0.0-1.0)
   - **CPU Threads**: Parallel processing cores

4. **EEMT-Specific Options** (if selected):
   - **Start/End Year**: DAYMET climate data range (1980-2024)

5. **Submit**: Click "Submit Workflow" to start processing

### Monitoring Jobs

The job monitor provides:
- **Summary Dashboard**: Count of pending, running, completed, and failed jobs
- **Job Table**: Detailed list with progress bars and status indicators
- **Real-time Updates**: Auto-refresh every 5 seconds (configurable)
- **Job Details**: Click the eye icon for detailed information
- **Results Download**: Download completed results as ZIP files

### Job Status Indicators

| Status | Description | Color | Container State |
|--------|-------------|--------|-----------------|
| Pending | Waiting to start | Yellow | Queued |
| Running | Currently processing | Blue | Container executing |
| Completed | Finished successfully | Green | Container finished |
| Failed | Error occurred | Red | Container failed/stopped |

### Container Execution Flow

1. **Job Submission**: DEM uploaded, parameters validated
2. **Container Launch**: Docker container started with volume mounts
3. **Workflow Execution**: Container runs GRASS/Makeflow workflows
4. **Progress Monitoring**: Real-time log streaming and parsing
5. **Results Collection**: Outputs saved to mounted volume
6. **Cleanup**: Container automatically removed, temp data cleaned

## API Reference

### REST Endpoints

#### Submit Job
```http
POST /api/submit-job
Content-Type: multipart/form-data

Parameters:
- workflow_type: "sol" or "eemt"
- dem_file: GeoTIFF file
- step: float (default: 15.0)
- linke_value: float (default: 3.0)
- albedo_value: float (default: 0.2)
- num_threads: int (default: 4)
- start_year: int (EEMT only)
- end_year: int (EEMT only)
```

#### List Jobs
```http
GET /api/jobs
```

#### Get Job Details
```http
GET /api/jobs/{job_id}
```

#### Download Results
```http
GET /api/jobs/{job_id}/results
```

#### System Status
```http
GET /api/system/status
```

Returns Docker availability and container statistics:
```json
{
  "docker_available": true,
  "container_stats": {
    "total_containers": 2,
    "running_jobs": ["job-123", "job-456"],
    "system_stats": {
      "cpus": 8,
      "memory": 16777216000,
      "containers_running": 2
    }
  },
  "image_name": "eemt:ubuntu24.04"
}
```

## Configuration

### Environment Variables
```bash
# Optional customization
export EEMT_HOST="0.0.0.0"        # Bind to all interfaces
export EEMT_PORT="5000"            # Default port (avoid conflict with mkdocs:8000)
export EEMT_UPLOAD_DIR="./uploads" # Custom upload directory
export EEMT_RESULTS_DIR="./results" # Custom results directory
```

### Database
The interface uses SQLite for job tracking:
- **Location**: `./jobs.db`
- **Schema**: Auto-created on first run
- **Backup**: Standard SQLite backup tools

## File Structure

### Host Directory Structure
```
web-interface/
├── app.py                             # FastAPI application with container integration
├── requirements.txt                   # Python dependencies (includes docker)
├── README.md                         # This file
├── containers/                        # Container management
│   ├── __init__.py
│   └── workflow_manager.py            # Docker orchestration and monitoring
├── templates/                         # HTML interfaces
│   ├── index.html                     # Job submission with Docker status
│   └── monitor.html                   # Real-time monitoring dashboard
├── static/                            # Frontend assets
│   ├── style.css                      # Enhanced responsive styling
│   ├── app.js                         # Job submission with container checks
│   └── monitor.js                     # Real-time progress monitoring
├── uploads/                           # DEM file uploads (auto-created)
├── results/                           # Containerized job outputs (auto-created) 
├── temp/                              # Temporary processing data (auto-created)
├── cache/                             # Workflow caching (auto-created)
└── jobs.db                           # SQLite job database (auto-created)
```

### Container Structure (eemt:ubuntu24.04)
```
/opt/eemt/
├── bin/                               # Container entry points
│   ├── run-solar-workflow.py         # Solar radiation wrapper
│   └── run-eemt-workflow.py          # Full EEMT wrapper
├── sol/                               # Solar workflow source
│   └── sol/
│       ├── run-workflow               # Original Python orchestrator
│       ├── rsun.sh                    # GRASS r.sun.mp wrapper
│       └── rsum.sh                    # Monthly aggregation
└── eemt/                              # EEMT workflow source
    └── eemt/
        ├── run-workflow               # Original Python orchestrator
        ├── reemt.sh                   # Core EEMT calculations
        └── metget.sh                  # Climate data retrieval
```

## Development

### Running in Development Mode
```bash
# Enable auto-reload and debug logging
uvicorn app:app --host 127.0.0.1 --port 5000 --reload --log-level debug
```

### Adding New Features
1. **REST Endpoints**: Add routes to `app.py`
2. **Frontend**: Modify templates and static files
3. **Database**: Update schema in `init_database()` function

### Testing
```bash
# Test job submission
curl -X POST "http://127.0.0.1:5000/api/submit-job" \
     -F "workflow_type=sol" \
     -F "dem_file=@test.tif" \
     -F "num_threads=2"

# Test API endpoints
curl "http://127.0.0.1:5000/api/jobs"
```

## Troubleshooting

### Common Issues

1. **"Docker not available or image not built"**:
   - Verify Docker daemon is running: `docker info`
   - Build container: `cd ../docker/ubuntu/24.04 && ./build.sh`
   - Check image exists: `docker images | grep eemt`

2. **"Container execution failed"**:
   - Check Docker logs: `docker logs <container_id>`
   - Verify volume mounts have correct permissions
   - Ensure adequate disk space for container execution

3. **"Job failed with errors"**:
   - Check job details in web interface for container logs
   - Verify DEM file is valid GeoTIFF with proper projection
   - Check available resources (CPU, memory, disk)

4. **"Upload fails"**:
   - Verify file is a valid GeoTIFF
   - Check file permissions and disk space
   - Ensure file size is reasonable (<1GB recommended for containers)

5. **"Container build fails"**:
   - Ensure Docker has sufficient space (20GB+)
   - Check network connectivity for package downloads
   - Verify base Ubuntu 24.04 image availability

### Performance Optimization

- **Large DEMs**: Consider tiling very large elevation models before processing
- **Container Resources**: Adjust CPU/memory limits in workflow_manager.py
- **Concurrent Jobs**: Limit simultaneous containers based on available resources
- **Disk Space**: Monitor storage usage in uploads/, results/, temp/, and cache/
- **Container Cleanup**: Automatic cleanup prevents resource leaks
- **Image Optimization**: Container image is ~5GB, ensure adequate Docker space

## Integration with Other Modes

This local interface serves as the foundation for:
- **Distributed Mode**: Replace local execution with Work Queue masters
- **OSG Mode**: Integrate with HTCondor job submission
- **Cloud Mode**: Deploy on cloud infrastructure with persistent storage

See `../PLAN.md` for the complete modernization roadmap.

## License

Part of the EEMT Algorithm Suite. See main project LICENSE for details.