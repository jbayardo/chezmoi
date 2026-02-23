function global:review {
  [CmdletBinding()]
  Param(
    [Switch]
    $Online
  )

  $branch = (git rev-parse --abbrev-ref HEAD | Out-String).Trim()
  $pullRequests = az repos pr list --status active --output json | ConvertFrom-Json;
  $pullRequests = $pullRequests | Where-Object { $_.sourceRefName.Equals("refs/heads/$branch") }

  if ($pullRequests.Count -eq 0) {
    Write-Error "Couldn't find any active PRs for the current branch"
  }
  elseif ($pullRequests.Count -gt 1) {
    Write-Error "Found too many PRs which match the current branch"
  }
  else {
    $pullRequest = $pullRequests[0]

    $Organization = [regex]::Match($pullRequest.url, "^https.*\.com/([^/]+)/.*").Groups[1].Value

    if ($Online) {
      $Url = "https://dev.azure.com/$Organization/$($pullRequest.repository.project.name)/_git/$($pullRequest.repository.name)/pullrequest/$($pullRequest.pullRequestId)"
      Start-Process $Url
    }
    else {
      $Url = "https://dev.azure.com/$Organization/&project=$($pullRequest.repository.project.id)&repo=$($pullRequest.repository.id)&pullRequest=$($pullRequest.pullRequestId)"
      Start-Process "codeflow:open?server=$Url"
    }
  }
}

function global:checkout {
  [CmdletBinding()]
  Param(
    [Switch]
    $Print = $false,
    [Parameter(Mandatory = $false)]
    [string] $Author = "jubayard@microsoft.com",
    [Parameter(Mandatory = $false, Position = 0)]
    [string] $Search = $null
  )
  
  $pullRequests = az repos pr list --status active --query "[].{id:pullRequestId, author:createdBy.uniqueName, branch:sourceRefName, title:title, displayName:createdBy.displayName}" --output json | ConvertFrom-Json;
  
  if (!($null -eq $Author)) {
    $pullRequests = $pullRequests | Where-Object { $_.author -imatch $Author };
  }

  $pullRequests = $pullRequests | ForEach-Object {
    $branch = ($_.branch -split "/")[2..($_.branch.Length)] -join "/";
    return "$($_.id):$($_.author):$($branch):$($_.title):$($_.displayName)";
  };

  if (!($null -eq $Search)) {
    $pullRequests = $pullRequests | rg -i $Search;
  }

  if ($pullRequests.Count -eq 0) {
    Write-Error "No pull requests found that match the patterns"
    return;
  }

  $pullRequests = $pullRequests -split "`r?`n";

  if ($Print) {
    Write-Output $pullRequests
    return;
  }

  $Command = 'git checkout'
  if ($pullRequests.Count -eq 1) {
    Write-Output "Checking out $($pullRequests[0])"
    Invoke-Expression "$Command $($pullRequests[0].Split(":")[2])"
  }
  else {
    # TODO: preview diff
    # --preview 'bat --color=always {1} --highlight-line {2}' --preview-window 'up,60%,border-bottom,+{2}+3/3,~3'
    $pullRequests | fzf --ansi --color "hl:-1:underline,hl+:-1:underline:reverse" --delimiter : --bind "enter:execute($Command {3})+abort"
  }
}
