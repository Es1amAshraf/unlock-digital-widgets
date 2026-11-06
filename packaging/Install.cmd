@echo off
setlocal
cd /d "%~dp0"
if not exist "%~dp0setup\Install.vbs" (
  echo Installer files are missing.
  pause
  exit /b 1
)
start "" wscript.exe "%~dp0setup\Install.vbs"
exit /b 0
