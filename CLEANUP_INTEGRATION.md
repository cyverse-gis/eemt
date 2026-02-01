# EEMT Job Data Cleanup - Docker Integration

This document describes the integrated job data cleanup system for EEMT containerized deployments.

## Overview

The EEMT system now includes automated job data cleanup functionality integrated into all Docker containers:

- **Successful jobs**: Data deleted after 7 days (configurable), job configurations preserved
- **Failed jobs**: Complete deletion after 12 hours (configurable)
- **Multiple deployment options**: Docker Compose, Kubernetes, standalone containers

## Quick Start

### Docker Compose (Recommended)

```bash
# Standard deployment with cleanup enabled
docker-compose up

# With custom retention periods
EEMT_SUCCESS_RETENTION_DAYS=14 EEMT_FAILED_RETENTION_HOURS=6 docker-compose up

# With dedicated cleanup service
docker-compose --profile cleanup up

# Disable cleanup
EEMT_CLEANUP_ENABLED=false docker-compose up
```

### Kubernetes Deployment

```bash
# Deploy cleanup CronJob
kubectl apply -f docker/kubernetes/cleanup-cronjob.yaml

# Check cleanup status
kubectl get cronjobs -n eemt
kubectl logs -n eemt job/eemt-cleanup-job-<timestamp>
```

### Manual Container Cleanup

```bash
# Run one-time cleanup
docker run --rm \
  -v ./data:/app/data \
  eemt-web:latest \
  python3 cleanup_jobs.py --dry-run

# With custom settings
docker run --rm \
  -v ./data:/app/data \
  -e EEMT_SUCCESS_RETENTION_DAYS=30 \
  -e EEMT_FAILED_RETENTION_HOURS=3 \
  eemt-web:latest \
  python3 cleanup_jobs.py
```

## Container Integration Details

### Web Interface Container (`eemt-web`)

**Location**: `docker/web-interface/Dockerfile`

**Added Components**:
- Cleanup scripts: `cleanup_jobs.py`, `setup_cleanup_cron.sh`
- Startup script: `startup.sh` (handles cleanup initialization)
- Cron service for automated execution
- Logging directory: `/app/logs/`

**Environment Variables**:
```bash
EEMT_CLEANUP_ENABLED=true          # Enable/disable cleanup
EEMT_SUCCESS_RETENTION_DAYS=7      # Days to keep successful job data
EEMT_FAILED_RETENTION_HOURS=12     # Hours to keep failed job data
```

**Automatic Features**:
- Cleanup cron job configured on container start
- Initial cleanup check performed during startup
- Comprehensive logging to `/app/logs/cleanup.log`

### Worker Container (`eemt:ubuntu24.04`)

**Location**: `docker/ubuntu/24.04/Dockerfile`

**Added Components**:
- Cleanup scripts copied to `/opt/eemt/bin/`
- Cron service installed for worker-level cleanup
- Logs directory: `/opt/eemt/logs/`

**Usage**: Worker nodes can clean up their temporary data independently

### Docker Compose Services

#### Main Services (with integrated cleanup)
- `eemt-web`: Web interface with automatic cleanup
- `eemt-master`: Distributed mode master with cleanup
- `eemt-worker`: Worker nodes with cleanup capability

#### Dedicated Cleanup Service
- `eemt-cleanup`: Standalone cleanup service
- Profile: `cleanup`
- Runs: Daily at 2 AM (configurable)

## Configuration Options

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `EEMT_CLEANUP_ENABLED` | `true` | Enable/disable automated cleanup |
| `EEMT_SUCCESS_RETENTION_DAYS` | `7` | Days to retain successful job data |
| `EEMT_FAILED_RETENTION_HOURS` | `12` | Hours to retain failed job data |
| `EEMT_CLEANUP_SCHEDULE` | `0 2 * * *` | Cron schedule for cleanup |

### Docker Compose Override

Create `docker-compose.override.yml`:

```yaml
version: '3.8'
services:
  eemt-web:
    environment:
      - EEMT_SUCCESS_RETENTION_DAYS=30  # Keep data for 30 days
      - EEMT_FAILED_RETENTION_HOURS=3   # Clean failed jobs after 3 hours
      - EEMT_CLEANUP_ENABLED=true
```

### Kubernetes Configuration

Modify `docker/kubernetes/cleanup-cronjob.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: eemt-cleanup-config
data:
  success-retention-days: "14"    # Custom retention period
  failed-retention-hours: "6"     # Custom retention period
  cleanup-schedule: "0 3 * * *"   # Run at 3 AM instead
```

## Deployment Profiles

### Profile: Standard (default)
- Web interface with integrated cleanup
- Automatic cron job setup
- Recommended for most deployments

### Profile: Distributed
- Master and worker nodes
- Each node handles its own cleanup
- Centralized data cleanup on master

### Profile: Cleanup (additional)
- Dedicated cleanup service
- Runs independently of main services
- Useful for high-volume deployments

### Profile: Docs
- Documentation server
- No cleanup functionality needed

## Monitoring and Debugging

### Log Files

**Container Logs**:
```bash
# Main application logs
docker logs eemt-web-local

# Cleanup-specific logs
docker exec eemt-web-local tail -f /app/logs/cleanup.log

# Cron service logs
docker exec eemt-web-local tail -f /var/log/cron.log
```

**Kubernetes Logs**:
```bash
# CronJob logs
kubectl logs -n eemt job/eemt-cleanup-job-$(date +%Y%m%d)

# Pod logs
kubectl logs -n eemt -l app=eemt-cleanup
```

### Health Checks

**Manual Cleanup Test**:
```bash
# Test cleanup (dry run)
docker exec eemt-web-local python3 cleanup_jobs.py --dry-run --verbose

# Check cron jobs
docker exec eemt-web-local crontab -l
```

**API Endpoint Test**:
```bash
# Manual cleanup via API
curl -X POST "http://localhost:5000/api/cleanup?dry_run=true"
```

### Troubleshooting

**Common Issues**:

1. **Cron not running**:
   ```bash
   docker exec eemt-web-local service cron status
   docker exec eemt-web-local service cron start
   ```

2. **Permission issues**:
   ```bash
   docker exec eemt-web-local ls -la /app/logs/
   docker exec eemt-web-local chmod 666 /app/logs/cleanup.log
   ```

3. **Database connection**:
   ```bash
   docker exec eemt-web-local python3 -c "import sqlite3; sqlite3.connect('/app/jobs.db').close(); print('Database OK')"
   ```

## Performance Impact

### Resource Usage
- **CPU**: Minimal impact during cleanup (< 5% CPU for ~10 minutes)
- **Memory**: ~256MB during cleanup operation
- **I/O**: High during cleanup, scheduled for low-usage hours (2 AM)

### Optimization
- Cleanup runs during low-activity hours
- Configurable retention periods balance storage vs. data availability
- Dry-run mode for testing without impact

## Security Considerations

### File Permissions
- Cleanup scripts run with container user privileges
- No elevated permissions required
- Logs written to container-local directories

### Data Safety
- Dry-run mode available for testing
- Job configurations preserved for successful runs
- Complete audit trail in logs

### Network Security
- Cleanup runs locally within containers
- No external network access required
- Database access limited to container filesystem

## Migration from Manual Cleanup

### Existing Deployments

1. **Update containers**:
   ```bash
   # Rebuild with cleanup integration
   docker-compose build
   ```

2. **Configure retention**:
   ```bash
   # Set environment variables
   export EEMT_SUCCESS_RETENTION_DAYS=14
   export EEMT_FAILED_RETENTION_HOURS=6
   ```

3. **Deploy updated services**:
   ```bash
   docker-compose up -d
   ```

### Data Preservation

Existing job data and configurations are preserved during migration. The cleanup system only affects future jobs based on their completion timestamps.

## Related Documentation

- [Job Cleanup Documentation](docs/infrastructure/job-cleanup.md)
- [Cleanup Scripts User Guide](docs/getting-started/cleanup-scripts.md)
- [Docker Integration Guide](docs/docker/cleanup-integration.md)
- [API Endpoints](docs/api/endpoints.md)

## Support

For issues with the cleanup system:

1. Check container logs: `docker logs <container-name>`
2. Verify configuration: `docker exec <container> env | grep EEMT`
3. Test cleanup manually: `docker exec <container> python3 cleanup_jobs.py --dry-run`
4. Review documentation: See links above

The integrated cleanup system provides automated, configurable, and safe management of EEMT job data across all deployment scenarios.