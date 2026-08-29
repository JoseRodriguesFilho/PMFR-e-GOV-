@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0\04_ATIVAR_MODO_EGOV.ps1"
