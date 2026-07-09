# Gateway Demo Status

This POC cluster has been rebuilt with host port mappings so a Gateway API controller can expose demo services through stable local ports.

## Current Starting Point

The cluster now has:

- kind cluster `platform-poc` with host mappings for `80`, `443`, and `30080`
- Crossplane `AppService` API restored
- Argo CD apps synced and healthy
- Tekton EventListener restored for `fastapi-demo-2`
- Backstage running on local port-forward `http://localhost:7007`
- Demo services running in namespace `demo`

Current service check:

```powershell
kubectl port-forward -n demo service/fastapi-demo-2 18082:80
curl.exe http://localhost:18082/health
```

Expected response:

```json
{"status":"ok"}
```

## Completed Gateway Validation

Envoy Gateway was installed with Helm:

```powershell
helm upgrade --install eg oci://docker.io/envoyproxy/gateway-helm `
  --version v1.8.2 `
  -n envoy-gateway-system `
  --create-namespace `
  --wait `
  --timeout 5m
```

The first Gateway API route is declared in:

```text
D:/Markdown/crossplane-backstage-poc/manifests/gateway/fastapi-demo-2-gateway.yaml
```

It creates:

- `GatewayClass/envoy`
- `EnvoyProxy/envoy-gateway-system/platform-gateway-proxy`
- `Gateway/demo/platform-gateway`
- `HTTPRoute/demo/fastapi-demo-2`

The `EnvoyProxy` forces the generated Envoy Service to use:

```text
Service type: NodePort
NodePort: 30080
externalTrafficPolicy: Cluster
```

`externalTrafficPolicy: Cluster` matters in this local kind setup because host port `30080` maps into the control-plane node, while the Envoy Pod may run on a worker node.

Verified local access:

```powershell
curl.exe --noproxy "*" http://localhost:30080/health
```

Expected response:

```json
{"status":"ok"}
```

Backstage catalog entry:

```text
D:/Markdown/crossplane-backstage-poc/catalog/services/fastapi-demo-2/catalog-info.yaml
```

now includes an `Open Service` link to:

```text
http://localhost:30080/health
```

Backstage discovers generated service catalog files from GitHub, so this link appears in Backstage after the catalog file is committed, pushed, and the GitHub discovery provider refreshes.

## Gateway Goal

Replace one-off service `kubectl port-forward` usage with a platform HTTP entrypoint:

```text
Browser / curl
  -> localhost:30080
  -> Gateway controller
  -> HTTPRoute
  -> demo/fastapi-demo-2 Service
  -> FastAPI Pod
```

Backstage should then link to the service URL from the Catalog entity, so a demo viewer can open the deployed service directly from the developer portal.

## Recommended Next POC Shape

Use Gateway API with a single shared platform Gateway and one `HTTPRoute` per service.

The first validation routes `fastapi-demo-2`:

```text
GET http://localhost:30080/health
  -> demo/fastapi-demo-2:80
```

After that works, decide whether multi-service routing should use:

- path prefixes such as `/fastapi-demo-2/health`, with URL rewrite if the controller supports it
- hostnames such as `fastapi-demo-2.localhost`, if local DNS/browser behavior is acceptable
- a generated route per service with a Backstage Catalog link

## Template Integration To Add Later

```text
apps/backstage-custom/templates/register-existing-fastapi/skeleton/httproute.yaml.njk
apps/backstage-custom/templates/register-existing-fastapi/skeleton/catalog-info.yaml.njk
```

The template should generate a service link in Catalog, for example:

```yaml
metadata:
  links:
    - url: http://localhost:30080/health
      title: Open Service
      icon: web
```

## What Not To Do Yet

- Do not replace Argo CD or Crossplane for this step.
- Do not expose every service at once before one service works.
- Do not put secrets or cloudflared quick tunnel URLs into committed manifests.
- Do not depend on Backstage internals for routing; Backstage should only generate or display the route contract.
