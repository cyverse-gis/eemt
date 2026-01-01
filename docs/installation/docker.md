# Docker Deployment Guide

## Overview

This guide provides comprehensive instructions for deploying EEMT using Docker containers. The containerized deployment offers the most reliable and reproducible way to run EEMT workflows, eliminating complex dependency management and ensuring consistent execution across different systems.

## Prerequisites

### System Requirements

**Minimum Hardware**:
- CPU: 4 cores (8+ recommended)
- RAM: 8 GB (16+ GB recommended)
- Storage: 50 GB free space
- Network: Stable internet connection for climate data downloads

**Software Requirements**:
- Docker Engine 20.10+ or Docker Desktop
- Docker Compose v2.0+
- Git (for cloning repository)
- Modern web browser (Chrome, Firefox, Safari, Edge)

### Docker Installation

#### Linux (Ubuntu/Debian)

```bash
# Update package index
sudo apt update

# Install prerequisites
sudo apt install -y apt-transport-https ca-certificates curl software-properties-common

# Add Docker GPG key
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# Add Docker repository
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Add user to docker group (log out and back in after)
sudo usermod -aG docker $USER

# Verify installation
docker --version
docker compose version
```

#### macOS

```bash
# Install Docker Desktop
# Download from: https://www.docker.com/products/docker-desktop

# Or use Homebrew
brew install --cask docker

# Start Docker Desktop from Applications
# Verify installation
docker --version
docker compose version
```

#### Windows

```powershell
# Install Docker Desktop
# Download from: https://www.docker.com/products/docker-desktop

# Enable WSL2 backend (recommended)
wsl --install

# Verify installation
docker --version
docker compose version
```

## Quick Start

### 1. Clone Repository

```bash
git clone https://github.com/cyverse-gis/eemt.git
cd eemt
```

### 2. Build Containers

```bash
# Build all required containers
docker compose build

# Or build specific service
docker compose build eemt-web
```

### 3. Start Services

```bash
# Start in foreground (see logs)
docker compose up

# Start in background
docker compose up -d

# Access web interface
open http://localhost:5000  # macOS
xdg-open http://localhost:5000  # Linux
start http://localhost:5000  # Windows
```

### 4. Submit a Job

1. Navigate to http://localhost:5000
2. Select workflow type (Solar or EEMT)
3. Upload your DEM file
4. Configure parameters
5. Click "Submit Job"
6. Monitor progress at http://localhost:5000/monitor

## Deployment Modes

### Local Mode (Default)

Single-container deployment for development and small-scale processing:

```yaml
# docker-compose.yml (simplified)
services:
  eemt-web:
    build:
      context: .
      dockerfile: docker/web-interface/Dockerfile
    ports:
      - "5000:5000"
    volumes:
      - ./data:/app/data
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - EEMT_MODE=local
```

**Start Command**:
```bash
docker compose up eemt-web
```

**Use Cases**:
- Development and testing
- Small to medium DEM processing
- Single-user environments
- Educational purposes

### Distributed Mode

Multi-container deployment with master-worker architecture:

```yaml
# docker-compose.yml (distributed profile)
services:
  eemt-master:
    profiles: [distributed]
    ports:
      - "5000:5000"  # Web interface
      - "9123:9123"  # Work Queue port
    environment:
      - EEMT_MODE=master
      - MAX_WORKERS=10

  eemt-worker:
    profiles: [distributed]
    environment:
      - MASTER_HOST=eemt-master
      - WORKER_CORES=4
    deploy:
      replicas: 5
```

**Start Command**:
```bash
# Start distributed cluster
docker compose --profile distributed up

# Scale workers dynamically
docker compose --profile distributed up --scale eemt-worker=10
```

**Use Cases**:
- Large-scale processing
- Multi-user environments
- Production deployments
- HPC integration

### Documentation Mode

Serve documentation alongside the application:

```bash
# Start with documentation
docker compose --profile docs up

# Access documentation at http://localhost:8000
```

## Configuration

### Environment Variables

Create a `.env` file in the project root:

```bash
# Application Configuration
EEMT_HOST=0.0.0.0
EEMT_PORT=5000
EEMT_MODE=local

# Resource Limits
CONTAINER_CPU_LIMIT=4
CONTAINER_MEMORY_LIMIT=8G
CONTAINER_DISK_LIMIT=50G

# Directory Configuration
EEMT_UPLOAD_DIR=./data/uploads
EEMT_RESULTS_DIR=./data/results
EEMT_TEMP_DIR=./data/temp
EEMT_CACHE_DIR=./data/cache

# Distributed Mode (optional)
WORK_QUEUE_PORT=9123
WORK_QUEUE_PROJECT=EEMT-Production
MAX_WORKERS=20

# Worker Configuration (optional)
MASTER_HOST=eemt-master
MASTER_PORT=9123
WORKER_CORES=8
WORKER_MEMORY=16G
```

### Docker Compose Override

Create `docker-compose.override.yml` for local customizations:

```yaml
version: '3.8'

services:
  eemt-web:
    environment:
      - DEBUG=true
      - LOG_LEVEL=INFO
    volumes:
      - ./custom-data:/app/custom-data
    ports:
      - "8080:5000"  # Use different port
```

### Volume Configuration

#### Persistent Data Volumes

```yaml
volumes:
  # Named volumes for persistence
  eemt-uploads:
    driver: local
  eemt-results:
    driver: local
  eemt-cache:
    driver: local

services:
  eemt-web:
    volumes:
      - eemt-uploads:/app/uploads
      - eemt-results:/app/results
      - eemt-cache:/app/cache
```

#### Bind Mounts for Development

```yaml
services:
  eemt-web:
    volumes:
      # Mount source code for live updates
      - ./web-interface:/app/web-interface
      - ./sol:/opt/eemt/sol
      - ./eemt:/opt/eemt/eemt
```

## Advanced Configuration

### Resource Management

#### CPU and Memory Limits

```yaml
services:
  eemt-worker:
    deploy:
      resources:
        limits:
          cpus: '4.0'
          memory: 8G
        reservations:
          cpus: '2.0'
          memory: 4G
```

#### GPU Support (Future)

```yaml
services:
  eemt-gpu-worker:
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]
```

### Network Configuration

#### Custom Network

```yaml
networks:
  eemt-network:
    driver: bridge
    ipam:
      driver: default
      config:
        - subnet: 172.20.0.0/16
          gateway: 172.20.0.1
```

#### External Network Access

```yaml
services:
  eemt-web:
    networks:
      - eemt-network
      - external-network

networks:
  external-network:
    external: true
```

### Security Configuration

#### Read-Only Root Filesystem

```yaml
services:
  eemt-worker:
    read_only: true
    tmpfs:
      - /tmp
      - /run
    volumes:
      - ./data:/data:ro
```

#### Secrets Management

```yaml
secrets:
  db_password:
    file: ./secrets/db_password.txt

services:
  eemt-web:
    secrets:
      - db_password
    environment:
      - DB_PASSWORD_FILE=/run/secrets/db_password
```

## Monitoring and Logging

### View Logs

```bash
# All services
docker compose logs

# Specific service
docker compose logs eemt-web

# Follow logs in real-time
docker compose logs -f

# Last 100 lines
docker compose logs --tail=100
```

### Container Statistics

```bash
# Resource usage
docker stats

# Specific containers
docker stats eemt-web eemt-worker

# Format output
docker stats --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}"
```

### Health Checks

```yaml
services:
  eemt-web:
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
```

## Backup and Recovery

### Backup Data Volumes

```bash
# Stop containers
docker compose down

# Backup uploads directory
docker run --rm -v eemt_data-uploads:/data -v $(pwd):/backup \
  ubuntu:24.04 tar czf /backup/uploads-backup.tar.gz /data

# Backup results directory  
docker run --rm -v eemt_data-results:/data -v $(pwd):/backup \
  ubuntu:24.04 tar czf /backup/results-backup.tar.gz /data

# Backup database
docker run --rm -v eemt_data:/data -v $(pwd):/backup \
  ubuntu:24.04 cp /data/jobs.db /backup/jobs-backup.db
```

### Restore Data Volumes

```bash
# Restore uploads
docker run --rm -v eemt_data-uploads:/data -v $(pwd):/backup \
  ubuntu:24.04 tar xzf /backup/uploads-backup.tar.gz -C /

# Restore results
docker run --rm -v eemt_data-results:/data -v $(pwd):/backup \
  ubuntu:24.04 tar xzf /backup/results-backup.tar.gz -C /

# Restore database
docker run --rm -v eemt_data:/data -v $(pwd):/backup \
  ubuntu:24.04 cp /backup/jobs-backup.db /data/jobs.db

# Restart services
docker compose up -d
```

## Troubleshooting

### Common Issues

#### Port Already in Use

```bash
# Check what's using port 5000
lsof -i :5000  # macOS/Linux
netstat -ano | findstr :5000  # Windows

# Use different port
docker compose up -e EEMT_PORT=8080
```

#### Docker Daemon Not Running

```bash
# Linux
sudo systemctl start docker

# macOS/Windows
# Start Docker Desktop application
```

#### Container Won't Start

```bash
# Check logs
docker compose logs eemt-web

# Inspect container
docker inspect eemt-web

# Debug interactively
docker compose run --entrypoint /bin/bash eemt-web
```

#### Permission Denied Errors

```bash
# Fix Docker socket permissions (Linux)
sudo chmod 666 /var/run/docker.sock

# Fix volume permissions
docker compose exec eemt-web chown -R eemt:eemt /app/data
```

#### Out of Disk Space

```bash
# Check disk usage
df -h

# Clean up Docker
docker system prune -a
docker volume prune
docker image prune
```

### Debugging

#### Interactive Shell Access

```bash
# Access running container
docker compose exec eemt-web /bin/bash

# Start new container with shell
docker compose run --rm eemt-web /bin/bash

# Override entrypoint
docker compose run --entrypoint /bin/bash eemt-web
```

#### Network Debugging

```bash
# Test connectivity between containers
docker compose exec eemt-worker ping eemt-master

# Inspect network
docker network inspect eemt_eemt-network

# Use network debugging container
docker run --rm -it --network eemt_eemt-network nicolaka/netshoot
```

## Performance Optimization

### Build Optimization

```bash
# Use BuildKit for faster builds
DOCKER_BUILDKIT=1 docker compose build

# Parallel builds
docker compose build --parallel

# Use cache
docker compose build --no-cache=false
```

### Runtime Optimization

```yaml
services:
  eemt-web:
    # Enable shared memory
    shm_size: '2gb'
    
    # Optimize logging
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
```

### Storage Optimization

```bash
# Use tmpfs for temporary data
docker compose run --tmpfs /tmp:size=2G eemt-worker

# Enable compression
docker save eemt:ubuntu24.04 | gzip > eemt.tar.gz
```

## Production Deployment

### SSL/TLS Configuration

```yaml
services:
  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf
      - ./certs:/etc/nginx/certs
    depends_on:
      - eemt-web
```

### Docker Swarm Deployment

```bash
# Initialize swarm
docker swarm init

# Deploy stack
docker stack deploy -c docker-compose.yml eemt

# Scale service
docker service scale eemt_eemt-worker=10

# Monitor services
docker service ls
docker service ps eemt_eemt-web
```

### Kubernetes Deployment

```bash
# Convert docker-compose to Kubernetes
kompose convert

# Deploy to Kubernetes
kubectl apply -f eemt-deployment.yaml
kubectl apply -f eemt-service.yaml

# Check deployment
kubectl get pods
kubectl get services
```

## Maintenance

### Update Containers

```bash
# Pull latest images
docker compose pull

# Rebuild containers
docker compose build --pull

# Restart with new images
docker compose up -d
```

### Clean Up

```bash
# Stop and remove containers
docker compose down

# Remove volumes (WARNING: deletes data)
docker compose down -v

# Remove everything including images
docker compose down --rmi all -v

# System-wide cleanup
docker system prune -a --volumes
```

### Log Rotation

```yaml
services:
  eemt-web:
    logging:
      driver: "json-file"
      options:
        max-size: "100m"
        max-file: "10"
        compress: "true"
```

## Best Practices

### Development

1. Use `.env` files for configuration
2. Mount source code as volumes for hot-reloading
3. Use override files for local settings
4. Keep images small with multi-stage builds

### Production

1. Use specific image tags (not `latest`)
2. Implement health checks
3. Set resource limits
4. Use secrets for sensitive data
5. Enable log rotation
6. Regular backups
7. Monitor resource usage

### Security

1. Run containers as non-root user
2. Use read-only filesystems where possible
3. Limit network exposure
4. Scan images for vulnerabilities
5. Keep base images updated

## Next Steps

- [Web Interface Guide](../web-interface/index.md) - Learn to use the web interface
- [API Reference](../web-interface/api-reference.md) - Integrate with the REST API
- [Distributed Deployment](../distributed-deployment/index.md) - Scale across multiple nodes
- [Container Architecture](../infrastructure/container-architecture.md) - Understand the container design