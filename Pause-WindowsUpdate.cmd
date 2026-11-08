@echo off
setlocal
chcp 65001 >nul
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS%" (
  echo [x] Windows PowerShell not found: %PS%
  pause
  exit /b 1
)
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Pause-WindowsUpdate.ps1" %*
exit /b %errorlevel%
