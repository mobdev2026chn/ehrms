@echo off
REM Start the persistent face-verify service (Windows). Run from this folder.
REM Uses the local venv python if present, else system python.
setlocal
cd /d "%~dp0"
set PORT=5005
if exist "venv\Scripts\python.exe" (
  set PY=venv\Scripts\python.exe
) else (
  set PY=python
)
echo Starting face-verify service on http://127.0.0.1:%PORT% ...
"%PY%" -m uvicorn server:app --host 127.0.0.1 --port %PORT%
endlocal
