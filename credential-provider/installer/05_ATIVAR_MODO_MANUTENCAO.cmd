@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0\05_ATIVAR_MODO_MANUTENCAO.ps1"
