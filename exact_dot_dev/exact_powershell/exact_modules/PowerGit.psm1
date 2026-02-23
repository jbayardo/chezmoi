function global:main { git checkout main; git pull; }

function global:master { git checkout master; git pull; }

function global:develop { git checkout develop; git pull; }

function global:prc {
  git add -A :/
  git commit -m 'Address PR comments'
  git push -u origin
}

function global:step {
  $TemporaryOutputFilePath = [System.IO.Path]::GetTempFileName()
  try {
    $stepDiff = git diff HEAD
    $stepPrompt = @"
Generate git commit description for these changes. Write the subject, one empty lines, and then the body. Don't include any other text.

Changes:
$stepDiff
"@
    Invoke-CopilotPrompt -Prompt $stepPrompt | Out-File -Encoding utf8 $TemporaryOutputFilePath
    git add -A :/
    git commit -F $TemporaryOutputFilePath
    git push -u origin
  }
  finally {
    Remove-Item $TemporaryOutputFilePath -ErrorAction SilentlyContinue
  }
}

function global:sync {
  $currentBranch = (git rev-parse --abbrev-ref HEAD | Out-String).Trim()
  
  # Detect the default branch
  $defaultBranch = Get-LatestGitBranch
  if ([string]::IsNullOrEmpty($defaultBranch)) {
    Write-Error "Could not determine default branch (main/master/develop)"
    return
  }
  
  # Fetch and merge the default branch without checking it out
  git fetch origin $defaultBranch
  git merge origin/$defaultBranch
}

function global:gd {
  if ([string]::IsNullOrEmpty($args)) {
    $arguments = ""
  }
  else {
    $arguments = $args
  }

  $RepoRoot = (git rev-parse --show-toplevel 2>$null | Out-String).Trim();
  try {
    Push-Location $RepoRoot
    Invoke-Expression "git diff --name-only $arguments" | fzf --ansi --preview "git diff $arguments --color=always -- {1} | delta --width $($Host.UI.RawUI.WindowSize.Width)" --color "hl:-1:underline,hl+:-1:underline:reverse" --preview-window 'up,80%,border-bottom,+{2}+3/3,~3'
  }
  finally {
    Pop-Location
  }
}

function global:gn {
  param(
    [string]$Moniker = "",
    [switch]$Date
  )

  $username = ((git config user.email).Trim() -split "@")[0]
  
  if (-not [string]::IsNullOrEmpty($Moniker)) {
    if ($Moniker -match "/") {
      $branch = $Moniker
    }
    else {
      $branch = "dev/$username/$Moniker"
    }
  }
  elseif ($Date) {
    $branchName = "$(Get-Date -UFormat "%Y%m%d%H%M%S")"
    $branch = "dev/$username/$branchName"
  }
  else {
    $hasChanges = git status --porcelain | Select-String -Pattern "^\s*[MADRCU]{1,2}" -Quiet
    if ($hasChanges) {
      $branchDiff = git diff
      $branchPrompt = @"
Generate a concise and descriptive branch name for a git branch based on these git changes. Only provide the branch name without any additional text. Use hyphens to separate words. Avoid special characters.

Changes:
$branchDiff
"@
      $branchName = Invoke-CopilotPrompt -Prompt $branchPrompt
    }

    if ([string]::IsNullOrEmpty($branchName)) {
      $branchName = "$(Get-Date -UFormat "%Y%m%d%H%M%S")"
    }

    $branch = "dev/$username/$branchName"
  }

  git checkout -b $branch
}

function global:pr {
  param(
    [switch]$Draft,
    [string]$Title = ""
  )
  
  $branch = (git rev-parse --abbrev-ref HEAD | Out-String).Trim()
  $hasChanges = git status --porcelain | Select-String -Pattern "^\s*[MADRCU]{1,2}" -Quiet
  if (($branch -eq "main") -or ($branch -eq "master") -or ($branch -eq "develop")) {
    if (-not $hasChanges) {
      Write-Error "No changes to commit and based out of the main branch."
      return
    }

    gn
  }

  if ($hasChanges) {
    step
  }

  if ([string]::IsNullOrEmpty($Title)) {
    $titleDiff = git diff (git merge-base $branch master)..$branch
    $titlePrompt = @"
Generate a concise and descriptive title for a pull request based on these git changes. Only provide the title without any additional text.

Changes:
$titleDiff
"@
    $Title = Invoke-CopilotPrompt -Prompt $titlePrompt
  }
  
  $remoteUrl = (git config --get remote.origin.url | Out-String).Trim()
  $isGitHub = $remoteUrl -match "(github\.com|\.ghe\.com)"
  if ($isGitHub) {
    if ($Draft) {
      gh pr create --web --draft --title "$Title"
    }
    else {
      gh pr create --web --title "$Title"
    }
  }
  else {
    if ($Draft) {
      az repos pr create --open --draft --title "$Title"
    }
    else {
      az repos pr create --open --title "$Title"
    }
  }
}

function global:syncall {
  $Repositories = Get-ChildItem -Path $env:SrcRoot -Directory -Recurse -Depth 2
  foreach ($repository in $Repositories) {
    $gitPath = Join-Path $repository.FullName ".git"
    if (!(Test-Path $gitPath -PathType Container)) { continue; }
    Write-Host "Syncing $($repository.FullName)"
    Push-Location $repository.FullName
    git fetch --all
    Pop-Location
  }
}

function Get-LatestGitBranch {
  param (
    [Parameter(Mandatory = $false)]
    [string]$RepoPath = "."
  )

  if (!(Test-Path -PathType Container $RepoPath)) {
    return $null
  }

  Push-Location -Path $RepoPath

  try {
    if (!(Test-Path ".git")) {
      return $null
    }

    $targetBranches = 'master', 'main', 'develop'
    $latestBranch = $null
    $latestDate = [DateTime]::MinValue

    foreach ($branch in $targetBranches) {
      if (git branch --all | Select-String -Pattern $branch) {
        $commitDateStr = git log -1 --format=%aI $branch 2>$null | Out-String
        $commitDateStr = $commitDateStr.Trim()
        
        if ([string]::IsNullOrEmpty($commitDateStr)) {
          continue
        }
        
        $commitDate = [DateTime]::Parse($commitDateStr)

        if ($commitDate -gt $latestDate) {
          $latestDate = $commitDate
          $latestBranch = $branch
        }
      }
    }
    return $latestBranch
  }
  finally {
    Pop-Location
  }
}

function global:Invoke-CopilotPrompt {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
    [string]$Prompt
  )

  $copilotCommand = Get-Command -Name "copilot" -ErrorAction SilentlyContinue
  if (-not $copilotCommand) {
    throw "copilot CLI not found in PATH."
  }

  # Build argument list explicitly so PowerShell handles all escaping/quoting for us.
  $copilotArgs = @(
    '--log-level', 'none',
    '--no-color',
    '--silent',
    '-p', $Prompt
  )

  # Capture stdout from copilot and bubble it back up to callers.
  $stdout = & $copilotCommand.Source @copilotArgs 2>$null

  if ($null -eq $stdout) {
    return ""
  }

  if ($stdout -is [System.Array]) {
    $stdout = ($stdout -join [Environment]::NewLine)
  }

  return $stdout.Trim()
}

function global:Search-Git-Commits {
  [CmdletBinding()]
  Param(
    [Parameter(Mandatory = $false)]
    [string] $Since = "1 week ago",
    [Parameter(Mandatory = $false)]
    [int] $Parallel = 16,
    [Parameter(Mandatory = $true)]
    [string] $Search 
  )

  git log --since=$Since --pretty=format:"%H" | ForEach-Object -ThrottleLimit $Parallel -Parallel { $commit = $_; git diff-tree --no-commit-id --name-only -r $commit | ForEach-Object { "$($commit):$($_)" } } | ForEach-Object -ThrottleLimit $Parallel -Parallel { $S = $_ -split ":"; $match = git show --pretty="fuller" -W $S[0] -- $S[1] | rg $using:Search; if ($match) { $_ } } | fzf --delimiter : --color "hl:-1:underline,hl+:-1:underline:reverse" --preview 'git show --color=always --patience {1} -- {2}' --preview-window 'up,60%,border-bottom,+{2}+4/4,~4'
}
