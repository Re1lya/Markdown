# Backstage Catalog GitHub Discovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Make Backstage automatically discover generated service catalog files from the GitOps repository.

**Architecture:** Backstage remains a replaceable developer portal. The durable platform contract is the GitOps directory layout, including `catalog/services/<service>/catalog-info.yaml`; Backstage uses GitHub catalog discovery to read that contract instead of requiring manual ConfigMap edits for each service.

**Tech Stack:** Backstage backend new system, `@backstage/plugin-catalog-backend-module-github`, GitHub PAT via `GITHUB_TOKEN`, Bitnami Backstage Helm values.

---

### Task 1: Register GitHub Catalog Provider

**Files:**
- Modify: `apps/backstage-custom/packages/backend/package.json`
- Modify: `apps/backstage-custom/packages/backend/src/index.ts`
- Modify: `apps/backstage-custom/yarn.lock`

- [x] Add dependency `@backstage/plugin-catalog-backend-module-github` to the backend workspace.
- [x] Add `backend.add(import('@backstage/plugin-catalog-backend-module-github'));` after the existing catalog backend module registrations.
- [x] Run `yarn tsc` in `apps/backstage-custom`.

### Task 2: Configure Service Catalog Discovery

**Files:**
- Modify: `manifests/backstage/backstage-values.yaml`

- [x] Add `catalog.providers.github.platformPoc` with organization `Re1lya`, repository filter `Markdown`, catalog path `/crossplane-backstage-poc/catalog/services/*/catalog-info.yaml`, and a short POC scan schedule.
- [x] Keep static file locations for bootstrap entities such as `guest`, `platform-team`, `helloworld`, and `fastapi-demo`.
- [x] Remove the temporary static `fastapi-demo-2` file location and ConfigMap entry after GitHub discovery is verified.

### Task 3: Document Portal Boundary

**Files:**
- Modify: `AGENTS.md`

- [x] Add a section explaining that Backstage is a replaceable client layer.
- [x] State that Crossplane, Argo CD, Tekton, Helm charts, Kubernetes, and GitOps directory contracts are the durable platform layer.
- [x] Document that generated services should be discovered from `crossplane-backstage-poc/catalog/services/*/catalog-info.yaml`.

### Task 4: Build, Deploy, Verify

**Files:**
- Modify if needed: `manifests/backstage/backstage-values.yaml`

- [x] Run `yarn tsc` and `yarn build:backend`.
- [x] Build a new image tag, load it into kind, and update the Backstage Helm values image tag.
- [x] Upgrade or patch Backstage and wait for rollout.
- [x] Verify the Backstage Catalog shows `fastapi-demo-2` after removing its static ConfigMap registration.
