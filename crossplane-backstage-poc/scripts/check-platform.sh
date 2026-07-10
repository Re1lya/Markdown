#!/usr/bin/env bash
set -euo pipefail

KUBE_CONTEXT="${KUBE_CONTEXT:-kind-platform-poc}"
SERVER_HOST="${SERVER_HOST:-localhost}"
DEMO_BASE_URL="${DEMO_BASE_URL:-http://${SERVER_HOST}:30080}"

pass() {
  echo "[PASS] $1"
}

check() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    pass "$label"
  else
    echo "[FAIL] $label" >&2
    "$@" || true
    exit 1
  fi
}

echo "Checking Kubernetes context: $KUBE_CONTEXT"
kubectl --context "$KUBE_CONTEXT" get nodes -o wide

check "Crossplane pods Ready" kubectl --context "$KUBE_CONTEXT" -n crossplane-system wait --for=condition=Ready pod --all --timeout=120s
check "provider-helm Healthy" kubectl --context "$KUBE_CONTEXT" wait provider.pkg.crossplane.io/provider-helm --for=condition=Healthy --timeout=120s
check "provider-kubernetes Healthy" kubectl --context "$KUBE_CONTEXT" wait provider.pkg.crossplane.io/provider-kubernetes --for=condition=Healthy --timeout=120s
check "function-patch-and-transform Healthy" kubectl --context "$KUBE_CONTEXT" wait function.pkg.crossplane.io/function-patch-and-transform --for=condition=Healthy --timeout=120s

check "Tekton controllers Available" kubectl --context "$KUBE_CONTEXT" -n tekton-pipelines wait --for=condition=Available deployment --all --timeout=120s
check "Tekton shared Tasks present" kubectl --context "$KUBE_CONTEXT" -n ci get task clone-repo test-fastapi-demo build-push-fastapi-demo update-fastapi-demo-gitops
check "Tekton fastapi-demo-2 EventListener present" kubectl --context "$KUBE_CONTEXT" -n ci get eventlistener fastapi-demo-2-ci-listener

check "Argo CD deployments Available" kubectl --context "$KUBE_CONTEXT" -n argocd wait --for=condition=Available deployment --all --timeout=120s
kubectl --context "$KUBE_CONTEXT" -n argocd get applications.argoproj.io || true

check "Backstage deployment Available" kubectl --context "$KUBE_CONTEXT" -n backstage wait --for=condition=Available deployment/backstage --timeout=180s
check "Envoy Gateway deployment Available" kubectl --context "$KUBE_CONTEXT" -n envoy-gateway-system wait --for=condition=Available deployment --all --timeout=120s

kubectl --context "$KUBE_CONTEXT" get appservices.platform.example.com -A || true
kubectl --context "$KUBE_CONTEXT" -n demo get pods,svc,httproute || true

if command -v curl >/dev/null 2>&1; then
  curl --connect-timeout 3 --max-time 10 -fsS "$DEMO_BASE_URL/health" | grep -q '"status":"ok"'
  pass "Gateway health $DEMO_BASE_URL/health"
else
  echo "[WARN] curl not found; skipping Gateway HTTP check"
fi
