# EktaHR adb-reverse tunnel watcher (set-and-forget)
#
# Keeps `adb reverse tcp:9001 tcp:9001` alive at all times so the app
# (baseUrl http://127.0.0.1:9001/api) can always reach the local backend.
# The tunnel drops on every device unplug/replug and adb-server restart;
# this watcher re-applies it within a few seconds, every time, forever.
#
# Runs headless. Install once as a logon scheduled task with install_tunnel_watch.ps1,
# or run manually:  powershell -ExecutionPolicy Bypass -File .\tools\ektahr_tunnel_watch.ps1

param([int]$Port = 9001)

# Resolve adb: prefer the relocated SDK location used on this machine, else PATH.
$adb = "D:\dev-cache\Android\Sdk\platform-tools\adb.exe"
if (-not (Test-Path $adb)) {
    $cmd = Get-Command adb -ErrorAction SilentlyContinue
    $adb = if ($cmd) { $cmd.Source } else { "adb" }
}

while ($true) {
    try {
        # Is a real device attached (not just "offline"/"unauthorized")?
        $hasDevice = (& $adb devices 2>$null | Select-String "`tdevice$")
        if ($hasDevice) {
            $list = (& $adb reverse --list 2>$null) -join "`n"
            if ($list -notmatch "tcp:$Port tcp:$Port") {
                & $adb reverse "tcp:$Port" "tcp:$Port" 2>$null | Out-Null
            }
        }
    } catch { }
    Start-Sleep -Seconds 3
}
