$CurrentScriptPath = $MyInvocation.MyCommand.Path
$ScriptsPath = [System.IO.Path]::GetFullPath((Join-Path $ProfileScriptResolvedPath "..\scripts"))

$ScriptPath = Join-Path $ScriptsPath "auto-approve.ps1"
$Parameters = "dev/BuildXL/"
$WorkingDirectory = "C:\src\CloudBuild"
$LogFilePath = "C:\work\logs\auto-approve.log"

$TaskPrincipal = New-ScheduledTaskPrincipal -Id "$env:USERNAME" -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Password -RunLevel Limited

$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoLogo -NoProfile -NonInteractive -WindowStyle Minimized -Command `"Set-Location '$WorkingDirectory'; & '$ScriptPath' $Parameters >$LogFilePath 2>&1`""
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 30) -RepetitionDuration (New-TimeSpan -Days (365 * 20))
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -RunOnlyIfNetworkAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
Register-ScheduledTask -TaskName "AutoApproveBuildXLIntegrations" -Trigger $trigger -Action $action -Settings $settings -Force -Principal $TaskPrincipal

Write-Host "PowerShell script '$ScriptPath $Parameters' scheduled to run every 30 minutes from '$WorkingDirectory'"

Get-ScheduledTask -TaskName "AutoApproveBuildXLIntegrations" | Start-ScheduledTask