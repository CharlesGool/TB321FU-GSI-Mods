@echo off
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0apply_patch.ps1" %*
set RC=%ERRORLEVEL%
if %RC% EQU 0 (timeout /t 5 >nul) else pause
exit /b %RC%
