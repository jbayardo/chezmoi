[CmdletBinding(PositionalBinding = $false)]
param (
  [Parameter(Mandatory=$false)]
  [string]$PythonVersion = "cp312",

  [Parameter(Mandatory=$false)]
  [string]$AiderVersion = "aider-chat==0.75.2",

  [Parameter(Mandatory=$false)]
  [string]$Model = "litellm_proxy/gpt-4o",

  [Parameter(Mandatory=$false)]
  [string]$ApiKey = "sk-1234",

  [Parameter(Mandatory=$false)]
  [string]$ApiBase = "http://localhost:4000",

  [Parameter(ValueFromRemainingArguments=$true)]
  [string[]]$RemainingArgs
)

if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
  Write-Error "uv command not found.";
  exit 1;
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  Write-Error "docker command not found.";
  exit 1;
}

if (-not (docker ps --format "{{.Names}}" | Select-String -Pattern "litellm")) {
  Write-Error "litellm container not found.";
  exit 1;
}

$Env:LITELLM_PROXY_API_KEY = $ApiKey;
$Env:LITELLM_PROXY_API_BASE = $ApiBase;

$arguments = @(
  "--4o",
  "--model", $Model,
  "--no-show-model-warnings"
) + $RemainingArgs
Write-Host "Running uv with the following arguments: $($arguments -join ' ')"

try {
  uv tool run --isolated --python $PythonVersion --from "$($AiderVersion)[browser]" aider $arguments
} catch {
  Write-Error "An error occurred while running the uv command: $_"
  exit 1
}
