Import-CloudBuild -Scripts > $null

$Machines = @(
  "DS4PNPF00005C7C"
)

while ($true) {
  foreach ($machine in $Machines) {
    $Stamp = (runq `
        -Database "CloudBuildProd" `
        -Cluster "https://cbuild.kusto.windows.net" `
        -Query `
        @"
CloudBuildLogEvent
| where PreciseTimeStamp > ago(1h)
| where Machine == '$Machine'
| distinct Stamp
"@ | Select-Object -First 1).Stamp
    Write-Host "Setting $Machine in stamp $Stamp to Debug"
    Set-MachineState -Environment PROD -Stamp $Stamp -Machine $machine -MachineState Debug
  }

  Start-Sleep -Duration ([TimeSpan]::FromMinutes(15))
}