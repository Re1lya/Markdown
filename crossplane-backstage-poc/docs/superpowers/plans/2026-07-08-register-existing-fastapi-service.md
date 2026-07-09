# Register Existing FastAPI Service Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Backstage Software Template that opens a GitHub PR to onboard an existing FastAPI service into the GitOps, Argo CD, Crossplane, Helm, and Backstage POC flow.

**Architecture:** Backstage Scaffolder renders a skeleton into a temporary workspace, then uses `publish:github:pull-request` to add generated service files to the platform repository. Argo CD app-of-apps watches generated Application manifests after merge.

**Tech Stack:** Backstage new frontend system, Backstage Scaffolder, GitHub PR action, Argo CD Application, Crossplane AppService, Helm.

---

### Task 1: Enable Backstage Frontend Pages

**Files:**

- Modify: `D:/Markdown/crossplane-backstage-poc/apps/backstage-custom/packages/app/src/App.tsx`

- [ ] Add `@backstage/plugin-scaffolder/alpha` and `@backstage/plugin-catalog-import/alpha` to the feature list.
- [ ] Run `yarn tsc`.

### Task 2: Add Scaffolder Template Files

**Files:**

- Create: `D:/Markdown/crossplane-backstage-poc/apps/backstage-custom/templates/register-existing-fastapi/template.yaml`
- Create: `D:/Markdown/crossplane-backstage-poc/apps/backstage-custom/templates/register-existing-fastapi/skeleton/gitops/appservices/service/Chart.yaml`
- Create: `D:/Markdown/crossplane-backstage-poc/apps/backstage-custom/templates/register-existing-fastapi/skeleton/gitops/appservices/service/values.yaml`
- Create: `D:/Markdown/crossplane-backstage-poc/apps/backstage-custom/templates/register-existing-fastapi/skeleton/gitops/appservices/service/templates/appservice.yaml`
- Create: `D:/Markdown/crossplane-backstage-poc/apps/backstage-custom/templates/register-existing-fastapi/skeleton/gitops/argocd/service-appservice.yaml`
- Create: `D:/Markdown/crossplane-backstage-poc/apps/backstage-custom/templates/register-existing-fastapi/skeleton/catalog/services/service/catalog-info.yaml`

- [ ] Write a Template entity with input fields for service name, owner, source repo, context directory, image repository, namespace, port, and GitOps repo.
- [ ] Use `fetch:template` to render the skeleton.
- [ ] Use `publish:github:pull-request` to open a PR.

### Task 3: Mount Template Into Backstage

**Files:**

- Modify: `D:/Markdown/crossplane-backstage-poc/manifests/backstage/backstage-values.yaml`

- [ ] Add a `register-existing-fastapi-template` ConfigMap in `extraDeploy`.
- [ ] Mount it at `/app/templates/register-existing-fastapi`.
- [ ] Add a Catalog location for `/app/templates/register-existing-fastapi/template.yaml`.
- [ ] Add `GITHUB_TOKEN` from Secret `backstage-github-token`.
- [ ] Bump Backstage image tag to `0.1.2`.

### Task 4: Add Argo CD App-of-Apps

**Files:**

- Create: `D:/Markdown/crossplane-backstage-poc/gitops/argocd/.gitkeep`
- Create: `D:/Markdown/crossplane-backstage-poc/gitops/appservices/.gitkeep`
- Create: `D:/Markdown/crossplane-backstage-poc/catalog/services/.gitkeep`
- Create: `D:/Markdown/crossplane-backstage-poc/manifests/argocd/platform-appservices-application.yaml`

- [ ] Add an Argo CD Application that watches `crossplane-backstage-poc/gitops/argocd`.
- [ ] Apply it to the cluster.

### Task 5: Build, Deploy, and Verify

**Files:**

- Modify: `D:/Markdown/crossplane-backstage-poc/AGENTS.md`
- Modify: `D:/Markdown/crossplane-backstage-poc/POC_GUIDE.md`

- [ ] Copy the existing GitHub PAT Secret into the `backstage` namespace as `backstage-github-token`.
- [ ] Run `yarn tsc`.
- [ ] Run `yarn build:backend`.
- [ ] Build `platform-poc-backstage:0.1.2`.
- [ ] Load it into kind.
- [ ] Helm upgrade Backstage.
- [ ] Verify Backstage `/create` and Catalog Template availability.
- [ ] Update handoff docs.
