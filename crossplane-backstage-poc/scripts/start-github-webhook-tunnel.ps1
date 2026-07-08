$ErrorActionPreference = "Stop"

$Namespace = "ci"
[string]$Service = $env:TEKTON_EVENTLISTENER_SERVICE
if ([string]::IsNullOrWhiteSpace($Service)) {
  $Service = "el-fastapi-demo-ci-listener"
}
$LocalPort = 8081
$TargetPort = 8080

Write-Host "Starting port-forward for Tekton EventListener..."
$PortForward = Start-Process -FilePath kubectl `
  -ArgumentList @("port-forward", "svc/$Service", "-n", $Namespace, "$LocalPort`:$TargetPort") `
  -WindowStyle Hidden `
  -PassThru

Start-Sleep -Seconds 3

Write-Host "Port-forward PID: $($PortForward.Id)"
Write-Host "EventListener Service: $Service"
Write-Host "Starting cloudflared tunnel. Copy the https://*.trycloudflare.com URL into GitHub Webhook Payload URL."
Write-Host "GitHub Webhook Secret: platform-poc-webhook-secret"
Write-Host ""

cloudflared tunnel --url "http://localhost:$LocalPort"
