# EEMT Workflow Execution Plan

## Overview

This document outlines the containerized workflow execution strategy for EEMT (Effective Energy and Mass Transfer) algorithms using Docker containers with Makeflow/Work Queue orchestration.

## Current Issues Diagnosed

### Host System Limitations
- **Missing GRASS GIS**: No native GRASS installation on host
- **Missing CCTools**: Makeflow and Work Queue not installed
- **Python Compatibility**: Legacy workflows use deprecated `imp` module (Python 3.12+ incompatible)
- **Direct Execution Failure**: Web interface attempts native execution instead of containerized

### Container Status ✅
The Docker container (`docker/ubuntu/24.04/`) includes all required components:
- **GRASS GIS 8.4+**: With r.sun.mp, r.sun.hourly, r.sun.daily extensions
- **CCTools 7.8.2**: Makeflow + Work Queue for distributed execution
- **Python 3.12**: Complete geospatial environment with conda
- **GDAL 3.11**: Modern geospatial data processing
- **QGIS 3.34+ LTR**: Additional processing capabilities

## Containerized Execution Strategy

### Phase 1: Local Container Execution

#### Architecture Overview
```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Web Interface │    │  Container Host  │    │ EEMT Container  │
│   (FastAPI)     │    │                  │    │                 │
│ • Job Submit   ◄────► • Docker Engine   ◄────► • GRASS GIS     │
│ • Monitor      │    │ • Volume Mounts  │    │ • CCTools       │
│ • Results      │    │ • Network Bridge │    │ • Workflows     │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

#### Container Execution Workflow

1. **Job Submission** (Web Interface):
   - Upload DEM file to host filesystem
   - Create job configuration
   - Trigger containerized execution

2. **Container Orchestration** (Host):
   - Build/pull EEMT container image
   - Mount data volumes (uploads, results)
   - Execute workflow within container
   - Monitor execution progress

3. **Workflow Execution** (Container):
   - Initialize GRASS environment
   - Run Makeflow workflow (local mode)
   - Process 365 daily solar calculations
   - Generate monthly aggregations
   - Save results to mounted volume

### Container Execution Modes

#### Mode 1: Single Container (Immediate)
- **Use Case**: Small DEMs, development, testing
- **Execution**: Direct docker run with volume mounts
- **Concurrency**: One job per container instance
- **Resource**: Local CPU/memory allocation

#### Mode 2: Local Makeflow Master (Phase 2)
- **Use Case**: Larger DEMs, production workloads
- **Execution**: Container runs Makeflow master, spawns worker containers
- **Concurrency**: Multiple parallel tasks within job
- **Resource**: Dynamic container scaling on single host

#### Mode 3: Distributed Makeflow (Future)
- **Use Case**: Very large DEMs, multi-host processing
- **Execution**: Master container + remote worker containers
- **Concurrency**: Cross-host distributed execution
- **Resource**: Multi-node container orchestration

## Implementation Plan

### Step 1: Container Integration
Update web interface to use containerized execution instead of direct workflow calls.

#### Modified Execution Flow
```python
# Replace direct subprocess execution:
# process = subprocess.Popen(["python", "run-workflow", ...])

# With containerized execution:
container_cmd = [
    "docker", "run", "--rm",
    "-v", f"{uploads_dir}:/data/input",
    "-v", f"{results_dir}:/data/output", 
    "-v", f"{password_file}:/home/eemt/.eemt-makeflow-password",
    "eemt:ubuntu24.04",
    "/opt/eemt/bin/run-container-workflow",
    workflow_type, dem_filename, json.dumps(parameters)
]
```

### Step 2: Container Workflow Wrapper
Create a containerized workflow entry point that:
- Accepts JSON parameters
- Sets up GRASS environment
- Executes appropriate workflow (sol/ or eemt/)
- Handles results export

### Step 3: Progress Monitoring
Implement container execution monitoring:
- **Log Streaming**: Monitor container stdout/stderr
- **Progress Parsing**: Extract progress from Makeflow logs
- **Status Updates**: Update database with real-time progress

### Step 4: Resource Management
- **Container Limits**: CPU, memory, and disk constraints
- **Cleanup**: Automatic container removal after completion
- **Queue Management**: Limit concurrent container executions

## Container Configuration

### Required Volume Mounts
```bash
# Data volumes
-v ${PWD}/uploads:/data/input:ro          # DEM files (read-only)
-v ${PWD}/results:/data/output:rw         # Results (read-write)
-v ${PWD}/temp:/data/temp:rw              # Temporary processing

# Configuration
-v ~/.eemt-makeflow-password:/home/eemt/.eemt-makeflow-password:ro

# Optional: Cache for repeated runs
-v ${PWD}/cache:/data/cache:rw            # Intermediate results cache
```

### Environment Variables
```bash
# Resource allocation
-e EEMT_NUM_THREADS=4
-e EEMT_MEMORY_LIMIT=8G
-e EEMT_DISK_LIMIT=50G

# Workflow configuration  
-e GRASS_BATCH_JOB=true
-e GRASS_MESSAGE_FORMAT=plain
-e GRASS_VERBOSE=1

# Makeflow settings
-e MAKEFLOW_BATCH_TYPE=local           # Local execution mode
-e MAKEFLOW_MAX_REMOTE_JOBS=8          # Parallel task limit
```

### Container Entry Points

#### Solar Radiation Workflow
```bash
docker run --rm \
  -v $(pwd)/uploads:/data/input:ro \
  -v $(pwd)/results:/data/output:rw \
  -v ~/.eemt-makeflow-password:/home/eemt/.eemt-makeflow-password:ro \
  eemt:ubuntu24.04 \
  /opt/eemt/bin/run-solar-workflow \
  --dem /data/input/dem.tif \
  --output /data/output/job_123 \
  --step 15 \
  --num-threads 4 \
  --linke-value 3.0 \
  --albedo-value 0.2
```

#### Full EEMT Workflow  
```bash
docker run --rm \
  -v $(pwd)/uploads:/data/input:ro \
  -v $(pwd)/results:/data/output:rw \
  -v ~/.eemt-makeflow-password:/home/eemt/.eemt-makeflow-password:ro \
  eemt:ubuntu24.04 \
  /opt/eemt/bin/run-eemt-workflow \
  --dem /data/input/dem.tif \
  --output /data/output/job_456 \
  --start-year 2020 \
  --end-year 2020 \
  --step 15 \
  --num-threads 8
```

## Progress Monitoring Strategy

### Makeflow Log Parsing
Monitor Makeflow execution logs for progress indicators:
```
# Makeflow progress format
# STARTED job_id timestamp
# COMPLETED job_id timestamp return_code
# FAILED job_id timestamp return_code

# Calculate progress: completed_tasks / total_tasks * 100
```

### Container Log Streaming
```python
import docker

client = docker.from_env()
container = client.containers.run(
    "eemt:ubuntu24.04",
    command=workflow_cmd,
    volumes=volume_mounts,
    detach=True,
    stdout=True,
    stderr=True,
    remove=True
)

# Stream logs for progress monitoring
for log_line in container.logs(stream=True):
    parse_progress(log_line.decode())
    update_job_status(job_id, progress)
```

## File Organization

### Container Workflow Scripts
```
/opt/eemt/bin/
├── run-solar-workflow          # Solar radiation container entry point
├── run-eemt-workflow          # Full EEMT container entry point  
├── makeflow-progress-monitor   # Progress monitoring utility
└── container-cleanup          # Post-execution cleanup
```

### Host Integration
```
web-interface/
├── containers/
│   ├── workflow_manager.py    # Container orchestration
│   ├── progress_monitor.py    # Log parsing and progress tracking
│   └── resource_manager.py    # Resource allocation and limits
└── app.py                     # Modified to use container execution
```

## Testing Strategy

### Unit Tests
- Container execution with sample DEM
- Progress monitoring accuracy
- Resource limit enforcement
- Error handling and cleanup

### Integration Tests  
- End-to-end workflow execution
- Web interface job submission
- Result file generation and download
- Concurrent job handling

### Performance Tests
- Large DEM processing (>100MB)
- Resource usage profiling
- Scaling limits (concurrent containers)
- Memory and disk utilization

## Rollout Plan

### Week 1: Foundation
- [ ] Build and test Ubuntu 24.04 container
- [ ] Create container workflow wrapper scripts
- [ ] Implement basic container execution in web interface

### Week 2: Integration  
- [ ] Add progress monitoring via log parsing
- [ ] Implement resource management and limits
- [ ] Add error handling and container cleanup

### Week 3: Testing
- [ ] End-to-end testing with various DEM sizes
- [ ] Performance profiling and optimization
- [ ] Documentation and user guides

### Week 4: Production
- [ ] Deploy containerized execution
- [ ] Monitor production workloads
- [ ] Gather user feedback and iterate

## Future Enhancements

### Phase 2: Local Distributed Execution
- Multiple worker containers on single host
- Load balancing across container instances
- Improved resource utilization

### Phase 3: Multi-Host Distribution
- Docker Swarm or Kubernetes orchestration
- Cross-host container networking
- Persistent volume management

### Phase 4: Cloud Integration
- Cloud container registries
- Elastic container scaling
- Spot instance utilization

This plan provides a clear path from the current broken native execution to a robust containerized workflow system that leverages the existing Docker infrastructure while maintaining compatibility with the legacy Makeflow/Work Queue architecture.