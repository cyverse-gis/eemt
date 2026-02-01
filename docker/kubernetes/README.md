# EEMT Kubernetes Deployment

This directory contains Kubernetes manifests and Helm charts for deploying the EEMT (Effective Energy and Mass Transfer) Algorithm Suite on Kubernetes clusters.

## Overview

The EEMT Kubernetes deployment provides:

- **Scalable Web Interface**: FastAPI-based web service for job submission and monitoring
- **Distributed Worker Nodes**: Auto-scaling compute nodes for geospatial processing
- **Automated Data Cleanup**: CronJob-based cleanup of old job data
- **Persistent Storage**: Configured storage for data, databases, cache, and logs
- **Monitoring & Observability**: Prometheus metrics and structured logging
- **Security**: RBAC, service accounts, and network policies

## Quick Start

### Prerequisites

- Kubernetes cluster (v1.20+)
- Helm 3.x
- kubectl configured with cluster access
- Sufficient cluster resources (see [Resource Requirements](#resource-requirements))

### 1. Basic Deployment

```bash
# Clone the repository
git clone https://github.com/cyverse-gis/eemt.git
cd eemt/docker/kubernetes

# Create namespace and basic resources
kubectl apply -f manifests/namespace.yaml
kubectl apply -f manifests/rbac.yaml

# Deploy using Helm
helm install eemt helm/eemt/ -n eemt

# Check deployment status
kubectl get pods -n eemt
kubectl get services -n eemt
```

### 2. Access the Web Interface

```bash
# Port forward to access locally
kubectl port-forward -n eemt service/eemt-web 5000:5000

# Open browser to http://localhost:5000
```

### 3. Scale Workers

```bash
# Manual scaling
kubectl scale deployment eemt-worker --replicas=10 -n eemt

# Auto-scaling (if enabled in values.yaml)
kubectl get hpa -n eemt
```

## Directory Structure

```
docker/kubernetes/
├── manifests/                    # Raw Kubernetes manifests
│   ├── namespace.yaml           # Namespace and resource quotas
│   ├── rbac.yaml               # Service accounts and RBAC
│   └── cleanup-cronjob.yaml    # Standalone cleanup job
├── helm/                       # Helm charts
│   └── eemt/                   # Main EEMT Helm chart
│       ├── Chart.yaml          # Chart metadata
│       ├── values.yaml         # Default configuration values
│       └── templates/          # Kubernetes manifest templates
│           ├── _helpers.tpl    # Template helpers
│           ├── web-interface-deployment.yaml
│           ├── web-interface-service.yaml
│           ├── worker-deployment.yaml
│           ├── worker-hpa.yaml
│           ├── persistentvolumes.yaml
│           ├── configmap.yaml
│           ├── serviceaccount.yaml
│           ├── ingress.yaml
│           └── cleanup-cronjob.yaml
├── kubeconfig-example.yaml     # Example kubeconfig template
└── README.md                   # This file
```

## Resource Requirements

### Minimum Cluster Resources

| Component | CPU | Memory | Storage |
|-----------|-----|--------|---------|
| Web Interface | 500m | 1Gi | - |
| Worker Node | 2 cores | 4Gi | 20Gi ephemeral |
| Database | - | - | 10Gi persistent |
| Data Storage | - | - | 100Gi persistent |
| Total (4 workers) | 8.5 cores | 17Gi | 130Gi |

### Recommended Production Resources

| Component | CPU | Memory | Storage |
|-----------|-----|--------|---------|
| Web Interface | 2 cores | 4Gi | - |
| Worker Nodes (10x) | 80 cores | 160Gi | 500Gi ephemeral |
| Database | - | - | 50Gi persistent |
| Data Storage | - | - | 1Ti persistent |
| Cache Storage | - | - | 200Gi persistent |
| Total | 82 cores | 164Gi | 1.75Ti |

## Configuration

### Helm Values Configuration

The main configuration is done through Helm values. See [`helm/eemt/values.yaml`](helm/eemt/values.yaml) for all available options.

#### Key Configuration Sections

```yaml
# Basic deployment mode
global:
  eemt:
    mode: distributed  # local, distributed, hybrid
    resourceStrategy: balanced  # minimal, balanced, performance

# Worker auto-scaling
workers:
  autoscaling:
    enabled: true
    minReplicas: 2
    maxReplicas: 20
    targetCPUUtilizationPercentage: 70

# Cleanup configuration
cleanup:
  enabled: true
  schedule: "0 2 * * *"
  retention:
    successfulJobs:
      days: 7
    failedJobs:
      hours: 12

# Storage configuration
persistence:
  data:
    enabled: true
    size: 100Gi
    storageClass: ""  # Use default storage class
```

### Custom Values File

Create a custom values file for your deployment:

```bash
# Create custom values
cat > eemt-values.yaml << EOF
global:
  imageRegistry: "your-registry.com"
  eemt:
    mode: distributed

workers:
  replicaCount: 8
  resources:
    limits:
      cpu: 8
      memory: 16Gi

ingress:
  enabled: true
  className: nginx
  hosts:
    - host: eemt.your-domain.com
      paths:
        - path: /
          pathType: Prefix
EOF

# Deploy with custom values
helm install eemt helm/eemt/ -n eemt -f eemt-values.yaml
```

### Environment-Specific Deployments

#### Development Environment

```yaml
# dev-values.yaml
global:
  resourceStrategy: minimal
  
development:
  debug: true
  mockServices: true
  reducedResources: true

workers:
  replicaCount: 2
  
persistence:
  data:
    size: 20Gi
  cache:
    size: 10Gi
```

#### Production Environment

```yaml
# prod-values.yaml
global:
  resourceStrategy: performance

workers:
  autoscaling:
    enabled: true
    maxReplicas: 50
  gpu:
    enabled: true
    count: 2

persistence:
  data:
    size: 1Ti
    storageClass: fast-ssd
  
ingress:
  enabled: true
  className: nginx
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
  tls:
    - secretName: eemt-tls
      hosts:
        - eemt.production.com

monitoring:
  prometheus:
    enabled: true
```

## Deployment Scenarios

### 1. Local Development (Minikube)

```bash
# Start minikube with sufficient resources
minikube start --cpus=8 --memory=16384 --disk-size=50g

# Deploy with minimal resources
helm install eemt helm/eemt/ -n eemt \
  --set global.resourceStrategy=minimal \
  --set workers.replicaCount=1 \
  --set development.reducedResources=true
```

### 2. Cloud Provider (EKS/GKE/AKS)

```bash
# Configure cloud-specific storage class
helm install eemt helm/eemt/ -n eemt \
  --set global.storageClass=gp2 \
  --set workers.autoscaling.enabled=true \
  --set ingress.enabled=true
```

### 3. On-Premise HPC Cluster

```bash
# Deploy with specific node selection
helm install eemt helm/eemt/ -n eemt \
  --set workers.nodeSelector.node-type=compute \
  --set workers.tolerations[0].key=eemt-dedicated \
  --set workers.tolerations[0].operator=Equal \
  --set workers.tolerations[0].value=true \
  --set workers.tolerations[0].effect=NoSchedule
```

### 4. GPU-Accelerated Deployment

```bash
# Deploy with GPU support
helm install eemt helm/eemt/ -n eemt \
  --set workers.gpu.enabled=true \
  --set workers.gpu.count=2 \
  --set workers.gpu.type=nvidia.com/gpu \
  --set workers.nodeSelector.accelerator=nvidia-tesla-v100
```

## Storage Configuration

### Storage Classes

EEMT requires different storage types for different purposes:

```yaml
# High-performance storage for data processing
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: eemt-fast
provisioner: kubernetes.io/aws-ebs
parameters:
  type: io1
  iopsPerGB: "50"
  fsType: ext4
volumeBindingMode: WaitForFirstConsumer

# Cost-effective storage for logs and backups  
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: eemt-standard
provisioner: kubernetes.io/aws-ebs
parameters:
  type: gp2
  fsType: ext4
```

### Backup and Recovery

```bash
# Create backup of persistent volumes
kubectl get pvc -n eemt

# Backup data volume
kubectl exec -n eemt deployment/eemt-web -- \
  tar czf - /app/data | gzip > eemt-data-backup-$(date +%Y%m%d).tar.gz

# Backup database
kubectl exec -n eemt deployment/eemt-web -- \
  sqlite3 /app/database/jobs.db .dump | gzip > eemt-db-backup-$(date +%Y%m%d).sql.gz
```

## Monitoring and Observability

### Logging

```bash
# View application logs
kubectl logs -n eemt deployment/eemt-web -f

# View worker logs
kubectl logs -n eemt deployment/eemt-worker -f

# View cleanup job logs
kubectl logs -n eemt job/eemt-cleanup-<timestamp>

# Aggregate logs
kubectl logs -n eemt -l app.kubernetes.io/name=eemt --tail=100
```

### Metrics and Health Checks

```bash
# Check health endpoints
kubectl port-forward -n eemt service/eemt-web 5000:5000 &
curl http://localhost:5000/health

# Check resource usage
kubectl top pods -n eemt
kubectl top nodes

# View HPA status
kubectl get hpa -n eemt -w
```

### Prometheus Monitoring

If Prometheus monitoring is enabled:

```yaml
# ServiceMonitor for Prometheus Operator
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: eemt-metrics
  namespace: eemt
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: eemt
  endpoints:
  - port: metrics
    interval: 30s
    path: /metrics
```

## Security

### RBAC Configuration

The deployment creates appropriate RBAC resources:

- `eemt-service-account`: Service account for EEMT components
- `eemt-cluster-role`: Cluster-level permissions for node access
- `eemt-namespace-role`: Namespace-level permissions for resource management

### Network Policies

Optional network policies for enhanced security:

```yaml
# Allow ingress traffic only from ingress controller
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: eemt-web-ingress
  namespace: eemt
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/component: web-interface
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
    ports:
    - protocol: TCP
      port: 5000
```

### Pod Security

Pod security contexts are configured for:
- Non-root user execution
- Read-only root filesystem where possible
- Dropped capabilities
- Security context constraints

## Troubleshooting

### Common Issues

#### 1. Pod Scheduling Issues

```bash
# Check node resources
kubectl describe nodes

# Check pod events
kubectl describe pod -n eemt <pod-name>

# Check resource quotas
kubectl describe resourcequota -n eemt
```

#### 2. Storage Issues

```bash
# Check PVC status
kubectl get pvc -n eemt

# Check storage class
kubectl get storageclass

# Check volume mount issues
kubectl describe pod -n eemt <pod-name>
```

#### 3. Worker Connection Issues

```bash
# Check service discovery
kubectl get svc -n eemt
kubectl get endpoints -n eemt

# Test connectivity between pods
kubectl exec -n eemt deployment/eemt-worker -- \
  nc -zv eemt-web 9123
```

#### 4. Image Pull Issues

```bash
# Check image pull secrets
kubectl get secrets -n eemt

# Check image availability
kubectl describe pod -n eemt <pod-name>

# Manually pull image
docker pull <image-name>
```

### Debug Mode

Enable debug mode for troubleshooting:

```bash
helm upgrade eemt helm/eemt/ -n eemt \
  --set development.debug=true \
  --set monitoring.logging.level=DEBUG
```

### Support Commands

```bash
# Generate support bundle
kubectl cluster-info dump --namespaces eemt --output-directory=eemt-debug

# Export configuration
helm get values eemt -n eemt > eemt-current-values.yaml
helm get manifest eemt -n eemt > eemt-current-manifest.yaml

# Resource utilization report
kubectl top pods -n eemt --containers=true
kubectl get events -n eemt --sort-by=.metadata.creationTimestamp
```

## Upgrades and Maintenance

### Helm Chart Upgrades

```bash
# Check for updates
helm repo update

# Upgrade with new values
helm upgrade eemt helm/eemt/ -n eemt \
  --set image.webInterface.tag=2.1 \
  --set image.worker.tag=ubuntu24.04-v2.1

# Rollback if needed
helm rollback eemt -n eemt
```

### Scaling Operations

```bash
# Scale workers manually
kubectl scale deployment eemt-worker --replicas=20 -n eemt

# Update HPA settings
kubectl patch hpa eemt-worker-hpa -n eemt -p '{"spec":{"maxReplicas":50}}'

# Scale down for maintenance
kubectl scale deployment eemt-worker --replicas=0 -n eemt
```

### Maintenance Windows

For planned maintenance:

```bash
# Disable cleanup jobs
kubectl patch cronjob eemt-cleanup -n eemt -p '{"spec":{"suspend":true}}'

# Scale down workers
kubectl scale deployment eemt-worker --replicas=0 -n eemt

# Perform maintenance...

# Re-enable services
kubectl scale deployment eemt-worker --replicas=4 -n eemt
kubectl patch cronjob eemt-cleanup -n eemt -p '{"spec":{"suspend":false}}'
```

## Contributing

For contributions to the Kubernetes deployment:

1. Test changes on a development cluster
2. Update documentation for any new features
3. Ensure backward compatibility with existing deployments
4. Follow Kubernetes best practices
5. Update resource requirements if needed

## Support

For issues with Kubernetes deployment:

- Check the [troubleshooting section](#troubleshooting)
- Review logs and events
- Check cluster resource availability
- Verify configuration values
- Open an issue at https://github.com/cyverse-gis/eemt/issues