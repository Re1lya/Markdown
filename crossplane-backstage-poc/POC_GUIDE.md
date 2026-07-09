# POC Guide

This guide describes the intended execution path for the local Crossplane + Backstage POC.

Commands are written for a local workstation with `kind`, `kubectl`, and `helm` available.

## 1. Create kind Multi-Node Cluster

The cluster config is already created at:

```text
D:/Markdown/crossplane-backstage-poc/configs/kind-platform-poc.yaml
```

Content:

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: platform-poc
nodes:
  - role: control-plane
  - role: worker
  - role: worker
```

Create the cluster:

```powershell
kind create cluster --config D:\Markdown\crossplane-backstage-poc\configs\kind-platform-poc.yaml
kubectl cluster-info --context kind-platform-poc
kubectl get nodes
```

Expected result:

```text
platform-poc-control-plane
platform-poc-worker
platform-poc-worker2
```

## 2. Install Crossplane

```bash
helm repo add crossplane-stable https://charts.crossplane.io/stable
helm repo update

helm install crossplane crossplane-stable/crossplane \
  --namespace crossplane-system \
  --create-namespace

kubectl get pods -n crossplane-system
```

## 3. Install Provider for Helm-Based App Delivery

The platformized POC uses:

```text
provider-helm
```

This lets Crossplane create Helm `Release` resources. Each `Release` installs an application Helm Chart into the cluster.

The desired chain is:

```text
AppService Claim
  -> Crossplane Composition
  -> provider-helm Release
  -> HelloWorld Helm Chart
  -> Deployment / Service
  -> Backstage label matching
```

Install provider-helm:

```powershell
kubectl apply -f D:\Markdown\crossplane-backstage-poc\manifests\crossplane\provider-helm.yaml
kubectl get providers.pkg.crossplane.io
kubectl get pods -n crossplane-system
```

Create ProviderConfig:

```powershell
kubectl apply -f D:\Markdown\crossplane-backstage-poc\manifests\crossplane\provider-config-helm.yaml
kubectl get providerconfigs.helm.crossplane.io
```

Grant local POC permissions to the provider ServiceAccount:

```powershell
$HelmProviderSA = kubectl get pod -n crossplane-system `
  -l pkg.crossplane.io/provider=provider-helm `
  -o jsonpath="{.items[0].spec.serviceAccountName}"

kubectl create clusterrolebinding provider-helm-admin `
  --clusterrole=cluster-admin `
  --serviceaccount=crossplane-system:$HelmProviderSA
```

This broad permission is acceptable for the local POC only. A production setup should grant only the exact verbs and resource types required by the Helm releases.

Note:

`provider-kubernetes` is already installed in this environment. It can stay installed, but the main app delivery POC should now use `provider-helm`.

## 4. Deploy Backstage

There are two possible paths:

### Option A: Direct Helm Install

This is faster and easier for first validation.

### Option B: Crossplane-Managed Helm Release

This better proves that Crossplane can manage platform components.

Recommended for this POC: Option B, unless it blocks progress.

## 5. Configure Backstage Kubernetes Plugin

Backstage must be configured to know about the local Kubernetes cluster.

The service entity should use:

```yaml
metadata:
  annotations:
    backstage.io/kubernetes-id: helloworld
```

The Kubernetes resources should use:

```yaml
metadata:
  labels:
    backstage.io/kubernetes-id: helloworld
```

## 6. Create HelloWorld Helm Chart and Composition

Create an application abstraction such as:

```yaml
apiVersion: platform.example.com/v1alpha1
kind: AppService
metadata:
  name: helloworld
spec:
  namespace: demo
  image: hashicorp/http-echo
  port: 5678
```

The Helm Chart should create:

- Namespace: `demo`
- Deployment: `helloworld`
- Service: `helloworld`

All resources should carry labels that Backstage can match.

The Composition should create a Helm `Release` pointing to that chart.

## 7. Register Backstage Catalog Entity

Create or register:

```yaml
apiVersion: backstage.io/v1alpha1
kind: Component
metadata:
  name: helloworld
  annotations:
    backstage.io/kubernetes-id: helloworld
spec:
  type: service
  lifecycle: experimental
  owner: platform-team
```

## 8. Verify

Cluster:

```bash
kubectl get nodes
kubectl get pods -n crossplane-system
kubectl get pods -n backstage
kubectl get pods -n demo
kubectl get svc -n demo
```

HelloWorld:

```bash
kubectl port-forward svc/helloworld -n demo 8080:80
curl http://localhost:8080
```

Backstage:

```bash
kubectl port-forward svc/backstage -n backstage 7007:7007
```

Open:

```text
http://localhost:7007
```

Expected outcome:

- Backstage opens.
- HelloWorld appears as a Catalog component.
- The HelloWorld component page shows related Kubernetes resources.
- The HelloWorld service responds locally.
## Argo CD CD Layer

Argo CD is installed as a Crossplane-managed Helm Release:

```powershell
kubectl get releases.helm.m.crossplane.io argocd -n default
kubectl get pods -n argocd
```

The first Argo CD application is:

```powershell
kubectl get applications.argoproj.io helloworld-appservice -n argocd
```

It syncs the `helloworld-appservice` chart from the in-cluster Helm repo:

```text
http://helm-repo.platform-system.svc.cluster.local
```

That chart renders the platform-level Crossplane claim:

```text
kind: AppService
name: helloworld
namespace: default
```

The control flow is:

```text
Argo CD Application
  -> helloworld-appservice Helm chart
  -> Crossplane AppService
  -> provider-helm Release
  -> demo/helloworld Deployment, Pod, Service
  -> Backstage Kubernetes page
```

Open Argo CD UI:

```powershell
kubectl port-forward svc/argocd-server -n argocd 8080:80
```

Then browse:

```text
http://localhost:8080
```

Login:

```text
username: admin
```

Get password:

```powershell
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | %{ [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_)) }
```

## Tekton GitHub Webhook Smoke

Tekton Pipelines and Triggers are installed.

Check control plane:

```powershell
kubectl get pods -n tekton-pipelines
kubectl get pods -n tekton-pipelines-resolvers
```

Check the GitHub webhook EventListener:

```powershell
kubectl get eventlistener,svc,deploy,pod -n ci
```

The EventListener service is:

```text
ci/el-github-listener:8080
```

For local GitHub webhook testing, expose it through localhost:

```powershell
kubectl port-forward svc/el-github-listener -n ci 8081:8080
```

Then expose localhost to GitHub with cloudflared:

```powershell
cloudflared tunnel --url http://localhost:8081
```

Or run the helper script:

```powershell
powershell -ExecutionPolicy Bypass -File ./scripts/start-github-webhook-tunnel.ps1
```

Quick tunnel reminder:

```text
The https://*.trycloudflare.com URL is temporary.
If the PowerShell window is closed or the machine restarts, run the script again and update the GitHub webhook Payload URL.
```

GitHub webhook page:

```text
https://github.com/Re1lya/Markdown/settings/hooks
```

If `cloudflared` is not installed:

```powershell
winget install --id Cloudflare.cloudflared
```

In GitHub repository settings, create a webhook:

```text
Payload URL: https://<cloudflared-generated-name>.trycloudflare.com
Content type: application/json
Secret: platform-poc-webhook-secret
Events: Just the push event
Active: checked
```

After pushing to GitHub, verify Tekton received the webhook:

```powershell
kubectl get pipelinerun -n ci
kubectl get taskrun -n ci
kubectl logs -n ci -l tekton.dev/pipelineRun=<pipelinerun-name> --all-containers=true
```

The current smoke Pipeline only proves webhook delivery. The next step is to replace it with a real CI pipeline that builds and pushes an image to GHCR, then updates the GitOps desired state for Argo CD.

## FastAPI Demo CI/CD Target

The POC now includes a small FastAPI service:

```text
apps/fastapi-demo
```

Run local tests:

```powershell
cd D:\Markdown\crossplane-backstage-poc\apps\fastapi-demo
python -m pytest -q
```

Build local image for kind:

```powershell
cd D:\Markdown\crossplane-backstage-poc
docker build -t ghcr.io/re1lya/fastapi-demo:latest apps\fastapi-demo
kind load docker-image ghcr.io/re1lya/fastapi-demo:latest --name platform-poc
```

Check deployment:

```powershell
kubectl get applications.argoproj.io fastapi-demo-appservice -n argocd
kubectl get appservice fastapi-demo -n default
kubectl get releases.helm.m.crossplane.io -n default
kubectl get deploy,pod,svc -n demo -l backstage.io/kubernetes-id=fastapi-demo
```

Test service:

```powershell
kubectl port-forward svc/fastapi-demo -n demo 8082:80
```

Open:

```text
http://localhost:8082/
http://localhost:8082/health
```

The real Tekton CI pipeline is:

```text
ci/fastapi-demo-ci
```

It does:

```text
clone repo -> pytest -> BuildKit build -> push ghcr.io/re1lya/fastapi-demo:<commit-sha>
```

The build task uses rootless BuildKit:

```text
moby/buildkit:rootless
```

It does not require Docker-in-Docker, a Docker socket mount, or an external BuildKit VM.

The EventListener service is:

```text
ci/el-fastapi-demo-ci-listener
```

Start the webhook tunnel for the real CI listener:

```powershell
cd D:\Markdown\crossplane-backstage-poc
powershell -ExecutionPolicy Bypass -File .\scripts\start-github-webhook-tunnel.ps1
```

Before running real CI, create the GHCR Docker registry secret:

```powershell
$GHCR_USER="Re1lya"
$GHCR_TOKEN="<your GitHub classic PAT>"

kubectl create secret docker-registry ghcr-auth `
  -n ci `
  --docker-server=ghcr.io `
  --docker-username=$GHCR_USER `
  --docker-password=$GHCR_TOKEN `
  --docker-email=unused@example.com `
  --dry-run=client -o yaml | kubectl apply -f -
```

Also create a Git clone secret. This can reuse the same GitHub classic PAT if it has `repo` scope:

```powershell
$GITHUB_USER="Re1lya"
$GITHUB_TOKEN="<your GitHub classic PAT>"

kubectl create secret generic github-git-auth `
  -n ci `
  --from-literal=username=$GITHUB_USER `
  --from-literal=token=$GITHUB_TOKEN `
  --dry-run=client -o yaml | kubectl apply -f -
```

Why two secrets:

```text
ghcr-auth       -> Docker/BuildKit login for ghcr.io image push
github-git-auth -> git clone authentication for https://github.com/Re1lya/Markdown.git
```

Required token scopes for this POC:

```text
write:packages
read:packages
repo
```

Current known limit:

The real CI/CD loop is now complete for the FastAPI demo.

Successful CI example:

```text
PipelineRun: fastapi-demo-ci-krh4q
Image: ghcr.io/re1lya/fastapi-demo:1ddefb7862e41ac2646e08c9bd8190248abfd373
```

Verify a run:

```powershell
kubectl get pipelinerun -n ci
kubectl get taskrun -n ci -l tekton.dev/pipelineRun=<pipelinerun-name>
kubectl logs -n ci pod/<pipelinerun-name>-build-push-pod -c step-build-and-push --tail=120
```

Expected successful BuildKit log includes:

```text
[auth] re1lya/fastapi-demo:pull,push token for ghcr.io
pushing manifest for ghcr.io/re1lya/fastapi-demo:<commit-sha>
DONE
```

## Full FastAPI CI/CD Flow

Current flow:

```text
GitHub push
  -> GitHub webhook
  -> cloudflared quick tunnel
  -> Tekton EventListener
  -> Tekton Pipeline
  -> clone GitHub repo
  -> pytest
  -> BuildKit rootless build
  -> push ghcr.io/re1lya/fastapi-demo:<commit-sha>
  -> edit charts/fastapi-demo-appservice/values.yaml
  -> commit/push GitOps update with [skip ci]
  -> Argo CD syncs GitHub chart path
  -> Crossplane updates Helm Release
  -> Kubernetes rolls out fastapi-demo
```

Argo CD source for FastAPI:

```text
repoURL: https://github.com/Re1lya/Markdown.git
path: crossplane-backstage-poc/charts/fastapi-demo-appservice
targetRevision: main
```

Check end-to-end state:

```powershell
kubectl get application fastapi-demo-appservice -n argocd
kubectl get appservice fastapi-demo -n default
kubectl get releases.helm.m.crossplane.io fastapi-demo-27b6ddc77acf -n default
kubectl get deploy,pod,svc -n demo -l backstage.io/kubernetes-id=fastapi-demo
```

Expected:

```text
Argo CD: Synced / Healthy
AppService: SYNCED=True READY=True
Release: SYNCED=True READY=True STATE=deployed
Deployment: 1/1
Pod: Running
```

Runtime GHCR pull credentials:

```text
demo/ghcr-auth
```

The default ServiceAccount in `demo` is patched with:

```text
imagePullSecrets:
  - name: ghcr-auth
```

Without this, Tekton can push to GHCR, but Kubernetes may fail to pull the private image with `ErrImagePull`.

## Backstage UI Troubleshooting

If Backstage shows:

```text
NotImplementedError
No implementation available for apiRef{plugin.notifications.service}
```

the custom Backstage frontend is missing the notifications frontend plugin registration.

Expected file:

```text
D:/Markdown/crossplane-backstage-poc/apps/backstage-custom/packages/app/src/App.tsx
```

Expected feature list:

```ts
import { createApp } from '@backstage/frontend-defaults';
import catalogPlugin from '@backstage/plugin-catalog/alpha';
import kubernetesPlugin from '@backstage/plugin-kubernetes/alpha';
import notificationsPlugin from '@backstage/plugin-notifications/alpha';
import { navModule } from './modules/nav';

export default createApp({
  features: [catalogPlugin, kubernetesPlugin, notificationsPlugin, navModule],
});
```

After changing Backstage frontend code, rebuild and redeploy the custom image:

```powershell
cd D:\Markdown\crossplane-backstage-poc\apps\backstage-custom
yarn tsc
yarn build:backend
docker build -f Dockerfile.overlay -t platform-poc-backstage:0.1.1 .
kind load docker-image platform-poc-backstage:0.1.1 --name platform-poc
helm upgrade backstage backstage/backstage -n backstage -f D:\Markdown\crossplane-backstage-poc\manifests\backstage\backstage-values.yaml
kubectl rollout status deployment/backstage -n backstage --timeout=180s
```

The current custom image tag in `manifests/backstage/backstage-values.yaml` is:

```text
platform-poc-backstage:0.1.1
```

If the browser cannot connect to `http://localhost:7007`, restart the Backstage port-forward:

```powershell
kubectl port-forward svc/backstage -n backstage 7007:7007
```

## Backstage Register Existing FastAPI Service

The POC now includes a Backstage Software Template:

```text
Register Existing FastAPI Service
```

Open:

```text
http://localhost:7007/create
```

The template asks for:

```text
serviceName
owner
sourceRepoUrl
sourceRepoCloneUrl
contextDir
imageRepository
runtimeNamespace
crossplaneNamespace
appPort
replicas
gitopsRepoUrl
gitopsHttpUrl
gitopsTargetBranch
```

It opens a GitHub pull request that adds:

```text
gitops/appservices/<serviceName>/...
gitops/argocd/<serviceName>-appservice.yaml
gitops/tekton/<serviceName>-ci.yaml
catalog/services/<serviceName>/catalog-info.yaml
```

After the PR is merged:

```text
platform-appservices Argo CD app
  -> syncs gitops/argocd
  -> creates the service Argo CD Application
  -> syncs the service AppService Helm chart
  -> Crossplane manages AppService
  -> provider-helm deploys the runtime chart

platform-ci Argo CD app
  -> syncs gitops/tekton
  -> creates the service Tekton EventListener/Pipeline
```

Important:

The app-of-apps Applications point to GitHub `main`. If they show:

```text
Unknown / Healthy
app path does not exist
```

then the local `gitops/argocd` and `gitops/tekton` directories have not been pushed to GitHub yet. Commit and push the platform files first.

For each onboarded service, the generated Tekton EventListener still needs a GitHub webhook. Use cloudflared in the same style as the FastAPI demo, but point the port-forward to that service listener:

```powershell
kubectl port-forward svc/el-<serviceName>-ci-listener -n ci 8081:8080
cloudflared tunnel --url http://localhost:8081
```

Then configure the application repository webhook:

```text
Payload URL: https://<new-trycloudflare-url>
Content type: application/json
Secret: platform-poc-webhook-secret
Events: Just the push event
```
