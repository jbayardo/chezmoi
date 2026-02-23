Start-Job -ScriptBlock {
  function PerformOperationIfNeeded {
    param (
      [String]$Name,
      [String]$TimestampFilePath,
      [TimeSpan]$Threshold,
      [ScriptBlock]$Operation,
      [String]$ProducingFilePath = $null
    )
  
    $performOperation = $false
  
    if ((-not [String]::IsNullOrEmpty($ProducingFilePath)) -and (-not (Test-Path $ProducingFilePath))) {
      Write-Debug "Executing operation because [ProducingFilePath] $ProducingFilePath does not exist."
      $performOperation = $true
    }
  
    if (Test-Path -PathType Leaf $TimestampFilePath) {
      $lastExecutionTime = Get-Content -Path $TimestampFilePath
      if ($null -ne $lastExecutionTime) {
        $lastExecutionTime = [DateTime]::ParseExact($lastExecutionTime, "yyyy-MM-dd HH:mm:ss", $null)
        $timeDifference = (Get-Date) - $lastExecutionTime
        if ($timeDifference -gt $Threshold) {
          Write-Debug "Executing operation because $timeDifference is greater than $Threshold."
          $performOperation = $true
        }
      }
      else {
        Write-Debug "Executing operation because [TimestampFilePath] $TimestampFilePath is empty."
        $performOperation = $true
      }
    }
    else {
      Write-Debug "Executing operation because [TimestampFilePath] $TimestampFilePath does not exist."
      $performOperation = $true
    }
  
    if ($performOperation) {
      $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
  
      $operationResult = $null
      try {
        $operationResult = & $Operation
  
        if ($LASTEXITCODE -ne 0) {
          Write-Host "Operation $Name failed with exit code $LASTEXITCODE."
          $operationResult = $null;
        }
      }
      catch {
        Write-Host "Operation $Name failed with error: $_"
      }
  
      if ($operationResult -eq $true) {
        (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") | Set-Content -Path $TimestampFilePath
        if ($Timing) {
          Write-Host "Operation $Name took $($stopwatch.Elapsed)."
        }
      }
      else {
        Write-Host "Operation $Name failed or returned false. No changes made to $TimestampFilePath."
      }
    }
  }
  
  $temp = [System.IO.Path]::GetTempPath()
  PerformOperationIfNeeded -Name "Chezmoi" -TimestampFilePath (Join-Path $temp "chezmoi-update.txt") -Threshold (New-TimeSpan -Days 1) -Operation {
    chezmoi update --keep-going --force --no-pager --no-tty --verbose
    chezmoi init
    return $true;
  }
} | Remove-Job -Force -ErrorAction Ignore
