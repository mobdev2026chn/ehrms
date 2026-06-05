# EktaHR dev launcher — self-healing adb reverse tunnel + flutter run
#
# WHY: The app calls http://127.0.0.1:9001/api (see lib/config/constants.dart).
# On a physical device, 127.0.0.1 only reaches the PC's backend through an
# `adb reverse tcp:9001 tcp:9001` tunnel. That tunnel silently drops whenever
# the phone is unplugged/replugged or the adb server restarts — which makes
# EVERY request fail with "Connection refused / Connection error".
#
# This script (re)establishes the tunnel, keeps a watcher running that
# re-applies it the instant it disappears, then launches the app. When you
# stop the app (q / Ctrl-C), the watcher is cleaned up automatically.
#
# Usage:   .\dev_run.ps1            # ensure tunnel + flutter run
#          .\dev_run.ps1 -TunnelOnly   # just fix the tunnel, don't run the app

param(
    [int]$Port = 9001,
    [switch]$TunnelOnly
)

function Ensure-Tunnel {
    param([int]$Port)
    $list = (adb reverse --list 2>$null) -join "`n"
    if ($list -notmatch "tcp:$Port tcp:$Port") {
        adb reverse "tcp:$Port" "tcp:$Port" | Out-Null
        return $true   # (re)applied
    }
    return $false
}

# --- preflight checks ---
$devices = (adb devices 2>$null | Select-String "`tdevice$")
if (-not $devices) {
    Write-Host "[dev_run] No device connected. Plug in the phone (USB debugging ON) and retry." -ForegroundColor Red
    exit 1
}

$backend = Test-NetConnection -ComputerName 127.0.0.1 -Port $Port -WarningAction SilentlyContinue
if (-not $backend.TcpTestSucceeded) {
    Write-Host "[dev_run] WARNING: nothing is listening on host 127.0.0.1:$Port." -ForegroundColor Yellow
    Write-Host "          Start the backend first (the app cannot connect without it)." -ForegroundColor Yellow
}

if (Ensure-Tunnel -Port $Port) {
    Write-Host "[dev_run] adb reverse tcp:$Port tcp:$Port established." -ForegroundColor Green
} else {
    Write-Host "[dev_run] adb reverse tunnel already present." -ForegroundColor Green
}

if ($TunnelOnly) {
    Write-Host "[dev_run] Tunnel ready. (-TunnelOnly: not launching app)" -ForegroundColor Green
    exit 0
}

# --- background watcher: re-applies the tunnel if it ever drops ---
$watcher = Start-Job -ArgumentList $Port -ScriptBlock {
    param($Port)
    while ($true) {
        $list = (adb reverse --list 2>$null) -join "`n"
        if ($list -notmatch "tcp:$Port tcp:$Port") {
            adb reverse "tcp:$Port" "tcp:$Port" | Out-Null
        }
        Start-Sleep -Seconds 3
    }
}

try {
    # Extra Dart heap to avoid "Out of memory" during kernel snapshot (kept from run_with_more_memory.ps1)
    $env:DART_VM_OPTIONS = "--old_gen_heap_size=4096"
    # baseUrl now defaults to PRODUCTION; for local dev we point it back at the
    # PC's backend via the adb-reverse tunnel established above.
    flutter run --dart-define=API_BASE="http://127.0.0.1:$Port/api" @args
}
finally {
    Stop-Job $watcher -ErrorAction SilentlyContinue | Out-Null
    Remove-Job $watcher -ErrorAction SilentlyContinue | Out-Null
    Write-Host "[dev_run] Watcher stopped." -ForegroundColor DarkGray
}
