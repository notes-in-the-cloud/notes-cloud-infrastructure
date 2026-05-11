# setup.ps1 - Windows PowerShell setup script for notes-cloud infrastructure
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$K8sDir = Join-Path $ScriptDir "k8s"

$ClusterName = "notes-cloud-cluster"
$Namespace = "notes-cloud"
$ApiPort = "6550"

function Write-Info {
    param($Message)
    Write-Host "[INFO] $Message" -ForegroundColor Green
}

function Write-Warn {
    param($Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Write-Err {
    param($Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Invoke-Checked {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Command,

        [Parameter(Mandatory = $true)]
        [string]$ErrorMessage
    )

    & $Command

    if ($LASTEXITCODE -ne 0) {
        Write-Err $ErrorMessage
        exit 1
    }
}

# Check prerequisites
function Test-Prerequisites {
    Write-Info "Checking prerequisites..."

    $commands = @("docker", "kubectl", "k3d")

    foreach ($cmd in $commands) {
        if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
            Write-Err "$cmd is not installed or is not available in PATH"
            exit 1
        }
    }

    Invoke-Checked {
        docker info *> $null
    } "Docker is not running. Please start Docker Desktop and try again."

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

        Invoke-Checked {
            k3d cluster create $ClusterName `
                --agents 2 `
                --api-port "127.0.0.1:$ApiPort" `
                --wait `
                --timeout 120s
        } "Failed to create k3d cluster '$ClusterName'"
    }

    Invoke-Checked {
        kubectl config use-context "k3d-$ClusterName"
    } "Failed to switch kubectl context to k3d-$ClusterName"

    Write-Info "Checking Kubernetes API connection..."

    Invoke-Checked {
        kubectl cluster-info
    } "kubectl cannot connect to the Kubernetes API server. Try deleting the cluster with: k3d cluster delete $ClusterName"
}

# Apply Kubernetes manifests in order
function Install-Manifests {
    Write-Info "Applying Kubernetes manifests..."

    # 1. Namespace first
    Write-Info "Creating namespace..."

    Invoke-Checked {
        kubectl apply -f (Join-Path $K8sDir "namespace.yaml")
    } "Failed to apply namespace manifest"

    # 2. Postgres
    Write-Info "Deploying Postgres..."

    Invoke-Checked {
        kubectl apply -f (Join-Path $K8sDir "postgres")
    } "Failed to deploy Postgres manifests"

    # 3. Wait for Postgres to be ready
    Write-Info "Waiting for Postgres to be ready..."

    kubectl wait --for=condition=ready pod -l app=postgres -n $Namespace --timeout=300s

    if ($LASTEXITCODE -ne 0) {
        Write-Warn "Postgres may not be ready yet. Check with: kubectl get pods -n $Namespace"
    }

    # 4. Run migrations
    $migrationsPath = Join-Path $K8sDir "migrations"

    if (Test-Path $migrationsPath) {
        Write-Info "Running migrations..."

        Invoke-Checked {
            kubectl apply -f $migrationsPath
        } "Failed to apply migration manifests"
    } else {
        Write-Warn "Migrations folder not found. Skipping migrations."
    }

    # 5. Deploy shared resources (JWT config/secret used by multiple services)
    $sharedPath = Join-Path $K8sDir "shared"

    if (Test-Path $sharedPath) {
        Write-Info "Deploying shared resources..."

        Invoke-Checked {
            kubectl apply -f $sharedPath
        } "Failed to deploy shared resources"
    }

    # 6. Deploy services
    $services = @(
        "auth-service",
        "reminder-service",
        "todo-service",
        "sharing-service",
        "notes-service",
        "api-gateway"
    )

    foreach ($service in $services) {
        $servicePath = Join-Path $K8sDir $service

        if (Test-Path $servicePath) {
            Write-Info "Deploying $service..."

            Invoke-Checked {
                kubectl apply -f $servicePath
            } "Failed to deploy $service"
        } else {
            Write-Warn "Folder for $service not found. Skipping."
        }
    }
}

# Wait for all deployments to be ready
function Wait-Deployments {
    Write-Info "Waiting for deployments to be ready..."

    kubectl wait --for=condition=available deployment --all -n $Namespace --timeout=180s

    if ($LASTEXITCODE -ne 0) {
        Write-Warn "Some deployments may not be ready. Check with: kubectl get pods -n $Namespace"
    }
}

# Show status
function Show-Status {
    Write-Host ""
    Write-Info "=== Cluster Status ==="
    Write-Host ""

    kubectl get pods -n $Namespace
    Write-Host ""

    kubectl get svc -n $Namespace
    Write-Host ""

    Write-Info "To access a service, run:"
    Write-Host "  kubectl port-forward -n $Namespace svc/<service-name> <local-port>:<service-port>"
    Write-Host ""
    Write-Info "Example:"
    Write-Host "  kubectl port-forward -n $Namespace svc/auth-service 8080:8080"
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

Main