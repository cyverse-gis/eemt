#!/bin/bash
#
# EEMT Kubernetes Cleanup Script
#
# This script removes EEMT deployment from Kubernetes clusters
# with options for selective cleanup.
#

set -euo pipefail

# Default configuration
NAMESPACE="eemt"
RELEASE_NAME="eemt"
FORCE=false
KEEP_NAMESPACE=false
KEEP_DATA=false
DRY_RUN=false

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
EEMT Kubernetes Cleanup Script

Usage: $0 [OPTIONS]

Options:
    -h, --help              Show this help message
    -n, --namespace NAME    Kubernetes namespace (default: eemt)
    -r, --release NAME      Helm release name (default: eemt)
    -f, --force             Force cleanup without confirmation
    --keep-namespace        Don't delete the namespace
    --keep-data             Don't delete persistent volumes and data
    --dry-run               Show what would be deleted without removing
    --all                   Remove everything including namespace and data

Examples:
    # Interactive cleanup (will ask for confirmation)
    $0

    # Force cleanup of specific release
    $0 --force --release my-eemt-release

    # Cleanup but preserve data
    $0 --keep-data

    # See what would be deleted
    $0 --dry-run

    # Complete removal including all data
    $0 --all --force

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
        -f|--force)
            FORCE=true
            shift
            ;;
        --keep-namespace)
            KEEP_NAMESPACE=true
            shift
            ;;
        --keep-data)
            KEEP_DATA=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --all)
            KEEP_NAMESPACE=false
            KEEP_DATA=false
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Confirmation function
confirm_cleanup() {
    if [[ "$FORCE" == "true" || "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    echo
    log_warning "This will remove the following:"
    echo "  - Helm release: $RELEASE_NAME"
    echo "  - Namespace: $NAMESPACE (unless --keep-namespace)"
    
    if [[ "$KEEP_DATA" == "false" ]]; then
        echo "  - All persistent volumes and data"
        echo "  - Job results, databases, logs, and uploads"
    else
        echo "  - Persistent volumes and data will be PRESERVED"
    fi
    
    echo
    read -p "Are you sure you want to continue? [y/N] " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Cleanup cancelled"
        exit 0
    fi
}

# Check prerequisites
check_prerequisites() {
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
    
    # Check if namespace exists
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        log_warning "Namespace $NAMESPACE does not exist"
        return 1
    fi
    
    return 0
}

# Get deployment info
show_deployment_info() {
    log_info "Current EEMT deployment in namespace '$NAMESPACE':"
    echo
    
    # Show Helm releases
    echo "Helm Releases:"
    helm list -n "$NAMESPACE" 2>/dev/null || echo "  No Helm releases found"
    echo
    
    # Show pods
    echo "Pods:"
    kubectl get pods -n "$NAMESPACE" 2>/dev/null || echo "  No pods found"
    echo
    
    # Show services
    echo "Services:"
    kubectl get services -n "$NAMESPACE" 2>/dev/null || echo "  No services found"
    echo
    
    # Show persistent volumes
    echo "Persistent Volume Claims:"
    kubectl get pvc -n "$NAMESPACE" 2>/dev/null || echo "  No PVCs found"
    echo
    
    # Show configmaps and secrets
    echo "ConfigMaps and Secrets:"
    kubectl get configmaps,secrets -n "$NAMESPACE" 2>/dev/null || echo "  No configmaps/secrets found"
    echo
    
    # Show CronJobs
    echo "CronJobs:"
    kubectl get cronjobs -n "$NAMESPACE" 2>/dev/null || echo "  No CronJobs found"
    echo
}

# Remove Helm release
remove_helm_release() {
    log_info "Removing Helm release '$RELEASE_NAME'..."
    
    if helm list -n "$NAMESPACE" | grep -q "$RELEASE_NAME"; then
        if [[ "$DRY_RUN" == "false" ]]; then
            if helm uninstall "$RELEASE_NAME" -n "$NAMESPACE"; then
                log_success "Helm release removed successfully"
            else
                log_error "Failed to remove Helm release"
                return 1
            fi
        else
            log_info "[DRY RUN] Would remove Helm release: $RELEASE_NAME"
        fi
    else
        log_warning "Helm release '$RELEASE_NAME' not found in namespace '$NAMESPACE'"
    fi
}

# Remove persistent volumes
remove_persistent_volumes() {
    if [[ "$KEEP_DATA" == "true" ]]; then
        log_info "Keeping persistent volumes and data as requested"
        return 0
    fi
    
    log_info "Removing persistent volume claims..."
    
    local pvcs
    pvcs=$(kubectl get pvc -n "$NAMESPACE" --no-headers 2>/dev/null | awk '{print $1}' || true)
    
    if [[ -n "$pvcs" ]]; then
        for pvc in $pvcs; do
            log_info "Removing PVC: $pvc"
            if [[ "$DRY_RUN" == "false" ]]; then
                kubectl delete pvc "$pvc" -n "$NAMESPACE" || log_warning "Failed to delete PVC: $pvc"
            else
                log_info "[DRY RUN] Would remove PVC: $pvc"
            fi
        done
        
        if [[ "$DRY_RUN" == "false" ]]; then
            log_success "Persistent volume claims removed"
        fi
    else
        log_info "No persistent volume claims found"
    fi
}

# Remove remaining resources
remove_remaining_resources() {
    log_info "Removing any remaining EEMT resources..."
    
    # Remove deployments
    local deployments
    deployments=$(kubectl get deployments -n "$NAMESPACE" -l "app.kubernetes.io/name=eemt" --no-headers 2>/dev/null | awk '{print $1}' || true)
    
    for deployment in $deployments; do
        log_info "Removing deployment: $deployment"
        if [[ "$DRY_RUN" == "false" ]]; then
            kubectl delete deployment "$deployment" -n "$NAMESPACE" || log_warning "Failed to delete deployment: $deployment"
        else
            log_info "[DRY RUN] Would remove deployment: $deployment"
        fi
    done
    
    # Remove services
    local services
    services=$(kubectl get services -n "$NAMESPACE" -l "app.kubernetes.io/name=eemt" --no-headers 2>/dev/null | awk '{print $1}' || true)
    
    for service in $services; do
        log_info "Removing service: $service"
        if [[ "$DRY_RUN" == "false" ]]; then
            kubectl delete service "$service" -n "$NAMESPACE" || log_warning "Failed to delete service: $service"
        else
            log_info "[DRY RUN] Would remove service: $service"
        fi
    done
    
    # Remove configmaps
    local configmaps
    configmaps=$(kubectl get configmaps -n "$NAMESPACE" -l "app.kubernetes.io/name=eemt" --no-headers 2>/dev/null | awk '{print $1}' || true)
    
    for configmap in $configmaps; do
        log_info "Removing configmap: $configmap"
        if [[ "$DRY_RUN" == "false" ]]; then
            kubectl delete configmap "$configmap" -n "$NAMESPACE" || log_warning "Failed to delete configmap: $configmap"
        else
            log_info "[DRY RUN] Would remove configmap: $configmap"
        fi
    done
    
    # Remove secrets (be careful with this)
    local secrets
    secrets=$(kubectl get secrets -n "$NAMESPACE" -l "app.kubernetes.io/name=eemt" --no-headers 2>/dev/null | awk '{print $1}' || true)
    
    for secret in $secrets; do
        log_info "Removing secret: $secret"
        if [[ "$DRY_RUN" == "false" ]]; then
            kubectl delete secret "$secret" -n "$NAMESPACE" || log_warning "Failed to delete secret: $secret"
        else
            log_info "[DRY RUN] Would remove secret: $secret"
        fi
    done
    
    # Remove CronJobs
    local cronjobs
    cronjobs=$(kubectl get cronjobs -n "$NAMESPACE" -l "app.kubernetes.io/name=eemt" --no-headers 2>/dev/null | awk '{print $1}' || true)
    
    for cronjob in $cronjobs; do
        log_info "Removing cronjob: $cronjob"
        if [[ "$DRY_RUN" == "false" ]]; then
            kubectl delete cronjob "$cronjob" -n "$NAMESPACE" || log_warning "Failed to delete cronjob: $cronjob"
        else
            log_info "[DRY RUN] Would remove cronjob: $cronjob"
        fi
    done
    
    # Remove HPA
    local hpas
    hpas=$(kubectl get hpa -n "$NAMESPACE" -l "app.kubernetes.io/name=eemt" --no-headers 2>/dev/null | awk '{print $1}' || true)
    
    for hpa in $hpas; do
        log_info "Removing HPA: $hpa"
        if [[ "$DRY_RUN" == "false" ]]; then
            kubectl delete hpa "$hpa" -n "$NAMESPACE" || log_warning "Failed to delete HPA: $hpa"
        else
            log_info "[DRY RUN] Would remove HPA: $hpa"
        fi
    done
}

# Remove namespace
remove_namespace() {
    if [[ "$KEEP_NAMESPACE" == "true" ]]; then
        log_info "Keeping namespace '$NAMESPACE' as requested"
        return 0
    fi
    
    log_info "Removing namespace '$NAMESPACE'..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        if kubectl delete namespace "$NAMESPACE"; then
            log_success "Namespace removed successfully"
        else
            log_error "Failed to remove namespace"
            return 1
        fi
    else
        log_info "[DRY RUN] Would remove namespace: $NAMESPACE"
    fi
}

# Cleanup cluster-wide resources
cleanup_cluster_resources() {
    log_info "Cleaning up cluster-wide EEMT resources..."
    
    # Remove cluster roles and bindings
    local cluster_roles
    cluster_roles=$(kubectl get clusterroles -l "app.kubernetes.io/name=eemt" --no-headers 2>/dev/null | awk '{print $1}' || true)
    
    for role in $cluster_roles; do
        log_info "Removing cluster role: $role"
        if [[ "$DRY_RUN" == "false" ]]; then
            kubectl delete clusterrole "$role" || log_warning "Failed to delete cluster role: $role"
        else
            log_info "[DRY RUN] Would remove cluster role: $role"
        fi
    done
    
    local cluster_role_bindings
    cluster_role_bindings=$(kubectl get clusterrolebindings -l "app.kubernetes.io/name=eemt" --no-headers 2>/dev/null | awk '{print $1}' || true)
    
    for binding in $cluster_role_bindings; do
        log_info "Removing cluster role binding: $binding"
        if [[ "$DRY_RUN" == "false" ]]; then
            kubectl delete clusterrolebinding "$binding" || log_warning "Failed to delete cluster role binding: $binding"
        else
            log_info "[DRY RUN] Would remove cluster role binding: $binding"
        fi
    done
}

# Main cleanup function
main() {
    log_info "Starting EEMT Kubernetes cleanup"
    log_info "Configuration:"
    log_info "  Namespace: $NAMESPACE"
    log_info "  Release: $RELEASE_NAME"
    log_info "  Keep namespace: $KEEP_NAMESPACE"
    log_info "  Keep data: $KEEP_DATA"
    log_info "  Dry run: $DRY_RUN"
    log_info "  Force: $FORCE"
    echo
    
    # Check prerequisites
    if ! check_prerequisites; then
        log_error "Prerequisites check failed"
        exit 1
    fi
    
    # Show current deployment
    show_deployment_info
    
    # Confirm cleanup
    confirm_cleanup
    
    echo
    log_info "Starting cleanup process..."
    
    # Remove Helm release
    remove_helm_release
    
    # Remove persistent volumes
    remove_persistent_volumes
    
    # Remove any remaining resources
    remove_remaining_resources
    
    # Cleanup cluster-wide resources
    cleanup_cluster_resources
    
    # Remove namespace
    remove_namespace
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log_success "EEMT cleanup completed successfully!"
        echo
        log_info "All EEMT resources have been removed from the cluster"
        
        if [[ "$KEEP_DATA" == "true" ]]; then
            log_warning "Note: Persistent data has been preserved and may incur storage costs"
        fi
    else
        log_info "Dry run completed. No resources were actually removed."
        echo
        log_info "To perform the actual cleanup, run the same command without --dry-run"
    fi
}

# Execute main function
main "$@"