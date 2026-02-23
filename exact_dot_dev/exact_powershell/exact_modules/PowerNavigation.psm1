function global:.. { Push-Location ..; }

function global:... { Push-Location .. ; Push-Location ..; }

function global:.... { Push-Location .. ; Push-Location ..; Push-Location ..; }

function global:Find-Src {
  if ($IsWindows) {
    $targets = @(
      "C:\src",
      "Q:\src",
      "D:\src",
      "Q:\",
      "D:\"
    )
  }
  else {
    $targets = @(
      "~/src",
      "/mnt/c/src",
      "/mnt/q/src",
      "/mnt/d/src",
      "/mnt/q",
      "/mnt/d"
    )
  }

  $existing = @()
  foreach ($target in $targets) {
    try {
      if (Test-Path -PathType Container $target -ErrorAction SilentlyContinue) {
        $existing += Assert-Path $target
      }
    }
    catch {
      continue
    }
  }

  return $existing
}

function global:src {
  $targets = @(Find-Src)
  if ($targets.Count -eq 0) {
    Write-Error "Unable to find src directory"
    return
  }

  $target = $targets[0]
  Push-Location -Path $target
}

function global:dev { 
  $target = "~/.dev"
  if (-not (Test-Path -PathType Container $target)) {
    Write-Error "Unable to find dev directory"
    return
  }

  Push-Location (Resolve-Path $target)
}

function global:eroot {
  $RepoRoot = (git rev-parse --show-toplevel 2>$null | Out-String).Trim()
  try {
    $RepoRoot = Resolve-Path $RepoRoot
    code $RepoRoot
  }
  catch {
    Write-Error "Unable to find git root"
  }
}

function global:root {
  $RepoRoot = (git rev-parse --show-toplevel 2>$null | Out-String).Trim()
  $Current = Get-Location
  try {
    $Path = Resolve-Path $RepoRoot
    Push-Location $Path
  }
  catch {
    # Can't use Pop-Location here because there's no guarantee that we're in a git repo, in which case we won't have 
    # moved anywhere.
    Set-Location $Current
  }
}

function global:gg {
  $directories = @(Find-Src);
  $repositories = @()

  foreach ($directory in $directories) {
    if (-not (Test-Path -PathType Container $directory)) {
      continue
    }

    $candidates = fd --unrestricted --max-depth 3 --absolute-path '.git$' $directory | ForEach-Object {
      return (Join-Path $_.Trim() '..' | Resolve-Path).ToString();
    }

    $repositories += $candidates
  }

  $repositories = @($repositories | Select-Object -Unique)

  if ($repositories.Count -eq 0) {
    Write-Error "Unable to find any repositories in the search directories."
    return
  }

  # Filter repositories first before fetching branch info
  $fzfOutput = ($repositories | fzf --filter "$args" | Out-String).Trim()
  if (-not $fzfOutput) {
    Write-Error "Unable to find repositories matching query: $args in the specified directories."
    return
  }
  $filteredRepos = @($fzfOutput -split "`r?`n" | Where-Object { $_ -ne "" })

  # If only one match, go directly without fetching branch info or using fzf
  $selected = $null
  if ($filteredRepos.Count -eq 1) {
    $selected = $filteredRepos[0]
  }
  else {
    # For display purposes, fetch branch info for filtered repositories
    $repositoryInfo = $filteredRepos | ForEach-Object -Parallel {
      $repo = $_
      Push-Location $repo
      try {
        $branch = (git branch --show-current 2>$null | Out-String).Trim()
        if (-not $branch) {
          $branch = "detached"
        }
        return @{Path = $repo; Display = "$repo [$branch]" }
      }
      catch {
        return @{Path = $repo; Display = "$repo [unknown]" }
      }
      finally {
        Pop-Location
      }
    } -ThrottleLimit 16

    $selectedDisplay = ($repositoryInfo.Display | fzf --query "$args" | Out-String).Trim()
    if (-not $selectedDisplay) {
      Write-Error "No repository selected."
      return
    }
    # Find the matching path from the display
    $selected = ($repositoryInfo | Where-Object { $_.Display -eq $selectedDisplay }).Path
  }

  if (-not $selected) {
    Write-Error "No repository selected."
    return
  }
  
  Push-Location $selected
}
New-Alias -Force repo gg

function global:Select-Path {
  param(
    [string]$query
  )

  # If we're in a git repo, use that as the search path
  $SearchRoot = (git rev-parse --show-toplevel 2>$null | Out-String).Trim()
  if ($LASTEXITCODE -eq 0) {
    $SearchRoot = Resolve-Path $SearchRoot
  }
  else {
    $SearchRoot = Get-Location
  }

  $Selection = $null
  $ExitCode = -1
  if (Get-Command "tv") {
    $Selection = (tv dirs $SearchRoot -i $query --no-preview --select-1 --no-remote | Out-String).Trim()
    $ExitCode = $LASTEXITCODE
  }
  elseif (Get-Command "fd" -and Get-Command "fzf") {
    try {
      Push-Location $SearchRoot
      $Env:FZF_DEFAULT_COMMAND = "fd --type d";
      $Selection = (fzf --ansi -- --query "$query" | Out-String).Trim();
      $ExitCode = $LASTEXITCODE
    }
    finally {
      Pop-Location
    }
  }
  else {
    throw "Neither tv nor fd/fzf are available. Please install one of them."
  }

  if ($ExitCode -ne 0) {
    throw "Selection tool exited with code $ExitCode"
  }

  $Selection = Join-Path $SearchRoot $Selection
  $Selection = Resolve-Path $Selection
  return $Selection
}

function global:goto {
  param(
    [string]$query
  )

  $Selection = Select-Path -query $query
  if (-not $Selection) {
    Write-Error "Unable to find directory matching query: $query"
    return
  }

  if (Test-Path -PathType Container $Selection) {
    $DirectoryName = $Selection
  }
  else {
    $DirectoryName = (Get-Item $Selection).DirectoryName
  }
  
  Set-Location $DirectoryName
}

function global:edit {
  # If we're in a git repo, use that as the search path
  $SearchRoot = (git rev-parse --show-toplevel 2>$null | Out-String).Trim()
  if ($LASTEXITCODE -eq 0) {
    $SearchRoot = Resolve-Path $SearchRoot
  }
  else {
    $SearchRoot = Get-Location
  }

  # Figure out where the user wants to go
  $Selection = $null
  $ExitCode = -1
  try {
    Push-Location $SearchRoot

    $Env:FZF_DEFAULT_COMMAND = "fd -tf"; $Selection = fzf --ansi --color "hl:-1:underline, hl+:-1:underline:reverse" --preview 'bat --color=always {1}' --preview-window 'up,60%,border-bottom,+{2}+3/3,~3' -- --query "$args" | Out-String;
    $ExitCode = $LASTEXITCODE
    
    $Selection = $Selection.Trim()
  }
  finally {
    Pop-Location
  }

  if ($ExitCode -ne 0) {
    Write-Error "fzf exited with code $ExitCode"
    return
  }

  $Selection = Join-Path $SearchRoot $Selection
  $Selection = Resolve-Path $Selection

  # Run the appropriate command
  if (Test-Path $Selection) {
    Invoke-Expression "$Env:EDITOR $Selection"
  }
  else {
    Write-Error "Unable to find entry at $Selection"
  }
}
New-Alias -Force e edit

if ($IsWindows) {
  function global:which ($command) { 
    # This is a Windows-only function because it could mess up with Linux where which is actually an executable
    Get-Command -Name $command -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Path -ErrorAction SilentlyContinue 
  }
}

function global:clip {
  # Cross-platform way to copy to clipboard
  param(
    [Parameter(ValueFromPipeline = $true)]
    [string]$InputObject,
    [int]$Depth = 1
  )
  
  begin {
    $contents = New-Object System.Text.StringBuilder
  }

  process {
    if ($InputObject) {
      if (Test-Path $InputObject -PathType Leaf) {
        [void]$contents.Append((Get-Content $InputObject -Raw))
      }
      elseif (Test-Path $InputObject -PathType Container) {
        $files = Get-ChildItem $InputObject -Recurse -File -Depth $Depth
        foreach ($file in $files) {
          [void]$contents.AppendLine("---- file: $($file.FullName) ----")
          [void]$contents.Append((Get-Content $file.FullName -Raw) + "`n")
        }
      }
      else {
        [void]$contents.Append($InputObject)
      }
    }
    else {
      [void]$contents.AppendLine($_)
    }
  }

  end {
    Set-Clipboard -Value $contents.ToString()
  }
}

function global:nvc {
  [CmdletBinding()]
  param(
    [switch]$Clear
  )

  $NvimPath = $null
  $NvimDataPath = $null
  $XdgConfigHome = $env:XDG_CONFIG_HOME
  $XdgDataHome = $env:XDG_DATA_HOME
  if ($XdgConfigHome) {
    $NvimPath = "$XdgConfigHome/nvim"
  }
  else {
    if ($IsWindows) {
      $NvimPath = "$env:LOCALAPPDATA/nvim"
    }
    else {
      $NvimPath = "~/.config/nvim"
    }
  }

  if ($XdgDataHome) {
    $NvimDataPath = "$XdgDataHome/nvim"
  }
  else {
    if ($IsWindows) {
      $NvimDataPath = "$env:LOCALAPPDATA/nvim-data"
    }
    else {
      throw "XDG_DATA_HOME is not set and $env:LOCALAPPDATA is not set. Please set one of them."
    }
  }

  if ($Clear) {
    if (Test-Path $NvimDataPath) {
      Remove-Item -Path $NvimDataPath -Recurse -Force
    }
  }
  else {
    if (-not (Test-Path $NvimPath)) {
      throw "nvim config directory not found at $NvimPath"
    }
    
    Set-Location $NvimPath
  }
}

function dns {
  dig +noall +answer +multiline $args any
}
function dns {
  dig +noall +answer +multiline $args any
}
