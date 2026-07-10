#!/usr/bin/env bash
set -euo pipefail

# Copy this file to scripts/create-secrets.sh, replace the placeholder values,
# then run it on the target server. Do not commit scripts/create-secrets.sh.

KUBE_CONTEXT="${KUBE_CONTEXT:-kind-platform-poc}"

GITHUB_USERNAME="REPLACE_WITH_GITHUB_USERNAME"
GITHUB_TOKEN="REPLACE_WITH_GITHUB_TOKEN"
GITHUB_WEBHOOK_SECRET="REPLACE_WITH_WEBHOOK_SECRET"
GHCR_SERVER="ghcr.io"
GHCR_USERNAME="$GITHUB_USERNAME"
GHCR_TOKEN="$GITHUB_TOKEN"
GITOPS_REPO_URL="https://github.com/Re1lya/Markdown.git"

kubectl --context "$KUBE_CONTEXT" create namespace ci --dry-run=client -o yaml | kubectl --context "$KUBE_CONTEXT" apply -f -
kubectl --context "$KUBE_CONTEXT" create namespace backstage --dry-run=client -o yaml | kubectl --context "$KUBE_CONTEXT" apply -f -
kubectl --context "$KUBE_CONTEXT" create namespace argocd --dry-run=client -o yaml | kubectl --context "$KUBE_CONTEXT" apply -f -

kubectl --context "$KUBE_CONTEXT" -n ci create secret docker-registry ghcr-auth \
  --docker-server="$GHCR_SERVER" \
  --docker-username="$GHCR_USERNAME" \
  --docker-password="$GHCR_TOKEN" \
  --dry-run=client -o yaml | kubectl --context "$KUBE_CONTEXT" apply -f -

kubectl --context "$KUBE_CONTEXT" -n backstage create secret docker-registry ghcr-auth \
  --docker-server="$GHCR_SERVER" \
  --docker-username="$GHCR_USERNAME" \
  --docker-password="$GHCR_TOKEN" \
  --dry-run=client -o yaml | kubectl --context "$KUBE_CONTEXT" apply -f -

kubectl --context "$KUBE_CONTEXT" -n ci create secret generic github-git-auth \
  --from-literal=username="$GITHUB_USERNAME" \
  --from-literal=token="$GITHUB_TOKEN" \
  --dry-run=client -o yaml | kubectl --context "$KUBE_CONTEXT" apply -f -

kubectl --context "$KUBE_CONTEXT" -n ci create secret generic github-webhook-secret \
  --from-literal=secretToken="$GITHUB_WEBHOOK_SECRET" \
  --dry-run=client -o yaml | kubectl --context "$KUBE_CONTEXT" apply -f -

kubectl --context "$KUBE_CONTEXT" -n backstage create secret generic backstage-github-token \
  --from-literal=token="$GITHUB_TOKEN" \
  --dry-run=client -o yaml | kubectl --context "$KUBE_CONTEXT" apply -f -

kubectl --context "$KUBE_CONTEXT" -n argocd create secret generic markdown-repo \
  --from-literal=type=git \
  --from-literal=url="$GITOPS_REPO_URL" \
  --from-literal=username="$GITHUB_USERNAME" \
  --from-literal=password="$GITHUB_TOKEN" \
  --dry-run=client -o yaml | kubectl --context "$KUBE_CONTEXT" apply -f -

kubectl --context "$KUBE_CONTEXT" -n argocd label secret markdown-repo \
  argocd.argoproj.io/secret-type=repository --overwrite
