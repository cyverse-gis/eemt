# Docker Cleanup Integration Guide

This guide explains how to integrate the EEMT job data cleanup system with Docker and container orchestration platforms.

## Overview

The EEMT cleanup system is designed to work seamlessly in containerized environments, providing multiple integration options:

- **Built-in container cleanup**: Cleanup runs within the web interface container
- **Dedicated cleanup container**: Separate container for cleanup operations  
- **Orchestration integration**: Works with Docker Compose, Kubernetes, and Swarm
- **Volume management**: Handles Docker volumes and bind mounts correctly
- **Multi-container coordination**: Supports distributed deployments

## Docker Compose Integration

### Basic Configuration

Add cleanup configuration to your `docker-compose.yml`:

```yaml
version: '3.8'

services:
  eemt-web:
    image: eemt-web:latest
    container_name: eemt-web
    ports:
      - "5000:5000"
    environment:
      # Cleanup configuration
      - EEMT_SUCCESS_RETENTION_DAYS=7
      - EEMT_FAILED_RETENTION_HOURS=12
      - EEMT_ENABLE_AUTO_CLEANUP=true
      - EEMT_CLEANUP_SCHEDULE=0 2 * * *  # Daily at 2 AM
    volumes:
      - ./data/uploads:/app/uploads
      - ./data/results:/app/results
      - ./data/jobs.db:/app/jobs.db
      - ./data/logs:/app/logs
    restart: unless-stopped
```

### With Dedicated Cleanup Service

For better separation of concerns, use a dedicated cleanup service:

```yaml
version: '3.8'

services:
  eemt-web:
    image: eemt-web:latest
    container_name: eemt-web
    ports:
      - "5000:5000"
    volumes:
      - eemt-uploads:/app/uploads
      - eemt-results:/app/results
      - eemt-db:/app/db
    restart: unless-stopped

  eemt-cleanup:
    image: eemt-web:latest
    container_name: eemt-cleanup
    environment:
      - EEMT_SUCCESS_RETENTION_DAYS=7
      - EEMT_FAILED_RETENTION_HOURS=12
    volumes:
      - eemt-uploads:/app/uploads:rw
      - eemt-results:/app/results:rw
      - eemt-db:/app/db:rw
    entrypoint: ["/bin/sh", "-c"]
    command:
      - |
        while true; do
          echo "Running cleanup at $$(date)"
          python /app/cleanup_jobs.py
          echo "Cleanup complete. Sleeping for 24 hours..."
          sleep 86400
        done
    restart: unless-stopped
    depends_on:
      - eemt-web

volumes:
  eemt-uploads:
  eemt-results:
  eemt-db:
```

### Production Configuration

Full production setup with monitoring and backups:

```yaml
version: '3.8'

services:
  eemt-web:
    image: eemt-web:${VERSION:-latest}
    container_name: eemt-web
    ports:
      - "5000:5000"
    environment:
      - EEMT_ENV=production
      - EEMT_LOG_LEVEL=INFO
    volumes:
      - eemt-uploads:/app/uploads
      - eemt-results:/app/results
      - eemt-db:/app/db
      - eemt-logs:/app/logs
    restart: always
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5000/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  eemt-cleanup:
    image: eemt-web:${VERSION:-latest}
    container_name: eemt-cleanup
    environment:
      - EEMT_SUCCESS_RETENTION_DAYS=${SUCCESS_RETENTION:-7}
      - EEMT_FAILED_RETENTION_HOURS=${FAILED_RETENTION:-12}
      - EEMT_CLEANUP_LOG_LEVEL=INFO
      - TZ=America/New_York  # Set timezone for scheduling
    volumes:
      - eemt-uploads:/app/uploads:rw
      - eemt-results:/app/results:rw
      - eemt-db:/app/db:rw
      - eemt-logs:/app/logs:rw
      - eemt-cleanup-logs:/app/cleanup-logs:rw
    entrypoint: ["/usr/local/bin/cleanup-scheduler.sh"]
    restart: always
    depends_on:
      eemt-web:
        condition: service_healthy
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 512M

  # Optional: Backup service
  eemt-backup:
    image: alpine:latest
    container_name: eemt-backup
    volumes:
      - eemt-results:/data/results:ro
      - eemt-db:/data/db:ro
      - ./backups:/backups:rw
    entrypoint: ["/bin/sh", "-c"]
    command:
      - |
        while true; do
          echo "Creating backup at $$(date)"
          tar -czf /backups/backup_$$(date +%Y%m%d_%H%M%S).tar.gz \
            /data/results /data/db
          # Keep only last 7 backups
          ls -t /backups/backup_*.tar.gz | tail -n +8 | xargs -r rm
          sleep 86400
        done
    restart: unless-stopped

volumes:
  eemt-uploads:
    driver: local
  eemt-results:
    driver: local
  eemt-db:
    driver: local
  eemt-logs:
    driver: local
  eemt-cleanup-logs:
    driver: local

networks:
  default:
    name: eemt-network
    driver: bridge
```

## Container Execution Methods

### Method 1: Execute in Running Container

Run cleanup in an existing web interface container:

```bash
# One-time cleanup
docker exec eemt-web python /app/cleanup_jobs.py

# Dry run to preview
docker exec eemt-web python /app/cleanup_jobs.py --dry-run

# With custom retention
docker exec eemt-web python /app/cleanup_jobs.py \
  --success-retention-days 3 \
  --failed-retention-hours 6

# View cleanup logs
docker exec eemt-web tail -f /app/logs/cleanup_jobs.log
```

### Method 2: Dedicated Cleanup Container

Run cleanup in a separate container:

```bash
# Create cleanup container
docker run -d \
  --name eemt-cleanup \
  --network eemt-network \
  -v eemt-uploads:/app/uploads \
  -v eemt-results:/app/results \
  -v eemt-db:/app/db \
  -e EEMT_SUCCESS_RETENTION_DAYS=7 \
  -e EEMT_FAILED_RETENTION_HOURS=12 \
  eemt-web:latest \
  sh -c 'while true; do python /app/cleanup_jobs.py; sleep 86400; done'

# Check cleanup status
docker logs eemt-cleanup --tail 50

# Stop cleanup container
docker stop eemt-cleanup
docker rm eemt-cleanup
```

### Method 3: One-off Cleanup Container

Run cleanup as a one-time operation:

```bash
# Run and remove container after cleanup
docker run --rm \
  --network eemt-network \
  -v $(pwd)/data/uploads:/app/uploads \
  -v $(pwd)/data/results:/app/results \
  -v $(pwd)/data/jobs.db:/app/jobs.db \
  eemt-web:latest \
  python /app/cleanup_jobs.py --verbose

# Dry run with bind mounts
docker run --rm \
  -v $(pwd)/uploads:/app/uploads:ro \
  -v $(pwd)/results:/app/results:ro \
  -v $(pwd)/jobs.db:/app/jobs.db:ro \
  eemt-web:latest \
  python /app/cleanup_jobs.py --dry-run
```

## Dockerfile Integration

### Adding Cleanup to Web Interface Image

Modify your Dockerfile to include cleanup capabilities:

```dockerfile
FROM eemt:ubuntu24.04

# Install cleanup dependencies
RUN pip install --no-cache-dir \
    schedule \
    python-crontab

# Copy cleanup scripts
COPY web-interface/cleanup_jobs.py /app/
COPY scripts/cleanup-scheduler.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/cleanup-scheduler.sh

# Create cleanup log directory
RUN mkdir -p /app/logs/cleanup

# Set cleanup environment defaults
ENV EEMT_SUCCESS_RETENTION_DAYS=7 \
    EEMT_FAILED_RETENTION_HOURS=12 \
    EEMT_ENABLE_AUTO_CLEANUP=false

# Entry point that optionally starts cleanup
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["python", "app.py"]
```

### Docker Entry Point Script

Create `docker-entrypoint.sh` to handle cleanup scheduling:

```bash
#!/bin/sh
set -e

# Start cleanup scheduler if enabled
if [ "$EEMT_ENABLE_AUTO_CLEANUP" = "true" ]; then
    echo "Starting cleanup scheduler..."
    
    # Create cron job
    SCHEDULE="${EEMT_CLEANUP_SCHEDULE:-0 2 * * *}"
    echo "$SCHEDULE cd /app && python cleanup_jobs.py >> /app/logs/cleanup/cleanup.log 2>&1" | crontab -
    
    # Start cron daemon
    crond || cron
    
    echo "Cleanup scheduler started with schedule: $SCHEDULE"
fi

# Execute main command
exec "$@"
```

### Cleanup Scheduler Script

Create `cleanup-scheduler.sh` for dedicated cleanup containers:

```bash
#!/bin/sh
#
# Cleanup scheduler for Docker containers
#

set -e

# Configuration from environment
SUCCESS_RETENTION=${EEMT_SUCCESS_RETENTION_DAYS:-7}
FAILED_RETENTION=${EEMT_FAILED_RETENTION_HOURS:-12}
CLEANUP_INTERVAL=${EEMT_CLEANUP_INTERVAL:-86400}  # Default 24 hours
DRY_RUN=${EEMT_DRY_RUN:-false}

echo "EEMT Cleanup Scheduler Started"
echo "================================"
echo "Success retention: $SUCCESS_RETENTION days"
echo "Failed retention: $FAILED_RETENTION hours"
echo "Cleanup interval: $CLEANUP_INTERVAL seconds"
echo "Dry run mode: $DRY_RUN"
echo ""

# Function to run cleanup
run_cleanup() {
    echo "[$(date)] Starting cleanup run..."
    
    CLEANUP_ARGS="--success-retention-days $SUCCESS_RETENTION"
    CLEANUP_ARGS="$CLEANUP_ARGS --failed-retention-hours $FAILED_RETENTION"
    
    if [ "$DRY_RUN" = "true" ]; then
        CLEANUP_ARGS="$CLEANUP_ARGS --dry-run"
    fi
    
    if python /app/cleanup_jobs.py $CLEANUP_ARGS; then
        echo "[$(date)] Cleanup completed successfully"
    else
        echo "[$(date)] Cleanup failed with exit code $?"
    fi
}

# Signal handlers
trap 'echo "Received SIGTERM, shutting down..."; exit 0' TERM
trap 'echo "Received SIGINT, shutting down..."; exit 0' INT

# Main loop
while true; do
    run_cleanup
    
    echo "[$(date)] Sleeping for $CLEANUP_INTERVAL seconds..."
    sleep $CLEANUP_INTERVAL &
    wait $!
done
```

## Kubernetes Integration

### Kubernetes CronJob

Deploy cleanup as a Kubernetes CronJob:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: eemt-cleanup
  namespace: eemt
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM UTC
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      template:
        metadata:
          labels:
            app: eemt-cleanup
        spec:
          containers:
          - name: cleanup
            image: eemt-web:latest
            imagePullPolicy: Always
            command:
              - python
              - /app/cleanup_jobs.py
            env:
            - name: EEMT_SUCCESS_RETENTION_DAYS
              value: "7"
            - name: EEMT_FAILED_RETENTION_HOURS
              value: "12"
            - name: EEMT_DRY_RUN
              value: "false"
            volumeMounts:
            - name: uploads
              mountPath: /app/uploads
            - name: results
              mountPath: /app/results
            - name: database
              mountPath: /app/db
            resources:
              requests:
                memory: "256Mi"
                cpu: "100m"
              limits:
                memory: "512Mi"
                cpu: "500m"
          restartPolicy: OnFailure
          volumes:
          - name: uploads
            persistentVolumeClaim:
              claimName: eemt-uploads-pvc
          - name: results
            persistentVolumeClaim:
              claimName: eemt-results-pvc
          - name: database
            persistentVolumeClaim:
              claimName: eemt-database-pvc
```

### Kubernetes ConfigMap

Store cleanup configuration in a ConfigMap:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: eemt-cleanup-config
  namespace: eemt
data:
  cleanup_config.yaml: |
    retention:
      successful_jobs:
        days: 7
        keep_metadata: true
      failed_jobs:
        hours: 12
        keep_error_logs: true
    
    performance:
      batch_size: 100
      parallel_delete: false
    
    logging:
      level: INFO
      format: json
```

### Helm Chart Integration

Add cleanup to your Helm chart:

```yaml
# values.yaml
cleanup:
  enabled: true
  schedule: "0 2 * * *"
  retention:
    successDays: 7
    failedHours: 12
  resources:
    requests:
      memory: 256Mi
      cpu: 100m
    limits:
      memory: 512Mi
      cpu: 500m

# templates/cleanup-cronjob.yaml
{{- if .Values.cleanup.enabled }}
apiVersion: batch/v1
kind: CronJob
metadata:
  name: {{ include "eemt.fullname" . }}-cleanup
spec:
  schedule: {{ .Values.cleanup.schedule | quote }}
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: cleanup
            image: {{ .Values.image.repository }}:{{ .Values.image.tag }}
            command: ["python", "/app/cleanup_jobs.py"]
            env:
            - name: EEMT_SUCCESS_RETENTION_DAYS
              value: {{ .Values.cleanup.retention.successDays | quote }}
            - name: EEMT_FAILED_RETENTION_HOURS
              value: {{ .Values.cleanup.retention.failedHours | quote }}
            resources:
              {{- toYaml .Values.cleanup.resources | nindent 14 }}
{{- end }}
```

## Docker Swarm Integration

### Swarm Service Configuration

Deploy cleanup as a Swarm service:

```yaml
version: '3.8'

services:
  eemt-cleanup:
    image: eemt-web:latest
    environment:
      - EEMT_SUCCESS_RETENTION_DAYS=7
      - EEMT_FAILED_RETENTION_HOURS=12
    volumes:
      - eemt-uploads:/app/uploads
      - eemt-results:/app/results
      - eemt-db:/app/db
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      restart_policy:
        condition: any
        delay: 5s
        max_attempts: 3
      resources:
        limits:
          cpus: '0.5'
          memory: 512M
        reservations:
          cpus: '0.1'
          memory: 128M
    networks:
      - eemt-network
    command: |
      sh -c '
        while true; do
          python /app/cleanup_jobs.py
          sleep 86400
        done
      '

volumes:
  eemt-uploads:
    driver: local
    driver_opts:
      type: nfs
      o: addr=nfs-server.example.com,rw
      device: ":/data/eemt/uploads"
  eemt-results:
    driver: local
    driver_opts:
      type: nfs
      o: addr=nfs-server.example.com,rw
      device: ":/data/eemt/results"
  eemt-db:
    driver: local
    driver_opts:
      type: nfs
      o: addr=nfs-server.example.com,rw
      device: ":/data/eemt/db"

networks:
  eemt-network:
    driver: overlay
    attachable: true
```

## Volume Management

### Docker Volume Best Practices

1. **Use Named Volumes**: Prefer named volumes over bind mounts for production:
   ```yaml
   volumes:
     eemt-data:
       driver: local
       driver_opts:
         type: none
         o: bind
         device: /data/eemt
   ```

2. **Volume Backup**: Before cleanup, backup important data:
   ```bash
   # Backup volume to tar
   docker run --rm \
     -v eemt-results:/data \
     -v $(pwd)/backups:/backup \
     alpine \
     tar czf /backup/results_$(date +%Y%m%d).tar.gz /data
   ```

3. **Volume Inspection**: Check volume usage:
   ```bash
   # List volumes
   docker volume ls | grep eemt
   
   # Inspect volume
   docker volume inspect eemt-results
   
   # Check volume size
   docker run --rm -v eemt-results:/data alpine du -sh /data
   ```

### Shared Volume Considerations

When multiple containers share volumes:

```yaml
services:
  eemt-web:
    volumes:
      - shared-data:/app/data:rw
  
  eemt-worker-1:
    volumes:
      - shared-data:/app/data:ro  # Read-only for workers
  
  eemt-cleanup:
    volumes:
      - shared-data:/app/data:rw  # Read-write for cleanup
```

## Monitoring in Docker

### Container Logs

Monitor cleanup operations:

```bash
# View cleanup logs
docker logs eemt-cleanup --follow

# View last 100 lines
docker logs eemt-cleanup --tail 100

# View logs since specific time
docker logs eemt-cleanup --since 2024-01-20T10:00:00

# Save logs to file
docker logs eemt-cleanup > cleanup_logs.txt 2>&1
```

### Docker Stats

Monitor resource usage:

```bash
# Real-time stats
docker stats eemt-cleanup

# One-time snapshot
docker stats --no-stream eemt-cleanup

# Format output
docker stats --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}"
```

### Health Checks

Add health checks to monitor cleanup service:

```dockerfile
HEALTHCHECK --interval=1h --timeout=5m --start-period=30s --retries=3 \
  CMD python /app/cleanup_jobs.py --dry-run || exit 1
```

## Troubleshooting Docker Integration

### Common Issues

#### Container Permissions

```bash
# Check container user
docker exec eemt-cleanup whoami

# Fix volume permissions
docker exec eemt-cleanup chown -R $(id -u):$(id -g) /app/data

# Run with specific user
docker run --user $(id -u):$(id -g) eemt-web cleanup_jobs.py
```

#### Volume Mount Issues

```bash
# Verify volume mounts
docker inspect eemt-cleanup | jq '.[0].Mounts'

# Test volume access
docker exec eemt-cleanup ls -la /app/uploads /app/results

# Check volume driver
docker volume inspect eemt-results | jq '.[0].Driver'
```

#### Container Networking

```bash
# Check container network
docker inspect eemt-cleanup | jq '.[0].NetworkSettings.Networks'

# Test connectivity
docker exec eemt-cleanup ping -c 3 eemt-web

# List network details
docker network inspect eemt-network
```

### Debug Mode

Enable detailed debugging in containers:

```bash
# Run with debug environment
docker run --rm \
  -e EEMT_CLEANUP_LOG_LEVEL=DEBUG \
  -e PYTHONUNBUFFERED=1 \
  -v eemt-data:/app/data \
  eemt-web:latest \
  python /app/cleanup_jobs.py --verbose --dry-run
```

## Best Practices

### 1. Container Lifecycle Management

```yaml
# Ensure cleanup runs after main services
depends_on:
  eemt-web:
    condition: service_healthy
```

### 2. Resource Limits

```yaml
# Set appropriate limits for cleanup
deploy:
  resources:
    limits:
      cpus: '0.5'
      memory: 512M
    reservations:
      cpus: '0.1'
      memory: 128M
```

### 3. Logging Strategy

```yaml
# Configure logging driver
logging:
  driver: json-file
  options:
    max-size: "10m"
    max-file: "3"
```

### 4. Security

```yaml
# Run as non-root user
user: "1000:1000"
read_only: true
security_opt:
  - no-new-privileges:true
```

### 5. Monitoring Integration

```yaml
# Prometheus metrics
ports:
  - "9090:9090"
environment:
  - ENABLE_METRICS=true
```

## Example Deployment Scripts

### Deploy with Cleanup

```bash
#!/bin/bash
# deploy-with-cleanup.sh

set -e

echo "Deploying EEMT with cleanup..."

# Build images
docker-compose build

# Start services
docker-compose up -d eemt-web

# Wait for web service to be healthy
echo "Waiting for web service..."
until docker-compose exec eemt-web curl -f http://localhost:5000/health; do
  sleep 5
done

# Start cleanup service
docker-compose up -d eemt-cleanup

echo "Deployment complete!"
echo "Web interface: http://localhost:5000"
echo "Cleanup service: running (check logs with: docker logs eemt-cleanup)"
```

### Manual Cleanup Trigger

```bash
#!/bin/bash
# trigger-cleanup.sh

set -e

echo "Triggering manual cleanup..."

# Check if dry run
DRY_RUN=${1:-false}

if [ "$DRY_RUN" = "true" ]; then
  echo "Running in dry-run mode..."
  docker exec eemt-web python /app/cleanup_jobs.py --dry-run
else
  echo "Running actual cleanup..."
  docker exec eemt-web python /app/cleanup_jobs.py
fi

echo "Cleanup complete. Check logs:"
echo "  docker logs eemt-web --tail 50"
```

## Summary

Docker integration provides flexible deployment options for the EEMT cleanup system:

- **Simple integration** with existing Docker Compose setups
- **Multiple execution methods** from built-in to dedicated containers
- **Orchestration support** for Kubernetes, Swarm, and other platforms
- **Volume management** with proper permissions and backup strategies
- **Comprehensive monitoring** through container logs and metrics

Choose the integration method that best fits your deployment architecture and operational requirements.