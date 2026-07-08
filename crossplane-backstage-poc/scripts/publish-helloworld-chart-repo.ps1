$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$ChartDir = Join-Path $Root "charts\helloworld"
$AppServiceChartDir = Join-Path $Root "charts\helloworld-appservice"
$FastApiChartDir = Join-Path $Root "charts\fastapi-demo"
$FastApiAppServiceChartDir = Join-Path $Root "charts\fastapi-demo-appservice"
$RepoDir = Join-Path $Root "dist\helm-repo"

New-Item -ItemType Directory -Force $RepoDir | Out-Null

helm lint $ChartDir
helm lint $AppServiceChartDir
helm lint $FastApiChartDir
helm lint $FastApiAppServiceChartDir
helm package $ChartDir --destination $RepoDir
helm package $AppServiceChartDir --destination $RepoDir
helm package $FastApiChartDir --destination $RepoDir
helm package $FastApiAppServiceChartDir --destination $RepoDir
helm repo index $RepoDir --url "http://helm-repo.platform-system.svc.cluster.local"

kubectl create namespace platform-system --dry-run=client -o yaml | kubectl apply -f -

kubectl create configmap helm-repo-content `
  --namespace platform-system `
  --from-file=$RepoDir `
  --dry-run=client `
  -o yaml | kubectl apply -f -

kubectl apply -f (Join-Path $Root "manifests\helm-repo\helm-repo-server.yaml")

kubectl rollout status deployment/helm-repo -n platform-system --timeout=120s
kubectl get svc helm-repo -n platform-system
