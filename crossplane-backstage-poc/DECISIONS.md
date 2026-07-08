# Architecture Decisions

## Decision 1: Keep the First POC Small

Status: accepted

The first POC validates the platform relationship between Kubernetes, Crossplane, Backstage, and a simple service.

It does not initially include Tekton, Argo CD, a Platform API, model serving, monitoring, or a frontend/backend demo application.

Reason:

The goal is to prove that Crossplane can create resources and Backstage can display those resources. Adding CI/CD or a full demo app before that would add complexity without proving the core integration.

## Decision 2: Use Backstage Catalog + Kubernetes Plugin Label Matching

Status: accepted

Backstage should show the HelloWorld service by matching a Backstage Catalog entity to Kubernetes resources through:

```yaml
backstage.io/kubernetes-id: helloworld
```

Reason:

This matches the common Backstage Kubernetes plugin model and keeps ownership metadata in the Catalog while runtime state remains in Kubernetes.

## Decision 3: Do Not Start With a Frontend/Backend HelloWorld Chart

Status: accepted

The first HelloWorld should be a simple Kubernetes service, likely based on `hashicorp/http-echo` or a similarly small image.

Reason:

The user wants to validate Backstage visibility and Crossplane management. A frontend/backend chart would validate application internal connectivity, which is useful later but not necessary for the first milestone.

## Decision 4: Prefer provider-kubernetes for HelloWorld

Status: superseded

Use Crossplane `provider-kubernetes` to create HelloWorld `Deployment` and `Service` directly.

Reason:

This keeps the Composition easy to inspect and avoids creating a custom Helm chart just for a trivial service.

Superseded because the user chose to keep the POC closer to the platformized delivery model, where applications are packaged as Helm Charts and managed by Crossplane.

## Decision 5: Backstage Installation Method Still Open

Status: open

Options:

- Install Backstage directly with Helm first.
- Use Crossplane `provider-helm` to install Backstage.

Recommendation:

Use `provider-helm` for Backstage if the user wants to prove Crossplane can manage platform components. Use direct Helm if the user wants the fastest path to validating Backstage display behavior.

## Decision 6: Use Crossplane + provider-helm for Application Delivery

Status: accepted

The POC should use this platformized delivery chain:

```text
AppService Claim
  -> Crossplane Composition
  -> provider-helm Release
  -> HelloWorld Helm Chart
  -> Kubernetes Deployment / Service
  -> Backstage Kubernetes plugin label matching
```

Reason:

This proves that applications are not installed manually with `helm install`. They are created from platform-level resources that Crossplane reconciles. Helm remains the application packaging format, while Crossplane becomes the platform control plane.
