param(
  [Parameter(Mandatory = $true)]
  [string]$url
)
# Example URL: https://dev.azure.com/mseng/Domino/_git/BuildXL.Internal/pullrequest/751041

$uri = New-Object System.Uri $url
$pullRequestOrg = $uri.Scheme + "://" + $uri.Host + "/" + $uri.Segments[1].TrimEnd('/')
$pullRequestId = $url.Split('/')[-1]

Write-Output "Organization: $pullRequestOrg / Id: $pullRequestId"
while ($true) {
  $state = az repos pr show --organization $pullRequestOrg --id $pullRequestId --query status -o tsv
  Write-Output "PR state is $state"
  if ($state -eq "completed" -or $state -eq "abandoned") {
    break
  }

  $evaluationIds = az repos pr policy list --organization $pullRequestOrg --id $pullRequestId --query "[?status != 'approved' && status != 'running' && configuration.isBlocking && configuration.isEnabled && configuration.settings.queueOnSourceUpdateOnly].evaluationId" | ConvertFrom-Json
  foreach ($evaluationId in $evaluationIds) {
    Write-Debug "Found evaluation ID: $evaluationId"
    az repos pr policy queue --organization $pullRequestOrg --id $pullRequestId --evaluation-id $evaluationId
  }
  
  az repos pr set-vote --organization $pullRequestOrg --id $pullRequestId --vote approve
  az repos pr update --organization $pullRequestOrg --id $pullRequestId --auto-complete --delete-source-branch --draft false

  Start-Sleep -Seconds 10
}