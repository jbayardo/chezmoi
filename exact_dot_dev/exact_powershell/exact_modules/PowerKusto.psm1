function global:run {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [ScriptBlock]$Perform,

    [Parameter(Mandatory = $true)]
    [ScriptBlock]$ShouldRetry,
      
    [Parameter(Mandatory = $true)]
    [TimeSpan]$PollingWait,

    [System.Nullable[TimeSpan]]$RetryUntil = $null,

    [ScriptBlock]$OnCompletion = $null
  )
  
  $startTime = Get-Date
  $deadline = [DateTime]::MaxValue
  if ($null -ne $RetryUntil) {
    $deadline = $startTime.Add($RetryUntil)
  }

  $output = $null
  $exitReason = 'Unknown'
  while ($true) {
    $now = Get-Date
    if ($now -gt $deadline) {
      Write-Error "Deadline exceeded"
      $exitReason = 'DeadlineExceeded'
      break
    }

    Write-Debug "Running script block..."
    $output = Invoke-Command -ScriptBlock $Perform
    Write-Debug "Output: $output"

    $retry = Invoke-Command -ScriptBlock $ShouldRetry -ArgumentList $output
    if ($retry -ne $true) {
      $exitReason = 'Success'
      break
    }

    Start-Sleep -Duration $PollingWait
  }

  if ($null -ne $OnCompletion) {
    $arguments = @($output, $exitReason)
    Invoke-Command -ScriptBlock $OnCompletion -ArgumentList $arguments
  }
}

function global:runq {
  [CmdletBinding()]
  param(
    [string]
    $Query = $null,
    
    [string]
    $Cluster = "https://cbuild.kusto.windows.net",

    [string]
    $Database = "CloudBuildProd",

    [string]
    $OutputPath = $null,

    [ValidateSet('csv', 'object', 'file')]
    [string]
    $Output = 'object'
  )

  if (($null -eq $Query) -or [string]::IsNullOrWhiteSpace($Query) -or ($Query -eq "-")) {
    $Query = [System.Console]::In.ReadToEnd()
  }
  elseif (Test-Path -PathType Leaf -Path $Query) {
    $Query = Get-Content -Path $Query
  }
  $Query = $Query.Trim()

  if (($null -eq $Query) -or [string]::IsNullOrWhiteSpace($Query)) {
    Write-Error "No query provided"
    return
  }

  Write-Debug "Query: $Query"

  $tmpPath = [System.IO.Path]::GetTempPath()
  $rand = [System.IO.Path]::GetRandomFileName()

  $StdoutPath = Join-Path $tmpPath ($rand + ".stdout")
  $StderrPath = Join-Path $tmpPath ($rand + ".stderr")
  $TemporaryScriptPath = Join-Path $tmpPath ($rand + ".kql")

  if ([string]::IsNullOrWhiteSpace($OutputPath) -or $null -eq $OutputPath) {
    # We need to put the temporary output in the cwd because Kusto.CLI doesn't work properly.
    $OutputPath = ($rand + ".csv")
  }
  
  if (Test-Path -PathType Leaf $OutputPath) {
    Write-Error "Output path already exists: $OutputPath"
    return
  }

  Write-Debug "Writing script to: $TemporaryScriptPath . Output to: $OutputPath . Stdout to: $StdoutPath . Stderr to: $StderrPath"

  $Script =
  @"
#connect $Cluster/$Database;Fed=true
#dbcontext $Database
#crp notruncation=true
#crp query_language=csl
#blockmode
#save $OutputPath

$Query

#quit
"@;

  Write-Debug "Script: $Script"

  try {
    Set-Content -Path $TemporaryScriptPath -Value $Script

    $KustoCliOutput = Kusto.Cli -console:true -banner:false -script:$TemporaryScriptPath 2>&1 | Out-String
    Write-Debug "KustoCliOutput: $KustoCliOutput"

    if ($KustoCliOutput.Contains("Error")) {
      Write-Error (($KustoCliOutput -split "`n") -join "`n")
      return
    }

    switch ($Output) {
      'csv' {
        return Get-Content -Raw -Path $OutputPath
      }
      'object' {
        return Get-Content -Raw -Path $OutputPath | ConvertFrom-Csv
      }
      'file' {
        return $OutputPath
      }
    }
  }
  finally {
    Remove-Item -Path $TemporaryScriptPath
    if ($Output -ne 'file') {
      Remove-Item -Path $OutputPath -ErrorAction SilentlyContinue
    }
  }
}

function global:runKustoQueryUntilChanged {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [string]$Query,

    [string]$Cluster = "https://cbuild.kusto.windows.net",

    [string]$Database = "CloudBuildProd",

    [TimeSpan]$PollingWait = [TimeSpan]::FromSeconds(30),

    [System.Nullable[TimeSpan]]$RetryUntil = $null
  )

  $Script:lastQueryOutput = $null
  $Script:lastResultChanged = $false

  $runKustoQuery = { runq -Query $Query -Cluster $Cluster -Database $Database }

  $shouldRetry = {
    param (
      $result
    )

    Write-Verbose "Checking if result changed...: $result vs $Script:lastQueryOutput"
    if ($null -eq $Script:lastQueryOutput) {
      $Script:lastQueryOutput = $result
      return $true
    }
    elseif ($Script:lastQueryOutput -ne $result) {
      $Script:lastResultChanged = $true
      return $false
    }

    return $true
  }

  $onCompletion = {
    param (
      [string]$Output,
      [string]$ExitReason
    )
    
    if ($ExitReason -eq 'Success' -and $Script:lastResultChanged) {
      Write-Output "Query result changed. Last output: $Output"
    }
    elseif ($ExitReason -eq 'DeadlineExceeded') {
      Write-Output "Deadline exceeded without query result change."
    }
    else {
      Write-Output "Query exited with reason: $ExitReason"
    }
  }

  run -Perform $runKustoQuery -ShouldRetry $shouldRetry -PollingWait $PollingWait -RetryUntil $RetryUntil -OnCompletion $onCompletion
}

function global:runqr {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$Query,

    [string]$Cluster = "https://cbuild.kusto.windows.net",

    [string]$Database = "CloudBuildProd",

    [int]$MaxRetryCount = 5,
    [int]$MinRetryInterval = 2
  )

  $result = runq -Query $Query -Cluster $Cluster -Database $Database
  $commands = $result | Select-Object -ExpandProperty Command
  $total = $commands.Count
  $complete = 0

  $retryCount = 0
  $pending = $commands

  while ($pending.Count -gt 0 -and $retryCount -lt $MaxRetryCount) {
    $failures = @()
    foreach ($command in $pending) {
      try {
        Invoke-Expression $command
        $complete++
      }
      catch {
        Write-Error "Command $command failed: $_"
        $failures += $command
      }
    }

    $pending = $failures
    Write-Output "Attempt $retryCount : Ran $($total - $pending.Count) / $total commands."
    if ($pending.Count -gt 0) {
      $retryCount++
      Start-Sleep -Seconds ([Math]::Pow(2, $retryCount) + $MinRetryInterval)
    }
  }

  if ($pending.Count -eq 0) {
    Write-Output "All commands succeeded."
  }
  else {
    Write-Error "Some commands failed after $MaxRetryCount retries:"
    foreach ($command in $pending) {
      Write-Error $command
    }
  }
}

function global:waitqci {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]
    $Commit
  )

  (runq -Database 'CloudBuildCI' -Query "CloudBuildLogs
  | where PreciseTimeStamp > ago(1h)
  | summarize arg_max(PreciseTimeStamp, ServiceVersion, ServiceVersionDate) by CI = Ring, Machine, Service
  | extend Commit = split(ServiceVersion, '_')[2]
  | sort by CI asc" | Where-Object { $_.Service -eq 'ContentAddressableStoreMasterService' -and $_.Commit.Contains($Commit) }).Count -gt 0
}