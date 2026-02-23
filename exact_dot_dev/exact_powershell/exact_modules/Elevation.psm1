function Test-Elevated() {
  return ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-Elevated() {
  [CmdletBinding()]
  param (
    [ScriptBlock] $ScriptBlock,
    
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $Args
  )

  if (Test-Elevated) {
    Invoke-Command -ScriptBlock $ScriptBlock
  }
  else {
    Write-Debug "Requesting elevation"
    $PowershellExe = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName

    $Arguments = @()
    if ($Args) {
      $Arguments += $Args
    }
    
    $Arguments += "-Command `"$ScriptBlock`""
    Start-Process $PowershellExe -Verb RunAs -ArgumentList $Arguments
  }
}
