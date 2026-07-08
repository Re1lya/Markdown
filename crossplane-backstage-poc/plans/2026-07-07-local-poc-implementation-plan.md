# Local POC Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a local kind-based POC where Crossplane creates a HelloWorld service and Backstage displays the service through Kubernetes label matching.

**Architecture:** A multi-node kind cluster runs Crossplane and Backstage. Crossplane manages HelloWorld through a Composition. Backstage Catalog owns the service metadata and the Backstage Kubernetes plugin finds matching Kubernetes resources by label.

**Tech Stack:** kind, Kubernetes, Helm, Crossplane, provider-kubernetes, Backstage, Backstage Kubernetes plugin.

---

## File Map

- `D:/Markdown/crossplane-backstage-poc/configs/kind-platform-poc.yaml`: kind multi-node cluster config.
- `D:/Markdown/crossplane-backstage-poc/POC_GUIDE.md`: human-readable execution guide.
- `D:/Markdown/crossplane-backstage-poc/AGENTS.md`: live handoff, progress log, and next action tracker.
- `D:/Markdown/crossplane-backstage-poc/DECISIONS.md`: architecture decisions.
- Future `D:/Markdown/crossplane-backstage-poc/manifests/`: Crossplane providers, XRDs, Compositions, Claims, RBAC, and Backstage catalog files.

## Task 1: Create the Local Cluster

- [ ] Step 1: Confirm current kind clusters.

Run:

```powershell
kind get clusters
```

Expected:

```text
dev
kind
```

or any existing cluster list. It is acceptable as long as `platform-poc` is not already present.

- [ ] Step 2: Create the POC cluster.

Run:

```powershell
kind create cluster --config D:\Markdown\crossplane-backstage-poc\configs\kind-platform-poc.yaml
```

Expected:

```text
Creating cluster "platform-poc" ...
```

- [ ] Step 3: Verify nodes.

Run:

```powershell
kubectl cluster-info --context kind-platform-poc
kubectl get nodes
```

Expected:

```text
platform-poc-control-plane   Ready
platform-poc-worker          Ready
platform-poc-worker2         Ready
```

- [ ] Step 4: Update `AGENTS.md`.

Record the cluster creation result, node status, and any error messages.

## Task 2: Install Crossplane

- [ ] Step 1: Add and update the Crossplane Helm repo.

Run:

```powershell
helm repo add crossplane-stable https://charts.crossplane.io/stable
helm repo update
```

- [ ] Step 2: Install Crossplane.

Run:

```powershell
helm install crossplane crossplane-stable/crossplane `
  --namespace crossplane-system `
  --create-namespace
```

- [ ] Step 3: Verify Crossplane pods.

Run:

```powershell
kubectl get pods -n crossplane-system
```

Expected:

```text
crossplane-...   Running
```

- [ ] Step 4: Update `AGENTS.md`.

Record Helm install status and pod status.

## Task 3: Install provider-kubernetes

- [ ] Step 1: Create provider manifest in `manifests/crossplane/provider-kubernetes.yaml`.

Use:

```yaml
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: provider-kubernetes
spec:
  package: xpkg.upbound.io/crossplane-contrib/provider-kubernetes:v1.2.1
```

- [ ] Step 2: Apply the provider.

Run:

```powershell
kubectl apply -f D:\Markdown\crossplane-backstage-poc\manifests\crossplane\provider-kubernetes.yaml
kubectl get providers
```

- [ ] Step 3: Wait until healthy.

Run:

```powershell
kubectl get providers.pkg.crossplane.io
kubectl get pods -n crossplane-system
```

Expected:

```text
provider-kubernetes   INSTALLED=True   HEALTHY=True
```

- [ ] Step 4: Update `AGENTS.md`.

Record provider health and any RBAC requirements.

- [ ] Step 5: Apply ProviderConfig.

Run:

```powershell
kubectl apply -f D:\Markdown\crossplane-backstage-poc\manifests\crossplane\provider-config-kubernetes.yaml
kubectl get providerconfigs.kubernetes.crossplane.io
```

Expected:

```text
default
```

- [ ] Step 6: Grant local POC RBAC permissions.

Run:

```powershell
$ProviderSA = kubectl get pod -n crossplane-system `
  -l pkg.crossplane.io/provider=provider-kubernetes `
  -o jsonpath="{.items[0].spec.serviceAccountName}"

kubectl create clusterrolebinding provider-kubernetes-admin `
  --clusterrole=cluster-admin `
  --serviceaccount=crossplane-system:$ProviderSA
```

Expected:

```text
clusterrolebinding.rbac.authorization.k8s.io/provider-kubernetes-admin created
```

## Task 4: Decide and Deploy Backstage

- [ ] Step 1: Choose install method.

Recommended for this POC:

```text
Use Helm first if speed matters.
Move Backstage under Crossplane provider-helm after HelloWorld display works.
```

- [ ] Step 2: Deploy Backstage.

Use a Helm-based deployment with Kubernetes plugin enabled. The exact chart and values should be written into project files before applying.

- [ ] Step 3: Verify access.

Use:

```powershell
kubectl port-forward svc/backstage -n backstage 7007:7007
```

Expected:

```text
http://localhost:7007 opens Backstage
```

- [ ] Step 4: Update `AGENTS.md`.

Record Backstage deployment method and access URL.

## Task 5: Create HelloWorld Crossplane Composition

- [ ] Step 1: Create XRD for `AppService`.
- [ ] Step 2: Create Composition that generates Kubernetes `Deployment` and `Service`.
- [ ] Step 3: Create a Claim named `helloworld`.
- [ ] Step 4: Verify Kubernetes resources are created in namespace `demo`.
- [ ] Step 5: Verify labels include `backstage.io/kubernetes-id: helloworld`.
- [ ] Step 6: Update `AGENTS.md`.

## Task 6: Register HelloWorld in Backstage

- [ ] Step 1: Create `catalog-info.yaml` for `helloworld`.
- [ ] Step 2: Register it in Backstage.
- [ ] Step 3: Open the service page.
- [ ] Step 4: Verify Kubernetes tab shows matching resources.
- [ ] Step 5: Update `AGENTS.md`.

## Task 7: Final Verification

- [ ] Step 1: Verify HelloWorld responds locally.

Run:

```powershell
kubectl port-forward svc/helloworld -n demo 8080:80
curl http://localhost:8080
```

- [ ] Step 2: Verify Backstage displays HelloWorld.
- [ ] Step 3: Update `README.md`, `POC_GUIDE.md`, and `AGENTS.md` with final results.
