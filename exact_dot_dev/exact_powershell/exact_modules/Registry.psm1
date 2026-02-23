function Set-RegistryValue() {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory)]
    [String] $Path,
    [String] $Name = $null,
    [String] $Data = "",
    [Microsoft.Win32.RegistryValueKind] $Type = "String",
    [switch] $Elevate
  )

  $existingValue = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Ignore
  if ($null -eq $existingValue) {
    Write-Debug "Adding registry value [$Path] $Name=$Data"

    if ($Name) {
      $CreateBlock = { New-Item -Path "$Path" -Name "$Name" -Force; New-ItemProperty -Path "$Path" -Name "$Name" -PropertyType $Type -Value $Data; }
    }
    else {
      $CreateBlock = { New-Item -Path "$Path" -Value $Data -Force; }
    }

    if ($Elevate) {
      Invoke-Elevated $CreateBlock
    }
    else {
      Invoke-Command -ScriptBlock $CreateBlock
    }

    return $true
  }
  else {
    if ($Name) {
      $existingData = $existingValue.$Name
    }
    else {
      $existingData = $existingValue."(default)"
    }

    if ($existingData -ne $Data) {
      Write-Debug "Setting registry [$Path] $Name=$Data (old data $existingData)"

      if ($Name) {
        $UpdateBlock = { Set-ItemProperty -Path $Path -Name $Name -Value $Data }
      }
      else {
        $UpdateBlock = { New-Item -Path $Path -Value $Data -Force }
      }

      if ($Elevate) {
        Invoke-Elevated $UpdateBlock
      }
      else {
        Invoke-Command -ScriptBlock $UpdateBlock
      }

      return $true
    }
    else {
      Write-Debug "Registry already set [$Path] $Name=$Data"
      return $false
    }
  }
}
