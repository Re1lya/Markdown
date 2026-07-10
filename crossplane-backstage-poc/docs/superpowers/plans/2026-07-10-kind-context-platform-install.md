# Kind Context Platform Install Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Package the existing POC so a second server can clone the repository, create a fresh kind cluster, and install the platform into the generated `kind-platform-poc` kube context.

**Architecture:** Keep the real kubeconfig and secrets out of Git. Commit reusable Helm charts, environment values, example secret creation, and ordered install/check scripts. Scripts use `KUBE_CONTEXT` explicitly for every `kubectl` and `helm` operation.

**Tech Stack:** Kubernetes, kind, Helm, Crossplane, Tekton, Argo CD, Envoy Gateway, Backstage, Bash.

---

### Task 1: Create Context-Aware Install Scaffolding

**Files:**
- Create: `crossplane-backstage-poc/environments/kind/values.env`
- Create: `crossplane-backstage-poc/scripts/create-secrets.example.sh`
- Create: `crossplane-backstage-poc/scripts/install-platform.sh`
- Create: `crossplane-backstage-poc/scripts/check-platform.sh`

- [ ] Add environment defaults for the kind target.
- [ ] Add an example secret script with placeholders only.
- [ ] Add an ordered install script that defaults to `KUBE_CONTEXT=kind-platform-poc`.
- [ ] Add a check script that verifies the target context and platform resources.

### Task 2: Add Platform Charts

**Files:**
- Create: `crossplane-backstage-poc/charts/platform-crossplane/`
- Create: `crossplane-backstage-poc/charts/platform-tekton/`
- Create: `crossplane-backstage-poc/charts/platform-argocd/`
- Create: `crossplane-backstage-poc/charts/platform-gateway/`
- Create: `crossplane-backstage-poc/charts/platform-backstage/`
- Create: `crossplane-backstage-poc/charts/platform-demo-appservices/`

- [ ] Wrap existing Crossplane provider/function/platform manifests as chart templates.
- [ ] Wrap existing Tekton shared and service manifests as chart templates.
- [ ] Wrap existing Argo CD Application manifests as chart templates.
- [ ] Wrap existing Gateway manifests as chart templates.
- [ ] Wrap Backstage RBAC and server-facing values as chart files.
- [ ] Wrap demo AppService claims as chart templates.

### Task 3: Document Clone, Context, and Install Flow

**Files:**
- Create: `crossplane-backstage-poc/docs/INSTALL_WITH_CONTEXT.md`
- Modify: `crossplane-backstage-poc/docs/SERVER_CODEX_HANDOFF.md`

- [ ] Document that kind creates the kube context automatically.
- [ ] Document the exact clone, kind create, context check, secret creation, install, and verification commands.
- [ ] Document that kubeconfig and real secrets must not be committed.

### Task 4: Verify and Push

**Files:**
- All files created or modified above.

- [ ] Run Helm lint/template checks for new charts where possible.
- [ ] Run shell syntax checks if available.
- [ ] Check git diff for accidental secrets.
- [ ] Commit and push to `origin`.
