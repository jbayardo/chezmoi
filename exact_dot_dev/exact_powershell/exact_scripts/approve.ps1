param(
  [Parameter(Mandatory=$true)]
  [string]$url
)

$organization = $url -replace '^(https?:\/\/[^\/]+)\/.*', '$1'
$id = $url -replace '^.+\/pullrequest\/(\d+)$', '$1'

while($true) {
  $state = az repos pr show --organization $organization --id $id --query status -o tsv
  Write-Output "PR state is $state"
  if ($state -eq "completed" -or $state -eq "abandoned") {
    break
  }

  az repos pr set-vote --organization $organization --id $id --vote approve
  Start-Sleep -Seconds 10
}
