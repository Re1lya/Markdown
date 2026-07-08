# Crossplane + Backstage Local POC

This project tracks a local proof of concept for a Kubernetes-based developer platform.

The target is to run a multi-node local Kubernetes cluster with kind, install Crossplane, deploy Backstage, then create a simple HelloWorld service through a Crossplane Composition and show that service in Backstage through Kubernetes resource labels.

## POC Goal

Build the smallest useful validation chain:

```text
kind multi-node cluster
  -> Crossplane
  -> Backstage
  -> Crossplane Composition creates HelloWorld Deployment and Service
  -> Backstage Catalog entity matches Kubernetes resources by label
  -> Backstage displays HelloWorld runtime status
```

## Important Scope Choice

The first POC does not need a frontend/backend HelloWorld chart.

The main thing to prove is:

```text
Crossplane can manage application resources
Backstage can discover and display those resources
The service can be reached locally
```

Later phases can add:

- Argo CD for GitOps-based CD.
- Tekton for CI.
- A real frontend/backend application.
- A Platform API between Backstage and Crossplane.

## Project Files

- [AGENTS.md](./AGENTS.md): current project state, decisions, next steps, and handoff notes for future agents.
- [POC_GUIDE.md](./POC_GUIDE.md): step-by-step implementation guide.
- [DECISIONS.md](./DECISIONS.md): architecture decisions and reasoning.

## Current Status

The documentation scaffold has been created. The next step is to create the local kind multi-node cluster and install Crossplane.

