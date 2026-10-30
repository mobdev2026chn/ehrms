# Builds the EktaHR DMA exes (no .NET SDK needed - uses the C# compiler that ships with Windows).
#
#   EktaHR-Agent.exe         employee PCs. Also written to agent\publish - the copy every DMA server
#                            hands out (Download Agent button + agent auto-update).
#   EktaHR-AdminConsole.exe  admin PCs. Office server + web console + Node + agent packed inside.
#
# Before a release:
#   - new agent:          raise AgentVersion in agent\AgentSingle.cs (1.1.1 -> 1.1.2 ...)
#   - new Admin Console:  raise ServerPayloadVersion in admin_console\AdminSingle.cs
#
# Usage (PowerShell, from the dma folder):
#   powershell -ExecutionPolicy Bypass -File .\build.ps1 -AgentOnly          # agent only
#   powershell -ExecutionPolicy Bypass -File .\build.ps1                     # agent + Admin Console
#   powershell -ExecutionPolicy Bypass -File .\build.ps1 -Release EktaHR-DMA-20261105
#
# Output: release\<Release>\  (default EktaHR-DMA-<today>). Then push and run `git pull` on the online
# server so it hands out the new agent.

param(
  [string]$Release = ("EktaHR-DMA-" + (Get-Date -Format yyyyMMdd)),
  [switch]$AgentOnly,
  # Office server inside the Admin Console: EktaHR login service and online server
  [string]$HrmsApiUrl = "https://my.ektahr.com",
  [string]$OnlineServerUrl = "https://track.ektahr.com"
)

$ErrorActionPreference = 'Stop'
$dma = $PSScriptRoot
$csc = Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"
$rel = Join-Path $dma "release\$Release"
New-Item -ItemType Directory -Force $rel | Out-Null

function Invoke-Csc([string[]]$CscArgs, [string]$What) {
  $out = & $csc @CscArgs
  $out | Where-Object { $_ -notmatch 'warning CS' } | ForEach-Object { Write-Host $_ }
  if ($LASTEXITCODE -ne 0) { throw "$What build failed" }
}

function Copy-Built([string]$From, [string]$To) {
  try { Copy-Item $From $To -Force }
  catch { throw "Cannot write $To - is it running? Close it (tray icon > Exit) and build again." }
}

# ---- 1. Agent -------------------------------------------------------------------------------
$agentSrc = Join-Path $dma "agent\AgentSingle.cs"
$agentVersion = ([regex]'AgentVersion = "([\d.]+)"').Match((Get-Content $agentSrc -Raw)).Groups[1].Value
Write-Host "Building agent $agentVersion ..."
$agentOut = Join-Path $env:TEMP "EktaHR-Agent-build.exe"
Push-Location (Join-Path $dma "agent")
try {
  Invoke-Csc @('-nologo', '-target:winexe', '-win32icon:ektaHr.ico', '-resource:ektaHr_icon_256.png,EktaHr.AppIcon.png',
    '-r:System.Windows.Forms.dll', '-r:System.Drawing.dll', '-r:Microsoft.VisualBasic.dll', "-out:$agentOut", 'AgentSingle.cs') 'Agent'
} finally { Pop-Location }
Copy-Built $agentOut (Join-Path $dma "agent\publish\EktaHR-Agent.exe")
Copy-Built $agentOut (Join-Path $rel "EktaHR-Agent.exe")
Write-Host "  agent $agentVersion -> agent\publish and release\$Release"
if ($AgentOnly) { return }

# ---- 2. Admin Console -----------------------------------------------------------------------
$adminSrc = Join-Path $dma "admin_console\AdminSingle.cs"
$payloadVersion = ([regex]'ServerPayloadVersion = "([^"]+)"').Match((Get-Content $adminSrc -Raw)).Groups[1].Value
Write-Host "Building Admin Console (server payload $payloadVersion) ..."

# Web console
Push-Location (Join-Path $dma "admin_console")
try {
  if (-not (Test-Path node_modules)) { npm ci; if ($LASTEXITCODE -ne 0) { throw "npm ci (admin_console) failed" } }
  npm run build; if ($LASTEXITCODE -ne 0) { throw "Web console build failed" }
} finally { Pop-Location }
$serverDir = Join-Path $dma "server"
if (-not (Test-Path (Join-Path $serverDir "node_modules"))) {
  Push-Location $serverDir
  try { npm ci --omit=dev; if ($LASTEXITCODE -ne 0) { throw "npm ci (server) failed" } } finally { Pop-Location }
}

# Payload layout (what AdminSingle.cs unpacks): admin_console\dist, agent\publish, node\node.exe, server\
$stage = Join-Path $env:TEMP "ektahr-dma-payload"
if (Test-Path $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
New-Item -ItemType Directory -Force "$stage\admin_console", "$stage\agent\publish", "$stage\node", "$stage\server\storage\idle-logs", "$stage\server\storage\screenshots" | Out-Null
Copy-Item (Join-Path $dma "admin_console\dist") "$stage\admin_console\dist" -Recurse
Copy-Item $agentOut "$stage\agent\publish\EktaHR-Agent.exe"
Copy-Item (Get-Command node).Source "$stage\node\node.exe"
Copy-Item (Join-Path $serverDir "src") "$stage\server\src" -Recurse
Copy-Item (Join-Path $serverDir "package.json") "$stage\server\package.json"
Copy-Item (Join-Path $serverDir "node_modules") "$stage\server\node_modules" -Recurse

# Office server settings: no database (logins + staff list via EktaHR), own random token secret
$secretBytes = New-Object byte[] 48
[Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($secretBytes)
$secret = -join ($secretBytes | ForEach-Object { '{0:x2}' -f $_ })
$envLines = @(
  "PORT=2005",
  "DMA_MODE=lan",
  "LAN_ONLY=true",
  "JWT_SECRET=$secret",
  "HRMS_API_URL=$HrmsApiUrl",
  "BACKEND_URL=$HrmsApiUrl",
  "ONLINE_SERVER_URL=$OnlineServerUrl",
  "SCREENSHOT_RETENTION_DAYS=1",
  "IDLE_THRESHOLD_SECONDS=300",
  "# No MONGODB_URI on purpose: logins and the staff list go through the EktaHR backend."
)
[IO.File]::WriteAllText("$stage\server\.env", ($envLines -join "`r`n") + "`r`n", (New-Object Text.UTF8Encoding($false)))

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = Join-Path $env:TEMP "EktaHR.DmaServer.zip"
if (Test-Path $zip) { Remove-Item -LiteralPath $zip -Force }
[IO.Compression.ZipFile]::CreateFromDirectory($stage, $zip, [IO.Compression.CompressionLevel]::Optimal, $false)

$adminOut = Join-Path $env:TEMP "EktaHR-AdminConsole-build.exe"
Push-Location (Join-Path $dma "admin_console")
try {
  Invoke-Csc @('-nologo', '-target:winexe', '-win32icon:public\ektaHr.ico', '-r:System.Windows.Forms.dll', '-r:System.Drawing.dll',
    '-r:System.IO.Compression.dll', '-r:System.IO.Compression.FileSystem.dll', "-resource:$zip,EktaHR.DmaServer.zip",
    "-out:$adminOut", 'AdminSingle.cs') 'Admin Console'
} finally { Pop-Location }
Copy-Built $adminOut (Join-Path $rel "EktaHR-AdminConsole.exe")
Remove-Item -LiteralPath $stage -Recurse -Force
Write-Host "  Admin Console (payload $payloadVersion, login via $HrmsApiUrl) -> release\$Release"
Write-Host "Done. Push, then run 'git pull' on the online server so it hands out agent $agentVersion."
