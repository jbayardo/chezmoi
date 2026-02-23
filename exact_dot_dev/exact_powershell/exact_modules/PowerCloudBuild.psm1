function global:Find-CloudBuild {
  $Paths = @(
    "C:\src\CloudBuild",
    "Q:\src\CloudBuild"
  )

  foreach ($Path in $Paths) {
    if (Test-Path $Path) {
      return $Path
    }
  }

  throw "Unable to find CloudBuild repository"
}

function global:Import-CloudBuild {
  Param(
    [Switch] $Scripts = $false,
    [Switch] $Shell = $false,
    [Switch] $AKS = $false
  )

  if (Get-Command Get-ActiveBuilds -ErrorAction SilentlyContinue) {
    Write-Debug "CloudBuild module already imported."
    return
  }

  $EnlistmentRoot = Find-CloudBuild

  try {
    Push-Location $EnlistmentRoot

    if ($Shell) {
      $ShellInit = Join-Path $EnlistmentRoot "/dev/shell/init.ps1"
      . $ShellInit
    }

    if ($Scripts) {
      @(
        "CI\Modules\Common\Common.psd1",
        "CI\Modules\AutoPilot\AutoPilot.psd1",
        "CloudBuildModule\CloudBuild.psd1",
        "Admin\Admin.psm1",
        "EnvironmentManagement\Stamps.psm1",
        "EnvironmentManagement\StampsDnsNames.psm1",
        "EnvironmentManagement\VESnippetGeneration.psm1"
      ) | ForEach-Object {
        $module = Import-Module (Join-Path $EnlistmentRoot "/private/Scripts/ps/$($_)") -Force -Passthru -DisableNameChecking -Scope Global
        Write-Host "`nAvailable $([IO.Path]::GetFileNameWithoutExtension($_)) Commands (from $_):"
        $module.ExportedCommands.Keys | ForEach-Object { Write-Host "     $_" }
      }
    }

    if ($AKS) {
      Import-Module "$EnlistmentRoot\private\Scripts\AKS\AKSModule.psd1" -Force -DisableNameChecking -Scope Global
    }
  }
  finally {
    Pop-Location
  }
}
New-Alias -Force pcb Import-CloudBuild

function global:Stop-User-Builds {
  [CmdletBinding()]
  Param(
    [String] $UserPrefix
  )

  Import-CloudBuild -Scripts
  Get-ActiveBuilds -Environment prod | Where-Object { $_.Requester.StartsWith($UserPrefix) } | ForEach-Object { Stop-Build -Environment prod -UniqueSessionId $_.UniqueSessionId }
}

function global:qreimage {
  [CmdletBinding()]
  Param(
    [String] $Machine
  )

  Import-CloudBuild -Scripts
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
  Reimage-Machine -Environment PROD -Machine $Machine -Stamp $Stamp
}

function global:qci {
  [CmdletBinding()]
  Param(
    [Switch] $Open
  )

  $Branch = (git rev-parse --abbrev-ref HEAD | Out-String).Trim()
  if ($Open) {
    az pipelines run --detect --name "CloudBuild Deploy Services CI" --branch $Branch --open
  }
  else {
    az pipelines run --detect --name "CloudBuild Deploy Services CI" --branch $Branch
  }
}

function global:Get-LatestBuildXLVersion {
  # Corresponds to: https://dev.azure.com/mseng/Domino/_build?definitionId=15756
  $Runs = az pipelines runs list -p Domino --org "https://dev.azure.com/mseng" --pipeline-ids 15756 --query-order FinishTimeDesc --status completed --top 1 2>$null
  $Runs = $Runs | ConvertFrom-Json
  $LatestVersion = $Runs | ForEach-Object { $_.buildNumber } | Select-Object -First 1
  return $LatestVersion
}

function global:qbxlu {
  $CloudBuildPath = Find-CloudBuild

  try {
    Push-Location $CloudBuildPath

    $Branch = (git rev-parse --abbrev-ref HEAD | Out-String).Trim()
    if ($Branch -ne "main") {
      throw "You are on a feature branch. Unwilling to proceed."
    }

    git checkout main
    git pull

    $LatestVersion = Get-LatestBuildXLVersion
    if ($null -eq $LatestVersion -or [string]::IsNullOrWhiteSpace($LatestVersion)) {
      throw "Unable to find the latest BuildXL version"
    }
    Write-Host "Latest BuildXL version: $LatestVersion"

    $Branch = (git rev-parse --abbrev-ref HEAD | Out-String).Trim()
    if ($Branch -ne "main") {
      throw "You are on a feature branch. Unwilling to proceed."
    }

    git branch | ForEach-Object {
      $branch = $_.Trim()

      if ($branch -match "dev/jubayard/BuildXL-.+") {
        Write-Host "Deleting branch: $branch"
        git branch -D $branch 2>$null
        git push origin --delete $branch 2>$null
      }
    }
    
    $FeatureBranch = "dev/jubayard/BuildXL-$LatestVersion"
    git checkout -b $FeatureBranch

    try {
      $PackagesPropsPath = Join-Path $CloudBuildPath "Directory.packages.props"
      $packagesProps = Get-Content -path $PackagesPropsPath -Raw
      $updatedProps = ($packagesProps -replace '<BuildXLPackagesVersion>.+?</BuildXLPackagesVersion>', "<BuildXLPackagesVersion>$LatestVersion</BuildXLPackagesVersion>")
      $updatedProps | Set-Content -NoNewline -Path $PackagesPropsPath
      
      git commit -am "Upgrade BuildXL packages to $LatestVersion"
      git push --set-upstream origin --force $FeatureBranch

      az repos pr create --open --description "Upgrade BuildXL packages to $LatestVersion" --title "Upgrade BuildXL packages to $LatestVersion" --target-branch main --source-branch $FeatureBranch
    }
    finally {
      git checkout main
    }
  }
  finally {
    Pop-Location
  }

}

function global:scoobydoobydoo {
  [CmdletBinding()]
  Param(
    [Switch] $Rollback,

    [Switch] $Publish,

    [String] $BuildXLPath = "Q:\src\BuildXL.Internal",

    [String] $CloudBuildPath = $null
  )

  if ($null -eq $CloudBuildPath) {
    $CloudBuildPath = Find-CloudBuild;
  }

  $RepoRoot = (git rev-parse --show-toplevel | Out-String).Trim()
  $Remote = (git remote get-url origin | Out-String).Trim()
  if ($Remote.Contains("BuildXL")) {
    $BuildXLPath = $RepoRoot
  }
  elseif ($Remote.Contains("CloudBuild")) {
    $CloudBuildPath = $RepoRoot
  }

  $BuildXLId = "$([Environment]::UserName)$(Get-Date -Format "yyyyMMddHHmmss")"
  $BuildXLVersion = "0.1.0-$BuildXLId"
  $Mode = "Release" # Release or Debug
  $DropAccountName = "cloudbuild"
  $CloudBuildDropName = $BuildXLId
  $BuildXLDropName = $BuildXLVersion

  $NugetPath = "C:\Users\jubayard\Downloads\nuget.exe"
  $DropExePath = "C:\Users\jubayard\Downloads\Drop.App\lib\net45\drop.exe"
  $LocalNugetFeedPath = "C:\LocalNugetFeed\$BuildXLId";

  if ($Mode -eq "Release") {
    $CloudBuildMode = "retail"
  }
  elseif ($Mode -eq "Debug") {
    $CloudBuildMode = "debug"
  }
  else {
    throw "Invalid mode: $Mode"
  }
  $BuildXLNugetPackagesPath = Join-Path $BuildXLPath "Out/Bin/$mode/pkgs/"
  $BuildXLPrivateNugetPackagesPath = Join-Path $BuildXLPath "Out/Bin/$mode/private/pkgs/"

  Write-Host "Running with $BuildXLPath and $CloudBuildPath in $Mode mode. The drop will be published to $DropAccountName/$CloudBuildDropName for CloudBuild and $DropAccountName/$BuildXLDropName for BuildXL."

  $BuildPaths = @(
    (Join-Path $CloudBuildPath "private\BuildEngine\BuildClient\src"),
    (Join-Path $CloudBuildPath "private\BuildEngine\Prepare\src"),
    (Join-Path $CloudBuildPath "private\Services\ServiceTools\BuildRunners")
  )

  $BuildOutputs = @(
    (Join-Path $CloudBuildPath "target\distrib\$CloudBuildMode\amd64\ClientTools"),
    (Join-Path $CloudBuildPath "target\distrib\$CloudBuildMode\amd64\App\BuildRunners")
  )

  # Cleanup packages that might be bothersome
  Remove-Item -Recurse -Force -ErrorAction SilentlyContinue (Join-Path $BuildXLPath "Out/Bin") > $null
  Remove-Item -Recurse -Force -ErrorAction SilentlyContinue (Join-Path $CloudBuildPath "target") > $null
  Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $LocalNugetFeedPath > $null

  # Produce BuildXL NuGet packages locally
  try {
    Push-Location $BuildXLPath

    # Generate cache NuGet packages and publish to a local nuget feed
    Invoke-Expression ".\bxl -SharedCacheMode Disable NugetPackages.dsc privatePackages.dsc /q:$mode /p:[BuildXL.Branding]SemanticVersion=$BuildXLVersion /p:[BuildXL.Branding]PrereleaseTag='' /p:[BuildXL.Branding]SourceIdentification='1' /exp:lazysodeletion- /forceGenerateNuGetSpecs+"
    if ($LASTEXITCODE -ne 0) {
      throw "Failed to generate BuildXL NuGet packages"
    }

    New-Item -Path $LocalNugetFeedPath -ItemType Directory -Force
    Get-ChildItem $BuildXLNugetPackagesPath | ForEach-Object { 
      $Command = "$NugetPath push `"$($_.FullName)`" -source `"$LocalNugetFeedPath`""
      Write-Host "Publishing $($_.FullName) to local NuGet feed with command: $Command"
      Invoke-Expression $Command
    }

    Get-ChildItem $BuildXLPrivateNugetPackagesPath | ForEach-Object { 
      $Command = "$NugetPath push `"$($_.FullName)`" -source `"$LocalNugetFeedPath`""
      Write-Host "Publishing $($_.FullName) to local NuGet feed with command: $Command"
      Invoke-Expression $Command
    }

    if ($Publish) {
      # Generate BuildXL Drop
      Invoke-Expression ".\bxl -Minimal -DeployConfig Release -SharedCacheMode Disable /q:$($mode)Net8 /p:[BuildXL.Branding]SemanticVersion=$BuildXLVersion /p:[BuildXL.Branding]PrereleaseTag='' /p:[BuildXL.Branding]SourceIdentification='1' /exp:lazysodeletion- /forceGenerateNuGetSpecs+"

      Invoke-Expression ".\dropout $BuildXLDropName $DropAccountName ' ' true"
    }
    
    $PackagesPropsPath = Join-Path $CloudBuildPath "Directory.packages.props"
    try {
      Push-Location $CloudBuildPath

      Remove-Item -Recurse -Force target/ -ErrorAction SilentlyContinue > $null
      Remove-Item -Recurse -Force C:\CloudBuildCache -ErrorAction SilentlyContinue > $null
      Remove-Item -Recurse -Force C:\HC -ErrorAction SilentlyContinue > $null
      Remove-Item -Recurse -Force C:\_cache -ErrorAction SilentlyContinue > $null
      git clean -xdf --exclude=.vs/ > $null

      pvs

      # Add local NuGet source to CloudBuild's nuget.config
      Invoke-Expression "$NugetPath sources add -Source $LocalNugetFeedPath -name `"BuildXL.Testing`""

      # Update CloudBuild to reference the generated NuGet packages
      $packagesProps = Get-Content -path $PackagesPropsPath -Raw
      $updatedProps = ($packagesProps -replace '<BuildXLPackagesVersion>.+?</BuildXLPackagesVersion>', "<BuildXLPackagesVersion>$BuildXLVersion</BuildXLPackagesVersion>")
      $updatedProps | Set-Content -Path $PackagesPropsPath

      # Build QuickBuild
      $continue = $true
      foreach ($BuildPath in $BuildPaths) {
        try {
          Push-Location $BuildPath
          msbuild /property:Configuration=$mode /tl:false /p:EnableQuickBuildCachePlugin=false
          if ($LASTEXITCODE -ne 0) {
            $continue = $false
            break;
          }
        }
        finally {
          Pop-Location
        }
      }

      if (-not $continue) {
        throw "Build failed."
      }

      if (-not $Publish) {
        return;
      }

      # CloudBuild & QuickBuild really like the drops to conform to the retail/amd64 layout, so we do that.
      $TemporaryPath = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
      try {
        $TargetPath = (Join-Path $TemporaryPath "$CloudBuildMode/amd64")
        New-Item -ItemType Directory -Path $TargetPath -Force
        foreach ($BuildOutput in $BuildOutputs) {
          Move-Item -Path $BuildOutput -Destination $TargetPath
        }

        Invoke-Expression "$DropExePath create --aadAuth --dropservice https://$($DropAccountName).artifacts.visualstudio.com/DefaultCollection --name `"$($CloudBuildDropName)`""
        Invoke-Expression "$DropExePath publish --aadAuth --dropservice https://$($DropAccountName).artifacts.visualstudio.com/DefaultCollection --name `"$($CloudBuildDropName)`" -d $TemporaryPath"
        Invoke-Expression "$DropExePath finalize --aadAuth --dropservice https://$($DropAccountName).artifacts.visualstudio.com/DefaultCollection --name `"$($CloudBuildDropName)`""
      }
      finally {
        Remove-Item -Force -Recurse $TemporaryPath -ErrorAction Ignore
      }

      $DropUrl = "https://$($DropAccountName).artifacts.visualstudio.com/DefaultCollection/_apis/drop/drops/$($CloudBuildDropName)"

      $ExploreUrl = "https://$($DropAccountName).visualstudio.com/DefaultCollection/_apps/hub/ms-vscs-artifact.build-tasks.drop-hub-group-explorer-hub?forcelowercase=true&name=$($CloudBuildDropName)"
      Write-Host "Explore URL: $ExploreUrl"

      $QuickBuildDropUrl = "$($DropUrl)?root=$($CloudBuildMode)/amd64/ClientTools"
      Write-Host "CloudBuildTools Drop URL: $QuickBuildDropUrl"

      $BuildRunnersDropUrl = "$($DropUrl)?root=$($CloudBuildMode)/amd64/BuildRunners"
      Write-Host "BuildRunners Drop URL: $BuildRunnersDropUrl"

      $BuildXLExploreUrl = "https://$($DropAccountName).visualstudio.com/DefaultCollection/_apps/hub/ms-vscs-artifact.build-tasks.drop-hub-group-explorer-hub?forcelowercase=true&name=$($BuildXLDropName)"
      Write-Host "BuildXL Explore URL: $BuildXLExploreUrl"

      $BuildXLDropUrl = "https://$($DropAccountName).artifacts.visualstudio.com/DefaultCollection/_apis/drop/drops/$($BuildXLDropName)?root=$($Mode)/win-x64"
      Write-Host "BuildXL Drop URL: $BuildXLDropUrl"
    }
    finally {
      if ($Rollback) {
        git checkout -- Directory.Packages.props
        git checkout -- nuget.config
      }

      Pop-Location
    }
  }
  finally {
    if ($Rollback) {
      Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $LocalNugetFeedPath
    }

    Pop-Location
  }
}


function global:mkgbr {
  $CloudBuildPath = "Q:/src/CloudBuild2";

  $DropId = "$([Environment]::UserName)$(Get-Date -Format "yyyyMMddHHmmss")"
  $Mode = "Release" # Release or Debug
  $DropAccountName = "cloudbuild"
  $CloudBuildDropName = $DropId

  $DropExePath = "C:\Users\jubayard\Downloads\Drop.App\lib\net45\drop.exe"

  if ($Mode -eq "Release") {
    $CloudBuildMode = "retail"
  }
  elseif ($Mode -eq "Debug") {
    $CloudBuildMode = "debug"
  }
  else {
    throw "Invalid mode: $Mode"
  }

  $BuildPaths = @(
    (Join-Path $CloudBuildPath "private\Services\ServiceTools\BuildRunners")
  )

  $BuildOutputs = @(
    (Join-Path $CloudBuildPath "target\distrib\$CloudBuildMode\amd64\App\BuildRunners")
  )

  # Cleanup packages that might be bothersome
  Remove-Item -Recurse -Force -ErrorAction SilentlyContinue (Join-Path $CloudBuildPath "target") > $null

  # Produce BuildXL NuGet packages locally
  try {
    Push-Location $CloudBuildPath

    Remove-Item -Recurse -Force target/ -ErrorAction SilentlyContinue > $null
    Remove-Item -Recurse -Force C:\CloudBuildCache -ErrorAction SilentlyContinue > $null
    Remove-Item -Recurse -Force C:\HC -ErrorAction SilentlyContinue > $null
    Remove-Item -Recurse -Force C:\_cache -ErrorAction SilentlyContinue > $null
    git clean -xdf --exclude=.vs/ > $null

    pvs

    $continue = $true
    foreach ($BuildPath in $BuildPaths) {
      try {
        Push-Location $BuildPath
        msbuild /property:Configuration=$mode /tl:false /p:EnableQuickBuildCachePlugin=false
        if ($LASTEXITCODE -ne 0) {
          $continue = $false
          break;
        }
      }
      finally {
        Pop-Location
      }
    }

    if (-not $continue) {
      throw "Build failed."
    }

    $TemporaryPath = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
    try {
      $TargetPath = (Join-Path $TemporaryPath "$CloudBuildMode/amd64")
      New-Item -ItemType Directory -Path $TargetPath -Force
      foreach ($BuildOutput in $BuildOutputs) {
        Move-Item -Path $BuildOutput -Destination $TargetPath
      }

      Invoke-Expression "$DropExePath create --aadAuth --dropservice https://$($DropAccountName).artifacts.visualstudio.com/DefaultCollection --name `"$($CloudBuildDropName)`""
      Invoke-Expression "$DropExePath publish --aadAuth --dropservice https://$($DropAccountName).artifacts.visualstudio.com/DefaultCollection --name `"$($CloudBuildDropName)`" -d $TemporaryPath"
      Invoke-Expression "$DropExePath finalize --aadAuth --dropservice https://$($DropAccountName).artifacts.visualstudio.com/DefaultCollection --name `"$($CloudBuildDropName)`""
    }
    finally {
      Remove-Item -Force -Recurse $TemporaryPath -ErrorAction Ignore
    }

    $DropUrl = "https://$($DropAccountName).artifacts.visualstudio.com/DefaultCollection/_apis/drop/drops/$($CloudBuildDropName)"

    $BuildRunnersDropUrl = "$($DropUrl)?root=$($CloudBuildMode)/amd64/BuildRunners"
    Write-Host "BuildRunners Drop URL: $BuildRunnersDropUrl"
  }
  finally {
    Pop-Location
  }
}

New-Alias qb quickbuild

function global:Convert-DropToExplorer {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [string]
    $Url,

    [switch]
    $DontOpen
  )

  $Target = [Regex]::Replace($Url, 'https?://([A-Za-z0-9]+)\.artifacts\.visualstudio\.com/DefaultCollection/_apis/drop/drops/([^\?]+)(\?.*)', 'https://$1.visualstudio.com/DefaultCollection/_apps/hub/ms-vscs-artifact.build-tasks.drop-hub-group-explorer-hub?forcelowercase=true&name=$2') 

  if ($DontOpen) {
    return $DontOpen
  }
  else {
    Start-Process $Target
  }
}

New-Alias drop2explorer Convert-DropToExplorer