# EEMT Kubernetes Deployment Complete

This document provides a comprehensive overview of the EEMT Kubernetes deployment infrastructure that has been implemented.

## Deployment Overview

The EEMT (Effective Energy and Mass Transfer) Algorithm Suite now includes a complete Kubernetes deployment solution with:

- **Production-ready Helm charts**
- **Auto-scaling worker nodes** 
- **Automated job data cleanup**
- **Persistent storage management**
- **Comprehensive monitoring and logging**
- **Multi-environment support**

## Directory Structure

```
docker/kubernetes/
├── manifests/                          # Raw Kubernetes YAML files
│   ├── namespace.yaml                   # Namespace, quotas, limits
│   ├── rbac.yaml                        # Service accounts and permissions
│   └── cleanup-cronjob.yaml             # Standalone cleanup job
├── helm/                                # Helm chart
│   └── eemt/                           
│       ├── Chart.yaml                   # Chart metadata and dependencies
│       ├── values.yaml                  # Configurable deployment values
│       └── templates/                   # Kubernetes resource templates
│           ├── _helpers.tpl             # Template helper functions
│           ├── web-interface-deployment.yaml     # FastAPI web service
│           ├── web-interface-service.yaml        # Service for web interface
│           ├── worker-deployment.yaml            # Distributed worker nodes
│           ├── worker-hpa.yaml                   # Auto-scaling configuration
│           ├── persistentvolumes.yaml           # Storage definitions
│           ├── configmap.yaml                   # Application configuration
│           ├── serviceaccount.yaml              # Service account creation
│           ├── ingress.yaml                     # External access rules
│           └── cleanup-cronjob.yaml             # Automated data cleanup
├── deploy.sh                           # Automated deployment script
├── cleanup.sh                          # Cleanup and removal script
├── kubeconfig-example.yaml             # Example cluster connection config
└── README.md                           # Comprehensive documentation
```

## Generated Resources

When deployed, the Helm chart creates the following Kubernetes resources:

| Resource Type | Count | Purpose |
|---------------|-------|---------|
| **Deployments** | 2 | Web interface + Worker nodes |
| **Services** | 1 | Web interface network access |
| **ConfigMaps** | 2 | Application configuration + Cleanup settings |
| **PersistentVolumeClaims** | 4 | Data, Database, Cache, Logs storage |
| **ServiceAccount** | 1 | Pod permissions and RBAC |
| **HorizontalPodAutoscaler** | 1 | Auto-scaling for workers |
| **CronJob** | 1 | Automated job data cleanup |

## Key Features Implemented

### 1. **Scalable Architecture**
- **Web Interface**: Single FastAPI pod handling job submission and monitoring
- **Worker Nodes**: Auto-scaling compute pods (2-20 replicas) for geospatial processing
- **Load Balancing**: Automatic distribution of work across available workers
- **Resource Management**: CPU/memory limits and requests for optimal cluster utilization

### 2. **Storage Management**
```yaml
persistence:
  data:     100Gi  # Job uploads and results
  database:  10Gi  # SQLite job metadata
  cache:     50Gi  # Intermediate processing files
  logs:      20Gi  # Application and cleanup logs
```

### 3. **Automated Cleanup System**
- **CronJob Schedule**: Daily at 2 AM UTC
- **Retention Policies**: 
  - Successful jobs: 7 days (data cleanup, preserve config)
  - Failed jobs: 12 hours (complete deletion)
- **Configurable**: Environment variables and Helm values
- **Monitoring**: Comprehensive logging and job history

### 4. **Multi-Environment Support**

#### Development Environment
```bash
./deploy.sh --dev --strategy minimal
```
- Reduced resource requirements
- Debug logging enabled
- Mock external services
- Single worker node

#### Production Environment  
```bash
./deploy.sh --strategy performance --gpu --ingress
```
- High-performance resources
- GPU acceleration support
- External access via ingress
- Auto-scaling up to 20+ workers

#### Custom Deployment
```bash
./deploy.sh --values custom-values.yaml --upgrade
```
- Organization-specific configuration
- Custom resource limits
- Environment-specific settings

## Quick Start Commands

### 1. **Basic Deployment**
```bash
# Clone repository
git clone https://github.com/cyverse-gis/eemt.git
cd eemt/docker/kubernetes

# Deploy with defaults (distributed mode, balanced resources)
./deploy.sh

# Access web interface
kubectl port-forward -n eemt service/eemt-web 5000:5000
# Open: http://localhost:5000
```

### 2. **Development Setup**
```bash
# Minimal resources for development
./deploy.sh --dev --namespace eemt-dev

# Check status
kubectl get pods -n eemt-dev
kubectl logs -n eemt-dev deployment/eemt-web -f
```

### 3. **Production Deployment**
```bash
# High-performance with GPU support
./deploy.sh --strategy performance --gpu --ingress \
  --values prod-values.yaml --namespace eemt-prod

# Scale workers manually if needed
kubectl scale deployment eemt-worker --replicas=30 -n eemt-prod
```

### 4. **Cloud Provider Deployments**

#### AWS EKS
```bash
# Configure kubectl for EKS
aws eks update-kubeconfig --region us-west-2 --name eemt-cluster

# Deploy with EBS storage
./deploy.sh --values aws-values.yaml
```

#### Google GKE
```bash
# Configure kubectl for GKE
gcloud container clusters get-credentials eemt-cluster --zone us-central1-a

# Deploy with persistent disks
./deploy.sh --values gke-values.yaml
```

#### Azure AKS
```bash
# Configure kubectl for AKS
az aks get-credentials --resource-group eemt-rg --name eemt-cluster

# Deploy with managed disks
./deploy.sh --values azure-values.yaml
```

## Configuration Options

### Resource Strategies

| Strategy | Web Interface | Worker Nodes | Use Case |
|----------|---------------|--------------|----------|
| **minimal** | 500m CPU, 1Gi RAM | 2 cores, 4Gi RAM | Development, testing |
| **balanced** | 1 CPU, 2Gi RAM | 4 cores, 8Gi RAM | General production |
| **performance** | 2 CPU, 4Gi RAM | 8 cores, 16Gi RAM | High-performance computing |

### Auto-scaling Configuration
```yaml
workers:
  autoscaling:
    enabled: true
    minReplicas: 2
    maxReplicas: 20
    targetCPUUtilizationPercentage: 70
    targetMemoryUtilizationPercentage: 80
```

### GPU Support
```yaml
workers:
  gpu:
    enabled: true
    count: 2
    type: "nvidia.com/gpu"
  nodeSelector:
    accelerator: nvidia-tesla-v100
```

### Storage Customization
```yaml
persistence:
  data:
    storageClass: "fast-ssd"
    size: 1Ti
    accessMode: ReadWriteMany
  database:
    storageClass: "standard"
    size: 50Gi
```

## Monitoring and Operations

### Health Monitoring
```bash
# Check deployment status
kubectl get pods,svc,pvc -n eemt

# Monitor resource usage
kubectl top pods -n eemt
kubectl top nodes

# View application logs
kubectl logs -n eemt deployment/eemt-web -f
kubectl logs -n eemt deployment/eemt-worker -f
```

### Cleanup Operations
```bash
# Check cleanup job status
kubectl get cronjobs -n eemt
kubectl get jobs -n eemt

# View cleanup logs
kubectl logs -n eemt job/eemt-cleanup-$(date +%Y%m%d)

# Manual cleanup
kubectl create job --from=cronjob/eemt-cleanup manual-cleanup -n eemt
```

### Scaling Operations
```bash
# Manual scaling
kubectl scale deployment eemt-worker --replicas=15 -n eemt

# Check auto-scaler status  
kubectl get hpa -n eemt -w

# View scaling events
kubectl get events -n eemt --field-selector reason=SuccessfulCreate
```

## Security Features

### RBAC Configuration
- **Service Account**: `eemt-service-account` with minimal required permissions
- **Cluster Role**: Node access for worker scheduling
- **Namespace Role**: Full access within EEMT namespace only
- **Pod Security**: Non-root containers, dropped capabilities, read-only root filesystem

### Network Security
```yaml
# Optional network policies
networkPolicy:
  enabled: true
  ingress:
    - from:
      - namespaceSelector:
          matchLabels:
            name: ingress-nginx
```

### Data Security
- **Persistent Volume Encryption**: Supported via storage class configuration
- **Secret Management**: External secret injection support
- **Image Security**: Non-root containers, minimal attack surface

## Backup and Recovery

### Data Backup
```bash
# Backup persistent volumes
kubectl exec -n eemt deployment/eemt-web -- \
  tar czf - /app/data | gzip > eemt-data-backup-$(date +%Y%m%d).tar.gz

# Backup database
kubectl exec -n eemt deployment/eemt-web -- \
  sqlite3 /app/database/jobs.db .dump | gzip > eemt-db-backup-$(date +%Y%m%d).sql.gz
```

### Disaster Recovery
```bash
# Export configuration
helm get values eemt -n eemt > eemt-values-backup.yaml
helm get manifest eemt -n eemt > eemt-manifest-backup.yaml

# Restore from backup
helm install eemt-restored helm/eemt/ -n eemt-restored -f eemt-values-backup.yaml
```

## Troubleshooting Guide

### Common Issues and Solutions

#### 1. **Pod Scheduling Problems**
```bash
# Check node resources
kubectl describe nodes
kubectl get events -n eemt --sort-by=.metadata.creationTimestamp

# Solution: Adjust resource requests or add nodes
kubectl patch deployment eemt-worker -n eemt -p '{"spec":{"template":{"spec":{"containers":[{"name":"worker","resources":{"requests":{"cpu":"1"}}}]}}}}'
```

#### 2. **Storage Issues**
```bash
# Check PVC status
kubectl get pvc -n eemt
kubectl describe pvc eemt-data -n eemt

# Solution: Verify storage class and node capacity
kubectl get storageclass
kubectl describe nodes | grep -A 5 "Allocated resources"
```

#### 3. **Worker Connection Issues**
```bash
# Test service connectivity
kubectl exec -n eemt deployment/eemt-worker -- nc -zv eemt-web 9123

# Solution: Check service endpoints and network policies
kubectl get endpoints -n eemt
kubectl describe service eemt-web -n eemt
```

### Debug Mode
```bash
# Enable debug logging
./deploy.sh --upgrade --debug --values debug-values.yaml

# Check detailed pod information
kubectl describe pod -n eemt <pod-name>
kubectl logs -n eemt <pod-name> --previous
```

## Upgrade and Maintenance

### Helm Chart Updates
```bash
# Upgrade deployment
./deploy.sh --upgrade --values current-values.yaml

# Rollback if needed
helm rollback eemt -n eemt

# View release history
helm history eemt -n eemt
```

### Node Maintenance
```bash
# Drain node for maintenance
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data

# Scale down workers temporarily
kubectl scale deployment eemt-worker --replicas=0 -n eemt

# Resume operations
kubectl uncordon <node-name>
kubectl scale deployment eemt-worker --replicas=4 -n eemt
```

## Performance Optimization

### Resource Tuning
- **CPU Requests**: Set to 80% of typical usage
- **Memory Requests**: Set to 90% of typical usage  
- **CPU Limits**: 2-3x requests for burst capacity
- **Memory Limits**: 1.5x requests to prevent OOM

### Storage Optimization
- **Fast Storage**: Use SSD storage classes for data processing
- **Network Storage**: Use ReadWriteMany for shared data
- **Local Storage**: Use local SSDs for temporary worker files

### Network Optimization
- **Node Affinity**: Place workers on compute-optimized nodes
- **Pod Anti-affinity**: Spread workers across nodes
- **Service Mesh**: Consider Istio for advanced traffic management

## Cost Optimization

### Resource Management
```yaml
# Use resource quotas
resources:
  requests:
    cpu: "50"      # 50 cores total
    memory: "200Gi" # 200GB RAM total
  limits:
    cpu: "100"     # Burst to 100 cores
    memory: "400Gi" # Max 400GB RAM
```

### Auto-scaling Policies
```yaml
# Aggressive scale-down for cost savings
behavior:
  scaleDown:
    stabilizationWindowSeconds: 60
    policies:
    - type: Percent
      value: 50  # Scale down 50% every minute
```

### Spot Instances
```yaml
# Use spot/preemptible instances for workers
nodeSelector:
  kubernetes.io/os: linux
  node-lifecycle: spot
tolerations:
- key: "spot-instance"
  operator: "Equal"
  value: "true"
  effect: "NoSchedule"
```

## Production Deployment Checklist

- [ ] Kubernetes cluster configured (1.18+)
- [ ] Storage classes configured for persistent volumes
- [ ] RBAC enabled and service accounts configured  
- [ ] Monitoring solution deployed (Prometheus/Grafana)
- [ ] Log aggregation configured (ELK/Fluent)
- [ ] Backup strategy implemented
- [ ] Ingress controller configured
- [ ] SSL/TLS certificates configured
- [ ] Network policies defined (if required)
- [ ] Resource quotas and limits configured
- [ ] Auto-scaling policies tuned
- [ ] Alerting rules configured
- [ ] Disaster recovery plan tested

## Support and Contributing

### Getting Help
1. **Documentation**: Check the comprehensive README.md
2. **Logs**: Use kubectl logs and describe commands
3. **Community**: Open issues at https://github.com/cyverse-gis/eemt/issues
4. **Monitoring**: Check Prometheus metrics if enabled

### Contributing
1. **Test Changes**: Use --dry-run for validation
2. **Update Documentation**: Keep README.md current
3. **Follow Conventions**: Use Kubernetes best practices
4. **Validate**: Ensure Helm chart passes lint tests

### Useful Commands Reference
```bash
# Quick deployment
./deploy.sh --dev

# Production deployment
./deploy.sh --strategy performance --gpu --ingress

# Cleanup deployment
./cleanup.sh --keep-data

# Monitor resources
kubectl top pods -n eemt
kubectl get hpa -n eemt -w

# Debug issues
kubectl describe pod -n eemt <pod-name>
kubectl logs -n eemt deployment/eemt-web -f

# Backup configuration
helm get values eemt -n eemt > backup-values.yaml
```

The EEMT Kubernetes deployment provides a robust, scalable, and production-ready platform for geospatial modeling and distributed computing workloads.