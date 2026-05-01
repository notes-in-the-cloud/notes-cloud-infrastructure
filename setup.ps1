# setup.ps1 - Windows PowerShell setup script for notes-cloud infrastructure
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$K8sDir = Join-Path $ScriptDir "k8s"
$ClusterName = "notes-cloud-cluster"

function Write-Info { param($Message) Write-Host "[INFO] $Message" -ForegroundColor Green }
function Write-Warn { param($Message) Write-Host "[WARN] $Message" -ForegroundColor Yellow }
function Write-Err { param($Message) Write-Host "[ERROR] $Message" -ForegroundColor Red }

# Check prerequisites
function Test-Prerequisites {
    Write-Info "Checking prerequisites..."

    $commands = @("kubectl", "k3d")
    foreach ($cmd in $commands) {
        if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
            Write-Err "$cmd is not installed"
            exit 1
        }
    }

    Write-Info "All prerequisites met"
}

# Create cluster if it doesn't exist
function New-Cluster {
    $clusters = k3d cluster list -o json | ConvertFrom-Json
    $exists = $clusters | Where-Object { $_.name -eq $ClusterName }

    if ($exists) {
        Write-Info "Cluster '$ClusterName' already exists"
    } else {
        Write-Info "Creating k3d cluster '$ClusterName'..."
        k3d cluster create $ClusterName --agents 2
    }

    kubectl config use-context "k3d-$ClusterName"
}

# Apply Kubernetes manifests in order
function Install-Manifests {
    Write-Info "Applying Kubernetes manifests..."

    # 1. Namespace first
    Write-Info "Creating namespace..."
    kubectl apply -f (Join-Path $K8sDir "namespace.yaml")

    # 2. Postgres (database must be ready before services)
    Write-Info "Deploying Postgres..."
    kubectl apply -f (Join-Path $K8sDir "postgres")

    # 3. Wait for Postgres to be ready
    Write-Info "Waiting for Postgres to be ready..."
    kubectl wait --for=condition=ready pod -l app=postgres -n notes-cloud --timeout=120s 2>$null
    if (-not $?) { Write-Warn "Postgres may not be ready yet" }

    # 4. Run migrations
    Write-Info "Running migrations..."
    kubectl apply -f (Join-Path $K8sDir "migrations")

    # 5. Deploy services
    $services = @("auth-service", "reminder-service", "todo-service", "sharing-service")
    foreach ($service in $services) {
        $servicePath = Join-Path $K8sDir $service
        if (Test-Path $servicePath) {
            Write-Info "Deploying $service..."
            kubectl apply -f $servicePath
        }
    }
}

# Wait for all deployments to be ready
function Wait-Deployments {
    Write-Info "Waiting for deployments to be ready..."

    kubectl wait --for=condition=available deployment --all -n notes-cloud --timeout=180s 2>$null
    if (-not $?) {
        Write-Warn "Some deployments may not be ready. Check with: kubectl get pods -n notes-cloud"
    }
}

# Show status
function Show-Status {
    Write-Host ""
    Write-Info "=== Cluster Status ==="
    Write-Host ""
    kubectl get pods -n notes-cloud
    Write-Host ""
    kubectl get svc -n notes-cloud
    Write-Host ""
    Write-Info "To access a service, run:"
    Write-Host "  kubectl port-forward -n notes-cloud svc/<service-name> <local-port>:<service-port>"
}

# Main
function Main {
    Write-Info "Setting up notes-cloud infrastructure..."

    Test-Prerequisites
    New-Cluster
    Install-Manifests
    Wait-Deployments
    Show-Status

    Write-Info "Setup complete!"
}

# Run
Main
