# Notes Cloud Infrastructure

Kubernetes infrastructure for the Notes Cloud platform.

## Prerequisites

Install the following tools:

| Tool | macOS | Windows |
|------|-------|---------|
| Docker | `brew install --cask docker` | [Docker Desktop](https://docs.docker.com/desktop/install/windows-install/) |
| kubectl | `brew install kubectl` | `choco install kubernetes-cli` |
| k3d | `brew install k3d` | `choco install k3d` |

## Quick Start

### macOS / Linux
```bash
./setup.sh
```

### Windows (PowerShell)
```powershell
.\setup.ps1
```

This will:
1. Create a k3d cluster called `notes-cloud-cluster`
2. Deploy PostgreSQL database
3. Run database migrations
4. Deploy all microservices

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    notes-cloud-cluster (k3d)                    │
│                                                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │auth-service │  │notes-service│  │ todo-service│             │
│  │   :8081     │  │   :8082     │  │    :8085    │             │
│  └─────────────┘  └─────────────┘  └─────────────┘             │
│                                                                 │
│  ┌──────────────┐  ┌─────────────────┐                         │
│  │sharing-service│ │reminder-service │                         │
│  │    :8083      │ │     :8084       │                         │
│  └──────────────┘  └─────────────────┘                         │
│                                                                 │
│  ┌─────────────────────────────────────┐                       │
│  │            PostgreSQL               │                       │
│  │              :5432                  │                       │
│  └─────────────────────────────────────┘                       │
└─────────────────────────────────────────────────────────────────┘
```

## Services

| Service | Port | Description |
|---------|------|-------------|
| auth-service | 8081 | Authentication and authorization |
| notes-service | 8082 | Notes management |
| sharing-service | 8083 | Note sharing functionality |
| reminder-service | 8084 | Reminders and notifications |
| todo-service | 8085 | Todo lists management |
| postgres | 5432 | PostgreSQL database |

## Common Commands

### Check cluster status
```bash
kubectl get pods -n notes-cloud
kubectl get svc -n notes-cloud
```

### Access a service locally
```bash
# Port forward to access a service
kubectl port-forward -n notes-cloud svc/auth-service 8081:8081

# Then call the service
curl http://localhost:8081/authService/api/v1/healthz
```

### View logs
```bash
kubectl logs -n notes-cloud -l app=auth-service -f
```

### Restart a deployment
```bash
kubectl rollout restart deployment auth-service -n notes-cloud
```

### Delete the cluster
```bash
k3d cluster delete notes-cloud-cluster
```

## Development Workflow

### 1. Make changes to a service

Edit your code locally.

### 2. Build and push the new image

```bash
# Login to Docker Hub (first time only)
docker login

# Build and push
docker build -t hristo12319/notes-cloud-auth-service:latest .
docker push hristo12319/notes-cloud-auth-service:latest
```

### 3. Update the cluster

```bash
kubectl rollout restart deployment auth-service -n notes-cloud
```

### 4. Verify the deployment

```bash
kubectl get pods -n notes-cloud -l app=auth-service
kubectl logs -n notes-cloud -l app=auth-service -f
```

## Docker Images

All images are hosted on Docker Hub under `hristo12319/`:

| Image | Repository |
|-------|------------|
| auth-service | `hristo12319/notes-cloud-auth-service` |
| notes-service | `hristo12319/notes-cloud-notes-service` |
| todo-service | `hristo12319/notes-cloud-todo-service` |
| sharing-service | `hristo12319/notes-cloud-sharing-service` |
| reminder-service | `hristo12319/notes-cloud-reminder-service` |
| migrations | `hristo12319/notes-cloud-migrations` |

## Troubleshooting

### Pod stuck in ImagePullBackOff
The image doesn't exist on Docker Hub. Build and push it:
```bash
docker build -t hristo12319/notes-cloud-<service>:latest .
docker push hristo12319/notes-cloud-<service>:latest
kubectl rollout restart deployment <service> -n notes-cloud
```

### Pod stuck in CrashLoopBackOff
Check the logs:
```bash
kubectl logs -n notes-cloud -l app=<service> --previous
```

### Database connection failed
Check if PostgreSQL is running:
```bash
kubectl get pods -n notes-cloud -l app=postgres
kubectl logs -n notes-cloud -l app=postgres
```

### Reset everything
```bash
k3d cluster delete notes-cloud-cluster
./setup.sh  # or .\setup.ps1 on Windows
```

## Project Structure

```
notes-cloud-infrastructure/
├── k8s/
│   ├── namespace.yaml
│   ├── postgres/
│   │   ├── postgres-config-map.yaml
│   │   ├── postgres-secrets.yaml
│   │   ├── postgres-stateful-set.yaml
│   │   ├── postgres-cluster-ip.yaml
│   │   └── postgres-headless-service.yaml
│   ├── migrations/
│   │   ├── config-map.yaml
│   │   └── job.yaml
│   ├── auth-service/
│   │   ├── auth-service-deployment.yaml
│   │   ├── auth-service-cluster-ip.yaml
│   │   ├── auth-service-config-map.yaml
│   │   └── auth-service-secret.yaml
│   ├── notes-service/
│   ├── todo-service/
│   ├── sharing-service/
│   └── reminder-service/
├── setup.sh          # Linux/macOS setup script
├── setup.ps1         # Windows setup script
└── README.md
```
