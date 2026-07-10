# Platform Engineering POC — Report & Walkthrough

## 1. Overview

This POC validates a **platform engineering workflow** on a local Kubernetes cluster (kind). A developer pushes code to GitHub and the platform automates everything from build to production-like delivery — fully observable across Backstage, Argo CD, and Tekton dashboards.

### Platform Stack

| Layer | Component | Role |
|-------|-----------|------|
| **CI** | Tekton Pipelines + Triggers | GitHub webhook → clone → test → build → push to GHCR |
| **Registry** | GitHub Container Registry (GHCR) | OCI image storage |
| **CD / GitOps** | Argo CD | Syncs Helm charts from Git to cluster, auto-healing |
| **Provisioning** | Crossplane (provider-helm) | Composes AppService abstractions into Helm Releases |
| **Gateway** | Envoy Gateway | Exposes services via HTTPRoute |
| **Developer Portal** | Backstage | Catalog, Kubernetes plugin, Software Templates for self-service |
| **Runtime** | Kubernetes (kind) | Runs everything — platform control plane + application workloads |

The entire flow is **Git-driven**: code push triggers CI, CI publishes the image, CI updates the GitOps repo, Argo CD syncs the new desired state, Crossplane reconciles the Helm Release, and Kubernetes rolls out the new Pod — with no manual `kubectl` or `docker` commands.

---

## 2. Architecture

```
┌──────────┐    Webhook     ┌───────────────┐
│  GitHub  │ ──────────────→│ Tekton         │
│  (Push)  │                │ EventListener  │
└──────────┘                └───────┬───────┘
                                    │ PipelineRun
                                    ▼
┌──────────────────────────────────────────────────────┐
│                 Tekton Pipeline                       │
│                                                       │
│  clone ──→ pytest ──→ BuildKit build ──→ push GHCR    │
│                                              │        │
│                                              ▼        │
│                              update GitOps values.yaml│
│                              commit & push [skip ci]  │
└──────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌──────────┐    Sync (30s)   ┌───────────────┐
│  Argo CD │ ←────────────── │ GitHub (GitOps │
│          │                 │  chart path)   │
└────┬─────┘                 └───────────────┘
     │ AppService Helm chart
     ▼
┌────────────────┐
│  Crossplane    │
│  provider-helm │
└──────┬─────────┘
       │ Helm Release
       ▼
┌─────────────────────────────────────────┐
│          Kubernetes (kind)              │
│                                         │
│  Namespace: demo                        │
│  ├── Deployment  (fastapi-demo)         │
│  ├── Service     (fastapi-demo)         │
│  └── HTTPRoute   (fastapi-demo)         │
│                   │                     │
│                   ▼                     │
│           Envoy Gateway                 │
│           → http://<host>/              │
└─────────────────────────────────────────┘
       │
       │ backstage.io/kubernetes-id label
       ▼
┌────────────────┐
│   Backstage    │
│   Catalog +    │
│   Kubernetes   │
│   Plugin       │
└────────────────┘
```

### Control Plane vs Application Plane

| Plane | Namespaces | What Runs |
|-------|-----------|-----------|
| **Control Plane** | `crossplane-system`, `argocd`, `tekton-pipelines`, `ci`, `backstage`, `envoy-gateway-system` | Platform components |
| **Application** | `demo` (per service) | FastAPI workloads, Deployments, Services |

Control plane components are **themselves managed by Crossplane** (Argo CD, Backstage), proving the platform can self-host.

---

## 3. CI/CD End-to-End Flow

### The Complete Chain

```
GitHub Push
  → GitHub Webhook
  → Tekton EventListener (ci/el-fastapi-demo-ci-listener)
  → PipelineRun triggers:
      1. clone          — git clone the repo at the pushed commit
      2. pytest         — run tests in python:3.12-slim
      3. BuildKit build — rootless OCI build, no Docker daemon required
      4. push GHCR      — ghcr.io/re1lya/fastapi-demo:<commit-sha>
      5. update GitOps  — edit charts/fastapi-demo-appservice/values.yaml
                          commit & push with [skip ci]
  → Argo CD detects drift, syncs the chart (30s polling)
  → Crossplane reconciles the AppService claim into a Helm Release
  → provider-helm deploys the runtime chart (Deployment, Service)
  → Envoy Gateway routes external traffic via HTTPRoute
  → Backstage shows the service in Catalog with live Kubernetes resource status
```

### Proven PipelineRun

The pipeline has completed successfully end-to-end:

```
PipelineRun: fastapi-demo-ci-krh4q
Image:        ghcr.io/re1lya/fastapi-demo:1ddefb7862e41ac2646e08c9bd8190248abfd373
Status:       Succeeded
```

Each step is observable:
- **Tekton Dashboard** — pipeline logs, task durations, commit SHA
- **Argo CD UI** — sync status, diff view, application health
- **Backstage** — Catalog entry with Kubernetes resource panel

---

## 4. Developer Experience

### Self-Service Onboarding via Backstage

A developer wants to deploy a new FastAPI service. They open the Backstage **Create** page and fill in the **"Register Existing FastAPI Service"** template:

| Parameter | Example |
|-----------|---------|
| Service Name | `fastapi-demo` |
| Owner | `platform-team` |
| Source Repo URL | `https://github.com/Re1lya/Markdown.git` |
| Context Dir | `apps/fastapi-demo` |
| Image Repository | `ghcr.io/re1lya/fastapi-demo` |
| Runtime Namespace | `demo` |
| App Port | `8000` |
| Replicas | `1` |

### What Happens Next — Fully Automated

The template **opens a GitHub Pull Request** that adds everything needed to onboard the service:

```
gitops/appservices/<serviceName>/        ← AppService Helm chart (deployment config)
gitops/argocd/<serviceName>-appservice.yaml  ← Argo CD Application
gitops/tekton/<serviceName>-ci.yaml         ← Tekton EventListener + Pipeline
catalog/services/<serviceName>/catalog-info.yaml  ← Backstage Component registration
```

### After the PR is Merged

The platform's **app-of-apps** Argo CD applications (one for `argocd`, one for `tekton`) pick up the new files automatically:

```
platform-appservices Argo CD app
  → syncs gitops/argocd
  → creates the service-specific Argo CD Application
  → syncs the AppService Helm chart
  → Crossplane provisions the AppService
  → provider-helm deploys runtime resources into demo namespace

platform-ci Argo CD app
  → syncs gitops/tekton
  → creates the service-specific Tekton EventListener + Pipeline
  → ready to receive GitHub webhooks for the new service
```

### What the Developer Does NOT Do

- ❌ No `docker build` / `docker push`
- ❌ No `kubectl apply`
- ❌ No `helm install`
- ❌ No CI config writing (Pipeline YAML is generated)
- ❌ No GitOps config writing (Helm chart + Application YAML are generated)
- ❌ No secret management for GHCR or Git auth

The developer only: **fills a form in Backstage → reviews the PR → merges it**. Everything else is automated.

---

## 5. Before vs After

| Step | Traditional | Platform (This POC) |
|------|-------------|---------------------|
| **Scaffold CI** | Write GitHub Actions / Jenkinsfile manually | Backstage template generates Tekton Pipeline |
| **Docker build** | `docker build && docker push` from local | Tekton runs rootless BuildKit in-cluster, pushes to GHCR |
| **Update manifest** | Edit YAML by hand, `kubectl apply` | CI commits to GitOps repo; Argo CD detects and syncs |
| **Deploy** | Manual `helm upgrade` or `kubectl set image` | Argo CD auto-sync → Crossplane reconciles Helm Release |
| **Expose** | Manual Ingress/Service YAML | Envoy Gateway HTTPRoute, auto-generated via Crossplane |
| **Register in catalog** | Manually write `catalog-info.yaml` | Template generates it in the PR |
| **Observability** | `kubectl logs`, `kubectl get pods` | Argo CD UI (sync/health), Backstage Kubernetes plugin, Tekton Dashboard |

### Key Automation Points

1. **Build** — Push triggers Tekton; rootless BuildKit builds and pushes the image. No local Docker needed.
2. **GitOps Sync** — CI commits the new image tag to the GitOps values file. Argo CD picks it up within 30 seconds.
3. **Provisioning** — Crossplane turns a high-level `AppService` claim into a concrete Helm Release. No raw Helm commands.
4. **Rolling Update** — Kubernetes performs a standard rolling update when Crossplane changes the Deployment image tag.

---

## 6. Verification

### FastAPI Demo — Deployment Success Page

Open the FastAPI service root path to see the deployment confirmation page:

```
http://localhost:30080/
```

The page shows:
- **HTTP 200 OK** badge (green)
- Service name, environment, version
- Full pipeline visualization: GitHub → Tekton CI → GHCR → Argo CD → Kubernetes → Gateway

This page is self-contained (no external CSS/JS) and serves as a live proof that the service is deployed and publicly reachable.

### Check End-to-End State

```bash
# Argo CD application status
kubectl get application fastapi-demo-appservice -n argocd

# Crossplane claim status
kubectl get appservice fastapi-demo -n default

# Helm Release status
kubectl get releases.helm.m.crossplane.io -n default

# Runtime resources
kubectl get deploy,pod,svc -n demo -l backstage.io/kubernetes-id=fastapi-demo
```

Expected output:

```
Argo CD:    Synced / Healthy
AppService: SYNCED=True  READY=True
Release:    SYNCED=True  READY=True  STATE=deployed
Deployment: 1/1
Pod:        Running
```

### Backstage

```bash
kubectl port-forward svc/backstage -n backstage 7007:7007
# Open http://localhost:7007
```

The FastAPI Demo component shows:
- Catalog entry with metadata
- Kubernetes plugin panel listing Deployments, Pods, Services
- Live status from the cluster

### Argo CD

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:80
# Open http://localhost:8080
```

The `fastapi-demo-appservice` Application shows the sync graph and resource tree.

### Health Check

```bash
curl http://localhost:30080/health
# → {"status": "ok"}
```

---

## Appendix: Key Repository Paths

| Path | Description |
|------|-------------|
| `apps/fastapi-demo/` | FastAPI service source + Dockerfile |
| `charts/fastapi-demo-appservice/` | Crossplane AppService Helm chart (deployment config) |
| `gitops/argocd/` | Argo CD Application manifests (per service) |
| `gitops/tekton/` | Tekton Pipeline + EventListener manifests (per service) |
| `manifests/crossplane/` | Crossplane Provider + Composition definitions |
| `manifests/tekton/` | Shared Tekton Task definitions (clone, test, build-push, update-gitops) |
| `catalog/services/` | Backstage catalog-info.yaml per service |
| `apps/backstage-custom/` | Customized Backstage image with Software Templates |
