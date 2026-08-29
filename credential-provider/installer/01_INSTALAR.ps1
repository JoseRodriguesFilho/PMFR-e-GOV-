﻿#requires -Version 5.1
$ErrorActionPreference = "Stop"

$Guid = "{D2D9E531-8DB1-4C83-ABF9-810F70A1EB09}"
$OldGuid = "{5FD3D285-0DD9-4362-8855-E0ABAACD4AF6}"

$StudentUser = "AlunoEGOV"
$StudentDisplay = "Aluno e-GOV"

$AdminUser = "AdminEGOV"
$AdminDisplay = "Admin e-GOV"

$DllSource = Join-Path $PSScriptRoot "LabCPFProvider.dll"
$AgentSource = Join-Path $PSScriptRoot "eGOVLabCPFAgent.exe"

$DllTarget = "$env:WINDIR\System32\LabCPFProvider.dll"
$ProgramDir = "$env:ProgramFiles\e-GOV\LabCPF"
$AgentTarget = Join-Path $ProgramDir "eGOVLabCPFAgent.exe"

$Providers = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\Credential Providers"
$Clsid = "Registry::HKEY_CLASSES_ROOT\CLSID"
$UserTile = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\UserTile"
$ConfigKey = "HKLM:\SOFTWARE\e-GOV\LabCPFProvider"

function Ensure-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($id)

    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        exit
    }
}

function New-RandomPassword {
    $bytes = New-Object byte[] 32
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()

    try {
        $rng.GetBytes($bytes)
    }
    finally {
        $rng.Dispose()
    }

    return ([Convert]::ToBase64String($bytes) + "!Aa1")
}

function Protect-Secret([string]$PlainText) {
    $bytes = [Text.Encoding]::Unicode.GetBytes($PlainText)

    try {
        return [Security.Cryptography.ProtectedData]::Protect(
            $bytes,
            $null,
            [Security.Cryptography.DataProtectionScope]::LocalMachine
        )
    }
    finally {
        [Array]::Clear($bytes, 0, $bytes.Length)
    }
}

function Ensure-LocalAccount(
    [string]$Name,
    [string]$DisplayName,
    [bool]$IsAdmin,
    [string]$Password
) {
    Import-Module Microsoft.PowerShell.LocalAccounts -ErrorAction Stop

    $secure = ConvertTo-SecureString $Password -AsPlainText -Force
    $user = Get-LocalUser -Name $Name -ErrorAction SilentlyContinue

    if ($null -eq $user) {
        Write-Host "Criando $DisplayName..." -ForegroundColor Cyan

        New-LocalUser `
            -Name $Name `
            -FullName $DisplayName `
            -Description "Conta tecnica do e-GOV Login" `
            -Password $secure `
            -PasswordNeverExpires `
            -UserMayNotChangePassword | Out-Null
    }
    else {
        Write-Host "$DisplayName ja existe; ajustando configuracao..." -ForegroundColor Yellow

        Set-LocalUser `
            -Name $Name `
            -FullName $DisplayName `
            -Description "Conta tecnica do e-GOV Login" `
            -Password $secure `
            -PasswordNeverExpires $true `
            -UserMayChangePassword $false

        if (-not $user.Enabled) {
            Enable-LocalUser -Name $Name
        }
    }

    $usersGroup = Get-LocalGroup -SID "S-1-5-32-545" -ErrorAction Stop
    $adminsGroup = Get-LocalGroup -SID "S-1-5-32-544" -ErrorAction Stop

    $memberUsers = Get-LocalGroupMember -Group $usersGroup.Name -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -ieq "$env:COMPUTERNAME\$Name" -or
            $_.Name -ieq $Name
        }

    if (-not $memberUsers) {
        Add-LocalGroupMember -Group $usersGroup.Name -Member $Name
        Write-Host "$DisplayName adicionado ao grupo $($usersGroup.Name)." -ForegroundColor Green
    }

    $memberAdmins = Get-LocalGroupMember -Group $adminsGroup.Name -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -ieq "$env:COMPUTERNAME\$Name" -or
            $_.Name -ieq $Name
        }

    if ($IsAdmin) {
        if (-not $memberAdmins) {
            Add-LocalGroupMember -Group $adminsGroup.Name -Member $Name
            Write-Host "$DisplayName adicionado ao grupo $($adminsGroup.Name)." -ForegroundColor Green
        }
    }
    else {
        if ($memberAdmins) {
            Remove-LocalGroupMember -Group $adminsGroup.Name -Member $Name
            Write-Host "$DisplayName removido do grupo $($adminsGroup.Name)." -ForegroundColor Green
        }
    }
}

function Protect-ConfigRegistry {
    New-Item $ConfigKey -Force | Out-Null

    $acl = New-Object System.Security.AccessControl.RegistrySecurity
    $acl.SetAccessRuleProtection($true, $false)

    $systemSid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-18")
    $adminsSid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")

    $systemRule = New-Object System.Security.AccessControl.RegistryAccessRule(
        $systemSid,
        "FullControl",
        "ContainerInherit,ObjectInherit",
        "None",
        "Allow"
    )

    $adminRule = New-Object System.Security.AccessControl.RegistryAccessRule(
        $adminsSid,
        "FullControl",
        "ContainerInherit,ObjectInherit",
        "None",
        "Allow"
    )

    $acl.AddAccessRule($systemRule)
    $acl.AddAccessRule($adminRule)

    Set-Acl -Path $ConfigKey -AclObject $acl
}

Ensure-Admin

if (-not (Test-Path $DllSource)) {
    throw "LabCPFProvider.dll nao encontrado no pacote."
}

if (-not (Test-Path $AgentSource)) {
    throw "eGOVLabCPFAgent.exe nao encontrado no pacote."
}

Write-Host ""
Write-Host "Instalando e-GOV Login v8..." -ForegroundColor Cyan
Write-Host ""

$studentPassword = New-RandomPassword
$adminPassword = New-RandomPassword

Ensure-LocalAccount `
    -Name $StudentUser `
    -DisplayName $StudentDisplay `
    -IsAdmin $false `
    -Password $studentPassword

Ensure-LocalAccount `
    -Name $AdminUser `
    -DisplayName $AdminDisplay `
    -IsAdmin $true `
    -Password $adminPassword

Protect-ConfigRegistry

$studentProtected = Protect-Secret $studentPassword
$adminProtected = Protect-Secret $adminPassword

New-ItemProperty `
    $ConfigKey `
    -Name StudentSecret `
    -PropertyType Binary `
    -Value $studentProtected `
    -Force | Out-Null

New-ItemProperty `
    $ConfigKey `
    -Name AdminSecret `
    -PropertyType Binary `
    -Value $adminProtected `
    -Force | Out-Null

$studentPassword = $null
$adminPassword = $null

$serviceName = "eGOVLabCPFAgent"
$existingService = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

if ($existingService) {
    Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
}

Copy-Item $DllSource $DllTarget -Force

New-Item -ItemType Directory -Force $ProgramDir | Out-Null
Copy-Item $AgentSource $AgentTarget -Force

Remove-Item "$Providers\$OldGuid" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "$Clsid\$OldGuid" -Recurse -Force -ErrorAction SilentlyContinue

New-Item "$Providers\$Guid" -Force | Out-Null
Set-Item "$Providers\$Guid" -Value "e-GOV Login"

New-Item "$Clsid\$Guid" -Force | Out-Null
Set-Item "$Clsid\$Guid" -Value "e-GOV Login"

New-Item "$Clsid\$Guid\InprocServer32" -Force | Out-Null
Set-Item "$Clsid\$Guid\InprocServer32" -Value $DllTarget

New-ItemProperty `
    "$Clsid\$Guid\InprocServer32" `
    -Name ThreadingModel `
    -PropertyType String `
    -Value "Apartment" `
    -Force | Out-Null

$studentSid = (Get-LocalUser -Name $StudentUser -ErrorAction Stop).SID.Value
$adminSid = (Get-LocalUser -Name $AdminUser -ErrorAction Stop).SID.Value

New-Item "$UserTile\$studentSid" -Force | Out-Null
Set-Item "$UserTile\$studentSid" -Value $Guid

New-Item "$UserTile\$adminSid" -Force | Out-Null
Set-Item "$UserTile\$adminSid" -Value $Guid

if ($existingService) {
    & sc.exe config $serviceName `
        binPath= "`"$AgentTarget`"" `
        start= auto `
        obj= LocalSystem `
        DisplayName= "e-GOV Lab CPF Agent" | Out-Null

    if ($LASTEXITCODE -ne 0) {
        throw "Falha ao atualizar o servico eGOVLabCPFAgent."
    }
}
else {
    & sc.exe create $serviceName `
        binPath= "`"$AgentTarget`"" `
        start= auto `
        obj= LocalSystem `
        DisplayName= "e-GOV Lab CPF Agent" | Out-Null

    if ($LASTEXITCODE -ne 0) {
        throw "Falha ao criar o servico eGOVLabCPFAgent."
    }
}

& sc.exe description $serviceName "Heartbeat, IP, MAC e controle de sessoes do e-GOV Login." | Out-Null
& sc.exe failure $serviceName reset= 86400 actions= restart/5000/restart/10000/restart/30000 | Out-Null

Start-Service -Name $serviceName

$dllOk = Test-Path $DllTarget
$providerOk = Test-Path "$Providers\$Guid"
$studentOk = $null -ne (Get-LocalUser -Name $StudentUser -ErrorAction SilentlyContinue)
$adminOk = $null -ne (Get-LocalUser -Name $AdminUser -ErrorAction SilentlyContinue)
$agentOk = (Get-Service -Name $serviceName -ErrorAction SilentlyContinue).Status -eq "Running"

Write-Host ""
Write-Host "Verificacao final:" -ForegroundColor Cyan
Write-Host "  Aluno e-GOV : $studentOk"
Write-Host "  Admin e-GOV : $adminOk"
Write-Host "  DLL          : $dllOk"
Write-Host "  Provider     : $providerOk"
Write-Host "  Agent        : $agentOk"
Write-Host ""

if (-not ($studentOk -and $adminOk -and $dllOk -and $providerOk -and $agentOk)) {
    throw "Instalacao incompleta."
}

Write-Host "e-GOV Login v8 instalado." -ForegroundColor Green
Write-Host "Agora execute 02_CONFIGURAR_API.cmd." -ForegroundColor Cyan
Read-Host "ENTER para fechar"
