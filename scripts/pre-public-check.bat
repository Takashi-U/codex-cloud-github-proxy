@echo off
setlocal
where pwsh >nul 2>nul
if %ERRORLEVEL% EQU 0 (
  pwsh -ExecutionPolicy Bypass -File "%~dp0pre-public-check.ps1"
  exit /b %ERRORLEVEL%
)

where powershell >nul 2>nul
if %ERRORLEVEL% EQU 0 (
  powershell -ExecutionPolicy Bypass -File "%~dp0pre-public-check.ps1"
  exit /b %ERRORLEVEL%
)

echo PowerShell was not found.
exit /b 1
