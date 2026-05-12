# Notes Cloud Infrastructure

Kubernetes infrastructure for the Notes Cloud platform — a microservices-based note-taking application with authentication, todos, sharing, and reminders.

## Prerequisites

| Tool | macOS | Windows |
|------|-------|---------|
| Docker | `brew install --cask docker` | [Docker Desktop](https://docs.docker.com/desktop/install/windows-install/) |
| kubectl | `brew install kubectl` | `choco install kubernetes-cli` |
| k3d | `brew install k3d` | `choco install k3d` |

Ensure Docker is running before proceeding.

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
4. Deploy shared resources (JWT config)
5. Deploy all microservices
6. Deploy the API Gateway and Frontend

Once complete, open your browser:
- **Frontend**: http://localhost:8080
- **API Gateway**: http://localhost:8090

## Architecture

```
                          ┌──────────────────┐
                          │     Frontend     │
                          │  (React/Nginx)   │
                          │  localhost:8080  │
                          └────────┬─────────┘
                                   │
                          ┌────────▼─────────┐
                          │   API Gateway    │
                          │  (Go/Chi Router) │
                          │  localhost:8090  │
                          └────────┬─────────┘
                                   │
        ┌──────────────────────────┼──────────────────────────┐
        │                          │                          │
┌───────▼───────┐  ┌───────────────▼───────────────┐  ┌───────▼───────┐
│ auth-service  │  │       notes-service           │  │ todo-service  │
│    :8081      │  │          :8082                │  │    :8085      │
└───────────────┘  └───────────────────────────────┘  └───────────────┘
                                   │
        ┌──────────────────────────┼──────────────────────────┐
        │                          │                          │
┌───────▼───────┐  ┌───────────────▼───────────────┐          │
│sharing-service│  │     reminder-service          │          │
│    :8083      │  │     :8084 (+ WebSocket)       │          │
└───────────────┘  └───────────────────────────────┘          │
                                                              │
                          ┌───────────────────────────────────▼──┐
                          │             PostgreSQL               │
                          │               :5432                  │
                          └──────────────────────────────────────┘
```

## Services

| Service | Internal Port | External Access | Description |
|---------|---------------|-----------------|-------------|
| frontend | 8080 | http://localhost:8080 | React SPA served by Nginx |
| api-gateway | 8090 | http://localhost:8090 | Routes requests, handles CORS, JWT validation |
| auth-service | 8081 | Via gateway only | User registration, login, JWT tokens |
| notes-service | 8082 | Via gateway only | Notes CRUD operations |
| sharing-service | 8083 | Via gateway only | Note sharing between users |
| reminder-service | 8084 | Via gateway only | Reminders with WebSocket push |
| todo-service | 8085 | Via gateway only | Todo lists management |
| postgres | 5432 | Via port-forward only | PostgreSQL database |

## API Endpoints

All API calls go through the gateway at `http://localhost:8090`:

```
POST   /api/v1/auth/register     - Register a new user
POST   /api/v1/auth/login        - Login, returns JWT
POST   /api/v1/auth/refresh      - Refresh JWT token

GET    /api/v1/notes             - List user's notes
POST   /api/v1/notes             - Create a note
GET    /api/v1/notes/:id         - Get a note
PUT    /api/v1/notes/:id         - Update a note
DELETE /api/v1/notes/:id         - Delete a note

GET    /api/v1/todos             - List user's todos
POST   /api/v1/todos             - Create a todo
PUT    /api/v1/todos/:id         - Update a todo
DELETE /api/v1/todos/:id         - Delete a todo

POST   /api/v1/share             - Share a note with another user
GET    /api/v1/share/:noteId     - Get sharing info for a note

GET    /api/v1/reminders         - List user's reminders
POST   /api/v1/reminders         - Create a reminder
DELETE /api/v1/reminders/:id     - Delete a reminder

WS     /ws                        - WebSocket for real-time reminder notifications
```

## Local Development

### Running with Local Frontend (Hot Reload)

If you're developing the frontend locally and want hot reload:

1. Start the infrastructure (backend services only):
   ```bash
   ./setup.sh
   ```

2. In your frontend project, configure the API URL:
   ```javascript
   // Point to the k8s API gateway
   const API_BASE_URL = "http://localhost:8090/api/v1";
   ```

3. Run your frontend dev server (Vite, Create React App, etc.):
   ```bash
   npm run dev
   ```

The API gateway is configured to accept requests from common dev server origins:
- `http://localhost:3000` (Create React App)
- `http://localhost:5173` (Vite dev)
- `http://localhost:4173` (Vite preview)

### Running with Local Backend Service

To test changes to a backend service without pushing to Docker Hub:

1. Build the image locally:
   ```bash
   docker build -t hristo12319/notes-cloud-auth-service:latest .
   ```

2. Import the image into k3d:
   ```bash
   k3d image import hristo12319/notes-cloud-auth-service:latest -c notes-cloud-cluster
   ```

3. Restart the deployment:
   ```bash
   kubectl rollout restart deployment auth-service -n notes-cloud
   ```

### Accessing the Database

```bash
# Port-forward to PostgreSQL
kubectl port-forward -n notes-cloud svc/postgres 5432:5432

# Connect with psql (password: localdevpassword)
psql -h localhost -p 5432 -U notesuser -d notesdb
```

### Viewing Logs

```bash
# All pods
kubectl logs -n notes-cloud -l app.kubernetes.io/part-of=notes-cloud-platform -f

# Specific service
kubectl logs -n notes-cloud -l app=auth-service -f

# Previous crash logs
kubectl logs -n notes-cloud -l app=auth-service --previous
```

## Common Commands

```bash
# Check cluster status
kubectl get pods -n notes-cloud
kubectl get svc -n notes-cloud

# Restart a service after code change
kubectl rollout restart deployment auth-service -n notes-cloud

# Watch pods in real-time
kubectl get pods -n notes-cloud -w

# Describe a failing pod
kubectl describe pod -n notes-cloud -l app=auth-service

# Delete and recreate the cluster
k3d cluster delete notes-cloud-cluster
./setup.sh
```

## Docker Images

All images are hosted on Docker Hub under `hristo12319/`:

| Image | Repository |
|-------|------------|
| frontend | `hristo12319/notes-cloud-frontend` |
| api-gateway | `hristo12319/notes-cloud-api-gateway` |
| auth-service | `hristo12319/notes-cloud-auth-service` |
| notes-service | `hristo12319/notes-cloud-notes-service` |
| todo-service | `hristo12319/notes-cloud-todo-service` |
| sharing-service | `hristo12319/notes-cloud-sharing-service` |
| reminder-service | `hristo12319/notes-cloud-reminder-service` |
| migrations | `hristo12319/notes-cloud-migrations` |

### Publishing a New Image

```bash
# Login to Docker Hub (first time only)
docker login

# Build, tag, and push
docker build -t hristo12319/notes-cloud-auth-service:v2 .
docker push hristo12319/notes-cloud-auth-service:v2

# Update the deployment to use the new tag
kubectl set image deployment/auth-service \
  auth-service=hristo12319/notes-cloud-auth-service:v2 \
  -n notes-cloud
```

## Configuration

### JWT Settings

JWT configuration is shared across services via ConfigMap and Secret in `k8s/shared/`:

| Setting | Value | Description |
|---------|-------|-------------|
| JWT_ISSUER | notes-cloud | Token issuer claim |
| JWT_AUDIENCE | notes-cloud | Token audience claim |
| JWT_TTL | 15m | Token expiration |
| JWT_SECRET | (in secret) | Signing key |

### API Gateway Routing

The gateway routes requests to internal services. Configuration is in `k8s/api-gateway/api-gateway-config-map.yaml`:

```yaml
AUTH_SERVICE_URL: "http://auth-service:8081"
NOTES_SERVICE_URL: "http://notes-service:8082"
TODO_SERVICE_URL: "http://todo-service:8085"
REMINDER_SERVICE_URL: "http://reminder-service:8084"
SHARING_SERVICE_URL: "http://sharing-service:8083"
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| **Pod stuck in ImagePullBackOff** | Image doesn't exist. Build and push it, or use `k3d image import` for local images |
| **Pod stuck in CrashLoopBackOff** | Check logs: `kubectl logs -n notes-cloud -l app=<service> --previous` |
| **Database connection failed** | Ensure postgres pod is running: `kubectl get pods -n notes-cloud -l app=postgres` |
| **CORS errors in browser** | Add your dev server origin to `ALLOWED_ORIGINS` in api-gateway-config-map.yaml |
| **WebSocket not connecting** | Ensure you're connecting to `ws://localhost:8090/ws` (not 8080) |
| **Port 8080/8090 already in use** | Stop existing processes: `lsof -ti :8080 | xargs kill` |
| **k3d cluster won't start** | Ensure Docker is running. Try: `docker info` |
| **Changes not reflected** | Restart the deployment: `kubectl rollout restart deployment <name> -n notes-cloud` |

### Reset Everything

```bash
k3d cluster delete notes-cloud-cluster
./setup.sh  # or .\setup.ps1 on Windows
```

## Project Structure

```
notes-cloud-infrastructure/
├── k8s/
│   ├── namespace.yaml           # notes-cloud namespace
│   ├── shared/                  # JWT config shared across services
│   │   ├── jwt-config.yaml
│   │   ├── jwt-secret.yaml
│   │   └── internal-token-secret.yaml
│   ├── postgres/                # Database
│   │   ├── postgres-stateful-set.yaml
│   │   ├── postgres-config-map.yaml
│   │   ├── postgres-secrets.yaml
│   │   ├── postgres-cluster-ip.yaml
│   │   └── postgres-headless-service.yaml
│   ├── migrations/              # DB schema migrations job
│   │   ├── job.yaml
│   │   └── config-map.yaml
│   ├── api-gateway/             # API Gateway (external entry point)
│   │   ├── api-gateway-deployment.yaml
│   │   ├── api-gateway-config-map.yaml
│   │   └── api-gateway-node-port.yaml
│   ├── frontend/                # React frontend
│   │   ├── frontend-deployment.yaml
│   │   ├── frontend-config-map.yaml
│   │   └── frontend-node-port.yaml
│   ├── auth-service/            # Authentication service
│   ├── notes-service/           # Notes CRUD service
│   ├── todo-service/            # Todo lists service
│   ├── sharing-service/         # Note sharing service
│   └── reminder-service/        # Reminders + WebSocket
├── setup.sh                     # Linux/macOS setup script
├── setup.ps1                    # Windows setup script
└── README.md
```
