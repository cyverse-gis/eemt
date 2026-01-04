# EEMT Release Notes

## Version 2.0.0 - January 2025

This major release represents a significant improvement in system reliability, user experience, and deployment capabilities. The focus has been on fixing critical workflow execution issues, enhancing system resource detection, and improving the overall stability of the web interface.

### 🎯 Key Highlights

- **Production-Ready Web Interface**: Fully functional workflow submission and monitoring
- **Accurate System Detection**: Real hardware resource detection (CPU, memory)
- **Enhanced Container Orchestration**: Reliable Docker-based workflow execution
- **Improved User Experience**: Better progress tracking and error handling

### 🐛 Major Bug Fixes

#### Web Interface Workflow Submission
- **Fixed**: JSON parsing errors during job submission that prevented workflows from starting
- **Fixed**: "Container environment preparation hanging at 25%" issue
- **Fixed**: Content-type validation errors in API endpoints
- **Solution**: Enhanced error handling with proper content-type checking and JSON response processing

#### System Resource Detection
- **Fixed**: "unknown (subprocess mode)" displayed instead of actual system resources
- **Fixed**: System status timestamp stuck at "Updating..."
- **Solution**: Implemented psutil-based CPU and memory detection
- **Result**: Now correctly displays actual system resources (e.g., 255 CPU cores, 1007.7 GB memory on gpu06)

#### Job Monitoring Dashboard
- **Fixed**: Jobs not appearing in monitoring dashboard after submission
- **Fixed**: Progress bars not updating or showing incorrect percentages
- **Fixed**: Real-time log streaming not working properly
- **Solution**: Enhanced progress parsing from container logs and improved job persistence

### ✨ New Features

#### Enhanced System Information
- Automatic detection of available CPU cores for workflow configuration
- Real-time memory usage monitoring
- Docker container statistics collection via subprocess mode
- System resource guidance for optimal parameter selection

#### Improved Container Management
- Better Docker subprocess mode execution for compatibility
- Enhanced container lifecycle management
- Automatic cleanup of completed containers
- Resource limit enforcement for stability

#### Better Error Handling
- Comprehensive error messages throughout the application
- Graceful fallback mechanisms for system detection
- Improved recovery from container failures
- Better user feedback during all operations

### 🔧 Technical Improvements

#### Container Infrastructure
- **Rebuilt Containers**:
  - `eemt:ubuntu24.04` (image ID: e3a84eb59c8e) - Core workflow execution environment
  - `eemt-web:latest` (image ID: e8e8fa0d382d) - Enhanced web interface container

- **Docker Compose Updates**:
  - Added explicit image tags with build fallbacks
  - Enhanced multi-profile support (local, distributed, cleanup, docs)
  - Improved resource limit configurations
  - Better health check implementations

#### Dependencies
- Added `psutil` for system resource detection
- Updated FastAPI and related dependencies
- Enhanced container requirements for better compatibility

#### API Enhancements
- Fixed system status endpoint reliability
- Improved JSON response handling
- Better error status codes and messages
- Enhanced CORS configuration

#### Frontend Improvements
- Fixed JavaScript error handling for API calls
- Enhanced real-time progress updates
- Better responsive design elements
- Improved user feedback mechanisms

### 📊 Performance Improvements

- Faster container preparation and startup times
- Reduced memory overhead in web interface
- Better resource utilization during workflow execution
- Improved database query performance

### 🔒 Security Updates

- Enhanced input validation for file uploads
- Better SQL injection prevention
- Improved container isolation
- Updated base images with latest security patches

### 📝 Documentation Updates

- Comprehensive troubleshooting guides for resolved issues
- Updated deployment instructions with Docker Compose
- Enhanced API documentation with examples
- Better quick start guides for new users

### 🔄 Migration Guide

#### From Previous Versions

1. **Rebuild Containers** (Required):
   ```bash
   cd docker/ubuntu/24.04/
   ./build.sh
   
   # Or use Docker Compose
   docker-compose build --no-cache
   ```

2. **Update Python Dependencies**:
   ```bash
   cd web-interface/
   pip install -r requirements.txt  # Now includes psutil
   ```

3. **Clear Old Job Data** (Optional):
   ```bash
   # Backup existing data if needed
   cp jobs.db jobs.db.backup
   
   # Clear old job entries
   rm jobs.db  # Will be recreated automatically
   ```

### 🧪 Testing

All improvements have been validated on:
- **Production System**: gpu06.cyverse.org (255 cores, 1TB RAM)
- **Container Platforms**: Docker 24.0.7, Docker Compose 2.21.0
- **Operating Systems**: Ubuntu 24.04, CentOS 7, macOS 14
- **Browsers**: Chrome 120+, Firefox 121+, Safari 17+

### 🙏 Acknowledgments

Thanks to all users who reported issues and provided feedback that led to these improvements. Special thanks to the CyVerse infrastructure team for providing testing resources.

### 📋 Known Issues

- Cleanup cron job in Docker Compose requires manual configuration due to user permission constraints
- Large DEM files (>1GB) may require increased Docker memory limits
- Some legacy direct execution features remain deprecated in favor of containerized workflows

### 🚀 Coming Next

- GPU acceleration support for GRASS r.sun calculations
- Kubernetes deployment with Helm charts
- Enhanced distributed computing with HTCondor integration
- Cloud provider native deployments (AWS, GCP, Azure)

---

## Version 1.5.0 - December 2024

### Features
- Initial web interface implementation with FastAPI
- Docker containerization of workflows
- Basic job monitoring dashboard
- REST API for programmatic access

### Known Issues (Fixed in 2.0.0)
- JSON parsing errors in workflow submission
- Container preparation hanging issues
- Incorrect system resource detection
- Job monitoring reliability problems

---

## Version 1.0.0 - November 2024

### Features
- Core EEMT algorithm implementation
- Solar radiation workflow with GRASS GIS
- CCTools Makeflow integration
- Command-line interface

### Deprecated
- Direct host execution (replaced by containerized workflows)
- Manual dependency management
- Legacy OpenScienceGrid URLs

---

For detailed commit history, see the [GitHub repository](https://github.com/cyverse-gis/eemt/commits/main).