# TODO: disable most visual things for perf.
# Installing WSL
wsl --list >NUL
if ($LASTEXITCODE -ne 0) {
  wsl --install
}

############################## DEVELOPER SETTINGS ##############################

# Enable Long Paths
Set-RegistryValue -Path "HKLM:\System\CurrentControlSet\Control\FileSystem" -Name "LongPathsEnabled" -Data 1 -Type DWord -Elevate

# Removing search from task bar
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "SearchboxTaskbarMode" -Data 0 -Type DWord > $null

# Removing Task View button from task bar
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowTaskViewButton" -Data 0 -Type DWord > $null

# Disabling Edge tabs showing in Alt+Tab
Set-RegistryValue -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "MultiTaskingAltTabFilter" -Data 3 -Type DWord

# Enable Developer Mode
Set-RegistryValue -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\AppModelUnlock" -Name "AllowDevelopmentWithoutDevLicense" -Data 1 -Type DWord -Elevate

# Showing file extensions in Explorer
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "HideFileExt" -Data 0 -Type DWord

# Showing hidden files and directories in Explorer
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Hidden" -Data 1 -Type DWord

# Restore classic context menu"
Set-RegistryValue -Path "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"

############################### PRIVACY SETTINGS ###############################

# Disable Windows Copilot
Set-RegistryValue -Path "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot" -Data 1 -Type DWord -Elevate

# Disable Bing in Windows Search
Set-RegistryValue -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" -Name "BingSearchEnabled" -Data 0 -Type DWord -Elevate

# Disable Cortana
Set-RegistryValue -Path "HKCU:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "AllowCortana" -Data 0 -Type DWord -Elevate

# Disable Windows Error Reporting
Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting" -Name "Disabled" -Data 1 -Type DWord -Elevate
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting" -Name "Disabled" -Data 1 -Type DWord -Elevate

# Disable Windows Tips
Set-RegistryValue -Path "HKLM:\Software\Policies\Microsoft\Windows\CloudContent" -Name "DisableSoftLanding" -Data 1 -Type DWord -Elevate
Set-RegistryValue -Path "HKLM:\Software\Policies\Microsoft\Windows\CloudContent" -Name "DisableWindowsSpotlightFeatures" -Data 1 -Type DWord -Elevate
Set-RegistryValue -Path "HKLM:\Software\Policies\Microsoft\Windows\CloudContent" -Name "DisableWindowsConsumerFeatures" -Data 1 -Type DWord -Elevate
Set-RegistryValue -Path "HKLM:\Software\Policies\Microsoft\Windows\DataCollection" -Name "DoNotShowFeedbackNotifications" -Data 1 -Type DWord -Elevate
Set-RegistryValue -Path "HKLM:\Software\Policies\Microsoft\WindowsInkWorkspace" -Name "AllowSuggestedAppsInWindowsInkWorkspace" -Data 0 -Type DWord -Elevate

# Opting out of Windows Telemetry
Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Data 0 -Type DWord -Elevate

Set-RegistryValue -Path "HKLM:\SOFTWARE\Wow6432Node\Microsoft\VSCommon\17.0\SQM" -Name "OptIn" -Data 0 -Type DWord -Elevate

Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Accessibility Insights for Windows" -Name "DisableTelemetry" -Data 1 -Type DWord -Elevate

# Opt out of lots of telemetry
Set-EnvironmentVariable -Name "POWERSHELL_UPDATECHECK" -Value "OFF"
Set-EnvironmentVariable -Name "POWERSHELL_UPDATECHECK_OPTOUT" -Value 1
Set-EnvironmentVariable -Name "POWERSHELL_TELEMETRY_OPTOUT" -Value 1
Set-EnvironmentVariable -Name "DOTNET_CLI_TELEMETRY_OPTOUT" -Value 1
Set-EnvironmentVariable -Name "GATSBY_TELEMETRY_DISABLED" -Value 1
Set-EnvironmentVariable -Name "NEXT_TELEMETRY_DISABLED" -Value 1
Set-EnvironmentVariable -Name "NUXT_TELEMETRY_DISABLED" -Value 1
Set-EnvironmentVariable -Name "VCPKG_DISABLE_METRICS" -Value 1
Set-EnvironmentVariable -Name "BINSTALL_DISABLE_TELEMETRY" -Value true
Disable-AzDataCollection

# TODO: setup dev drive https://learn.microsoft.com/en-us/windows/dev-drive/#what-should-i-put-on-my-dev-drive
# TODO: https://consoledonottrack.com/
# TODO: https://github.com/beatcracker/toptout/tree/master
# TODO: https://raw.githubusercontent.com/beatcracker/toptout/master/examples/toptout_pwsh.ps1

# Uninstalling Bloatware Appx
$UninstallBloatwareBlock = {
  $BloatwareApps = @(
    "Microsoft.549981C3F5F10", # Cortana
    "Microsoft.BingWeather",
    "Microsoft.BingNews",
    "Microsoft.WindowsSoundRecorder",
    "Microsoft.GetHelp",
    "Microsoft.Getstarted",
    "MicrosoftCorporationII.QuickAssist",
    "Microsoft.YourPhone",
    "Microsoft.MixedReality.Portal",
    "Microsoft.MicrosoftStickyNotes",
    "Microsoft.WindowsMaps",
    "Microsoft.WindowsAlarms",
    "*Microsoft.XboxGamingOverlay*",
    "*Microsoft.Xbox.TCUI*",
    "*Microsoft.XboxApp*",
    "*Microsoft.GamingServices*",
    "*Microsoft.XboxIdentityProvider*",
    "*Microsoft.XboxSpeechToTextOverlay*"
  )
  foreach ($appName in $BloatwareApps) {
    Get-AppxPackage -AllUsers $appName | Remove-AppxPackage -AllUsers
  }
}
Invoke-Elevated $UninstallBloatwareBlock

# Restart the Windows Explorer to apply changes
# Stop-Process -Name explorer -Force
# Start-Process explorer

# param (
#     [switch] $InstallCommsApps
# )

# Import-Module "$PSScriptRoot\lib\Console.psm1"
# Import-Module "$PSScriptRoot\lib\Elevation.psm1"
# Import-Module "$PSScriptRoot\lib\Environment.psm1"
# Import-Module "$PSScriptRoot\lib\Firewall.psm1"
# Import-Module "$PSScriptRoot\lib\Registry.psm1"

# Write-Header "Configuring registry and environment variables"

# Write-Message "Configuring CodeDir"

# if (-not (Test-Path $CodeDir))
# {
#     New-Item -Path $CodeDir -ItemType Directory
# }

# Set-EnvironmentVariable -Name "CodeDir" -Value $CodeDir
# Set-EnvironmentVariable -Name "NUGET_PACKAGES" -Value "$CodeDir\.nuget"
# Set-EnvironmentVariable -Name "NUGET_HTTP_CACHE_PATH" -Value "$CodeDir\.nuget\.http"

# Copy-Item -Path "$PSScriptRoot\bin\*" -Destination $BinDir -Recurse -Force
# Set-EnvironmentVariable -Name "BinDir" -Value $BinDir
# Add-PathVariable -Path $BinDir

# Write-Message "Configuring cmd Autorun"
# Set-RegistryValue -Path "HKCU:\Software\Microsoft\Command Processor" -Name "Autorun" -Data "`"$BinDir\init.cmd`"" -Type ExpandString


# Write-Message "Installing Azure Artifacts Credential Provider (NuGet)"
# Invoke-Expression "& { $(Invoke-RestMethod https://aka.ms/install-artifacts-credprovider.ps1) } -AddNetfx"


# Write-Header "Installing applications via WinGet"
# $InstallApps = @(
#     "7zip.7zip"
#     "Git.Git"
#     "REALiX.HWiNFO"
#     "icsharpcode.ILSpy"
#     "KirillOsenkov.MSBuildStructuredLogViewer"
#     "Microsoft.DotNet.SDK.7"
#     "Microsoft.NuGet"
#     "Microsoft.PowerShell"
#     "Microsoft.PowerToys"
#     "Microsoft.RemoteDesktopClient"
#     "Microsoft.SQLServerManagementStudio"
#     "Microsoft.VisualStudioCode"
#     "Microsoft.VisualStudio.2022.Enterprise"
#     "Microsoft.VisualStudio.2022.Enterprise.Preview"
#     "Microsoft.WindowsTerminal"
#     "Notepad++.Notepad++"
#     "NuGet Package Explorer"
#     "OpenJS.NodeJS"
#     "Regex Hero"
#     "SourceGear.DiffMerge"
#     "Sysinternals Suite"
#     "WinDirStat.WinDirStat"
# )
# if ($InstallCommsApps)
# {
#     $InstallApps += @(
#         "Telegram.TelegramDesktop"
#         "Microsoft.Teams"
#     )
# }
# foreach ($appName in $InstallApps)
# {
#     Write-Message "Installing $appName"
#     winget install $appName --silent --no-upgrade --accept-package-agreements --accept-source-agreements
#     if ($LASTEXITCODE -eq 0)
#     {
#         Write-Message "$appName installed successfully"
#     }
#     # 0x8A150061 (APPINSTALLER_CLI_ERROR_PACKAGE_ALREADY_INSTALLED)
#     elseif ($LASTEXITCODE -eq -1978335135)
#     {
#         Write-Message "$appName already installed"
#     }
#     else
#     {
#         Write-Error "$appName failed to install! winget exit code $LASTEXITCODE"
#     }
# }

# # After installing apps, the Path will have changed
# Update-PathVariable



# Write-Debug "Enable WAM integration for Git (promptless auth)"
# # See: https://github.com/git-ecosystem/git-credential-manager/blob/main/docs/windows-broker.md
# git config --global credential.msauthUseBroker true
# git config --global credential.msauthUseDefaultAccount true

# Write-Header "Copying Windows Terminal settings"
# Copy-Item -Path "$BinDir\terminal\settings.json" -Destination "$env:LocalAppData\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
