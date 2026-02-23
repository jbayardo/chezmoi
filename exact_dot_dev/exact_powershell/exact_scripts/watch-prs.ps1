$Path = Join-Path $Env:SrcRoot 'PRs.txt'

while ($true) {
  $PRs = Get-Content $Path
  $PRs = $PRs | ForEach-Object { $_.Trim() }
  $PRs = $PRs | Where-Object { $_ -ne '' }
  $PRs = $PRs | Sort-Object -Unique

  $PRs | ForEach-Object {
    $PR = $_
    # Split by first space
    $split = $PR -split ' ', 2
    $command = $split[0]
    $url = $split[1]

    if ($command -eq "merge") {
      
    }
    elseif ($command -eq "approve") {
      # TODO: parse url and do the thing

    }
    else {
      Write-Error "Found unexpected command $command"
    }
  }
}