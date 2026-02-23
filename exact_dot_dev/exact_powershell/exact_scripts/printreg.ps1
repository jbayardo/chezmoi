function Get-RegistryKeys {
  param (
    [string]$Path,
    [string]$Indent = ""
  )

  $regItem = Get-Item -Path $Path
  Write-Host ("$Indent Path: $Path")
  foreach ($value in $regItem.GetValueNames()) {
    $valueData = $regItem.GetValue($value)
    Write-Host ("$Indent -> Value: $value, Data: $valueData")
  }

  $nextIndent = $Indent + "  "
  foreach ($subKeyName in $regItem.GetSubKeyNames()) {
    $subKeyPath = Join-Path $Path $subKeyName
    Get-RegistryKeys -Path $subKeyPath -Indent $nextIndent
  }
}

$registryPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"
Get-RegistryKeys -Path $registryPath
