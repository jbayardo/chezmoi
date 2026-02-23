$netstatData = netstat -aof | Where-Object { $_ -match '^\s*TCP|\s*UDP' } | ForEach-Object { $parts = ($_.Trim()) -split '\s+';
  $processId = $parts[-1];
  $process = Get-Process -Id $processId -ErrorAction SilentlyContinue;

  $s = $parts[1];
  $splitPoint = $s.lastIndexOf(':');
  $localAddress = $s.Substring(0, $splitPoint);
  $localPort = $s.Substring($splitPoint + 1);

  $s = $parts[2];
  $splitPoint = $s.lastIndexOf(':');
  $foreignAddress = $s.Substring(0, $splitPoint);
  $foreignPort = $s.Substring($splitPoint + 1);

  return [PSCustomObject]@{
    Protocol       = $parts[0];
    LocalAddress   = $localAddress;
    LocalPort      = $localPort;
    ForeignAddress = $foreignAddress;
    ForeignPort    = $foreignPort;
    State          = if ($parts[0] -eq 'TCP') { $parts[3] } else { $null };
    PID            = $processId;
    ProcessName    = $process.ProcessName;
    ExecutablePath = $process.MainModule.FileName;
  };
}

$netstatData | ConvertTo-Csv -NoTypeInformation | Write-Output

function Count-Connections {
  param (
    [string]$Title,
    [scriptblock]$GroupBy
  )

  Write-Host $Title

  $netstatData `
  | Group-Object -Property $GroupBy `
  | Select-Object Name, @{
    Name       = 'Count';
    Expression = { $_.Group.Count } 
  } `
  | Where-Object { $_.Count -gt 2 } `
  | Sort-Object -Property 'Count' -Descending `
  | Format-Table
}

Count-Connections -Title "--- Inbound Connections per ProcessName and LocalPort ---" -GroupBy { "$($_.ProcessName), $($_.LocalPort)" }
Count-Connections -Title "--- Outbound Connections per ProcessName and ForeignPort ---" -GroupBy { "$($_.ProcessName), $($_.ForeignPort)" }
Count-Connections -Title "--- Inbound Connections per LocalPort ---" -GroupBy { "$($_.LocalPort)" }
Count-Connections -Title "--- Outbound Connections per ForeignPort ---" -GroupBy { "$($_.ForeignPort)" }
Count-Connections -Title "--- Inbound Connections per LocalAddress ---" -GroupBy { "$($_.LocalAddress)" }
Count-Connections -Title "--- Outbound Connections per ForeignAddress ---" -GroupBy { "$($_.ForeignAddress)" }