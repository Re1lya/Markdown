# Server Codex Handoff: Crossplane + Backstage POC Migration

This document is for the Codex agent running on the target server.

The goal is to migrate and reproduce the existing local POC on this server so it can be demonstrated reliably. Do not start by rewriting the architecture. First understand the current POC, inspect the server environment, then propose a small migration plan for user approval.

## Required First Step

Before making any changes, read these files:

```text
crossplane-backstage-poc/AGENTS.md
crossplane-backstage-poc/POC_GUIDE.md
crossplane-backstage-poc/README.md
crossplane-backstage-poc/DECISIONS.md
crossplane-backstage-poc/docs/INSTALL_WITH_CONTEXT.md
```

Then inspect these directories:

```text
crossplane-backstage-poc/manifests/
crossplane-backstage-poc/gitops/
crossplane-backstage-poc/charts/
crossplane-backstage-poc/apps/
crossplane-backstage-poc/scripts/
```

`AGENTS.md` is especially important. It contains the latest state, historical fixes, local rebuild notes, secrets that were required, and known rough edges.

## Current POC Architecture

The existing POC validates a platform engineering workflow:

```text
GitHub push
  -> Tekton Triggers / Tekton Pipelines
  -> pytest
  -> BuildKit image build
  -> GHCR image push
  -> GitOps values update
  -> Argo CD sync
  -> Crossplane AppService
  -> provider-helm Release
  -> Helm chart deploys Kubernetes workload
  -> Envoy Gateway exposes the app
  -> Backstage displays Catalog and Kubernetes runtime status
```

Main components:

```text
Crossplane
  Platform API: AppService
  XRD and Composition under manifests/platform/
  Providers under manifests/crossplane/

Tekton
  CI pipelines, shared tasks, EventListeners
  GitOps-managed files under gitops/tekton/
  Reference manifests under manifests/tekton/

Argo CD
  App-of-apps style platform sync
  Application manifests under manifests/argocd/ and gitops/argocd/

Backstage
  Custom Backstage app under apps/backstage-custom/
  Helm values under manifests/backstage/backstage-values.yaml
  Catalog discovery uses GitHub
  Kubernetes plugin reads cluster resources by labels/annotations

Envoy Gateway
  Gateway / HTTPRoute manifests under manifests/gateway/

Demo app
  FastAPI app under apps/fastapi-demo/
  Runtime Helm charts under charts/ and gitops/appservices/
```

## Known Local Assumptions To Replace

This POC was originally proven on a local kind cluster. The server migration must identify and replace local-only assumptions.

Known examples:

```text
localhost URLs:
  Backstage baseUrl may be http://localhost:7007
  Demo service links may be http://localhost:30080/

kind-specific behavior:
  configs/kind-platform-poc.yaml
  NodePort 30080 mapping through kind extraPortMappings
  local image loading with kind load docker-image

local image:
  platform-poc-backstage:0.1.5
  This must become a pullable registry image, for example:
  ghcr.io/re1lya/platform-poc-backstage:0.1.5

local / runtime secrets:
  ci/ghcr-auth
  ci/github-git-auth
  ci/github-webhook-secret
  backstage/backstage-github-token
  argocd/markdown-repo
```

Do not commit real tokens, kubeconfigs, secret backups, or generated runtime state.

## kubeconfig Context Direction

Do not ask the user to commit kubeconfig or context files. For the second server flow, the user should create a fresh kind cluster:

```bash
kind create cluster --config crossplane-backstage-poc/configs/kind-platform-poc.yaml
```

Because the kind cluster name is `platform-poc`, kind automatically creates this context on the target server:

```text
kind-platform-poc
```

All install and check commands should use this context explicitly:

```bash
export KUBE_CONTEXT=kind-platform-poc
kubectl --context "$KUBE_CONTEXT" get nodes -o wide
helm --kube-context "$KUBE_CONTEXT" list -A
```

The repository includes:

```text
crossplane-backstage-poc/environments/kind/values.env
crossplane-backstage-poc/scripts/install-platform.sh
crossplane-backstage-poc/scripts/check-platform.sh
crossplane-backstage-poc/scripts/create-secrets.example.sh
```

## Server Environment To Inspect

Run read-only checks first and summarize the result to the user:

```bash
pwd
git status --short
uname -a
cat /etc/os-release || true

kubectl version --client
kubectl config current-context
kubectl get nodes -o wide
kubectl get ns

helm version

docker version || true
nerdctl version || true
crictl version || true

ss -lntp || netstat -lntp || true
```

Also check whether the server already has:

```text
Kubernetes cluster
kubectl access
Helm
container build tool
public IP or domain
open firewall/security-group ports
existing namespaces or old POC resources
```

If Kubernetes is not installed, propose the simplest server-appropriate option before installing anything. For a demo server, k3s is likely the simplest choice, but confirm with the user first.

## Desired Migration Output

The migration should create a repeatable server demo deployment, not just manually apply resources once.

Preferred new files:

```text
crossplane-backstage-poc/scripts/install-server-demo.sh
crossplane-backstage-poc/scripts/check-server-demo.sh
crossplane-backstage-poc/scripts/create-secrets.example.sh
crossplane-backstage-poc/docs/SERVER_DEPLOYMENT.md
```

Optional if needed:

```text
crossplane-backstage-poc/manifests/server/
crossplane-backstage-poc/manifests/server/backstage-values.server.yaml
crossplane-backstage-poc/manifests/server/gateway-server.yaml
```

The install script should be conservative and ordered. A single giant Helm chart is not required and is not preferred for this POC because CRDs and controllers have strict installation order.

Recommended order:

```text
1. Create required namespaces.
2. Install Crossplane.
3. Install Crossplane providers and functions.
4. Wait for providers/functions to become healthy.
5. Apply AppService XRD and Composition.
6. Install Tekton Pipelines and Triggers.
7. Install Argo CD.
8. Install Envoy Gateway.
9. Install or upgrade Backstage with server-safe values.
10. Apply GitOps bootstrap / app-of-apps resources.
11. Verify demo AppServices, Argo CD Applications, Tekton EventListeners, Gateway, Backstage.
```

## Required Secrets

Create an example script only. Do not hard-code real values.

The example should guide the user to create or provide:

```text
GHCR auth secret for image push/pull
GitHub git auth secret for clone/push
GitHub webhook secret for Tekton Triggers
Backstage GitHub token secret
Argo CD repository secret if private repo access is required
```

Use placeholders such as:

```text
REPLACE_WITH_GITHUB_USERNAME
REPLACE_WITH_GITHUB_TOKEN
REPLACE_WITH_WEBHOOK_SECRET
```

## What To Propose Before Implementing

After reading the docs and inspecting the server, do not immediately migrate. First present a short plan to the user and wait for confirmation.

The plan should answer:

```text
1. Is Kubernetes already available on this server?
2. Which access URLs will be used for Backstage and the demo service?
3. Will the custom Backstage image be built on the server or pulled from GHCR?
4. Which ports/domains need to be opened?
5. Which secrets must the user provide before end-to-end CI/CD can work?
6. Which files will be added or changed?
7. What will be verified at the end?
```

Keep the first plan simple. The goal is a reproducible demo, not production hardening.

## Expected Final Verification

The server migration is successful only when these checks pass or when a clearly documented blocker remains:

```text
Crossplane pods Ready
Crossplane provider-helm Ready
Crossplane function-patch-and-transform Ready
AppService XRD and Composition installed
Tekton controllers Ready
Tekton shared Tasks present
Tekton EventListener Ready
Argo CD server Ready
Argo CD Applications Synced / Healthy
Envoy Gateway Ready
Backstage Ready and accessible from the user machine
fastapi-demo-2 reachable through the chosen server URL
/health returns {"status":"ok"}
Backstage Catalog can show the demo service
Backstage Kubernetes plugin can show runtime resources
```

If GitHub webhook or GHCR credentials are not available yet, still make the base platform reproducible and document exactly which secret or external setting remains.

## Important Constraints

- Do not commit real secrets.
- Do not delete unrelated user work.
- Do not assume kind-specific networking on the server.
- Do not rely on `localhost` for user-facing demo URLs unless the user explicitly wants SSH tunnels.
- Prefer small ordered scripts plus GitOps over one giant Helm chart.
- Preserve the existing platform contract under:

```text
catalog/services/<service>/catalog-info.yaml
gitops/appservices/<service>/
gitops/argocd/<service>-appservice.yaml
gitops/tekton/<service>-ci.yaml
```

Backstage is a replaceable portal layer. Crossplane, Tekton, Argo CD, Helm charts, and the GitOps file layout are the durable platform pieces.

## Suggested User-Facing Opening Response

After reading this document and inspecting the server, respond to the user with something like:

```text
I have read the POC handoff docs and inspected the server. Current environment:
- Kubernetes: ...
- kubectl context: ...
- Helm: ...
- Container build tool: ...
- Public/demo access: ...

Recommended migration plan:
1. ...
2. ...
3. ...

Before I make changes, please confirm:
- Backstage URL should be ...
- Demo service URL should be ...
- I should use GHCR image ... or build/push it first.
```

Wait for user confirmation before making migration changes.
