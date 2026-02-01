#!/bin/bash
#
# EEMT Kubernetes Deployment Script
#
# This script simplifies the deployment of EEMT on Kubernetes clusters
# with various configuration options and deployment modes.
#

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELM_CHART_DIR="${SCRIPT_DIR}/helm/eemt"

# Default configuration
NAMESPACE="eemt"
RELEASE_NAME="eemt"
DEPLOYMENT_MODE="distributed"
RESOURCE_STRATEGY="balanced"
VALUES_FILE=""
DRY_RUN=false
UPGRADE=false
DEBUG=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Help function
show_help() {
    cat << EOF
EEMT Kubernetes Deployment Script

Usage: $0 [OPTIONS]

Options:
    -h, --help              Show this help message
    -n, --namespace NAME    Kubernetes namespace (default: eemt)
    -r, --release NAME      Helm release name (default: eemt)
    -m, --mode MODE         Deployment mode: local|distributed|hybrid (default: distributed)
    -s, --strategy STRATEGY Resource strategy: minimal|balanced|performance (default: balanced)
    -f, --values FILE       Custom Helm values file
    -u, --upgrade           Upgrade existing deployment
    -d, --dry-run           Show what would be deployed without applying
    --debug                 Enable debug output
    --gpu                   Enable GPU support for workers
    --ingress               Enable ingress with example domain
    --dev                   Development mode (reduced resources, debug enabled)
    --cleanup-only          Deploy only the cleanup CronJob

Examples:
    # Basic deployment
    $0

    # Development deployment with minimal resources
    $0 --dev --strategy minimal

    # Production deployment with GPU support and ingress
    $0 --mode distributed --strategy performance --gpu --ingress

    # Upgrade existing deployment with custom values
    $0 --upgrade --values prod-values.yaml

    # Dry run to see what would be deployed
    $0 --dry-run --values custom-values.yaml

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -r|--release)
            RELEASE_NAME="$2"
            shift 2
            ;;
        -m|--mode)
            DEPLOYMENT_MODE="$2"
            shift 2
            ;;
        -s|--strategy)
            RESOURCE_STRATEGY="$2"
            shift 2
            ;;
        -f|--values)
            VALUES_FILE="$2"
            shift 2
            ;;
        -u|--upgrade)
            UPGRADE=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        --debug)
            DEBUG=true
            shift
            ;;
        --gpu)
            GPU_ENABLED=true
            shift
            ;;
        --ingress)
            INGRESS_ENABLED=true
            shift
            ;;
        --dev)
            DEVELOPMENT_MODE=true
            RESOURCE_STRATEGY="minimal"
            DEBUG=true
            shift
            ;;
        --cleanup-only)
            CLEANUP_ONLY=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validation functions
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is required but not installed"
        exit 1
    fi
    
    # Check helm
    if ! command -v helm &> /dev/null; then
        log_error "helm is required but not installed"
        exit 1
    fi
    
    # Check cluster connectivity
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    # Check Helm chart exists
    if [[ ! -f "${HELM_CHART_DIR}/Chart.yaml" ]]; then
        log_error "Helm chart not found at ${HELM_CHART_DIR}"
        exit 1
    fi
    
    log_success "Prerequisites validated"
}

# Check cluster resources
check_cluster_resources() {
    log_info "Checking cluster resources..."
    
    # Get available resources
    local cpu_available
    local memory_available
    
    cpu_available=$(kubectl top nodes --no-headers | awk '{sum+=$3} END {print sum}' 2>/dev/null || echo "unknown")
    memory_available=$(kubectl top nodes --no-headers | awk '{sum+=$5} END {print sum}' 2>/dev/null || echo "unknown")
    
    if [[ "$cpu_available" != "unknown" ]]; then
        log_info "Available CPU: ${cpu_available} cores"
        log_info "Available Memory: ${memory_available}"
    else
        log_warning "Could not determine available cluster resources"
    fi
    
    # Check storage classes
    local storage_classes
    storage_classes=$(kubectl get storageclass --no-headers 2>/dev/null | wc -l || echo "0")
    
    if [[ "$storage_classes" -eq 0 ]]; then
        log_warning "No storage classes found - persistent storage may not work"
    else
        log_info "Found ${storage_classes} storage class(es)"
    fi
}

# Generate Helm values
generate_helm_values() {
    local values_content=""
    
    # Base configuration
    values_content+="global:\n"
    values_content+="  eemt:\n"
    values_content+="    mode: ${DEPLOYMENT_MODE}\n"
    values_content+="  resourceStrategy: ${RESOURCE_STRATEGY}\n\n"
    
    # GPU configuration
    if [[ "${GPU_ENABLED:-false}" == "true" ]]; then
        values_content+="workers:\n"
        values_content+="  gpu:\n"
        values_content+="    enabled: true\n"
        values_content+="    count: 1\n\n"
    fi
    
    # Ingress configuration
    if [[ "${INGRESS_ENABLED:-false}" == "true" ]]; then
        values_content+="ingress:\n"
        values_content+="  enabled: true\n"
        values_content+="  className: nginx\n"
        values_content+="  hosts:\n"
        values_content+="    - host: eemt.example.com\n"
        values_content+="      paths:\n"
        values_content+="        - path: /\n"
        values_content+="          pathType: Prefix\n\n"
    fi
    
    # Development mode
    if [[ "${DEVELOPMENT_MODE:-false}" == "true" ]]; then
        values_content+="development:\n"
        values_content+="  debug: true\n"
        values_content+="  mockServices: true\n"
        values_content+="  reducedResources: true\n\n"
        
        values_content+="workers:\n"
        values_content+="  replicaCount: 2\n"
        values_content+="  autoscaling:\n"
        values_content+="    enabled: false\n\n"
        
        values_content+="persistence:\n"
        values_content+="  data:\n"
        values_content+="    size: 20Gi\n"
        values_content+="  cache:\n"
        values_content+="    size: 10Gi\n"
        values_content+="  logs:\n"
        values_content+="    size: 5Gi\n\n"
    fi
    
    # Debug mode
    if [[ "$DEBUG" == "true" ]]; then
        values_content+="monitoring:\n"
        values_content+="  logging:\n"
        values_content+="    level: DEBUG\n\n"
    fi
    
    echo -e "$values_content"
}

# Create namespace if it doesn't exist
create_namespace() {
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        log_info "Creating namespace: $NAMESPACE"
        
        if [[ "$DRY_RUN" == "false" ]]; then
            kubectl apply -f "${SCRIPT_DIR}/manifests/namespace.yaml"
            kubectl apply -f "${SCRIPT_DIR}/manifests/rbac.yaml"
        else
            log_info "[DRY RUN] Would create namespace and RBAC resources"
        fi
    else
        log_info "Namespace $NAMESPACE already exists"
    fi
}

# Deploy with Helm
deploy_helm() {
    local helm_command="install"
    local helm_args=()
    
    if [[ "$UPGRADE" == "true" ]]; then
        helm_command="upgrade"
        helm_args+=("--install")
    fi
    
    # Add common arguments
    helm_args+=("$RELEASE_NAME" "$HELM_CHART_DIR")
    helm_args+=("--namespace" "$NAMESPACE")
    
    if [[ "$DRY_RUN" == "true" ]]; then
        helm_args+=("--dry-run")
    fi
    
    if [[ "$DEBUG" == "true" ]]; then
        helm_args+=("--debug")
    fi
    
    # Add values file if specified
    if [[ -n "$VALUES_FILE" ]]; then
        if [[ -f "$VALUES_FILE" ]]; then
            helm_args+=("--values" "$VALUES_FILE")
        else
            log_error "Values file not found: $VALUES_FILE"
            exit 1
        fi
    fi
    
    # Generate and use dynamic values
    local temp_values_file
    temp_values_file=$(mktemp)
    generate_helm_values > "$temp_values_file"
    helm_args+=("--values" "$temp_values_file")
    
    # Deploy specific components
    if [[ "${CLEANUP_ONLY:-false}" == "true" ]]; then
        helm_args+=("--set" "webInterface.enabled=false")
        helm_args+=("--set" "workers.enabled=false")
    fi
    
    log_info "Deploying EEMT with Helm..."
    log_info "Command: helm $helm_command ${helm_args[*]}"
    
    if helm "$helm_command" "${helm_args[@]}"; then
        log_success "Helm deployment completed successfully"
    else
        log_error "Helm deployment failed"
        rm -f "$temp_values_file"
        exit 1
    fi
    
    # Cleanup temporary file
    rm -f "$temp_values_file"
}

# Wait for deployment
wait_for_deployment() {
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    log_info "Waiting for deployment to be ready..."
    
    # Wait for web interface if enabled
    if [[ "${CLEANUP_ONLY:-false}" != "true" ]]; then
        if kubectl wait --for=condition=available deployment/"${RELEASE_NAME}-web" \
           --namespace="$NAMESPACE" --timeout=300s; then
            log_success "Web interface is ready"
        else
            log_error "Web interface failed to become ready"
            return 1
        fi
        
        # Wait for workers if enabled
        if kubectl wait --for=condition=available deployment/"${RELEASE_NAME}-worker" \
           --namespace="$NAMESPACE" --timeout=300s; then
            log_success "Workers are ready"
        else
            log_warning "Workers failed to become ready (this may be normal if no work is available)"
        fi
    fi
    
    log_success "Deployment is ready!"
}

# Show deployment status
show_status() {
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    log_info "Deployment Status:"
    echo
    
    # Show pods
    echo "Pods:"
    kubectl get pods -n "$NAMESPACE" -o wide
    echo
    
    # Show services
    echo "Services:"
    kubectl get services -n "$NAMESPACE"
    echo
    
    # Show ingress if enabled
    if kubectl get ingress -n "$NAMESPACE" &> /dev/null; then
        echo "Ingress:"
        kubectl get ingress -n "$NAMESPACE"
        echo
    fi
    
    # Show HPA if enabled
    if kubectl get hpa -n "$NAMESPACE" &> /dev/null; then
        echo "Horizontal Pod Autoscaler:"
        kubectl get hpa -n "$NAMESPACE"
        echo
    fi
    
    # Show CronJobs
    if kubectl get cronjobs -n "$NAMESPACE" &> /dev/null; then
        echo "CronJobs:"
        kubectl get cronjobs -n "$NAMESPACE"
        echo
    fi
    
    # Show access information
    echo "Access Information:"
    echo "  Web Interface:"
    echo "    kubectl port-forward -n $NAMESPACE service/${RELEASE_NAME}-web 5000:5000"
    echo "    Then open: http://localhost:5000"
    echo
    
    if [[ "${INGRESS_ENABLED:-false}" == "true" ]]; then
        echo "  External Access (if ingress is configured):"
        echo "    http://eemt.example.com"
        echo
    fi
}

# Main execution
main() {
    log_info "Starting EEMT Kubernetes deployment"
    log_info "Configuration:"
    log_info "  Namespace: $NAMESPACE"
    log_info "  Release: $RELEASE_NAME"
    log_info "  Mode: $DEPLOYMENT_MODE"
    log_info "  Strategy: $RESOURCE_STRATEGY"
    log_info "  Dry Run: $DRY_RUN"
    log_info "  Upgrade: $UPGRADE"
    echo
    
    validate_prerequisites
    check_cluster_resources
    create_namespace
    deploy_helm
    
    if [[ "$DRY_RUN" == "false" ]]; then
        wait_for_deployment
        show_status
        
        log_success "EEMT deployment completed successfully!"
        echo
        log_info "Next steps:"
        log_info "1. Access the web interface using the information above"
        log_info "2. Upload a DEM file and submit a job"
        log_info "3. Monitor job progress and results"
        log_info "4. Check logs with: kubectl logs -n $NAMESPACE -f deployment/${RELEASE_NAME}-web"
    else
        log_info "Dry run completed. No resources were created."
    fi
}

# Execute main function
main "$@"