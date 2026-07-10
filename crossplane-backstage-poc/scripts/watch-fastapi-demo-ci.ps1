param(
  [string]$Namespace = "ci",
  [string]$Pipeline = "fastapi-demo-2-ci",
  [string]$PipelineRun = "",
  [switch]$WaitForNew,
  [int]$PollSeconds = 10,
  [int]$TimeoutMinutes = 30,
  [switch]$SkipCdChecks
)

$ErrorActionPreference = "Stop"

function Invoke-KubectlJson {
  param([string[]]$KubectlArgs)

  $raw = & kubectl @KubectlArgs -o json
  if ($LASTEXITCODE -ne 0) {
    throw "kubectl $($KubectlArgs -join ' ') failed"
  }
  return $raw | ConvertFrom-Json
}

function Get-PipelineRunObject {
  param([string]$Name)

  return Invoke-KubectlJson @("get", "pipelinerun", $Name, "-n", $Namespace)
}

function Get-LatestPipelineRunName {
  param([datetime]$After)

  $runs = Invoke-KubectlJson @("get", "pipelinerun", "-n", $Namespace, "-l", "tekton.dev/pipeline=$Pipeline")
  $items = @($runs.items)

  if ($WaitForNew) {
    $items = @($items | Where-Object {
      ([datetime]$_.metadata.creationTimestamp).ToUniversalTime() -ge $After.ToUniversalTime()
    })
  }

  $latest = $items |
    Sort-Object { [datetime]$_.metadata.creationTimestamp } -Descending |
    Select-Object -First 1

  if ($null -eq $latest) {
    return ""
  }

  return $latest.metadata.name
}

function Get-Condition {
  param($Resource)

  $conditions = @($Resource.status.conditions)
  if ($conditions.Count -eq 0) {
    return [pscustomobject]@{
      Status  = "Unknown"
      Reason  = "Pending"
      Message = ""
    }
  }

  $succeeded = $conditions | Where-Object { $_.type -eq "Succeeded" } | Select-Object -First 1
  if ($null -eq $succeeded) {
    $succeeded = $conditions | Select-Object -First 1
  }

  return [pscustomobject]@{
    Status  = [string]$succeeded.status
    Reason  = [string]$succeeded.reason
    Message = [string]$succeeded.message
  }
}

function Write-CheckLine {
  param(
    [string]$Name,
    [string]$Status,
    [string]$Reason,
    [string]$Extra = ""
  )

  $label = "[WAIT]"
  $color = "Yellow"

  if ($Status -eq "True") {
    $label = "[PASS]"
    $color = "Green"
  } elseif ($Status -eq "False") {
    $label = "[FAIL]"
    $color = "Red"
  }

  $line = "{0,-7} {1,-18} {2}" -f $label, $Name, $Reason
  if (-not [string]::IsNullOrWhiteSpace($Extra)) {
    $line = "$line - $Extra"
  }

  Write-Host $line -ForegroundColor $color
}

function Get-TaskRuns {
  param([string]$RunName)

  $taskRuns = Invoke-KubectlJson @("get", "taskrun", "-n", $Namespace, "-l", "tekton.dev/pipelineRun=$RunName")
  return @($taskRuns.items | Sort-Object { [datetime]$_.metadata.creationTimestamp })
}

function Get-TaskRunLog {
  param($TaskRun)

  $podName = [string]$TaskRun.status.podName
  if ([string]::IsNullOrWhiteSpace($podName)) {
    return ""
  }

  try {
    return (& kubectl logs -n $Namespace "pod/$podName" --all-containers=true 2>$null) -join "`n"
  } catch {
    return ""
  }
}

function Write-TestSummary {
  param([string]$RunName)

  $testTask = Get-TaskRuns $RunName |
    Where-Object { $_.metadata.labels."tekton.dev/pipelineTask" -eq "test" } |
    Select-Object -First 1

  if ($null -eq $testTask) {
    Write-Host ""
    Write-Host "Test summary: no test task found." -ForegroundColor Yellow
    return
  }

  $log = Get-TaskRunLog $testTask
  $passLines = @($log -split "`n" | Where-Object {
    $_ -match "TEST PASS" -or $_ -match "\d+\s+passed"
  })

  Write-Host ""
  Write-Host "Test Result" -ForegroundColor Cyan
  Write-Host "-----------" -ForegroundColor Cyan

  $condition = Get-Condition $testTask
  Write-CheckLine "pytest" $condition.Status $condition.Reason

  if ($passLines.Count -gt 0) {
    foreach ($line in $passLines) {
      Write-Host "  $line" -ForegroundColor Green
    }
  } else {
    Write-Host "  No TEST PASS line found in test logs." -ForegroundColor Yellow
  }
}

function Write-CdSummary {
  if ($SkipCdChecks) {
    return
  }

  Write-Host ""
  Write-Host "CD / Runtime Checks" -ForegroundColor Cyan
  Write-Host "-------------------" -ForegroundColor Cyan

  try {
    $argo = & kubectl get application fastapi-demo-2-appservice -n argocd -o json | ConvertFrom-Json
    $sync = [string]$argo.status.sync.status
    $health = [string]$argo.status.health.status
    $argoStatus = if ($sync -eq "Synced" -and $health -eq "Healthy") { "True" } else { "False" }
    Write-CheckLine "Argo CD" $argoStatus "$sync / $health"
  } catch {
    Write-CheckLine "Argo CD" "False" "Unable to read application"
  }

  try {
    $appService = & kubectl get appservice fastapi-demo-2 -n default -o json | ConvertFrom-Json
    $ready = @($appService.status.conditions | Where-Object { $_.type -eq "Ready" } | Select-Object -First 1)
    $synced = @($appService.status.conditions | Where-Object { $_.type -eq "Synced" } | Select-Object -First 1)
    $status = if ($ready.status -eq "True" -and $synced.status -eq "True") { "True" } else { "False" }
    Write-CheckLine "AppService" $status "Synced=$($synced.status), Ready=$($ready.status)"
  } catch {
    Write-CheckLine "AppService" "False" "Unable to read AppService"
  }

  try {
    & kubectl rollout status deployment/fastapi-demo-2 -n demo --timeout=180s | Out-Null
    Write-CheckLine "Rollout" "True" "deployment/fastapi-demo-2"
  } catch {
    Write-CheckLine "Rollout" "False" "deployment/fastapi-demo-2"
  }

  try {
    $root = & curl.exe --noproxy "*" --connect-timeout 5 --max-time 15 -s -i http://localhost:30080/
    $rootText = $root -join "`n"
    $rootOk = ($rootText -match "HTTP/1.1 200" -and $rootText -match "Platform POC Service is Running")
    Write-CheckLine "Gateway /" $(if ($rootOk) { "True" } else { "False" }) "http://localhost:30080/"
  } catch {
    Write-CheckLine "Gateway /" "False" "http://localhost:30080/"
  }

  try {
    $health = & curl.exe --noproxy "*" --connect-timeout 5 --max-time 15 -s http://localhost:30080/health
    $healthOk = ($health -join "`n") -match '"status"\s*:\s*"ok"'
    Write-CheckLine "Gateway health" $(if ($healthOk) { "True" } else { "False" }) "http://localhost:30080/health"
  } catch {
    Write-CheckLine "Gateway health" "False" "http://localhost:30080/health"
  }
}

$startedAt = (Get-Date).ToUniversalTime()
$deadline = (Get-Date).AddMinutes($TimeoutMinutes)

if ([string]::IsNullOrWhiteSpace($PipelineRun)) {
  Write-Host "Finding PipelineRun for pipeline '$Pipeline' in namespace '$Namespace'..."
  if ($WaitForNew) {
    Write-Host "Waiting for a new PipelineRun created after $($startedAt.ToString("u"))..."
  }

  do {
    $PipelineRun = Get-LatestPipelineRunName $startedAt
    if (-not [string]::IsNullOrWhiteSpace($PipelineRun)) {
      break
    }
    Start-Sleep -Seconds $PollSeconds
  } while ((Get-Date) -lt $deadline)
}

if ([string]::IsNullOrWhiteSpace($PipelineRun)) {
  throw "No PipelineRun found for pipeline '$Pipeline'."
}

Write-Host ""
Write-Host "Checks for $PipelineRun" -ForegroundColor Cyan
Write-Host ("=" * ("Checks for $PipelineRun").Length) -ForegroundColor Cyan

do {
  $run = Get-PipelineRunObject $PipelineRun
  $condition = Get-Condition $run
  $taskRuns = Get-TaskRuns $PipelineRun

  Clear-Host
  Write-Host "Checks for $PipelineRun" -ForegroundColor Cyan
  Write-Host ("=" * ("Checks for $PipelineRun").Length) -ForegroundColor Cyan
  Write-CheckLine "Pipeline" $condition.Status $condition.Reason $condition.Message
  Write-Host ""
  Write-Host "Tasks" -ForegroundColor Cyan
  Write-Host "-----" -ForegroundColor Cyan

  foreach ($taskRun in $taskRuns) {
    $taskCondition = Get-Condition $taskRun
    $taskName = [string]$taskRun.metadata.labels."tekton.dev/pipelineTask"
    if ([string]::IsNullOrWhiteSpace($taskName)) {
      $taskName = [string]$taskRun.metadata.name
    }
    Write-CheckLine $taskName $taskCondition.Status $taskCondition.Reason
  }

  if ($condition.Status -ne "Unknown") {
    break
  }

  Start-Sleep -Seconds $PollSeconds
} while ((Get-Date) -lt $deadline)

$run = Get-PipelineRunObject $PipelineRun
$condition = Get-Condition $run

Write-TestSummary $PipelineRun

if ($condition.Status -eq "True") {
  Write-CdSummary
}

Write-Host ""
Write-Host "Result" -ForegroundColor Cyan
Write-Host "------" -ForegroundColor Cyan
if ($condition.Status -eq "True") {
  Write-Host "[PASS] CI/CD completed successfully." -ForegroundColor Green
  exit 0
}

Write-Host "[FAIL] CI/CD did not complete successfully: $($condition.Reason)" -ForegroundColor Red
if (-not [string]::IsNullOrWhiteSpace($condition.Message)) {
  Write-Host $condition.Message -ForegroundColor Red
}
exit 1
