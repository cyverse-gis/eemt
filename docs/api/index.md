---
title: API Documentation
---

# API Documentation

## Overview

The EEMT suite provides multiple interfaces for workflow execution and data processing. This documentation covers the REST API, web interface, command-line tools, and Python modules.

## API Interfaces

### 🌐 [REST API Endpoints](endpoints.md)
Complete reference for the FastAPI-based REST interface:
- Job submission and management
- Status monitoring
- Results retrieval
- Health checks and metrics

### 📊 [Web Interface](web-interface.md)
Browser-based interface for workflow management:
- Interactive job submission forms
- Real-time progress monitoring
- Result visualization and downloads
- Multi-user support

### 🔧 [Workflow Parameters](parameters.md)
Comprehensive parameter documentation:
- Solar radiation parameters
- EEMT calculation options
- Climate data settings
- Performance tuning

### 💻 [Command Line Interface](cli.md)
Direct workflow execution via command line:
- Python workflow scripts
- Shell script utilities
- Batch processing options

### 🐍 [Python Modules](python-modules.md)
Programmatic access to EEMT functions:
- Core calculation functions
- Data I/O utilities
- Visualization tools
- Custom workflow development

## Quick Start Examples

### REST API
```bash
# Submit a solar radiation job
curl -X POST "http://localhost:5000/api/jobs" \
  -F "workflow_type=sol" \
  -F "dem_file=@your_dem.tif" \
  -F "parameters={\"step\": 15, \"num_threads\": 4}"

# Check job status
curl "http://localhost:5000/api/jobs/JOB_ID/status"

# Download results
curl -O "http://localhost:5000/api/jobs/JOB_ID/download"
```

### Python SDK
```python
from eemt import EEMTClient

# Initialize client
client = EEMTClient(base_url="http://localhost:5000")

# Submit job
job_id = client.submit_job(
    workflow_type="eemt",
    dem_file="path/to/dem.tif",
    parameters={
        "start_year": 2020,
        "end_year": 2022,
        "step": 15
    }
)

# Monitor progress
status = client.get_job_status(job_id)
print(f"Progress: {status.progress}%")

# Download results
client.download_results(job_id, output_dir="./results")
```

### Command Line
```bash
# Run solar radiation workflow
python /opt/eemt/sol/run-workflow \
  --dem input_dem.tif \
  --output ./output \
  --step 15 \
  --num-threads 8

# Run full EEMT analysis
python /opt/eemt/eemt/run-workflow \
  --dem input_dem.tif \
  --output ./output \
  --start-year 2020 \
  --end-year 2022 \
  --step 15
```

## API Features

### Authentication & Security
- API key authentication (optional)
- Rate limiting and quotas
- HTTPS support
- CORS configuration

### Job Management
- Asynchronous job submission
- Queue management
- Priority scheduling
- Resource allocation

### Data Handling
- Large file uploads (chunked)
- Streaming downloads
- Compression support
- Format conversion

### Monitoring & Metrics
- Real-time progress tracking
- Resource usage statistics
- Error logging and debugging
- Performance metrics

## Response Formats

### Standard Response Structure
```json
{
  "status": "success",
  "data": {
    // Response data
  },
  "message": "Operation completed successfully",
  "timestamp": "2024-01-15T10:30:00Z"
}
```

### Error Response
```json
{
  "status": "error",
  "error": {
    "code": "INVALID_PARAMETER",
    "message": "Step value must be between 1 and 30",
    "details": {
      "parameter": "step",
      "provided_value": 45,
      "allowed_range": [1, 30]
    }
  },
  "timestamp": "2024-01-15T10:30:00Z"
}
```

### Job Status Response
```json
{
  "job_id": "20240115-103000-abc123",
  "status": "running",
  "progress": 45,
  "current_task": "Processing day 165 of 365",
  "started_at": "2024-01-15T10:30:00Z",
  "estimated_completion": "2024-01-15T11:30:00Z",
  "resources": {
    "cpu_usage": 85,
    "memory_usage": 4.2,
    "disk_usage": 12.5
  }
}
```

## Rate Limits

| Endpoint | Rate Limit | Burst |
|----------|------------|-------|
| Job submission | 10/hour | 2 |
| Status checks | 60/minute | 10 |
| Result downloads | 20/hour | 5 |
| Health checks | Unlimited | - |

## Versioning

The API follows semantic versioning:

- **Current Version**: v1.0
- **Base URL**: `/api/v1/`
- **Deprecation Policy**: 6 months notice
- **Backwards Compatibility**: Maintained within major versions

## API Clients

Official client libraries:

- **Python**: `pip install eemt-client`
- **JavaScript**: `npm install @eemt/client`
- **R**: `install.packages("eemtr")`

Community clients:

- [Julia Client](https://github.com/community/EEMT.jl)
- [MATLAB Interface](https://github.com/community/eemt-matlab)

## OpenAPI Specification

The complete OpenAPI 3.0 specification is available at:

- **JSON**: `/api/openapi.json`
- **YAML**: `/api/openapi.yaml`
- **Interactive Docs**: `/api/docs` (Swagger UI)
- **ReDoc**: `/api/redoc`

## Support

For API support:

1. Check the [FAQ](../about/index.md#api-faq)
2. Review [Examples](../examples/index.md)
3. Post on [Discussions](https://github.com/cyverse-gis/eemt/discussions)
4. Report [Issues](https://github.com/cyverse-gis/eemt/issues)

---

*For installation instructions, see [Installation Guide](../installation/index.md). For workflow details, see [Workflows Documentation](../workflows/index.md).*