# Installs the EktaHR tunnel watcher as a Windows scheduled task that starts
# at logon and runs hidden in the background. Run ONCE:
#
#   powershell -ExecutionPolicy Bypass -File .\tools\install_tunnel_watch.ps1
#
# To remove later:  Unregister-ScheduledTask -TaskName "EktaHR Tunnel Watch" -Confirm:$false

$ErrorActionPreference = "Stop"
$taskName = "EktaHR Tunnel Watch"
$watcher  = Join-Path $PSScriptRoot "ektahr_tunnel_watch.ps1"

if (-not (Test-Path $watcher)) { throw "Watcher script not found: $watcher" }

$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$watcher`""

$trigger = New-ScheduledTaskTrigger -AtLogOn

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit ([TimeSpan]::Zero)

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
    -Settings $settings -Description "Keeps adb reverse tcp:9001 alive for EktaHR dev." `
    -Force | Out-Null

# Start it now so you don't have to log out/in first.
Start-ScheduledTask -TaskName $taskName

Write-Host "Installed and started '$taskName'. The adb reverse tunnel will now stay alive automatically." -ForegroundColor Green
