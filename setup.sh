#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="$SCRIPT_DIR/k8s"
CLUSTER_NAME="notes-cloud-cluster"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    for cmd in kubectl k3d; do
        if ! command -v $cmd &> /dev/null; then
            log_error "$cmd is not installed"
            exit 1
        fi
    done

    log_info "All prerequisites met"
}

# Create cluster if it doesn't exist
create_cluster() {
    if k3d cluster list | grep -q "$CLUSTER_NAME"; then
        log_info "Cluster '$CLUSTER_NAME' already exists"
    else
        log_info "Creating k3d cluster '$CLUSTER_NAME'..."
        k3d cluster create "$CLUSTER_NAME" --agents 2
    fi

    kubectl config use-context "k3d-$CLUSTER_NAME"
}

# Apply Kubernetes manifests in order
apply_manifests() {
    log_info "Applying Kubernetes manifests..."

    # 1. Namespace first
    log_info "Creating namespace..."
    kubectl apply -f "$K8S_DIR/namespace.yaml"

    # 2. Postgres (database must be ready before services)
    log_info "Deploying Postgres..."
    kubectl apply -f "$K8S_DIR/postgres/"

    # 3. Wait for Postgres to be ready
    log_info "Waiting for Postgres to be ready..."
    kubectl wait --for=condition=ready pod -l app=postgres -n notes-cloud --timeout=300s || true

    # 4. Run migrations
    log_info "Running migrations..."
    kubectl apply -f "$K8S_DIR/migrations/"

    # 5. Deploy shared resources (JWT config/secret used by multiple services)
    if [ -d "$K8S_DIR/shared" ]; then
        log_info "Deploying shared resources..."
        kubectl apply -f "$K8S_DIR/shared/"
    fi

    # 6. Deploy services
    for service in auth-service reminder-service todo-service sharing-service notes-service api-gateway frontend; do
        if [ -d "$K8S_DIR/$service" ]; then
            log_info "Deploying $service..."
            kubectl apply -f "$K8S_DIR/$service/"
        fi
    done
}

# Wait for all deployments to be ready
wait_for_deployments() {
    log_info "Waiting for deployments to be ready..."

    kubectl wait --for=condition=available deployment --all -n notes-cloud --timeout=180s || {
        log_warn "Some deployments may not be ready. Check with: kubectl get pods -n notes-cloud"
    }
}

# Show status
show_status() {
    echo ""
    log_info "=== Cluster Status ==="
    echo ""
    kubectl get pods -n notes-cloud
    echo ""
    kubectl get svc -n notes-cloud
    echo ""
    log_info "To access a service, run:"
    echo "  kubectl port-forward -n notes-cloud svc/<service-name> <local-port>:<service-port>"
}

# Main
main() {
    log_info "Setting up notes-cloud infrastructure..."

    check_prerequisites
    create_cluster
    apply_manifests
    wait_for_deployments
    show_status

    log