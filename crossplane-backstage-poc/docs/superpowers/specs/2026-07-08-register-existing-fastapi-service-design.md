# Register Existing FastAPI Service Design

## Goal

Add a Backstage Software Template that lets a developer onboard an existing FastAPI repository by opening a GitHub pull request against the platform GitOps repository. After the PR is merged, Argo CD syncs the generated application, Crossplane manages the AppService, and Kubernetes runs the service.

## Chosen Approach

Use Backstage Scaffolder with `publish:github:pull-request`.

The template generates:

- A per-service AppService Helm chart under `gitops/appservices/<serviceName>`.
- A per-service Argo CD Application manifest under `gitops/argocd/<serviceName>-appservice.yaml`.
- A Backstage `catalog-info.yaml` under `catalog/services/<serviceName>/catalog-info.yaml`.

Argo CD gets one app-of-apps Application named `platform-appservices`. It watches `crossplane-backstage-poc/gitops/argocd`, so merged PRs create or update service Applications automatically.

## Developer Flow

1. Open Backstage.
2. Go to Create.
3. Select `Register Existing FastAPI Service`.
4. Fill in service name, GitHub repo URL, context directory, image repository, namespace, and port.
5. Backstage opens a GitHub PR against `Re1lya/Markdown`.
6. Platform owner reviews and merges.
7. Argo CD syncs the new Application.
8. Crossplane reconciles the generated AppService.
9. The service runs on Kubernetes.

## Boundaries

The template does not invent a new application Helm chart per service. It generates a standard thin AppService chart that uses the existing Crossplane Composition and the existing `fastapi-demo` runtime chart.

The first version generates `catalog-info.yaml` and enables the Catalog Import page. Automatic GitHub catalog discovery is intentionally left out because the required catalog GitHub discovery backend module is not installed in this POC.

## Required Configuration

Backstage needs a GitHub token as `GITHUB_TOKEN` so `publish:github:pull-request` can create PRs.

In this POC, reuse the existing GitHub PAT stored in `ci/github-git-auth` by copying it into a `backstage/backstage-github-token` Secret and exposing it through `backstage.extraEnvVars`.

## Validation

- `yarn tsc` passes for the custom Backstage app.
- `yarn build:backend` passes.
- Backstage deploys with image `platform-poc-backstage:0.1.2`.
- `http://localhost:7007/create` loads.
- The Template entity appears in Backstage.
- Argo CD has `platform-appservices` watching `gitops/argocd`.
