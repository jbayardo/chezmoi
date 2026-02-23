# Setup profile.ps1 hardlink

$ProfilePaths = @();
if ($IsWindows) {
    $ProfilePaths += "$env:USERPROFILE\Documents\PowerShell\Microsoft.PowerShell_profile.ps1"
    $ProfilePaths += "$env:USERPROFILE\Documents\PowerShell\Microsoft.VSCode_profile.ps1"
}
else {
    $ProfilePaths += "~/.config/powershell/Microsoft.PowerShell_profile.ps1"
    $ProfilePaths += "~/.config/powershell/Microsoft.VSCode_profile.ps1"
}

if ($PROFILE) {
    $ProfilePaths += $PROFILE
}

$ProfilePaths = $ProfilePaths | Where-Object { $_ } | Select-Object -Unique

foreach ($profilePath in $profilePaths) {
    if (Test-Path $profilePath) {
        Remove-Item $profilePath -Force
    }

    $ProfileTargetFolderPath = [System.IO.Path]::GetFullPath((Join-Path $profilePath ".."))
    if (!(Test-Path $ProfileTargetFolderPath)) {
        New-Item -ItemType Directory -Path $ProfileTargetFolderPath
    }

    $targetProfilePath = "~/.dev/powershell/profile.ps1" | Resolve-Path
    Write-Output "Creating hardlink to $targetProfilePath in $profilePath"
    if ($IsWindows) {
        fsutil hardlink create $profilePath $targetProfilePath
    }
    else {
        ln -s $targetProfilePath $profilePath
    }
}

# Create config directory
New-Item "~/.config" -ItemType Directory -Force

# Create tmp directory in Downloads
if ($IsWindows) {
    $DownloadsPath = (New-Object -ComObject Shell.Application).NameSpace('shell:Downloads').Self.Path
    $DownloadsTmpSource = Join-Path $DownloadsPath "tmp"
    if (-not (Test-Path $DownloadsTmpSource)) {
        $DownloadsTmpTarget = Join-Path $Env:TEMP "downloads"
        mkdir $DownloadsTmpTarget
        New-Item -ItemType SymbolicLink -Path $DownloadsTmpSource -Target $DownloadsTmpTarget -Force
    }
}

$EspansoTargetPath = "~/.config/espanso" | Resolve-Path
if ($IsWindows) {
    $EspansoConfigPath = "$Env:APPDATA\espanso"
}
elseif ($IsMacOS) {
    $EspansoConfigPath = "$Env:HOME/Library/Application Support/espanso"
}

function Test-ReparsePoint([string]$path) {
    $file = Get-Item $path -Force -ea SilentlyContinue
    return [bool]($file.Attributes -band [IO.FileAttributes]::ReparsePoint)
}

# On Linux, chezmoi manages ~/.config/espanso directly, no symlink needed.
# On Windows/macOS, symlink from OS-specific path to ~/.config/espanso.
if ($EspansoConfigPath -and -not (Test-ReparsePoint $EspansoConfigPath)) {
    New-Item -ItemType SymbolicLink -Path $EspansoConfigPath -Target $EspansoTargetPath -Force
}

if (Get-Command "az") {
    az config set extension.use_dynamic_install=yes_without_prompt
    az config set auto-upgrade.enable=no
}

if ($IsWindows) {
    $ExtraWindowsPaths = @(
        "$Env:ProgramFiles\Go\bin",
        "$Env:ProgramFiles\GitHub CLI",
        "$Env:ProgramFiles\KeePassXC",
        "$Env:ProgramData\nvm",
        "$Env:ProgramFiles\nodejs",
        "$Env:ProgramFiles\LLVM\bin",
        "$Env:ProgramFiles\CMake\bin",
        "${Env:ProgramFiles(x86)}\Hourglass",
        "${Env:ProgramFiles(x86)}\GnuWin32\bin",
        "$Env:APPDATA\Python\Python310\Scripts",
        "$Env:APPDATA\Python\Python311\Scripts",
        "$Env:APPDATA\local\bin\",
        "$Env:USERPROFILE\.local\bin",
        "$Env:USERPROFILE\.cargo\bin",
        "$Env:USERPROFILE\.dotnet\tools"
        "$Env:USERPROFILE\.go\bin",
        "$Env:ProgramFiles\OpenSSH"
    )

    foreach ($path in $ExtraWindowsPaths) {
        if (Test-Path -PathType Container $path) {
            Add-PathVariable $path
        }
    }
}