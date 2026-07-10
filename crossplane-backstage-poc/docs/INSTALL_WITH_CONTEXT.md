# Install the POC With a kubeconfig Context

This guide explains how to clone the repository on another server, create a fresh kind cluster, and install the POC into the generated Kubernetes context.

Do not commit kubeconfig files or real tokens. The target server creates its own kubeconfig context when `kind create cluster` runs.

## 1. Clone the Repository

```bash
git clone https://github.com/Re1lya/Markdown.git
cd Markdown/crossplane-backstage-poc
```

## 2. Create the kind Cluster

The repository already contains the kind config:

```text
configs/kind-platform-poc.yaml
```

Create the cluster:

```bash
kind create cluster --config configs/kind-platform-poc.yaml
```

Because the cluster name is `platform-poc`, kind automatically writes this context into `~/.kube/config`:

```text
kind-platform-poc
```

Check it:

```bash
kubectl config get-contexts
kubectl --context kind-platform-poc get nodes -o wide
```

## 3. Load Environment Defaults

```bash
source environments/kind/values.env
```

If the demo is accessed from another machine, override `SERVER_HOST`:

```bash
export SERVER_HOST="YOUR_SERVER_IP_OR_DOMAIN"
export BACKSTAGE_BASE_URL="http://${SERVER_HOST}:7007"
export DEMO_BASE_URL="http://${SERVER_HOST}:30080"
```

All install scripts use:

```bash
kubectl --context "$KUBE_CONTEXT" ...
helm --kube-context "$KUBE_CONTEXT" ...
```

The default is:

```bash
KUBE_CONTEXT=kind-platform-poc
```

## 4. Prepare the Backstage Image

The original local POC used a local kind-loaded image:

```text
platform-poc-backstage:0.1.5
```

On another server, the image must be pullable by the cluster. Push it to a registry such as GHCR, then set:

```bash
export BACKSTAGE_IMAGE_REGISTRY="ghcr.io"
export BACKSTAGE_IMAGE_REPOSITORY="re1lya/platform-poc-backstage"
export BACKSTAGE_IMAGE_TAG="0.1.5"
```

If you prefer to rebuild on the server, build and push from:

```text
apps/backstage-custom/
```

## 5. Create Secrets

Copy the example script and replace placeholders:

```bash
cp scripts/create-secrets.example.sh scripts/create-secrets.sh
chmod +x scripts/create-secrets.sh
vim scripts/create-secrets.sh
```

Then run:

```bash
bash scripts/create-secrets.sh
```

The real `scripts/create-secrets.sh` file is ignored by Git. Do not commit it.

Secrets created by the example:

```text
ci/ghcr-auth
ci/github-git-auth
ci/github-webhook-secret
backstage/backstage-github-token
argocd/markdown-repo
```

## 6. Install the Platform

```bash
bash scripts/install-platform.sh
```

The script installs resources in dependency order:

```text
1. Namespaces
2. Crossplane
3. Crossplane providers and function
4. Crossplane ProviderConfig, XRD, and Composition chart
5. In-cluster Helm repo manifest
6. Tekton Pipelines and Triggers
7. Tekton CI chart
8. Argo CD through Crossplane provider-helm
9. Argo CD Application chart
10. Envoy Gateway
11. Gateway chart
12. Demo AppService chart
13. Backstage Helm release and RBAC chart
```

## 7. Verify

```bash
bash scripts/check-platform.sh
```

Expected highlights:

```text
[PASS] Crossplane pods Ready
[PASS] provider-helm Healthy
[PASS] provider-kubernetes Healthy
[PASS] function-patch-and-transform Healthy
[PASS] Tekton controllers Available
[PASS] Argo CD deployments Available
[PASS] Backstage deployment Available
[PASS] Envoy Gateway deployment Available
[PASS] Gateway health http://SERVER_HOST:30080/health
```

You can also inspect manually:

```bash
kubectl --context "$KUBE_CONTEXT" get appservices.platform.example.com -A
kubectl --context "$KUBE_CONTEXT" -n argocd get applications
kubectl --context "$KUBE_CONTEXT" -n ci get eventlisteners,pipelines,tasks
kubectl --context "$KUBE_CONTEXT" -n demo get pods,svc,httproute
```

## 8. Access

Demo service:

```text
http://SERVER_HOST:30080/
http://SERVER_HOST:30080/health
```

Backstage:

```text
http://SERVER_HOST:7007/catalog
```

If Backstage is not exposed directly, use port-forward:

```bash
kubectl --context "$KUBE_CONTEXT" -n backstage port-forward svc/backstage 7007:7007
```

## Notes

- `configs/kind-platform-poc.yaml` is only for creating a kind cluster.
- It is not a Kubernetes manifest and should not be applied with `kubectl apply`.
- The kube context is generated on the target server by kind.
- Keep real kubeconfigs and secrets out of Git.
- The install charts are intentionally split by platform layer instead of one giant umbrella chart.
