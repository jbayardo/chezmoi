function global:Import-Python {
  $CondaPaths = @("$env:UserProfile\miniconda3", "$env:UserProfile\anaconda3", "C:\miniconda3", "$Env:ProgramData\anaconda3", "C:\anaconda3", "$Env:ProgramData\miniconda3", "$Env:LocalAppData\miniconda3");
  
  $Conda = $null;
  foreach ($Path in $CondaPaths) {
    if (Test-Path -PathType Container $Path) {
      $Conda = $Path
      break
    }
  }

  if ($null -eq $Conda) {
    Write-Error "Unable to find Anaconda installation"
  }
  else {
    # $Env:CONDA_EXE = "$Conda\Scripts\conda.exe"
    # $Env:_CE_M = ""
    # $Env:_CE_CONDA = ""
    # $Env:_CONDA_ROOT = "$Conda"
    # $Env:_CONDA_EXE = "$Conda\Scripts\conda.exe"
    # $CondaModuleArgs = @{ChangePs1 = $True }
    # Import-Module -Global "$Env:_CONDA_ROOT\shell\condabin\Conda.psm1" -ArgumentList $CondaModuleArgs
    # Remove-Variable CondaModuleArgs

    # conda activate $conda
    & "$Conda\shell\condabin\conda-hook.ps1"
    conda activate $Conda
  }
}
New-Alias -Force ppy Import-Python

function global:Get-VsInstallInfo {
  $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"

  if (-not (Test-Path -PathType Leaf $vswhere)) {
    Write-Error "Unable to find any recent Visual Studio installation. Please install the latest Visual Studio and try again."
    return $null
  }

  # Look for any recent version of Visual Studio
  $vsInstallInfoJson = & $vswhere /nologo /all /prerelease /format json /latest

  # ConvertFrom-Json requires the root element be an object, not an array, so wrap it.
  $vsInstallInfo = (ConvertFrom-Json "{ 'data': $vsInstallInfoJson }").data[0]

  if ($null -eq $vsInstallInfo) {
    Write-Error "Unable to retrieve Visual Studio installation information."
    return $null
  }

  return $vsInstallInfo
}

function global:Import-VcVarsAll {
  [CmdletBinding()]
  param (
    [Parameter(Position = 0)]
    [String] $Arch = "x64",

    [Parameter(Position = 1)]
    [String] $PlatformType = $null,

    [Parameter(Position = 2)]
    [String] $WinSdkVersion = $null,

    [Switch] $Force = $false
  )

  $msbuild = Get-Command -Name msbuild -ErrorAction Ignore
  if ($Force -eq $false -and ($null -ne $Env:VSCMD_VER -or $null -ne $msbuild)) {
    Write-Warning "Visual Studio Developer Command Prompt is already initialized."
    return
  }

  $vsInstallInfo = Get-VsInstallInfo
  if ($null -eq $vsInstallInfo) {
    return
  }

  $vsInstallVersion = New-Object -TypeName System.Version -ArgumentList $vsInstallInfo.installationVersion
  $vsInstallPath = $vsInstallInfo.installationPath
  $vcVarsAll = "$vsInstallPath\VC\Auxiliary\Build\vcvarsall.bat"

  if (-not (Test-Path $vcVarsAll)) {
    Write-Error "Unable to find $vcVarsAll.  Ensure your Visual Studio installation is complete and try again."
    Exit 1
  }

  $parameters = (@($Arch, $PlatformType, $WinSdkVersion) | Where-Object { $_ -ne $null }) -join " "
  Write-Host "Initializing Developer Command Prompt for $($vsInstallInfo.displayName) ($vsInstallVersion) [$parameters]"
  & "${env:COMSPEC}" /s /c "`"$vcVarsAll`" $parameters && set" | ForEach-Object {
    if ($_ -match "^([A-Za-z0-9_]+?)=(.+)$") {
      Write-Debug "Setting $($Matches[1])=$($Matches[2])"
      Set-Item -Force -Path "ENV:\$($Matches[1])" -Value "$($Matches[2])"
    }
    else {
      Write-Warning "Ignoring: $_"
    }
  } 
}

function global:Import-VsDevCmd {
  [CmdletBinding()]
  param (
    [Switch] $Force = $false
  )

  $msbuild = Get-Command -Name msbuild -ErrorAction Ignore
  if ($Force -eq $false -and $null -ne $Env:VSCMD_VER -and $msbuild) {
    Write-Warning "Visual Studio Developer Command Prompt is already initialized."
    return
  }

  $Env:EnableQuickBuildCachePlugin = $false;

  $vsInstallInfo = Get-VsInstallInfo
  if ($null -eq $vsInstallInfo) {
    return
  }

  $vsInstallVersion = New-Object -TypeName System.Version -ArgumentList $vsInstallInfo.installationVersion
  $vsInstallPath = $vsInstallInfo.installationPath
  $vsDevCmd = "$vsInstallPath\Common7\Tools\vsdevcmd.bat"

  if (-not (Test-Path -PathType Leaf $vsDevCmd)) {
    Write-Error "Unable to find $vsDevCmd. Ensure your Visual Studio installation is complete and try again."
    Exit 1
  }

  Write-Host "Initializing Developer Command Prompt for $($vsInstallInfo.displayName) ($vsInstallVersion)"
  & "${env:COMSPEC}" /s /c "`"$vsDevCmd`" -no_logo && set" | ForEach-Object {
    if ($_ -match "^([A-Za-z0-9_]+?)=(.+)$") {
      Write-Debug "Setting $($Matches[1])=$($Matches[2])"
      Set-Item -Force -Path "ENV:\$($Matches[1])" -Value "$($Matches[2])"
    }
    else {
      Write-Warning "Ignoring: $_"
    }
  }
}
New-Alias -Force pvs Import-VsDevCmd
New-Alias -Force Import-VisualStudio Import-VsDevCmd

function global:Find-SolutionCandidates {
  $RepoRoot = (git rev-parse --show-toplevel 2>$null | Out-String).Trim()
  if (-not $RepoRoot) {
    Write-Error "Not inside a git repository"
    return
  }

  $RepoRoot = Resolve-Path $RepoRoot
  Push-Location $RepoRoot
  try {
    $Selection = (fd -tf -g '*.proj' | fzf --ansi -- --query "$args" | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) {
      return $null
    }

    if (-not $Selection) {
      return $null
    }

    $Selection = Resolve-Path $Selection
    return (Get-Item $Selection).Directory
  }
  finally {
    Pop-Location
  }
}

function global:Open-VisualStudio {
  [CmdletBinding()]
  Param(
    [Switch]
    $Cache,

    [Switch]
    $Code,

    [Parameter(Mandatory = $false, ValueFromRemainingArguments = $true)]
    [string]
    [AllowEmptyString()]
    [AllowNull()]
    $Query
  )

  $repoRoot = (git rev-parse --show-toplevel 2>$null | Out-String).Trim()

  $repoRemotes = (git remote -v | ForEach-Object {
      $splitLine = $_ -split '\s+'
      "{1}" -f $splitLine[0], $splitLine[1]
    } | Sort-Object | Get-Unique | Out-String).Trim();

  Write-Host "Git: $repoRoot / $repoRemotes"
  if ($repoRemotes.Contains("BuildXL")) {
    $bxlArgs = "-vs"
    if ($Cache) {
      $bxlArgs += " -cache"
    }
    else {
      $bxlArgs += " *.dsc"
    }

    try {
      Push-Location $repoRoot

      $bxlLog = .\bxl $bxlArgs | Out-String
      $solutionPath = ($bxlLog | Select-String -Pattern 'VS Solution File: (.*)' | ForEach-Object { $_.Matches.Groups[1].Value } | Out-String).Trim()
      Write-Host "Solution File Path: $solutionPath"

      if ($Code) {
        code $repoRoot $solutionPath
      }
      else {
        Invoke-Item $solutionPath
      }
    }
    finally {
      Pop-Location
    }
  }
  else {
    # Install SlnGen if its not installed
    if ($null -eq (Get-Command "slngen.exe" -ErrorAction SilentlyContinue)) {
      & "${env:COMSPEC}" /s /c "dotnet tool install --global Microsoft.VisualStudio.SlnGen.Tool --add-source https://api.nuget.org/v3/index.json --ignore-failed-sources"
    }

    Import-VsDevCmd

    $SearchPath = $null
    if (![string]::IsNullOrEmpty($Query)) {
      $SearchPath = Find-SolutionCandidates $Query
    }

    if ([string]::IsNullOrEmpty($SearchPath)) {
      $SearchPath = Get-Location
    }

    Set-Location $SearchPath

    $solutionName = (Get-Item (Get-Location).Path).BaseName + ".sln"

    $dirsProj = Get-ChildItem | Where-Object { $_.Name.EndsWith(".proj") }
    if ($dirsProj.Count -gt 0) {
      if ($Code) {
        slngen -o $solutionName --launch false $dirsProj[0].Name
        code $repoRoot $solutionName
      }
      else {
        slngen -o $solutionName $dirsProj[0].Name
      }

      return
    }

    $sln = Get-ChildItem | Where-Object { $_.Name.EndsWith(".sln") }
    if ($sln.Count -gt 0) {
      Write-Host "Opening existing solution: $($sln[0].FullName)"

      if ($Code) {
        code $repoRoot $sln[0].FullName
      }
      else {
        Invoke-Item $sln[0].FullName
      }
      return
    }

    Write-Error "No solution file found"
  }
}
New-Alias -Force vs Open-VisualStudio

function global:restore {
  msbuild /t:restore (Get-ChildItem *proj | Select-Object -first 1).Name
}