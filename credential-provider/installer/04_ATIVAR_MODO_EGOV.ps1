#requires -Version 5.1
$ErrorActionPreference = "Stop"

$Guid = "{D2D9E531-8DB1-4C83-ABF9-810F70A1EB09}"
$Providers = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\Credential Providers"
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

if (-not (Test-Path "$Providers\$Guid")) {
    throw "e-GOV Credential Provider nao registrado."
}

$student = Get-LocalUser -Name "AlunoEGOV" -ErrorAction Stop
$admin = Get-LocalUser -Name "AdminEGOV" -ErrorAction Stop

$usersGroup = Get-LocalGroup -SID "S-1-5-32-545" -ErrorAction Stop
$adminsGroup = Get-LocalGroup -SID "S-1-5-32-544" -ErrorAction Stop

$studentInUsers = Get-LocalGroupMember -Group $usersGroup.Name -ErrorAction SilentlyContinue |
    Where-Object { $_.SID -eq $student.SID }

$studentInAdmins = Get-LocalGroupMember -Group $adminsGroup.Name -ErrorAction SilentlyContinue |
    Where-Object { $_.SID -eq $student.SID }

$adminInAdmins = Get-LocalGroupMember -Group $adminsGroup.Name -ErrorAction SilentlyContinue |
    Where-Object { $_.SID -eq $admin.SID }

if (-not $studentInUsers) {
    throw "Aluno e-GOV nao pertence ao grupo Usuarios."
}

if ($studentInAdmins) {
    throw "Aluno e-GOV nao pode estar em Administradores."
}

if (-not $adminInAdmins) {
    throw "Admin e-GOV nao pertence ao grupo Administradores."
}

$agent = Get-Service -Name "eGOVLabCPFAgent" -ErrorAction Stop

if ($agent.Status -ne "Running") {
    throw "e-GOV Lab CPF Agent nao esta em execucao."
}

$config = Get-ItemProperty "HKLM:\SOFTWARE\e-GOV\LabCPFProvider" -ErrorAction Stop

$health = Invoke-RestMethod `
    -Method Get `
    -Uri "$($config.ApiBaseUrl)/health" `
    -TimeoutSec 5

if ($health.status -ne "ok") {
    throw "API e-GOV nao respondeu OK."
}

Get-ChildItem $Providers | ForEach-Object {
    Remove-ItemProperty $_.PSPath -Name Disabled -Force -ErrorAction SilentlyContinue
}

$excluded = @(
    Get-ChildItem $Providers |
    ForEach-Object { $_.PSChildName } |
    Where-Object { $_ -ine $Guid }
)

New-Item $ExcludeKey -Force | Out-Null
New-ItemProperty `
    $ExcludeKey `
    -Name ExcludedCredentialProviders `
    -PropertyType String `
    -Value ($excluded -join ",") `
    -Force | Out-Null

New-Item $DefaultKey -Force | Out-Null
New-ItemProperty `
    $DefaultKey `
    -Name DefaultCredentialProvider `
    -PropertyType String `
    -Value $Guid `
    -Force | Out-Null

Write-Host ""
Write-Host "MODO e-GOV ATIVO." -ForegroundColor Green
Write-Host "Tiles esperadas: Aluno e-GOV e Admin e-GOV." -ForegroundColor Cyan
Write-Host "Reinicie o Windows." -ForegroundColor Cyan
Read-Host "ENTER para fechar"
