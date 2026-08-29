#requires -Version 5.1
$ErrorActionPreference = "Stop"

$Guid = "{D2D9E531-8DB1-4C83-ABF9-810F70A1EB09}"
$Providers = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\Credential Providers"
$Clsid = "Registry::HKEY_CLASSES_ROOT\CLSID"
$ExcludeKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
$DefaultKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
$ConfigKey = "HKLM:\SOFTWARE\e-GOV\LabCPFProvider"
$UserTile = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\UserTile"

function Ensure-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($id)

    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        exit
    }
}

Ensure-Admin

Remove-ItemProperty $ExcludeKey -Name ExcludedCredentialProviders -Force -ErrorAction SilentlyContinue
Remove-ItemProperty $DefaultKey -Name DefaultCredentialProvider -Force -ErrorAction SilentlyContinue

Stop-Service -Name "eGOVLabCPFAgent" -Force -ErrorAction SilentlyContinue
& sc.exe delete "eGOVLabCPFAgent" | Out-Null

Remove-Item "$Providers\$Guid" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "$Clsid\$Guid" -Recurse -Force -ErrorAction SilentlyContinue

if (Test-Path $UserTile) {
    Get-ChildItem $UserTile | ForEach-Object {
        try {
            if ([string]$_.GetValue("") -ieq $Guid) {
                Remove-Item $_.PSPath -Recurse -Force
            }
        }
        catch {}
    }
}

Remove-Item "$env:WINDIR\System32\LabCPFProvider.dll" -Force -ErrorAction SilentlyContinue
Remove-Item "$env:ProgramFiles\e-GOV\LabCPF" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $ConfigKey -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "e-GOV Login removido." -ForegroundColor Green
Write-Host "As contas Aluno e-GOV e Admin e-GOV foram preservadas." -ForegroundColor Yellow
Write-Host "Reinicie o Windows." -ForegroundColor Cyan
Read-Host "ENTER para fechar"
