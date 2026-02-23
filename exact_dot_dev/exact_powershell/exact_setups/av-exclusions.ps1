$ExclusionFolderPatterns = @(
  '*\.git'
);

foreach ($ExclusionFolderPattern in $ExclusionFolderPatterns) {
  Write-Host "Adding exclusion folder pattern $ExclusionFolderPattern"
  Add-MpPreference -ExclusionPath $ExclusionFolderPattern
}

$ExclusionFolders = @(
  'C:\src',
  'C:\work',
  'C:\CloudBuildCache',
  'B:\',
  'Q:\',
  '~\.dev',
  '~\.local\share\chezmoi',
  '~\.cargo',
  '~\.dotnet',
  '~\.nuget',
  '~\.vscode'
);

foreach ($ExclusionFolder in $ExclusionFolders) {
  if (Test-Path $ExclusionFolder -PathType Container) {
    $Resolved = Resolve-Path $ExclusionFolder
    Write-Output "Adding exclusion folder $ExclusionFolder -> $Resolved"
    Add-MpPreference -ExclusionPath $Resolved
  }
}

$ExclusionProcesses = @(
  'code.exe',
  'Code.exe',
  'devenv.exe',
  'bxl.exe',
  'buildxl.exe',
  'rustc.exe',
  'msbuild.exe',
  'quickbuild.exe',
  'nuget.exe',
  'cl.exe',
  'csc.exe',
  'link.exe',
  'clang.exe',
  'clang++.exe',
  'gcc.exe',
  'g++.exe',
  'lsd.exe',
  'ldd.exe',
  'git.exe',
  'dotnet.exe',
  'docker.exe',
  'npm.exe',
  'node.exe',
  'nodejs.exe',
  'docker-compose.exe',
  'oh-my-posh.exe',
  'pwsh.exe',
  'powershell.exe',
  'python.exe',
  'chezmoi.exe',
  "onedrive.exe"
);

foreach ($ExclusionProcess in $ExclusionProcesses) {
  Write-Host "Adding exclusion process $ExclusionProcess"
  Add-MpPreference -ExclusionProcess $ExclusionProcess
}

$ExclusionExtensions = @(
  'tmp',
  'cs',
  'cpp',
  'h',
  'hpp',
  'rs',
  'go',
  'py',
  'sh',
  'bat',
  'cmd',
  'ps1',
  'psm1',
  'psd1'
);

foreach ($ExclusionExtension in $ExclusionExtensions) {
  Write-Host "Adding exclusion extension $ExclusionExtension"
  Add-MpPreference -ExclusionExtension $ExclusionExtension
}