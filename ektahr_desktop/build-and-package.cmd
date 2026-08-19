@echo off
REM Run the PowerShell build script (use this from CMD or when double-clicking)
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build-and-package.ps1"
pause
