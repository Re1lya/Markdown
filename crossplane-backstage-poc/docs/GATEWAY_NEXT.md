# Gateway Demo Next Step

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

## Gateway Goal

Replace one-off service `kubectl port-forward` usage with a platform HTTP entrypoint:

```text
Browser / curl
  -> localhost:80 or localhost:30080
  -> Gateway controller
  -> HTTPRoute
  -> demo/fastapi-demo-2 Service
  -> FastAPI Pod
```

Backstage should then link to the service URL from the Catalog entity, so a demo viewer can open the deployed service directly from the developer portal.

## Recommended POC Shape

Use Gateway API with a single shared platform Gateway and one `HTTPRoute` per service.

For the first Gateway validation, route `fastapi-demo-2`:

```text
GET http://localhost/health
  -> demo/fastapi-demo-2:80
```

After that works, decide whether multi-service routing should use:

- path prefixes such as `/fastapi-demo-2/health`, with URL rewrite if the controller supports it
- hostnames such as `fastapi-demo-2.localhost`, if local DNS/browser behavior is acceptable
- a generated route per service with a Backstage Catalog link

## Files To Add Next

Suggested files for the next implementation step:

```text
manifests/gateway/
  gatewayclass.yaml
  gateway.yaml
  fastapi-demo-2-httproute.yaml
```

Optional later template integration:

```text
apps/backstage-custom/templates/register-existing-fastapi/skeleton/httproute.yaml.njk
apps/backstage-custom/templates/register-existing-fastapi/skeleton/catalog-info.yaml.njk
```

The template should generate a service link in Catalog, for example:

```yaml
metadata:
  links:
    - url: http://localhost/health
      title: Open Service
      icon: web
```

## Important Decision Before Installing

Pick one Gateway controller:

- Envoy Gateway: good default for a Gateway API focused demo.
- nginx-gateway-fabric: good if the platform wants to stay close to the nginx ecosystem.

Before installing either one, check the current official install command and version. Gateway controller install docs change often enough that the exact command should be verified at implementation time.

## What Not To Do Yet

- Do not replace Argo CD or Crossplane for this step.
- Do not expose every service at once before one service works.
- Do not put secrets or cloudflared quick tunnel URLs into committed manifests.
- Do not depend on Backstage internals for routing; Backstage should only generate or display the route contract.
