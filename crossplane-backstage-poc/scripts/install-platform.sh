#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBE_CONTEXT="${KUBE_CONTEXT:-kind-platform-poc}"
SERVER_HOST="${SERVER_HOST:-localhost}"
BACKSTAGE_BASE_URL="${BACKSTAGE_BASE_URL:-http://${SERVER_HOST}:7007}"
DEMO_BASE_URL="${DEMO_BASE_URL:-http://${SERVER_HOST}:30080}"
BACKSTAGE_IMAGE_REGISTRY="${BACKSTAGE_IMAGE_REGISTRY:-ghcr.io}"
BACKSTAGE_IMAGE_REPOSITORY="${BACKSTAGE_IMAGE_REPOSITORY:-re1lya/platform-poc-backstage}"
BACKSTAGE_IMAGE_TAG="${BACKSTAGE_IMAGE_TAG:-0.1.5}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

wait_deploy() {
  local namespace="$1"
  local selector="$2"
  kubectl --context "$KUBE_CONTEXT" -n "$namespace" wait --for=condition=Available deployment -l "$selector" --timeout=300s
}

require_cmd kubectl
require_cmd helm

echo "Using Kubernetes context: $KUBE_CONTEXT"
kubectl --context "$KUBE_CONTEXT" get nodes -o wide

echo "Creating namespaces"
for ns in crossplane-system platform-system default demo ci argocd backstage envoy-gateway-system; do
  kubectl --context "$KUBE_CONTEXT" create namespace "$ns" --dry-run=client -o yaml | kubectl --context "$KUBE_CONTEXT" apply -f -
done

echo "Adding Helm repositories"
helm repo add crossplane-stable https://charts.crossplane.io/stable --force-update >/dev/null
helm repo add backstage https://backstage.github.io/charts --force-update >/dev/null
helm repo add argo https://argoproj.github.io/argo-helm --force-update >/dev/null
helm repo update >/dev/null

echo "Installing Crossplane"
helm --kube-context "$KUBE_CONTEXT" upgrade --install crossplane crossplane-stable/crossplane \
  -n crossplane-system \
  --wait \
  --timeout 10m

kubectl --context "$KUBE_CONTEXT" apply -f "$ROOT_DIR/manifests/crossplane/provider-kubernetes.yaml"
kubectl --context "$KUBE_CONTEXT" apply -f "$ROOT_DIR/manifests/crossplane/provider-helm.yaml"
kubectl --context "$KUBE_CONTEXT" apply -f "$ROOT_DIR/manifests/crossplane/function-patch-and-transform.yaml"

echo "Waiting for Crossplane providers and functions"
kubectl --context "$KUBE_CONTEXT" wait provider.pkg.crossplane.io/provider-kubernetes --for=condition=Healthy --timeout=10m
kubectl --context "$KUBE_CONTEXT" wait provider.pkg.crossplane.io/provider-helm --for=condition=Healthy --timeout=10m
kubectl --context "$KUBE_CONTEXT" wait function.pkg.crossplane.io/function-patch-and-transform --for=condition=Healthy --timeout=10m

echo "Granting POC cluster-admin permissions to Crossplane provider service accounts"
for sa in $(kubectl --context "$KUBE_CONTEXT" -n crossplane-system get sa -o name | grep -E 'provider-(helm|kubernetes)' | sed 's#serviceaccount/##'); do
  kubectl --context "$KUBE_CONTEXT" create clusterrolebinding "platform-poc-${sa}-admin" \
    --clusterrole cluster-admin \
    --serviceaccount "crossplane-system:${sa}" \
    --dry-run=client -o yaml | kubectl --context "$KUBE_CONTEXT" apply -f -
done

echo "Installing Crossplane platform configuration"
helm --kube-context "$KUBE_CONTEXT" upgrade --install platform-crossplane "$ROOT_DIR/charts/platform-crossplane" \
  -n default \
  --wait \
  --timeout 5m

echo "Packaging and installing in-cluster Helm repository for demo charts"
HELM_REPO_DIR="$(mktemp -d)"
helm lint "$ROOT_DIR/charts/helloworld"
helm lint "$ROOT_DIR/charts/helloworld-appservice"
helm lint "$ROOT_DIR/charts/fastapi-demo"
helm lint "$ROOT_DIR/charts/fastapi-demo-appservice"
helm package "$ROOT_DIR/charts/helloworld" --destination "$HELM_REPO_DIR" >/dev/null
helm package "$ROOT_DIR/charts/helloworld-appservice" --destination "$HELM_REPO_DIR" >/dev/null
helm package "$ROOT_DIR/charts/fastapi-demo" --destination "$HELM_REPO_DIR" >/dev/null
helm package "$ROOT_DIR/charts/fastapi-demo-appservice" --destination "$HELM_REPO_DIR" >/dev/null
helm repo index "$HELM_REPO_DIR" --url "http://helm-repo.platform-system.svc.cluster.local"
kubectl --context "$KUBE_CONTEXT" -n platform-system create configmap helm-repo-content \
  --from-file="$HELM_REPO_DIR" \
  --dry-run=client -o yaml | kubectl --context "$KUBE_CONTEXT" apply -f -
kubectl --context "$KUBE_CONTEXT" apply -f "$ROOT_DIR/manifests/helm-repo/helm-repo-server.yaml"
rm -rf "$HELM_REPO_DIR"
kubectl --context "$KUBE_CONTEXT" -n platform-system rollout status deployment/helm-repo --timeout=120s

echo "Installing Tekton Pipelines and Triggers"
kubectl --context "$KUBE_CONTEXT" apply -f https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml
kubectl --context "$KUBE_CONTEXT" apply -f https://storage.googleapis.com/tekton-releases/triggers/latest/release.yaml
kubectl --context "$KUBE_CONTEXT" apply -f https://storage.googleapis.com/tekton-releases/triggers/latest/interceptors.yaml
kubectl --context "$KUBE_CONTEXT" -n tekton-pipelines wait --for=condition=Available deployment --all --timeout=10m

echo "Installing Tekton CI configuration"
helm --kube-context "$KUBE_CONTEXT" upgrade --install platform-tekton "$ROOT_DIR/charts/platform-tekton" \
  -n ci \
  --wait \
  --timeout 5m

echo "Installing Argo CD through Crossplane provider-helm"
kubectl --context "$KUBE_CONTEXT" apply -f "$ROOT_DIR/manifests/argocd/argocd-release.yaml"
kubectl --context "$KUBE_CONTEXT" -n default wait release.helm.m.crossplane.io/argocd --for=condition=Ready --timeout=10m
kubectl --context "$KUBE_CONTEXT" -n argocd wait --for=condition=Available deployment --all --timeout=10m

echo "Installing Argo CD Applications"
helm --kube-context "$KUBE_CONTEXT" upgrade --install platform-argocd "$ROOT_DIR/charts/platform-argocd" \
  -n argocd \
  --wait \
  --timeout 5m

echo "Installing Envoy Gateway"
helm --kube-context "$KUBE_CONTEXT" upgrade --install eg oci://docker.io/envoyproxy/gateway-helm \
  --version v1.8.2 \
  -n envoy-gateway-system \
  --wait \
  --timeout 5m

echo "Installing Gateway routes"
helm --kube-context "$KUBE_CONTEXT" upgrade --install platform-gateway "$ROOT_DIR/charts/platform-gateway" \
  -n demo \
  --wait \
  --timeout 5m

echo "Installing demo AppServices"
helm --kube-context "$KUBE_CONTEXT" upgrade --install platform-demo-appservices "$ROOT_DIR/charts/platform-demo-appservices" \
  -n default \
  --wait \
  --timeout 5m

echo "Installing Backstage"
BACKSTAGE_OVERRIDE="$(mktemp)"
cat > "$BACKSTAGE_OVERRIDE" <<EOF
backstage:
  image:
    registry: "$BACKSTAGE_IMAGE_REGISTRY"
    repository: "$BACKSTAGE_IMAGE_REPOSITORY"
    tag: "$BACKSTAGE_IMAGE_TAG"
    pullPolicy: IfNotPresent
  appConfig:
    app:
      baseUrl: "$BACKSTAGE_BASE_URL"
    backend:
      baseUrl: "$BACKSTAGE_BASE_URL"
      cors:
        origin: "$BACKSTAGE_BASE_URL"
EOF

helm --kube-context "$KUBE_CONTEXT" upgrade --install backstage backstage/backstage \
  -n backstage \
  -f "$ROOT_DIR/manifests/backstage/backstage-values.yaml" \
  -f "$BACKSTAGE_OVERRIDE" \
  --wait \
  --timeout 10m
rm -f "$BACKSTAGE_OVERRIDE"

helm --kube-context "$KUBE_CONTEXT" upgrade --install platform-backstage "$ROOT_DIR/charts/platform-backstage" \
  -n backstage \
  --wait \
  --timeout 5m

echo "Install completed. Run scripts/check-platform.sh for verification."
