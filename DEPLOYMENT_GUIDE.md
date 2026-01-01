# EEMT Infrastructure Deployment Guide

## Overview
This guide documents the comprehensive modernization and deployment of the EEMT (Effective Energy and Mass Transfer) infrastructure, completed on January 1, 2026.

## Recent Modernization Changes

### 1. Python 2 to Python 3 Migration (Completed)
- **Status**: ✅ Fully migrated
- All workflow scripts updated to Python 3.12+
- Removed legacy Python 2 dependencies
- Updated imports and syntax across all modules
- Migrated from `imp` to `importlib.util` for dynamic module loading

### 2. Container Infrastructure (Completed)
- **Web Interface Container**: `eemt_eemt-web` - FastAPI-based web service
- **Ubuntu 24.04 Container**: `eemt:ubuntu24.04` - Core processing environment
  - GRASS GIS 8.4+ installed
  - CCTools 7.15.14 installed (updated from broken 7.8.2)
  - Python 3.12+ with full geospatial stack
  - 8.42GB image size with all dependencies

### 3. Resource Management (Implemented)
```yaml
Docker Resource Limits:
- Web Interface: 2 CPU cores, 4GB RAM
- Worker Nodes: 8 CPU cores, 16GB RAM
- Health checks: Every 30 seconds
- Auto-restart: Unless stopped
```

### 4. UI/UX Improvements (Deployed)
- Fixed file upload spacing (12px padding)
- Auto-refresh system status (15 seconds)
- Auto-refresh job list (30 seconds)
- Enhanced Bootstrap 5 styling
- Real-time progress tracking
- Immediate file upload on selection

## Quick Start Deployment

### 1. Prerequisites
```bash
# Verify Docker installation
docker --version  # Should be 20.10+
docker-compose --version  # Should be 1.29+

# Clone repository
git clone https://github.com/cyverse-gis/eemt.git
cd eemt
```

### 2. Build and Deploy

#### Option A: Docker Compose (Recommended)
```bash
# Build and start all services
docker-compose up -d

# Verify deployment
docker ps | grep eemt
curl http://127.0.0.1:5000/health

# Access web interface
firefox http://127.0.0.1:5000
```

#### Option B: Manual Container Build
```bash
# Build Ubuntu processing container
cd docker/ubuntu/24.04/
./build.sh

# Build web interface container
cd ../../..
docker build -t eemt-web -f docker/web-interface/Dockerfile .

# Run containers
docker-compose up -d
```

### 3. Verify Installation
```bash
# Check container health
docker exec eemt-web-local curl -s http://localhost:5000/health | jq

# Test GRASS GIS
docker run --rm eemt:ubuntu24.04 grass --version

# Test CCTools
docker run --rm eemt:ubuntu24.04 makeflow --version

# Check Docker-in-Docker
docker exec eemt-web-local docker version
```

## Architecture Components

### Web Interface (FastAPI)
- **URL**: http://127.0.0.1:5000
- **Health Check**: http://127.0.0.1:5000/health
- **Monitor**: http://127.0.0.1:5000/monitor
- **API Docs**: http://127.0.0.1:5000/docs

### Container Configuration
```yaml
Services:
  eemt-web:
    - FastAPI application
    - Docker-in-Docker for workflow execution
    - SQLite job tracking
    - Real-time monitoring
    
  eemt:ubuntu24.04:
    - GRASS GIS 8.4+
    - CCTools 7.15.14
    - Python 3.12+ with geospatial stack
    - GDAL 3.8+, PROJ 9.0+
```

### Volume Mounts
```bash
./data/uploads    # DEM file uploads
./data/results    # Workflow outputs
./data/temp       # Temporary processing
./data/cache      # Cached data
./sol             # Solar workflow scripts
./eemt            # EEMT workflow scripts
```

## Workflow Execution

### Via Web Interface
1. Navigate to http://127.0.0.1:5000
2. Select workflow type (Solar or EEMT)
3. Upload DEM file (auto-uploads on selection)
4. Configure parameters
5. Submit job
6. Monitor progress at http://127.0.0.1:5000/monitor

### Via API
```bash
# Submit solar workflow
curl -X POST "http://127.0.0.1:5000/api/submit-job" \
  -F "workflow_type=sol" \
  -F "dem_file=@your_dem.tif" \
  -F "step=15" \
  -F "num_threads=4"

# Check job status
curl "http://127.0.0.1:5000/api/jobs/{job_id}"
```

### Direct Container Execution
```bash
# Solar radiation workflow
docker run --rm \
  -v $(pwd)/uploads:/data/input:ro \
  -v $(pwd)/results:/data/output:rw \
  eemt:ubuntu24.04 \
  python3 /opt/eemt/sol/sol/run-workflow \
  --step 15 --num_threads 4 /data/input/dem.tif

# Full EEMT workflow
docker run --rm \
  -v $(pwd)/uploads:/data/input:ro \
  -v $(pwd)/results:/data/output:rw \
  eemt:ubuntu24.04 \
  python3 /opt/eemt/eemt/eemt/run-workflow \
  --start-year 2020 --end-year 2020 \
  --step 15 /data/input/dem.tif
```

## Monitoring and Maintenance

### Health Monitoring
```bash
# Check web interface health
curl http://127.0.0.1:5000/health

# View container logs
docker logs -f eemt-web-local

# Monitor resource usage
docker stats eemt-web-local

# Check running jobs
curl http://127.0.0.1:5000/api/jobs
```

### Troubleshooting

#### Container Issues
```bash
# Restart containers
docker-compose restart

# Rebuild with no cache
docker-compose build --no-cache

# Clean up old containers
docker system prune -a
```

#### Permission Issues
```bash
# Fix Docker socket permissions
sudo usermod -aG docker $USER
newgrp docker

# Fix volume permissions
sudo chown -R 57275:984 ./data/
```

#### Workflow Failures
```bash
# Check logs
docker logs eemt-web-local | grep ERROR

# Verify GRASS installation
docker exec eemt-web-local grass --version

# Test CCTools
docker exec eemt-web-local makeflow --version
```

## Security Considerations

### Current Implementation
- Container runs with specific UID:GID (57275:984)
- Docker socket mounted for container management
- No authentication (local deployment only)

### Future Security Roadmap
See AUTHENTICATION_ROADMAP.md for planned security enhancements:
- JWT-based authentication
- Role-based access control
- LDAP/OAuth integration
- API key management

## Performance Optimization

### Resource Allocation
```yaml
Recommended Settings:
  Web Interface:
    - 2-4 CPU cores
    - 4-8 GB RAM
    
  Processing Containers:
    - 8-16 CPU cores
    - 16-32 GB RAM
    - SSD storage for temp files
```

### Scaling Options
```bash
# Scale workers
docker-compose --profile distributed up --scale eemt-worker-2=5

# Adjust resource limits
docker update --cpus="16" --memory="32g" eemt-worker
```

## Backup and Recovery

### Data Backup
```bash
# Backup results
tar -czf results-$(date +%Y%m%d).tar.gz ./data/results/

# Backup database
cp ./data/jobs.db ./backups/jobs-$(date +%Y%m%d).db
```

### Recovery
```bash
# Restore results
tar -xzf results-20260101.tar.gz

# Restore database
cp ./backups/jobs-20260101.db ./data/jobs.db

# Restart services
docker-compose restart
```

## Updates and Maintenance

### Updating Containers
```bash
# Pull latest changes
git pull origin main

# Rebuild containers
docker-compose build --no-cache

# Deploy updates
docker-compose up -d
```

### Monitoring Updates
- Check GitHub releases: https://github.com/cyverse-gis/eemt/releases
- Review CHANGELOG.md for breaking changes
- Test updates in staging environment first

## Support and Documentation

### Documentation
- User Guide: docs/user-guide.md
- API Reference: http://127.0.0.1:5000/docs
- Algorithm Details: EEMT.md
- Development Guide: CLAUDE.md

### Getting Help
- GitHub Issues: https://github.com/cyverse-gis/eemt/issues
- CyVerse Support: support@cyverse.org
- Community Forum: https://cyverse.org/forum

## Version Information
- Deployment Date: January 1, 2026
- Python Version: 3.12+
- GRASS GIS: 8.4+
- CCTools: 7.15.14
- Docker Compose: 3.8
- FastAPI: 0.104.1

---
Generated with Claude Code (claude.ai/code)