#requires -Version 5.1
$ErrorActionPreference = "Stop"

$ExcludeKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
$DefaultKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"

function Ensure-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($id)

    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        exit
    }
}

Ensure-Admin

Remove-ItemProperty `
    $ExcludeKey `
    -Name ExcludedCredentialProviders `
    -Force `
    -ErrorAction SilentlyContinue

Remove-ItemProperty `
    $DefaultKey `
    -Name DefaultCredentialProvider `
    -Force `
    -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "MODO MANUTENCAO ATIVO." -ForegroundColor Green
Write-Host "Senha/PIN/providers nativos foram liberados." -ForegroundColor Cyan
Write-Host "Reinicie ou faca logoff." -ForegroundColor Cyan
Read-Host "ENTER para fechar"
