# EktaHR Desktop Agent - Build and store output in output folder
# Run from repo: .\ektahr_desktop\build-agent.ps1
# Output: ektahr_desktop\output\

$ErrorActionPreference = "Stop"
$scriptRoot = $PSScriptRoot
Set-Location $scriptRoot

$projectDir = ".\EktaHR.DesktopAgent"
$outputDir = ".\output"

Write-Host "Building EktaHR Desktop Agent (single .exe)..." -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

# Single-file publish: one exe for client share (native SQLite + tessdata extracted at runtime)
dotnet publish $projectDir -c Release -r win-x64 --self-contained true -o $outputDir

if ($LASTEXITCODE -ne 0) {
    Write-Host "Build failed." -ForegroundColor Red
    exit 1
}

Remove-Item "$outputDir\*.pdb" -ErrorAction SilentlyContinue
$agentExe = Join-Path $outputDir "EktaHR.DesktopAgent.exe"
$shareExe = Join-Path $outputDir "EktaHR-Agent-Portable.exe"
if (Test-Path -LiteralPath $agentExe) {
    Copy-Item -Force $agentExe $shareExe
    $resolved = Resolve-Path $shareExe
    Write-Host "Done! Portable build created: $resolved" -ForegroundColor Yellow
} else {
    $resolved = Resolve-Path $outputDir
    Write-Host "Done! Output: $resolved" -ForegroundColor Green
}
