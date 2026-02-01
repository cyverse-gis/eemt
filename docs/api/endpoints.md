# API Reference

The EEMT Web Interface exposes a comprehensive REST API for programmatic workflow submission and monitoring.

## Base URL

```
http://127.0.0.1:5000
```

## Authentication

Currently, the API does not require authentication. Future versions may include:

- API key authentication
- JWT token-based access
- Role-based permissions

## Content Types

- **Request**: `multipart/form-data` for file uploads, `application/json` for data
- **Response**: `application/json` for all endpoints except file downloads

## Job Management

### Submit Workflow Job

Submit a new EEMT or solar radiation workflow for processing.

```http
POST /api/submit-job
Content-Type: multipart/form-data
```

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `workflow_type` | string | Yes | `"sol"` for solar radiation, `"eemt"` for full analysis |
| `dem_file` | file | Yes | GeoTIFF elevation model file |
| `step` | float | No | Time step in minutes (default: 15.0, range: 3-60) |
| `linke_value` | float | No | Atmospheric turbidity (default: 3.0, range: 1.0-8.0) |
| `albedo_value` | float | No | Surface reflectance (default: 0.2, range: 0.0-1.0) |
| `num_threads` | integer | No | CPU threads (default: 4, range: 1-32) |
| `start_year` | integer | No | Start year for EEMT (default: 2020, range: 1980-2024) |
| `end_year` | integer | No | End year for EEMT (default: 2020, range: 1980-2024) |

**Example Request:**

```bash
curl -X POST "http://127.0.0.1:5000/api/submit-job" \
  -F "workflow_type=sol" \
  -F "dem_file=@my_elevation_data.tif" \
  -F "step=15" \
  -F "linke_value=3.5" \
  -F "albedo_value=0.2" \
  -F "num_threads=8"
```

**Response:**

```json
{
  "job_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "status": "submitted"
}
```

**Error Responses:**

```json
// Invalid file format
{
  "detail": "DEM file must be a GeoTIFF (.tif)"
}

// Missing required parameter
{
  "detail": "workflow_type is required"
}

// Docker not available
{
  "detail": "Container execution failed: Docker daemon not available"
}
```

### List All Jobs

Retrieve a list of all workflow jobs.

```http
GET /api/jobs
```

**Response:**

```json
[
  {
    "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "workflow_type": "sol",
    "status": "completed",
    "created_at": "2025-01-15T10:30:00Z",
    "dem_filename": "my_elevation_data.tif",
    "progress": 100
  },
  {
    "id": "b2c3d4e5-f6g7-8901-bcde-f23456789012",
    "workflow_type": "eemt", 
    "status": "running",
    "created_at": "2025-01-15T11:15:00Z",
    "dem_filename": "large_dem.tif",
    "progress": 65
  }
]
```

### Get Job Details

Retrieve detailed information about a specific job.

```http
GET /api/jobs/{job_id}
```

**Response:**

```json
{
  "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "workflow_type": "sol",
  "status": "completed",
  "created_at": "2025-01-15T10:30:00Z",
  "started_at": "2025-01-15T10:30:15Z",
  "completed_at": "2025-01-15T10:45:30Z",
  "parameters": {
    "step": 15.0,
    "linke_value": 3.5,
    "albedo_value": 0.2,
    "num_threads": 8
  },
  "dem_filename": "my_elevation_data.tif",
  "error_message": null,
  "progress": 100
}
```

**Error Responses:**

```json
// Job not found
{
  "detail": "Job not found"
}
```

### Download Job Results

Download the complete results of a completed job as a ZIP archive.

```http
GET /api/jobs/{job_id}/results
```

**Response:**

- **Success**: ZIP file download with filename `eemt_results_{job_id}.zip`
- **Content-Type**: `application/zip`

**Example Request:**

```bash
curl -O "http://127.0.0.1:5000/api/jobs/a1b2c3d4-e5f6-7890-abcd-ef1234567890/results"
```

**Error Responses:**

```json
// Job not completed
{
  "detail": "Job not completed"
}

// Results not found
{
  "detail": "Results not found"
}
```

## System Information

### Get System Status

Retrieve Docker availability and container statistics.

```http
GET /api/system/status
```

**Response:**

```json
{
  "docker_available": true,
  "container_stats": {
    "total_containers": 2,
    "running_jobs": [
      "job-a1b2c3d4",
      "job-b2c3d4e5"
    ],
    "system_stats": {
      "cpus": 8,
      "memory": 16777216000,
      "containers_running": 2
    }
  },
  "image_name": "eemt:ubuntu24.04"
}
```

**Error Response (Docker unavailable):**

```json
{
  "docker_available": false,
  "error": "Docker daemon not reachable",
  "image_name": "eemt:ubuntu24.04"
}
```

## Data Management

### Trigger Job Cleanup

Execute cleanup of old job data based on retention policies.

```http
POST /api/cleanup
Content-Type: application/json
```

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `dry_run` | boolean | No | Preview cleanup without deletion (default: false) |
| `success_retention_days` | integer | No | Days to keep successful job data (default: 7) |
| `failed_retention_hours` | integer | No | Hours to keep failed job data (default: 12) |

**Example Request:**

```bash
# Trigger cleanup with defaults
curl -X POST http://127.0.0.1:5000/api/cleanup

# Dry run with custom retention
curl -X POST http://127.0.0.1:5000/api/cleanup \
  -H "Content-Type: application/json" \
  -d '{
    "dry_run": true,
    "success_retention_days": 3,
    "failed_retention_hours": 6
  }'
```

**Response:**

```json
{
  "success": true,
  "summary": {
    "start_time": "2024-01-20T14:30:00.123456",
    "end_time": "2024-01-20T14:30:05.789012",
    "dry_run": false,
    "successful_jobs_processed": 3,
    "failed_jobs_processed": 2,
    "total_size_freed_mb": 15678.9,
    "configs_preserved": 3,
    "configs_deleted": 2,
    "errors": [],
    "job_details": [
      {
        "job_id": "job-20240113-123456",
        "status": "completed",
        "completed_at": "2024-01-13T14:23:45",
        "data_deleted": true,
        "config_preserved": true,
        "size_freed_mb": 8234.5
      }
    ]
  },
  "timestamp": "2024-01-20T14:30:05.789012"
}
```

**Error Response:**

```json
{
  "success": false,
  "error": "Cleanup process failed",
  "details": "Database is locked by another process"
}
```

### Get Cleanup Status

Retrieve information about the last cleanup run.

```http
GET /api/cleanup/status
```

**Response:**

```json
{
  "last_run": "2024-01-20T02:00:00",
  "next_scheduled": "2024-01-21T02:00:00",
  "auto_cleanup_enabled": true,
  "retention_settings": {
    "success_retention_days": 7,
    "failed_retention_hours": 12
  },
  "disk_usage": {
    "uploads_mb": 1234.5,
    "results_mb": 45678.9,
    "total_mb": 46913.4
  }
}
```

## Job Status Values

| Status | Description |
|--------|-------------|
| `pending` | Job queued, waiting to start |
| `running` | Container executing workflow |
| `completed` | Job finished successfully |
| `failed` | Job terminated with error |

## Progress Tracking

Progress is reported as integer percentage (0-100):

- **0-10**: Job initialization and container startup
- **10-90**: Workflow execution (varies by complexity)
- **90-100**: Results collection and cleanup

## Rate Limiting

Currently no rate limiting is implemented. Consider implementing:

- Max concurrent jobs per client
- File upload size limits (currently ~1GB recommended)
- API request frequency limits

## Error Handling

All errors follow consistent format:

```json
{
  "detail": "Human-readable error message"
}
```

Common HTTP status codes:

- `200`: Success
- `400`: Bad Request (invalid parameters)
- `404`: Not Found (job/resource doesn't exist)
- `422`: Unprocessable Entity (validation error)
- `500`: Internal Server Error (system/container issue)

## Examples

### Python Client Example

```python
import requests
import time

# Submit job
with open('my_dem.tif', 'rb') as f:
    response = requests.post(
        'http://127.0.0.1:5000/api/submit-job',
        files={'dem_file': f},
        data={
            'workflow_type': 'sol',
            'step': 15,
            'num_threads': 4
        }
    )

job_id = response.json()['job_id']
print(f"Job submitted: {job_id}")

# Monitor progress
while True:
    status = requests.get(f'http://127.0.0.1:5000/api/jobs/{job_id}').json()
    print(f"Status: {status['status']} ({status['progress']}%)")
    
    if status['status'] in ['completed', 'failed']:
        break
    time.sleep(10)

# Download results if successful
if status['status'] == 'completed':
    results = requests.get(f'http://127.0.0.1:5000/api/jobs/{job_id}/results')
    with open(f'results_{job_id}.zip', 'wb') as f:
        f.write(results.content)
    print("Results downloaded!")
```

### JavaScript Client Example

```javascript
// Submit job
const formData = new FormData();
formData.append('workflow_type', 'sol');
formData.append('dem_file', demFileInput.files[0]);
formData.append('step', '15');
formData.append('num_threads', '4');

const submitResponse = await fetch('/api/submit-job', {
    method: 'POST',
    body: formData
});

const submitResult = await submitResponse.json();
console.log('Job submitted:', submitResult.job_id);

// Monitor progress
const jobId = submitResult.job_id;
const checkStatus = async () => {
    const response = await fetch(`/api/jobs/${jobId}`);
    const job = await response.json();
    
    console.log(`Status: ${job.status} (${job.progress}%)`);
    
    if (job.status === 'completed') {
        // Download results
        window.open(`/api/jobs/${jobId}/results`);
    } else if (job.status === 'failed') {
        console.error('Job failed:', job.error_message);
    } else {
        setTimeout(checkStatus, 5000); // Check again in 5 seconds
    }
};

checkStatus();
```

### Bash Script Example

```bash
#!/bin/bash

# Submit job
RESPONSE=$(curl -s -X POST "http://127.0.0.1:5000/api/submit-job" \
  -F "workflow_type=sol" \
  -F "dem_file=@dem.tif" \
  -F "step=15" \
  -F "num_threads=4")

JOB_ID=$(echo $RESPONSE | jq -r '.job_id')
echo "Job submitted: $JOB_ID"

# Monitor progress
while true; do
    STATUS=$(curl -s "http://127.0.0.1:5000/api/jobs/$JOB_ID" | jq -r '.status')
    PROGRESS=$(curl -s "http://127.0.0.1:5000/api/jobs/$JOB_ID" | jq -r '.progress')
    
    echo "Status: $STATUS ($PROGRESS%)"
    
    if [[ "$STATUS" == "completed" ]]; then
        echo "Downloading results..."
        curl -O "http://127.0.0.1:5000/api/jobs/$JOB_ID/results"
        break
    elif [[ "$STATUS" == "failed" ]]; then
        echo "Job failed!"
        break
    fi
    
    sleep 10
done
```

## OpenAPI Documentation

Interactive API documentation is automatically generated and available at:

- **Swagger UI**: http://127.0.0.1:5000/docs
- **ReDoc**: http://127.0.0.1:5000/redoc  
- **OpenAPI JSON**: http://127.0.0.1:5000/openapi.json

The interactive documentation allows you to:

- Browse all available endpoints
- Test API calls directly in the browser
- View detailed parameter descriptions
- See example requests and responses