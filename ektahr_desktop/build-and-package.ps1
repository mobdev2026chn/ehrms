# EktaHR Agent - Build and create Inno Setup installer
# 1. Edit BuildConfig.cs (ApiBaseUrl, Version) before running
# 2. Install Inno Setup 6 from https://jrsoftware.org/isinfo.php
# 3. Run from PowerShell: .\build-and-package.ps1   OR from cmd: .\build-and-package.cmd
# 4. Share: ektahr_desktop\output\EktaHR-Agent-Setup.exe

$ErrorActionPreference = "Stop"
$root = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
Set-Location -LiteralPath $root

$projectDir = Join-Path $root "EktaHR.DesktopAgent"
$csproj = Join-Path $projectDir "EktaHR.DesktopAgent.csproj"
$publishDir = Join-Path $root "publish"
$outputDir = Join-Path $root "output"
$issPath = Join-Path $root "EktaHR-Agent.iss"

# Inno Setup compiler (default install path)
$iscc = Join-Path ${env:ProgramFiles(x86)} "Inno Setup 6\ISCC.exe"
if (-not (Test-Path -LiteralPath $iscc)) {
    $iscc = Join-Path $env:ProgramFiles "Inno Setup 6\ISCC.exe"
}
if (-not (Test-Path -LiteralPath $iscc)) {
    Write-Host "Inno Setup 6 not found. Install from https://jrsoftware.org/isinfo.php" -ForegroundColor Red
    exit 1
}

Write-Host "Cleaning and building EktaHR Desktop Agent (single .exe)..." -ForegroundColor Cyan
# Clean first so App.config (ApiBaseUrl, Version) is picked up fresh
dotnet clean $csproj -c Release -q
# Single-file publish: one exe, native SQLite + tessdata extracted at runtime (InvariantGlobalization in csproj)
dotnet publish $csproj -c Release -r win-x64 --self-contained true -o $publishDir

Remove-Item "$publishDir\*.pdb" -ErrorAction SilentlyContinue
<<<<<<< HEAD
=======
Remove-Item "$publishDir\*.targets" -ErrorAction SilentlyContinue
Get-ChildItem -Path $publishDir -Recurse -Filter "*.targets" -File | Remove-Item -Force -ErrorAction SilentlyContinue
>>>>>>> development
$agentExe = Join-Path $publishDir "EktaHR.DesktopAgent.exe"
if (-not (Test-Path -LiteralPath $agentExe)) {
    Write-Host "Single-file exe not found: $agentExe" -ForegroundColor Red
    exit 1
}

Write-Host "Creating installer with Inno Setup..." -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
& $iscc $issPath

if ($LASTEXITCODE -eq 0) {
    $setupPath = Join-Path $outputDir "EktaHR-Agent-Setup.exe"
<<<<<<< HEAD
    # Copy single exe for direct share (one file, no zip)
    $singleExe = Join-Path $outputDir "EktaHR-Agent.exe"
    Copy-Item -Force $agentExe $singleExe
    if (Test-Path $setupPath) {
        Write-Host "Done! Share with clients: $singleExe  (or installer: $setupPath)" -ForegroundColor Green
    } else {
        Write-Host "Single exe: $singleExe" -ForegroundColor Green
=======
    # Keep portable build separate so client installs always use the setup package.
    $portableExe = Join-Path $outputDir "EktaHR-Agent-Portable.exe"
    Copy-Item -Force $agentExe $portableExe
    if (Test-Path $setupPath) {
        Write-Host "Done! Share with clients: $setupPath" -ForegroundColor Green
        Write-Host "Portable build for internal/dev use only: $portableExe" -ForegroundColor Yellow
    } else {
        Write-Host "Portable build only: $portableExe" -ForegroundColor Yellow
>>>>>>> development
    }
} else {
    Write-Host "Inno Setup failed." -ForegroundColor Red
    exit 1
}
