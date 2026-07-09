# Agent Handoff: Crossplane + Backstage Local POC

This file is the primary handoff document for agents working on this POC. Keep it updated whenever a step is completed, a decision changes, a command fails, or a new constraint appears.

## User Goal

The user wants to complete a local POC for the architecture described in:

- `D:/Markdown/CI CD Pipeline方案.md`
- `D:/Markdown/Backstage+crossplane.markdown`

The POC should show that:

1. A local multi-node Kubernetes cluster can run the platform components.
2. Crossplane can manage application/platform resources through Composition.
3. Backstage can display a service managed by Crossplane.
4. A simple HelloWorld service can be reached locally.

## Current Understanding

The user already has `kind` installed locally.

The preferred POC flow is:

```text
Create kind multi-node cluster
Install Crossplane with Helm
Install Crossplane provider-kubernetes or provider-helm as needed
Deploy Backstage
Configure Backstage Kubernetes plugin
Create a PlatformService / AppService Composition
Use Crossplane to create a HelloWorld Deployment and Service
Label Kubernetes resources for Backstage matching
Register a Backstage Catalog entity for HelloWorld
Verify Backstage shows the service runtime status
```

## Key Clarifications Already Made

### Ingress Controller

An Ingress Controller is the component that makes Kubernetes `Ingress` resources actually route HTTP traffic from outside the cluster to internal Services.

For the first local POC, Ingress is optional. `kubectl port-forward` is acceptable and simpler.

### Crossplane Helm Provider

`provider-helm` lets Crossplane create and manage Helm releases through resources such as:

```yaml
apiVersion: helm.crossplane.io/v1beta1
kind: Release
```

Use it when Crossplane should install a Helm chart.

### Crossplane Kubernetes Provider

`provider-kubernetes` lets Crossplane create and manage Kubernetes objects directly.

For HelloWorld, this is likely simpler than creating a Helm chart. The Composition can directly create:

- Namespace
- Deployment
- Service
- Optional Ingress

### RBAC

RBAC is Kubernetes permission control. It defines which ServiceAccount can perform which actions on which resources.

For the POC, broad permissions are acceptable. For production, these permissions must be narrowed.

### Backstage Matching

Backstage usually does not display arbitrary cluster resources by magic. A Backstage Catalog entity is registered first, then Backstage Kubernetes plugin uses annotations to query matching Kubernetes resources.

Common entity annotation:

```yaml
metadata:
  annotations:
    backstage.io/kubernetes-id: helloworld
```

Matching Kubernetes resource label:

```yaml
metadata:
  labels:
    backstage.io/kubernetes-id: helloworld
```

Alternative entity annotation:

```yaml
metadata:
  annotations:
    backstage.io/kubernetes-label-selector: 'app=helloworld'
```

## Architecture Decision

Use the smallest useful POC:

```text
Backstage installed as a platform component
HelloWorld created by Crossplane Composition
Backstage displays HelloWorld through Kubernetes plugin label matching
```

Do not start with a frontend/backend HelloWorld chart. That would test application-to-application connectivity, but the user's current goal is to validate Crossplane-managed service visibility in Backstage.

## Portal Boundary Decision

Backstage is the current developer portal for this POC, not the durable platform core. Treat it as a replaceable client layer.

Durable platform core:

- Kubernetes runtime
- Crossplane `AppService` API and Composition
- Helm charts and chart values
- Tekton CI pipelines and EventListeners
- BuildKit image builds
- Argo CD GitOps sync
- GitOps repository directory contract

Replaceable client layer:

- Backstage UI
- Backstage Scaffolder templates
- Backstage Catalog rendering
- Backstage plugin-specific configuration

The stable contract between a client and the platform is the generated GitOps file layout:

```text
crossplane-backstage-poc/
  catalog/services/<service>/catalog-info.yaml
  gitops/appservices/<service>/Chart.yaml
  gitops/appservices/<service>/values.yaml
  gitops/appservices/<service>/templates/appservice.yaml
  gitops/argocd/<service>-appservice.yaml
  gitops/tekton/<service>-ci.yaml
```

If Backstage is replaced later by a custom web portal, CLI, TUI, or another developer portal, the replacement should generate or update the same files and keep the same platform API contract. Crossplane, Tekton, Argo CD, Helm, and Kubernetes should not depend on Backstage internals.

Catalog automation direction:

- Generated services must place their entity metadata at `crossplane-backstage-poc/catalog/services/<service>/catalog-info.yaml`.
- Backstage should discover these files with GitHub Catalog Discovery rather than requiring a manual ConfigMap edit for every new service.
- Argo CD webhook and Backstage Catalog discovery solve different problems:
  - Argo CD webhook shortens GitOps-to-deploy latency.
  - Backstage Catalog discovery makes newly merged service metadata appear in the developer portal.

## Recommended Implementation Path

### Phase 1: Local Cluster

Create a multi-node kind cluster named `platform-poc`.

Expected result:

```bash
kubectl get nodes
```

shows one control-plane node and two worker nodes.

### Phase 2: Crossplane

Install Crossplane with Helm into namespace `crossplane-system`.

Expected result:

```bash
kubectl get pods -n crossplane-system
```

shows Crossplane pods running.

### Phase 3: Provider Selection

For Backstage:

- Use Helm directly at first, or use Crossplane `provider-helm` if the user specifically wants Backstage managed by Crossplane from the start.

For HelloWorld:

- Prefer Crossplane `provider-kubernetes`, because it can create simple Kubernetes resources directly without introducing a custom HelloWorld chart.

### Phase 4: Backstage

Deploy Backstage and enable/configure the Kubernetes plugin.

Backstage should be able to access the local cluster API using a service account token or local cluster configuration.

### Phase 5: HelloWorld Composition

Create a Crossplane abstraction such as:

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

The Composition should create Kubernetes resources labeled with:

```yaml
backstage.io/kubernetes-id: helloworld
```

### Phase 6: Backstage Catalog Entity

Register a `catalog-info.yaml` entity:

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

Expected result:

Backstage service page shows Kubernetes resources for HelloWorld.

## Open Questions

1. Should Backstage itself be installed directly with Helm first, or also managed by Crossplane through `provider-helm`?
2. Should the first HelloWorld use `provider-kubernetes` direct object creation, or should it intentionally use `provider-helm` to prove Helm-based app delivery?
3. Should Ingress be part of the first POC, or should local access use `kubectl port-forward`?

## Current Progress Log

### 2026-07-07

- Read `D:/Markdown/CI CD Pipeline方案.md`.
- Read `D:/Markdown/Backstage+crossplane.markdown`.
- Clarified that the initial POC should focus on Crossplane-managed service visibility in Backstage.
- Clarified that a frontend/backend HelloWorld chart is not required for the first POC.
- Created project directory: `D:/Markdown/crossplane-backstage-poc`.
- Created this handoff file.
- Confirmed local tools:
  - `kind v0.32.0`
  - `kubectl client v1.34.1`
  - `helm v4.2.2`
- Existing kind clusters before starting the POC:
  - `dev`
  - `kind`
- Created kind config:
  - `D:/Markdown/crossplane-backstage-poc/configs/kind-platform-poc.yaml`
- Created implementation plan:
  - `D:/Markdown/crossplane-backstage-poc/plans/2026-07-07-local-poc-implementation-plan.md`
- Created local kind cluster `platform-poc`.
- Verified cluster API:
  - Kubernetes control plane: `https://127.0.0.1:3046`
  - Context: `kind-platform-poc`
- Verified nodes:
  - `platform-poc-control-plane` Ready, Kubernetes `v1.36.1`
  - `platform-poc-worker` Ready, Kubernetes `v1.36.1`
  - `platform-poc-worker2` Ready, Kubernetes `v1.36.1`
- Installed Crossplane into namespace `crossplane-system`.
- Verified Crossplane pods:
  - `crossplane-67c7c46bfc-spnvm` Ready `1/1`, Running
  - `crossplane-rbac-manager-58d8596898-ms9ff` Ready `1/1`, Running
- Created provider manifest:
  - `D:/Markdown/crossplane-backstage-poc/manifests/crossplane/provider-kubernetes.yaml`
- First attempt to apply `provider-kubernetes` failed because `spec.package` did not include a version tag.
- Root cause:
  - Current Crossplane package validation requires a fully qualified package image including tag or digest.
  - The original value was `xpkg.upbound.io/crossplane-contrib/provider-kubernetes`.
- Fix applied:
  - Updated package to `xpkg.upbound.io/crossplane-contrib/provider-kubernetes:v1.2.1`.
  - Version source: Upbound Marketplace latest listing for `crossplane-contrib/provider-kubernetes`.
- Applied `provider-kubernetes` successfully.
- Verified provider health:
  - `provider-kubernetes` Installed `True`, Healthy `True`
  - Package `xpkg.upbound.io/crossplane-contrib/provider-kubernetes:v1.2.1`
- Verified provider pod:
  - `provider-kubernetes-f6665ef36536-84646f8968-vtnd7` Ready `1/1`, Running
- Created ProviderConfig manifest:
  - `D:/Markdown/crossplane-backstage-poc/manifests/crossplane/provider-config-kubernetes.yaml`
- User chose to continue with the platformized path:
  - Helm installs platform components such as Crossplane.
  - Crossplane manages application delivery.
  - Applications are delivered through Helm Charts via `provider-helm`.
  - Backstage displays applications through Catalog entities and Kubernetes label matching.
- Confirmed Crossplane image:
  - `xpkg.crossplane.io/crossplane/crossplane:v2.3.3`
- Created Helm provider manifests:
  - `D:/Markdown/crossplane-backstage-poc/manifests/crossplane/provider-helm.yaml`
  - `D:/Markdown/crossplane-backstage-poc/manifests/crossplane/provider-config-helm.yaml`
- Applied `provider-helm` successfully.
- Verified provider health:
  - `provider-helm` Installed `True`, Healthy `True`
  - Package `xpkg.upbound.io/crossplane-contrib/provider-helm:v1.3.0`
- Verified provider pod:
  - `provider-helm-97e4d1e72f3f-75bc764df5-hwb4b` Ready `1/1`, Running
- Created `provider-helm` ProviderConfig:
  - `default`
- Created `provider-helm-admin` ClusterRoleBinding:
  - `crossplane-system/provider-helm-97e4d1e72f3f`
- Created HelloWorld Helm Chart:
  - `D:/Markdown/crossplane-backstage-poc/charts/helloworld/Chart.yaml`
  - `D:/Markdown/crossplane-backstage-poc/charts/helloworld/values.yaml`
  - `D:/Markdown/crossplane-backstage-poc/charts/helloworld/templates/deployment.yaml`
  - `D:/Markdown/crossplane-backstage-poc/charts/helloworld/templates/service.yaml`
- Created local in-cluster Helm repo support:
  - `D:/Markdown/crossplane-backstage-poc/scripts/publish-helloworld-chart-repo.ps1`
  - `D:/Markdown/crossplane-backstage-poc/manifests/helm-repo/helm-repo-server.yaml`
- Verified HelloWorld Helm Chart:
  - `helm lint` passed.
  - `helm template` rendered Deployment and Service.
  - Rendered resources include `backstage.io/kubernetes-id: "helloworld"`.
- Published HelloWorld Chart into in-cluster Helm repository:
  - Namespace: `platform-system`
  - Service: `helm-repo`
  - URL inside cluster: `http://helm-repo.platform-system.svc.cluster.local`
  - Chart URL: `http://helm-repo.platform-system.svc.cluster.local/helloworld-0.1.0.tgz`
- Verified the in-cluster Helm repository by curling `index.yaml` from an ephemeral pod.
- Crossplane v2 requires Pipeline mode Composition with composition functions.
- Created composition function manifest:
  - `D:/Markdown/crossplane-backstage-poc/manifests/crossplane/function-patch-and-transform.yaml`
- Created platform API manifests:
  - `D:/Markdown/crossplane-backstage-poc/manifests/platform/appservice-xrd.yaml`
  - `D:/Markdown/crossplane-backstage-poc/manifests/platform/appservice-composition.yaml`
  - `D:/Markdown/crossplane-backstage-poc/manifests/platform/helloworld-appservice.yaml`
- Applied `function-patch-and-transform`; it became Installed `True`, Healthy `True`.
- Applied `AppService` XRD, Composition, and `helloworld` AppService.
- First reconcile failed:
  - `AppService` Synced `False`
  - Error: `cannot apply cluster scoped composed resource "helm-release" (a Release named ) for a namespaced composite resource`
- Root cause:
  - `AppService` is a namespaced XR in Crossplane v2.
  - The Composition attempted to create cluster-scoped `helm.crossplane.io/v1beta1 Release`.
  - Crossplane v2 does not allow a namespaced composite to compose cluster-scoped managed resources.
- Fix prepared:
  - Added `D:/Markdown/crossplane-backstage-poc/manifests/crossplane/cluster-provider-config-helm-m.yaml`.
  - Updated Composition to use namespaced managed resource API `helm.m.crossplane.io/v1beta1 Release`.
  - Updated Release `providerConfigRef.kind` to `ClusterProviderConfig`.
- Applied the fix successfully.
- Current successful state:
  - `AppService` `default/helloworld` is `SYNCED=True`, `READY=True`.
  - Crossplane generated namespaced Helm Release `default/helloworld-600ff7d5fe3e`.
  - Helm Release is `SYNCED=True`, `READY=True`, `STATE=deployed`, `REVISION=1`, `DESCRIPTION=Install complete`.
  - Namespace `demo` exists.
  - Deployment `demo/helloworld` is available `1/1`.
  - Pod `demo/helloworld-bc7fbfd8-vg7rx` is Running `1/1`.
  - Service `demo/helloworld` exists on port `80`.
  - Deployment, Pod, and Service all include label `backstage.io/kubernetes-id=helloworld`.
- In-cluster curl verification was executed with an ephemeral `curlimages/curl` pod. The command exited successfully, but PowerShell did not show the response body inline. If visible output is needed, run a log-based check or local `kubectl port-forward`.

### 2026-07-08

- Continued with Backstage Helm deployment.
- Added Backstage Helm repo:
  - `https://backstage.github.io/charts`
- Confirmed Backstage chart version:
  - `backstage/backstage` chart `2.8.2`
- Created Backstage values file:
  - `D:/Markdown/crossplane-backstage-poc/manifests/backstage/backstage-values.yaml`
- Values file configures:
  - Backstage app title `Platform POC`
  - Local base URL `http://localhost:7007`
  - Built-in PostgreSQL dependency enabled
  - Backstage ServiceAccount `backstage`
  - Catalog ConfigMap containing `helloworld` entity
  - Catalog location mounted at `/app/catalog/helloworld-catalog-info.yaml`
- Installed Backstage:
  - Release: `backstage`
  - Namespace: `backstage`
  - Chart: `backstage/backstage`
  - Chart version: `2.8.2`
- Initial rollout timed out because Backstage started before PostgreSQL was ready.
- Root cause from logs:
  - Backstage plugin startup failed to connect to PostgreSQL with `ECONNREFUSED 10.96.71.2:5432`.
  - PostgreSQL later became Ready, but the first Backstage pod stayed unready.
- Fix applied:
  - Deleted the Backstage pod so Deployment recreated it after PostgreSQL was ready.
- Current Backstage status:
  - `backstage/backstage-5749866799-4ng4h` Ready `1/1`, Running
  - `backstage/backstage-postgresql-0` Ready `1/1`, Running
- User asked to configure the Backstage Kubernetes plugin permissions.
- Added Kubernetes plugin configuration to Backstage app config:
  - `kubernetes.serviceLocatorMethod.type: multiTenant`
  - Cluster name: `platform-poc`
  - Cluster URL from inside the pod: `https://kubernetes.default.svc`
  - Auth provider: `serviceAccount`
  - `skipTLSVerify: true`
  - `skipMetricsLookup: true`
- Added `backstage.io/kubernetes-namespace: demo` to the `helloworld` Catalog entity.
- Created Backstage Kubernetes read-only RBAC:
  - `D:/Markdown/crossplane-backstage-poc/manifests/backstage/backstage-kubernetes-rbac.yaml`
  - ClusterRole: `backstage-kubernetes-read-only`
  - ClusterRoleBinding: `backstage-kubernetes-read-only`
  - Subject: `system:serviceaccount:backstage:backstage`
- RBAC verification:
  - `kubectl auth can-i list pods --as=system:serviceaccount:backstage:backstage -n demo` -> yes
  - `kubectl auth can-i list deployments.apps --as=system:serviceaccount:backstage:backstage -n demo` -> yes
  - `kubectl auth can-i list services --as=system:serviceaccount:backstage:backstage -n demo` -> yes
- First Backstage Helm upgrade failed because the existing PostgreSQL secret used key `password`, while the chart expected `user-password` on upgrade.
- Fix applied:
  - Added `postgresql.auth.secretKeys.userPasswordKey: password` to `backstage-values.yaml`.
- Backstage Helm upgrade then succeeded:
  - Release revision: `2`
  - New Pod: `backstage-6d4468cdfb-4hlbj`
  - Pod Ready `1/1`, Running
- Backstage logs confirmed:
  - `Initializing Kubernetes backend`
  - `Plugin initialization complete`
- Local port-forward was restarted:
  - `kubectl port-forward svc/backstage -n backstage 7007:7007`
- Direct Catalog API request returned `401`, which means the API is reachable but protected by Backstage auth. Use the web UI guest sign-in to inspect the Catalog entity.
- User saw Backstage frontend 404 at `http://localhost:7007/` and a toast:
  - `Failed to load user identity: ResponseError: Request failed with 401 Unauthorized`
- Investigation:
  - `http://localhost:7007/catalog` returned `200`, so the app was reachable and the root `/` route was just not configured by the default Backstage image.
  - `http://localhost:7007/api/auth/guest/refresh` returned `403`, meaning guest auth was configured but not allowed in the production runtime.
  - Logs showed `Configuring auth provider: guest`.
  - Logs also showed `User` and `Group` entities were rejected as not allowed for the file catalog location.
- Fix applied:
  - Updated `backstage-values.yaml` guest provider:
    - `userEntityRef: user:default/guest`
    - `dangerouslyAllowOutsideDevelopment: true`
  - Added catalog entities:
    - `guest-user.yaml`
    - `platform-team.yaml`
  - Added catalog rules allowing:
    - `Component`
    - `API`
    - `Resource`
    - `System`
    - `Domain`
    - `Location`
    - `User`
    - `Group`
- Backstage Helm upgraded successfully to revision `4`.
- Verification:
  - `http://localhost:7007/catalog` returned `200`.
  - `http://localhost:7007/api/auth/guest/refresh` returned `200`.
  - Authenticated Catalog API lookup using the guest token returned `Component:default/helloworld`.
- Current browser guidance:
  - Use `http://localhost:7007/catalog`, not `/`.
  - If the old 401 toast remains, hard refresh the browser tab or open `/catalog` in a fresh tab.
- User opened `http://localhost:7007/catalog/default/component/helloworld` and saw only standard Catalog cards such as About, Depends on components, Depends on resources, and Has subcomponents.
- Investigation:
  - The `helloworld` Catalog entity has the correct annotations:
    - `backstage.io/kubernetes-id: helloworld`
    - `backstage.io/kubernetes-namespace: demo`
  - Kubernetes resources in namespace `demo` have the correct label:
    - `backstage.io/kubernetes-id=helloworld`
  - Backstage Kubernetes backend API was tested directly with a guest token:
    - `POST /api/kubernetes/services/helloworld`
    - Response status: `200`
    - Returned resources:
      - `pods: 1`
      - `services: 1`
      - `deployments: 1`
      - `replicasets: 1`
      - Other optional resource types: `0`
  - Saved API response:
    - `D:/Markdown/crossplane-backstage-poc/dist/kubernetes-api-helloworld.json`
- Conclusion:
  - Backstage Kubernetes backend integration is working.
  - RBAC, cluster config, entity annotations, and Kubernetes labels are correct.
  - The default `ghcr.io/backstage/backstage:latest` frontend page currently displayed in the browser does not include the Kubernetes entity page/card/tab.
- Remaining choice:
  - For a lightweight POC, treat the direct Kubernetes backend API result as proof that Backstage can query and associate runtime resources.
  - For a full visual POC, build a custom Backstage app image that includes the Kubernetes frontend plugin components on the entity page, then deploy that image with the existing Helm chart.
- User chose to complete the frontend visual integration.
- Created custom Backstage app:
  - `D:/Markdown/crossplane-backstage-poc/apps/backstage-custom`
- Added Kubernetes frontend plugin to the custom app:
  - File: `D:/Markdown/crossplane-backstage-poc/apps/backstage-custom/packages/app/src/App.tsx`
  - Added `@backstage/plugin-kubernetes/alpha`
  - Added `kubernetesPlugin` to `createApp({ features })`
- Environment checks:
  - Node.js `v22.19.0`
  - npm `11.6.3`
  - Docker `28.5.2`
  - Global Yarn was not installed, so Corepack was used.
- Dependency install:
  - `corepack prepare yarn@4.13.0 --activate`
  - `yarn install --no-immutable`
  - Completed with peer dependency warnings only.
- Verification:
  - `yarn tsc` passed.
  - `yarn build:backend` passed and generated:
    - `apps/backstage-custom/packages/backend/dist/bundle.tar.gz`
    - `apps/backstage-custom/packages/backend/dist/skeleton.tar.gz`
- Docker image build attempt:
  - Command attempted: `yarn build-image --tag platform-poc-backstage:0.1.0`
  - The tool execution was aborted before completion.
  - No `platform-poc-backstage:0.1.0` image exists.
  - Kubernetes deployment is still using `ghcr.io/backstage/backstage:latest`.
  - Current cluster state remains safe:
    - Backstage deployment ready `1/1`
    - Backstage PostgreSQL ready `1/1`
- Current diagnosis for the abort:
  - The interruption happened during Docker image construction, after app compilation succeeded.
  - Docker Desktop and BuildKit are running.
  - No active long-running custom Backstage image build was found after the abort.
  - Build cache is almost empty, so the aborted build did not complete substantial cached layers.
- Safest next step:
  - Run Docker build directly instead of through Yarn indirection.
  - Capture full output to `D:/Markdown/crossplane-backstage-poc/dist/backstage-image-build.log`.
  - Do not update Helm or Kubernetes until the image exists locally and has been loaded into kind.
- Root cause confirmed:
  - Direct Docker build with the generated `packages/backend/Dockerfile` failed while pulling `node:24-trixie-slim` from Docker Hub.
  - Error:
    - `failed to fetch anonymous token`
    - `dial tcp 108.160.166.9:443: connectex`
  - Full log:
    - `D:/Markdown/crossplane-backstage-poc/dist/backstage-image-build.log`
- Safe fix:
  - Pulled `ghcr.io/backstage/backstage:latest` successfully.
  - Created overlay Dockerfile:
    - `D:/Markdown/crossplane-backstage-poc/apps/backstage-custom/Dockerfile.overlay`
  - The overlay image uses the already-available GHCR Backstage image and replaces the built app/backend bundle.
  - Built image successfully:
    - `platform-poc-backstage:0.1.0`
    - Image ID `02dae071a23d`
    - Size `1.82GB`
  - Build log:
    - `D:/Markdown/crossplane-backstage-poc/dist/backstage-overlay-image-build.log`
  - Loaded image into kind cluster `platform-poc` on all three nodes.
  - Updated Backstage values to use local image:
    - `registry: ""`
    - `repository: platform-poc-backstage`
    - `tag: "0.1.0"`
    - `pullPolicy: IfNotPresent`

## Next Immediate Step

Verify Backstage UI locally:

```powershell
kubectl port-forward svc/backstage -n backstage 7007:7007
```

Open:

```text
http://localhost:7007
```

Then verify the `helloworld` catalog entity is visible. After that, configure Backstage Kubernetes plugin access so it can show the `demo/helloworld` Deployment, Pod, and Service by matching `backstage.io/kubernetes-id=helloworld`.

Previously discussed path choices:

```text
A. Fastest path:
   Install Backstage directly with Helm.
   Use Crossplane provider-kubernetes for HelloWorld.

B. More platform-faithful path:
   Use Crossplane provider-helm to manage Backstage.
   Use Crossplane provider-kubernetes for HelloWorld.

C. Helm-everything path:
   Use Crossplane provider-helm for both Backstage and HelloWorld.
```

Recommended: B.

## 2026-07-08 Runtime Check: Backstage Shows A Pod Error

User reported that the Backstage Kubernetes page for:

```text
http://localhost:7007/catalog/default/component/helloworld/kubernetes
```

appeared to show one pod error.

Checked the live cluster state:

```powershell
kubectl get pod -n demo -l backstage.io/kubernetes-id=helloworld
```

Current result:

```text
helloworld-bc7fbfd8-vg7rx   1/1   Running   1 (110m ago)
```

Diagnosis:

- The HelloWorld pod is currently healthy:
  - `phase=Running`
  - `ready=true`
  - liveness/readiness probes are returning HTTP 200.
- There is one historical restart from about 110 minutes earlier.
- `kubectl describe pod` shows the previous container state as:
  - `Last State: Terminated`
  - `Reason: Unknown`
  - `Exit Code: 255`
- There are no current warning events in the `demo` namespace.
- `kubectl logs` only shows successful kube-probe requests.
- Backstage itself is also healthy:
  - `backstage-7bf5c65c5b-j9gsg` ready `1/1`
  - `backstage-postgresql-0` ready `1/1`

Conclusion:

This is not an active application failure. Backstage is likely surfacing the historical restart count or terminated last state. No immediate fix is required unless the restart count keeps increasing.

If this happens again, rerun:

```powershell
kubectl get pod -n demo -l backstage.io/kubernetes-id=helloworld
kubectl describe pod -n demo -l backstage.io/kubernetes-id=helloworld
kubectl logs -n demo -l backstage.io/kubernetes-id=helloworld --tail=80
kubectl get events -n demo --sort-by=.lastTimestamp
```

For Windows screenshots, if `Ctrl+Alt+A` stops responding, use the built-in shortcut:

```text
Win + Shift + S
```

`Ctrl+Alt+A` is usually owned by a separate app or screenshot tool, so it can stop working if that process is not running, loses focus, or its hotkey is captured by another app.

## 2026-07-08 Next Step Decision: Add Argo CD Before Tekton

Current POC has already proven:

- kind multi-node cluster works.
- Crossplane v2 is installed and healthy.
- provider-helm and provider-kubernetes are installed and healthy.
- A platform `AppService` composition can create a Helm-managed HelloWorld service.
- Backstage is installed, customized, and can show the HelloWorld Kubernetes runtime objects.

Recommended next milestone:

Add Argo CD as the CD/GitOps layer before adding Tekton CI.

Reason:

- Argo CD has a clear, visible result: it watches Git state and syncs Kubernetes/Helm manifests into the cluster.
- It fits the platform story better than jumping straight into CI:
  - Crossplane defines platform abstractions.
  - Argo CD continuously applies desired application/platform state.
  - Backstage shows catalog and runtime visibility.
  - Tekton later builds/tests/images and updates Git or image tags.

Target next POC flow:

```text
Git repo/path with desired state
        |
        v
Argo CD Application watches it
        |
        v
Syncs Crossplane claim / Helm chart / Kubernetes manifests
        |
        v
Crossplane reconciles AppService
        |
        v
HelloWorld runs in demo namespace
        |
        v
Backstage shows service + Kubernetes runtime
```

Do not add Tekton yet unless Argo CD sync is already proven. Tekton should be the next layer after this:

```text
GitHub push -> Tekton CI builds/tests/image -> updates Git desired state -> Argo CD deploys
```

Immediate implementation options:

1. Install Argo CD with Helm, ideally managed by Crossplane provider-helm for platform consistency.
2. Create an Argo CD `Application` that points to this repo's desired-state folder.
3. Start with Argo CD syncing the HelloWorld `AppService` claim, not raw Deployment YAML.
4. Verify by changing desired state in Git/manifests, syncing Argo CD, and confirming:
   - Crossplane claim is healthy.
   - Helm Release is healthy.
   - demo/helloworld Deployment rolls out.
   - Backstage still shows runtime state.

## 2026-07-08 Argo CD POC Completed

Implemented the next platform milestone: Argo CD now manages the HelloWorld `AppService`.

Files added:

- `D:/Markdown/crossplane-backstage-poc/manifests/argocd/argocd-release.yaml`
  - Crossplane-managed Helm Release for Argo CD.
  - Chart: `argo-cd`
  - Repository: `https://argoproj.github.io/argo-helm`
  - Version: `10.1.2`
  - Namespace: `argocd`
  - Dex disabled for local POC.
  - Server runs with `--insecure` so local HTTP port-forward works.
- `D:/Markdown/crossplane-backstage-poc/charts/helloworld-appservice/`
  - Small Helm chart that renders only the Crossplane `AppService` claim.
  - It does not create Pods directly.
  - Argo CD syncs this chart, then Crossplane reconciles the AppService into a provider-helm Release.
- `D:/Markdown/crossplane-backstage-poc/manifests/argocd/helloworld-appservice-application.yaml`
  - Argo CD `Application`.
  - Source: in-cluster Helm repo `http://helm-repo.platform-system.svc.cluster.local`
  - Chart: `helloworld-appservice`
  - `targetRevision: 0.1.*`
  - Destination namespace: `default`
- Updated `D:/Markdown/crossplane-backstage-poc/scripts/publish-helloworld-chart-repo.ps1`
  - Now packages both:
    - `helloworld`
    - `helloworld-appservice`

Commands run:

```powershell
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update argo
helm lint charts/helloworld-appservice
helm template helloworld-appservice charts/helloworld-appservice
powershell -ExecutionPolicy Bypass -File ./scripts/publish-helloworld-chart-repo.ps1
kubectl apply -f manifests/argocd/argocd-release.yaml
kubectl apply -f manifests/argocd/helloworld-appservice-application.yaml
```

Current verified state:

```text
Argo CD Helm Release:
default/argocd
SYNCED=True
READY=True
STATE=deployed
REVISION=1

Argo CD Application:
argocd/helloworld-appservice
SYNC STATUS=Synced
HEALTH STATUS=Healthy

Crossplane AppService:
default/helloworld
SYNCED=True
READY=True

HelloWorld provider-helm Release:
default/helloworld-600ff7d5fe3e
SYNCED=True
READY=True
STATE=deployed
REVISION=2

HelloWorld runtime:
demo/helloworld Deployment 1/1
demo/helloworld Pod 1/1 Running, 0 restarts
```

Important behavior proven:

```text
Argo CD Application
  -> syncs helloworld-appservice Helm chart
  -> configures Crossplane AppService default/helloworld
  -> Crossplane updates provider-helm Release
  -> provider-helm upgrades demo/helloworld Helm release
  -> Kubernetes rolls a new HelloWorld Pod
```

During verification, provider-helm temporarily showed:

```text
helloworld Release READY=False, STATE=deployed
```

Actual Helm and Kubernetes runtime were healthy:

```powershell
helm status helloworld -n demo
kubectl get deploy,pod,svc -n demo -l backstage.io/kubernetes-id=helloworld
```

The safe fix was to restart the provider-helm controller Pod:

```powershell
kubectl delete pod -n crossplane-system -l pkg.crossplane.io/provider=provider-helm
```

After the provider Pod restarted, the Crossplane Release and AppService both returned to `READY=True`.

Argo CD UI:

```text
http://localhost:8080
```

Port-forward started with:

```powershell
kubectl port-forward svc/argocd-server -n argocd 8080:80
```

Current background port-forward PID from this run:

```text
29616
```

Login:

```text
username: admin
password: retrieve with:
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | %{ [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_)) }
```

Architectural answer:

- Argo CD itself is an application/platform service running on Kubernetes.
- In this POC it is managed by Crossplane provider-helm as a Helm Release.
- Argo CD then manages application desired state.
- The desired state is not raw Deployment YAML. It is the platform-level `AppService` claim.
- Crossplane remains responsible for turning `AppService` into the actual Helm release and Kubernetes resources.

## 2026-07-08 Tekton + GitHub Webhook Smoke Completed

Installed Tekton control plane:

```powershell
kubectl apply -f https://infra.tekton.dev/tekton-releases/pipeline/latest/release.yaml
kubectl apply -f https://storage.googleapis.com/tekton-releases/triggers/latest/release.yaml
kubectl apply -f https://storage.googleapis.com/tekton-releases/triggers/latest/interceptors.yaml
```

Observed behavior:

- Tekton Pipelines and Triggers controllers are running in the `tekton-pipelines` namespace.
- `tekton-triggers` namespace is not used by this current release layout.
- Remote resolvers run in `tekton-pipelines-resolvers`.

Created GitHub webhook smoke resources:

- `D:/Markdown/crossplane-backstage-poc/manifests/tekton/github-webhook-smoke.yaml`
  - Namespace: `ci`
  - Secret: `github-webhook-secret`
  - ServiceAccount/RBAC: `tekton-triggers-github`
  - Task: `github-push-smoke`
  - Pipeline: `github-push-smoke`
  - TriggerBinding: `github-push-binding`
  - TriggerTemplate: `github-push-template`
  - EventListener: `github-listener`
- `D:/Markdown/crossplane-backstage-poc/scripts/start-github-webhook-tunnel.ps1`
  - Starts `kubectl port-forward svc/el-github-listener -n ci 8081:8080`
  - Starts `cloudflared tunnel --url http://localhost:8081`

RBAC issue encountered:

- EventListener initially entered `CrashLoopBackOff`.
- Root cause from logs:
  - ServiceAccount `ci/tekton-triggers-github` could not list/watch `eventlisteners`, `triggerbindings`, `triggertemplates`, `triggers`, `interceptors`, `clusterinterceptors`, and `clustertriggerbindings`.
- Fixed by adding namespaced Trigger read permissions and a cluster-scoped read-only ClusterRole/ClusterRoleBinding for cluster interceptors/bindings.

Current verified state:

```text
EventListener ci/github-listener:
READY=True
AVAILABLE=True
ADDRESS=http://el-github-listener.ci.svc.cluster.local:8080

Service:
ci/el-github-listener
ClusterIP
Ports: 8080, 9000
```

Local signed webhook smoke test:

```text
POST http://localhost:8081
X-GitHub-Event: push
X-Hub-Signature-256: valid HMAC SHA256
```

Result:

```text
HTTP 202
PipelineRun github-push-smoke-5j8ht Succeeded
TaskRun github-push-smoke-5j8ht-smoke Succeeded
```

Smoke task logs:

```text
GitHub webhook reached Tekton.
repo_url=https://github.com/Re1lya/Markdown.git
git_ref=refs/heads/main
commit_sha=0000000000000000000000000000000000000000
pusher=local-smoke
```

Current background port-forward PID from this run:

```text
75644
```

cloudflared status:

- `cloudflared` was not found in PowerShell PATH.
- User should install it locally before running the tunnel script.
- Recommended Windows install:

```powershell
winget install --id Cloudflare.cloudflared
```

GitHub webhook settings for the POC:

```text
Payload URL: the https://*.trycloudflare.com URL printed by cloudflared
Content type: application/json
Secret: platform-poc-webhook-secret
Events: Just the push event
Active: checked
```

Important reminder for future sessions:

- The current setup uses a cloudflared quick tunnel.
- A quick tunnel URL is temporary and is only valid while the PowerShell/cloudflared process is running.
- If the terminal window is closed, the computer restarts, or cloudflared exits, the old `https://*.trycloudflare.com` URL should be treated as invalid.
- When resuming this experiment after a long break, remind the user to run:

```powershell
cd D:\Markdown\crossplane-backstage-poc
powershell -ExecutionPolicy Bypass -File .\scripts\start-github-webhook-tunnel.ps1
```

- Then copy the newly printed `https://*.trycloudflare.com` URL into the GitHub webhook Payload URL.
- The GitHub webhook secret remains:

```text
platform-poc-webhook-secret
```

- The target repository webhook page for this POC is:

```text
https://github.com/Re1lya/Markdown/settings/hooks
```

- Do not assume an old trycloudflare URL still works.
- A fixed URL would require a Cloudflare named tunnel and DNS setup; that is outside the current quick local POC.

Next CI/CD milestone:

- Replace the smoke Pipeline with a real build Pipeline:
  - clone GitHub repo
  - run tests
  - build container image
  - push image to GHCR
  - update GitOps/AppService values or chart version
  - let Argo CD sync the updated desired state

## 2026-07-08 FastAPI Demo CI/CD Target Added

User chose not to use the existing `xingang-community` Java project for the first real CI/CD test. Instead, a minimal Python/FastAPI service was created for a cleaner POC.

FastAPI app:

- `D:/Markdown/crossplane-backstage-poc/apps/fastapi-demo/requirements.txt`
- `D:/Markdown/crossplane-backstage-poc/apps/fastapi-demo/requirements-dev.txt`
- `D:/Markdown/crossplane-backstage-poc/apps/fastapi-demo/app/main.py`
- `D:/Markdown/crossplane-backstage-poc/apps/fastapi-demo/tests/test_app.py`
- `D:/Markdown/crossplane-backstage-poc/apps/fastapi-demo/Dockerfile`
- `D:/Markdown/crossplane-backstage-poc/apps/fastapi-demo/.dockerignore`

TDD evidence:

- First test run failed with:
  - `ModuleNotFoundError: No module named 'app'`
- After adding the minimal FastAPI app:
  - `python -m pytest -q`
  - Result: `2 passed`

Docker image:

- Initial base image `python:3.12-slim` failed because Docker Hub token fetch timed out.
- Fixed by using:
  - `public.ecr.aws/docker/library/python:3.12-slim`
- Built locally:
  - `ghcr.io/re1lya/fastapi-demo:latest`
- Loaded into kind cluster `platform-poc`.

FastAPI Helm chart:

- `D:/Markdown/crossplane-backstage-poc/charts/fastapi-demo/`
- Creates:
  - Deployment
  - ClusterIP Service
- Uses:
  - `image.repository`
  - `image.tag`
  - `backstage.io/kubernetes-id: fastapi-demo`

FastAPI AppService chart:

- `D:/Markdown/crossplane-backstage-poc/charts/fastapi-demo-appservice/`
- Renders only a Crossplane `AppService`.
- Argo CD syncs this chart.
- Crossplane turns the AppService into a provider-helm Release.

Platform abstraction updated:

- `D:/Markdown/crossplane-backstage-poc/manifests/platform/appservice-xrd.yaml`
  - Added optional:
    - `spec.chartName`
    - `spec.image.repository`
    - `spec.image.tag`
- `D:/Markdown/crossplane-backstage-poc/manifests/platform/appservice-composition.yaml`
  - Patches:
    - `spec.chartName` -> Helm chart name
    - optional image fields -> Helm chart values

Important incident:

- The first Composition update accidentally put empty `image.repository` and `image.tag` values in the base Helm values.
- That broke the old `helloworld` chart because it also uses `.Values.image`.
- Symptom:
  - `helloworld` Helm Release revision 3 failed
  - A new pod showed `InvalidImageName`
- Fix:
  - Removed the empty image values from the Composition base.
  - Kept image patches optional.
  - Reconciled `helloworld`.
  - Restarted provider-helm once because its Ready condition was stuck even after Helm state returned to `deployed`.
- Current state is healthy:
  - `helloworld` AppService `READY=True`
  - `helloworld` Helm Release `READY=True`, `STATE=deployed`, `REVISION=4`

Argo CD:

- Added `D:/Markdown/crossplane-backstage-poc/manifests/argocd/fastapi-demo-appservice-application.yaml`
- Current state:
  - `fastapi-demo-appservice` is `Synced / Healthy`

Crossplane:

- Current state:
  - `default/fastapi-demo` AppService `SYNCED=True READY=True`
  - `default/fastapi-demo-27b6ddc77acf` Helm Release `SYNCED=True READY=True STATE=deployed`

Runtime:

- `demo/fastapi-demo` Deployment `1/1`
- `demo/fastapi-demo` Pod `1/1 Running`
- `demo/fastapi-demo` Service `ClusterIP`
- Local service check succeeded:
  - `/health` returned `{"status":"ok"}`

Backstage:

- Updated `D:/Markdown/crossplane-backstage-poc/manifests/backstage/backstage-values.yaml`
- Added `fastapi-demo` catalog entity with:
  - `backstage.io/kubernetes-id: fastapi-demo`
  - `backstage.io/kubernetes-namespace: demo`
- Upgraded Backstage to revision 6.
- Current state:
  - `backstage` Deployment `1/1`
  - `backstage-postgresql` StatefulSet `1/1`

Tekton real CI resources:

- Added `D:/Markdown/crossplane-backstage-poc/manifests/tekton/fastapi-demo-ci.yaml`
- Creates:
  - ServiceAccount `fastapi-demo-ci`
  - Tasks:
    - `clone-repo`
    - `test-fastapi-demo`
    - `build-push-fastapi-demo`
  - Pipeline:
    - `fastapi-demo-ci`
  - TriggerBinding:
    - `fastapi-demo-ci-binding`
  - TriggerTemplate:
    - `fastapi-demo-ci-template`
  - EventListener:
    - `fastapi-demo-ci-listener`

Current Tekton state:

- `fastapi-demo-ci-listener` is `READY=True`
- Service:
  - `ci/el-fastapi-demo-ci-listener`
- Pipeline:
  - `ci/fastapi-demo-ci`

2026-07-08 update:

- Replaced Kaniko with BuildKit rootless in `build-push-fastapi-demo`.
- Current build image:
  - `moby/buildkit:rootless`
- Current build command:

```sh
buildctl-daemonless.sh build \
  --frontend dockerfile.v0 \
  --local context="$(workspaces.source.path)/repo/$(params.context_dir)" \
  --local dockerfile="$(workspaces.source.path)/repo/$(params.context_dir)" \
  --output "type=image,name=$(params.image),push=true"
```

- `DOCKER_CONFIG` points to the Tekton `dockerconfig` workspace, backed by `ci/ghcr-auth`.
- `BUILDKITD_FLAGS=--oci-worker-no-process-sandbox` is set for rootless BuildKit in kind/Tekton.
- The pytest step now uses:
  - `public.ecr.aws/docker/library/python:3.12-slim`
- Reason:
  - Avoid relying on the archived Kaniko project.
  - Avoid Docker Hub pull/token timeouts seen during earlier local builds.

Known remaining blocker:

- Secret `ci/ghcr-auth` does not exist yet.
- Because of this, the real CI Pipeline has not been run to completion.
- User must create a GHCR token and then create:

```powershell
$GHCR_USER="Re1lya"
$GHCR_TOKEN="<token>"

kubectl create secret docker-registry ghcr-auth `
  -n ci `
  --docker-server=ghcr.io `
  --docker-username=$GHCR_USER `
  --docker-password=$GHCR_TOKEN `
  --docker-email=unused@example.com `
  --dry-run=client -o yaml | kubectl apply -f -
```

2026-07-08 clone failure:

- After `ci/ghcr-auth` was created, GitHub webhook successfully triggered PipelineRuns:
  - `fastapi-demo-ci-zkm6x`
  - `fastapi-demo-ci-bjbzn`
- Both failed at the `clone` task.
- Root cause from pod logs:

```text
fatal: could not read Username for 'https://github.com': No such device or address
```

- Cause:
  - `https://github.com/Re1lya/Markdown.git` requires authentication from inside the Tekton Pod.
  - The GHCR docker-registry secret only authenticates image push/pull to `ghcr.io`.
  - It does not authenticate `git clone`.
- Fix applied:
  - Updated `clone-repo` Task in `manifests/tekton/fastapi-demo-ci.yaml`.
  - It now reads `GIT_USERNAME` and `GIT_TOKEN` from Secret `ci/github-git-auth`.
  - It uses `GIT_ASKPASS` instead of embedding credentials in the URL.
- User must create:

```powershell
$GITHUB_USER="Re1lya"
$GITHUB_TOKEN="<same PAT is ok if it has repo scope>"

kubectl create secret generic github-git-auth `
  -n ci `
  --from-literal=username=$GITHUB_USER `
  --from-literal=token=$GITHUB_TOKEN `
  --dry-run=client -o yaml | kubectl apply -f -
```

- Then retrigger the GitHub webhook with another push.

After `ghcr-auth` exists, the next validation is:

1. Ensure this POC folder is pushed to GitHub, because Tekton clones from GitHub.
2. Start cloudflared against `el-fastapi-demo-ci-listener`.
3. Configure GitHub webhook with secret `platform-poc-webhook-secret`.
4. Push a change under `crossplane-backstage-poc/apps/fastapi-demo`.
5. Watch:

```powershell
kubectl get pipelinerun -n ci
kubectl get taskrun -n ci
```

Note:

- The CI Pipeline currently builds and pushes the image.
- It does not yet write the new image tag back to GitOps values.
- The next implementation step is to add a Git update task that changes `charts/fastapi-demo-appservice/values.yaml` or a future GitOps values file, then lets Argo CD deploy the new tag.

## 2026-07-08 FastAPI Demo Real CI Succeeded

After creating:

- `ci/ghcr-auth`
- `ci/github-git-auth`

and after fixing BuildKit's Docker config path, the real FastAPI CI pipeline succeeded.

Successful PipelineRun:

```text
fastapi-demo-ci-krh4q
```

Result:

```text
PipelineRun fastapi-demo-ci-krh4q: Succeeded
TaskRuns:
  fastapi-demo-ci-krh4q-clone: Succeeded
  fastapi-demo-ci-krh4q-test: Succeeded
  fastapi-demo-ci-krh4q-build-push: Succeeded
```

Image pushed to GHCR:

```text
ghcr.io/re1lya/fastapi-demo:1ddefb7862e41ac2646e08c9bd8190248abfd373
```

Important BuildKit fix:

- Initial BuildKit run built the image but failed to push:

```text
failed to fetch anonymous token ... 403 Forbidden
```

- Root cause:
  - BuildKit did not read Kubernetes docker-registry Secret file `.dockerconfigjson` as Docker's expected `config.json`.
- Fix in `manifests/tekton/fastapi-demo-ci.yaml`:

```sh
mkdir -p /tmp/docker-config
cp "$(workspaces.dockerconfig.path)/.dockerconfigjson" /tmp/docker-config/config.json
export DOCKER_CONFIG=/tmp/docker-config
```

Evidence from successful BuildKit logs:

```text
[auth] re1lya/fastapi-demo:pull,push token for ghcr.io
pushing manifest for ghcr.io/re1lya/fastapi-demo:1ddefb7862e41ac2646e08c9bd8190248abfd373
DONE
```

Current milestone complete:

```text
GitHub push/webhook
  -> cloudflared tunnel
  -> Tekton EventListener
  -> clone private GitHub repo
  -> pytest
  -> BuildKit rootless build
  -> push image to GHCR
```

Still remaining for full CD automation:

```text
Tekton must update GitOps/AppService image.tag
  -> push that change to GitHub
  -> Argo CD detects the Git change
  -> Crossplane updates Helm Release
  -> fastapi-demo Deployment rolls out the new GHCR image tag
```

## 2026-07-08 Full FastAPI CI/CD Loop Completed

Implemented and verified the final CD automation step:

```text
GitHub webhook / manual PipelineRun
  -> Tekton clone
  -> pytest
  -> BuildKit rootless build
  -> push image to GHCR
  -> update GitOps values.yaml
  -> push GitOps commit to GitHub
  -> Argo CD syncs GitHub chart path
  -> Crossplane updates provider-helm Release
  -> fastapi-demo Deployment rolls out new GHCR image
```

Changes made:

- `D:/Markdown/crossplane-backstage-poc/manifests/argocd/fastapi-demo-appservice-application.yaml`
  - Changed Argo CD source from in-cluster Helm repo to GitHub:

```text
repoURL: https://github.com/Re1lya/Markdown.git
path: crossplane-backstage-poc/charts/fastapi-demo-appservice
targetRevision: main
```

- Created Argo CD repo credential secret:

```text
argocd/markdown-repo
```

  - It uses the same GitHub PAT from `ci/github-git-auth`.
  - It allows Argo CD to read `https://github.com/Re1lya/Markdown.git`.

- `D:/Markdown/crossplane-backstage-poc/manifests/tekton/fastapi-demo-ci.yaml`
  - Added Task `update-fastapi-demo-gitops`.
  - Added Pipeline task `update-gitops` after `build-push`.
  - The task edits:

```text
crossplane-backstage-poc/charts/fastapi-demo-appservice/values.yaml
```

  - It updates:

```yaml
appService:
  image:
    tag: <commit_sha>
```

  - It commits with:

```text
chore: update fastapi-demo image tag [skip ci]
```

  - It pushes to `main`.

- Added CEL filter to `fastapi-demo-ci-listener`:

```text
!body.head_commit.message.contains('[skip ci]')
```

  - Purpose: ignore Tekton's own GitOps update commit and avoid an infinite CI loop.

Successful manual verification PipelineRun:

```text
fastapi-demo-ci-manual-tw6wn
```

TaskRuns:

```text
fastapi-demo-ci-manual-tw6wn-clone: Succeeded
fastapi-demo-ci-manual-tw6wn-test: Succeeded
fastapi-demo-ci-manual-tw6wn-build-push: Succeeded
fastapi-demo-ci-manual-tw6wn-update-gitops: Succeeded
```

GitOps commit created by Tekton:

```text
71ebfc4 chore: update fastapi-demo image tag [skip ci]
```

Argo CD:

```text
fastapi-demo-appservice
SYNC STATUS=Synced
HEALTH STATUS=Healthy
revision=71ebfc4dec6a95230d2e4b5f2eaa8ba930f76a10
```

Crossplane:

```text
default/fastapi-demo
SYNCED=True
READY=True
```

provider-helm Release:

```text
default/fastapi-demo-27b6ddc77acf
SYNCED=True
READY=True
STATE=deployed
REVISION=2
DESCRIPTION=Upgrade complete
```

Runtime:

```text
demo/fastapi-demo Deployment 1/1
demo/fastapi-demo Pod Running
current tag: 1ddefb7862e41ac2646e08c9bd8190248abfd373
```

GHCR image pull issue and fix:

- After Argo synced the new GHCR tag, `demo/fastapi-demo` initially hit `ErrImagePull`.
- Cause:
  - `ci/ghcr-auth` allowed Tekton/BuildKit to push.
  - Runtime namespace `demo` did not have GHCR pull credentials.
- Fix applied:
  - Copied `ci/ghcr-auth` docker config into `demo/ghcr-auth`.
  - Patched `demo/default` ServiceAccount:

```powershell
kubectl patch serviceaccount default -n demo -p '{"imagePullSecrets":[{"name":"ghcr-auth"}]}'
```

- After deleting the failed Pod, Deployment rolled out successfully.

provider-helm condition note:

- After successful Helm upgrade, provider-helm again temporarily showed `READY=False` while Helm state was already `deployed`.
- Restarting the provider-helm Pod refreshed the condition:

```powershell
kubectl delete pod -n crossplane-system -l pkg.crossplane.io/provider=provider-helm
```

- Final state is healthy.

## 2026-07-08 Backstage Notifications Frontend API Fix

User reported a Backstage UI runtime error:

```text
NotImplementedError
No implementation available for apiRef{plugin.notifications.service}
```

Root cause:

- The custom Backstage app was using the new frontend system.
- `packages/app/src/App.tsx` registered:
  - `@backstage/plugin-catalog/alpha`
  - `@backstage/plugin-kubernetes/alpha`
  - local `navModule`
- Some Backstage frontend UI now expects the notifications API.
- `@backstage/plugin-notifications/alpha` was installed but not registered as a frontend feature.

Fix applied:

- Updated `D:/Markdown/crossplane-backstage-poc/apps/backstage-custom/packages/app/src/App.tsx`
- Added:

```ts
import notificationsPlugin from '@backstage/plugin-notifications/alpha';
```

- Registered it in:

```ts
features: [catalogPlugin, kubernetesPlugin, notificationsPlugin, navModule]
```

Verification:

```powershell
cd D:\Markdown\crossplane-backstage-poc\apps\backstage-custom
yarn tsc
yarn build:backend
docker build -f Dockerfile.overlay -t platform-poc-backstage:0.1.1 .
kind load docker-image platform-poc-backstage:0.1.1 --name platform-poc
helm upgrade backstage backstage/backstage -n backstage -f D:\Markdown\crossplane-backstage-poc\manifests\backstage\backstage-values.yaml
kubectl rollout status deployment/backstage -n backstage --timeout=180s
```

Current Backstage deployment state after the fix:

```text
Helm release: backstage revision 7
Image: platform-poc-backstage:0.1.1
Deployment: backstage 1/1 Ready
Service URL through port-forward: http://localhost:7007
```

The port-forward had stopped during the Pod rollout. It was restarted with:

```powershell
kubectl port-forward svc/backstage -n backstage 7007:7007
```

If `http://localhost:7007` is refused in a later session, restart the port-forward before debugging Backstage itself.

## 2026-07-09 Backstage Register Existing FastAPI Template Added

Implemented the POC version of a developer-facing Backstage onboarding flow for existing FastAPI services.

Backstage frontend:

- `D:/Markdown/crossplane-backstage-poc/apps/backstage-custom/packages/app/src/App.tsx`
  - Added `@backstage/plugin-scaffolder/alpha`
  - Added `@backstage/plugin-catalog-import/alpha`

Backstage template:

- `D:/Markdown/crossplane-backstage-poc/apps/backstage-custom/templates/register-existing-fastapi/template.yaml`
- Skeleton files under:
  - `D:/Markdown/crossplane-backstage-poc/apps/backstage-custom/templates/register-existing-fastapi/skeleton/`

The template is visible in Backstage as:

```text
Template: default/register-existing-fastapi-service
Title: Register Existing FastAPI Service
URL: http://localhost:7007/create
```

Verified through the Catalog API:

```text
steps=chart-metadata,chart-values,appservice-template,argocd-application,catalog-info,tekton-ci,publish
publish_action=publish:github:pull-request
```

The template opens a GitHub PR against the platform GitOps repository. It generates:

- `gitops/appservices/<serviceName>/Chart.yaml`
- `gitops/appservices/<serviceName>/values.yaml`
- `gitops/appservices/<serviceName>/templates/appservice.yaml`
- `gitops/argocd/<serviceName>-appservice.yaml`
- `gitops/tekton/<serviceName>-ci.yaml`
- `catalog/services/<serviceName>/catalog-info.yaml`

Backstage GitHub integration:

- Created Kubernetes Secret:

```text
backstage/backstage-github-token
```

- It reuses the token from `ci/github-git-auth`.
- `manifests/backstage/backstage-values.yaml` exposes it as `GITHUB_TOKEN`.
- `appConfig.integrations.github[0].token` uses `${GITHUB_TOKEN}`.

Custom Backstage image:

```text
platform-poc-backstage:0.1.3
```

Deployment state:

```text
Helm release: backstage revision 9
Deployment image: platform-poc-backstage:0.1.3
Backstage /create: HTTP 200
```

Crossplane platform API update:

- `AppService.spec.port`
- `AppService.spec.replicas`

Composition now patches:

- `spec.port` -> Helm values `containerPort`
- `spec.replicas` -> Helm values `replicaCount`

Tekton shared task update:

- `update-fastapi-demo-gitops` now supports:
  - `gitops_repo_url`
  - `gitops_branch`
- This lets CI clone an application repo, then separately clone and update the platform GitOps repo.

Argo CD app-of-apps added:

- `manifests/argocd/platform-appservices-application.yaml`
- `manifests/argocd/platform-ci-application.yaml`

Current app-of-apps status:

```text
platform-appservices: Unknown / Healthy
platform-ci: Unknown / Healthy
```

Root cause:

- These apps point to GitHub `main`.
- The new local directories do not exist in GitHub `main` yet:
  - `crossplane-backstage-poc/gitops/argocd`
  - `crossplane-backstage-poc/gitops/tekton`

Required next step before using the template end-to-end:

```text
Commit and push the new local platform files to https://github.com/Re1lya/Markdown main.
```

After that:

- Argo CD app-of-apps should become Synced.
- Backstage template can create onboarding PRs.
- After a service onboarding PR is merged, Argo CD will apply the generated app and CI config.
- For each generated service CI listener, expose its EventListener through cloudflared and configure the service repository GitHub webhook.

## 2026-07-09 Backstage Catalog GitHub Discovery Added

Backstage has been updated so newly generated service catalog files can be discovered from GitHub instead of being manually added to the Backstage Catalog ConfigMap.

Design principle:

- Backstage is a replaceable developer portal/client.
- The durable platform contract is the GitOps file layout under `crossplane-backstage-poc/`.
- Future clients must generate the same files rather than depending on Backstage internals.

Provider installed and registered:

- Package added to Backstage backend:
  - `@backstage/plugin-catalog-backend-module-github`
- Registered in:
  - `D:/Markdown/crossplane-backstage-poc/apps/backstage-custom/packages/backend/src/index.ts`

Backstage config:

- `D:/Markdown/crossplane-backstage-poc/manifests/backstage/backstage-values.yaml`
- Added GitHub Catalog Discovery provider:

```yaml
catalog:
  providers:
    github:
      platformPocServices:
        organization: Re1lya
        catalogPath: /crossplane-backstage-poc/catalog/services/*/catalog-info.yaml
        filters:
          branch: main
          repository: Markdown
        schedule:
          frequency:
            minutes: 5
          timeout:
            minutes: 3
```

Static Catalog entries are still used only for bootstrap entities:

- `helloworld`
- `fastapi-demo`
- `guest`
- `platform-team`
- Backstage template file

Generated service entries should live in GitHub at:

```text
crossplane-backstage-poc/catalog/services/<service>/catalog-info.yaml
```

Image and deployment:

- Built custom Backstage image:
  - `platform-poc-backstage:0.1.5`
- Loaded it into kind cluster:
  - `kind load docker-image platform-poc-backstage:0.1.5 --name platform-poc`
- Upgraded Backstage with Helm:
  - Release revision: `12`
  - Image: `platform-poc-backstage:0.1.5`
  - Deployment rolled out successfully.

Helm note:

- A previous manual `kubectl apply` on Backstage ConfigMaps created field-manager conflicts with Helm 4 server-side apply.
- The successful upgrade used:

```powershell
helm upgrade backstage backstage/backstage `
  -n backstage `
  -f D:\Markdown\crossplane-backstage-poc\manifests\backstage\backstage-values.yaml `
  --force-conflicts
```

Verification:

- Backstage logs show the provider task was registered:

```text
Registered scheduled task: github-provider:platformPocServices:refresh
Read 11 GitHub repositories (1 matching the pattern)
```

- Authenticated Catalog API lookup for `fastapi-demo-2` succeeded.
- The returned entity proves it came from GitHub discovery:

```text
backstage.io/managed-by-location:
url:https://github.com/Re1lya/Markdown/tree/main/crossplane-backstage-poc/catalog/services/fastapi-demo-2/catalog-info.yaml

backstage.io/managed-by-origin-location:
url:https://github.com/Re1lya/Markdown/blob/main/crossplane-backstage-poc/catalog/services/*/catalog-info.yaml
```

Implication:

- Future services created by the Backstage template should appear in Catalog after their onboarding PR is merged and the GitHub discovery provider refreshes.
- Argo CD webhook is still separate; it improves GitOps sync latency but does not control Backstage Catalog discovery.

## 2026-07-09 Cluster Rebuild With extraPortMappings

The local kind cluster `platform-poc` was rebuilt successfully with host port mappings prepared for better later demos.

Updated kind config:

```text
D:/Markdown/crossplane-backstage-poc/configs/kind-platform-poc.yaml
```

Important mapping:

```yaml
extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
  - containerPort: 30080
    hostPort: 30080
    protocol: TCP
```

Before deleting the old cluster, these external/runtime secrets were backed up locally under `.runtime/secret-backup/` and then restored into the new cluster:

- `ci/ghcr-auth`
- `ci/github-git-auth`
- `ci/github-webhook-secret`
- `backstage/backstage-github-token`
- `argocd/markdown-repo`

Do not commit `.runtime/`; it contains local runtime logs and sensitive secret backups.

Rebuild sequence used:

```powershell
kind delete cluster --name platform-poc
kind create cluster --config D:\Markdown\crossplane-backstage-poc\configs\kind-platform-poc.yaml
kubectl wait --for=condition=Ready nodes --all --timeout=180s
```

Platform components restored:

- Crossplane chart `2.3.3`
- `provider-kubernetes:v1.2.1`
- `provider-helm:v1.3.0`
- `function-patch-and-transform:v0.10.7`
- `AppService` XRD and `appservice-helm-release` Composition
- Argo CD through Crossplane-managed Helm Release `default/argocd`
- Tekton Pipelines and Triggers from the same official release URLs used earlier
- In-cluster Helm repo `platform-system/helm-repo`
- Backstage Helm release using local image `platform-poc-backstage:0.1.5`

Rebuild issues and fixes:

1. AppService Helm Releases initially failed because the in-cluster Helm repo did not exist after cluster recreation.
   - Symptom: Crossplane `Release` could not fetch `http://helm-repo.platform-system.svc.cluster.local/index.yaml`.
   - Fix: reran `D:/Markdown/crossplane-backstage-poc/scripts/publish-helloworld-chart-repo.ps1`.

2. `fastapi-demo-2-ci-listener` initially crash-looped.
   - Root cause: shared Tekton Triggers RBAC from `manifests/tekton/github-webhook-smoke.yaml` had not been restored.
   - Fix: applied `D:/Markdown/crossplane-backstage-poc/manifests/tekton/github-webhook-smoke.yaml`, then restarted the EventListener Pod.
   - Note: this means shared CI RBAC should eventually be moved into GitOps/bootstrap so future rebuilds do not require remembering the smoke manifest.

3. Backstage initially stayed unready.
   - Root cause: Backstage started before PostgreSQL accepted connections and got stuck at readiness `503`.
   - Fix: after PostgreSQL became Ready, deleted the Backstage Pod and let the Deployment recreate it.

Current verified state after rebuild:

```text
Nodes:
  platform-poc-control-plane Ready
  platform-poc-worker Ready
  platform-poc-worker2 Ready

Argo CD Applications:
  fastapi-demo-2-appservice Synced / Healthy
  fastapi-demo-appservice Synced / Healthy
  helloworld-appservice Synced / Healthy
  platform-appservices Synced / Healthy
  platform-ci Synced / Healthy

Crossplane AppServices:
  default/helloworld READY=True
  default/fastapi-demo READY=True
  default/fastapi-demo-2 READY=True

Tekton EventListeners:
  ci/fastapi-demo-2-ci-listener READY=True
  ci/github-listener READY=True

Backstage:
  backstage/backstage READY=1/1
  backstage/backstage-postgresql READY=1/1
```

Runtime service verification:

```powershell
kubectl port-forward -n demo service/fastapi-demo-2 18082:80
curl.exe http://localhost:18082/health
```

Expected response:

```json
{"status":"ok"}
```

Backstage verification:

- Backstage port-forward was restarted on local port `7007`.
- Authenticated Catalog API lookup for `component:default/fastapi-demo-2` succeeded.
- The entity is still managed by GitHub Catalog Discovery, not by a manual static ConfigMap entry.

External connection reminder after rebuild:

- GitHub repository configuration remains valid.
- GHCR/GitHub/Backstage tokens were restored from local backup in this rebuild.
- The cloudflared quick tunnel URL does not survive process/window shutdown.
- Before testing GitHub webhook again, start a fresh tunnel to the current EventListener and update the GitHub Webhook Payload URL.
- After each rebuild or terminal restart, start a fresh tunnel for `ci/el-fastapi-demo-2-ci-listener`:

```text
Local port-forward:
  localhost:18081 -> ci/service/el-fastapi-demo-2-ci-listener:8080
```

Use the newly generated `https://*.trycloudflare.com` URL as the GitHub Webhook Payload URL while the local `kubectl port-forward` and `cloudflared` processes remain running. When those processes stop, generate a new quick tunnel and update the GitHub webhook again.

Gateway next-step note:

- The cluster was rebuilt specifically so Gateway/Ingress style local exposure can bind host ports.
- Continue from:
  - `D:/Markdown/crossplane-backstage-poc/docs/GATEWAY_NEXT.md`
- Recommended next validation:
  - install one Gateway API controller
  - create one shared platform Gateway
  - route `demo/fastapi-demo-2` first
  - verify `curl.exe http://localhost/health` or the selected local route returns `{"status":"ok"}`
  - then add the service URL as a Backstage Catalog link
- Keep Backstage replaceable: the durable contract should be Gateway/HTTPRoute manifests generated into GitOps, not a Backstage-only runtime dependency.
