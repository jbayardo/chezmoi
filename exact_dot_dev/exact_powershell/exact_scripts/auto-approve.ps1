param(
  [Parameter(Mandatory=$true)]
  [string]$sourceBranchPattern 
)

# Authenticate with Azure CLI and Azure DevOps extension
# az login
# az devops login --organization $organization

# Get all pull requests where the source branch matches the regex pattern
$pullRequests = az repos pr list --detect true --status active --query "[?contains(sourceRefName, '$sourceBranchPattern')].pullRequestId" --output tsv

Write-Output "Found $($pullRequests.Count) pull requests matching pattern '$sourceBranchPattern'"

# Loop through each pull request and approve, set to auto-complete, and resolve comments
foreach ($pullRequestId in $pullRequests) {
  Write-Output "Processing pull request $pullRequestId"	

  $evaluationIds = az repos pr policy list --detect true --id $pullRequestId --query "[?status != 'approved' && configuration.isBlocking && configuration.isEnabled && configuration.settings.queueOnSourceUpdateOnly].evaluationId"
  foreach ($evaluationId in $evaluationIds) {
    az repos pr policy queue --detect true --id $pullRequestId --evaluation-id $evaluationId
  }

  az repos pr set-vote --detect true --id $pullRequestId --vote approve
  az repos pr update --detect true --id $pullRequestId --auto-complete --delete-source-branch --draft false
}
