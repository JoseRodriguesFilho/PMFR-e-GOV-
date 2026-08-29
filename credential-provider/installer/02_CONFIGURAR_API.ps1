#requires -Version 5.1
$ErrorActionPreference = "Stop"

$ConfigKey = "HKLM:\SOFTWARE\e-GOV\LabCPFProvider"

function Ensure-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($id)

    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        exit
    }
}

Ensure-Admin

New-Item $ConfigKey -Force | Out-Null

$currentBase = ""
try {
    $currentBase = (Get-ItemProperty $ConfigKey -Name ApiBaseUrl -ErrorAction Stop).ApiBaseUrl
}
catch {}

Write-Host ""
Write-Host "CONFIGURAR API e-GOV" -ForegroundColor Cyan
Write-Host ""

if ($currentBase) {
    Write-Host "Atual: $currentBase"
}

$baseUrl = Read-Host "URL base (ex.: https://egov.francodarocha.sp.gov.br)"

if (-not $baseUrl) {
    $baseUrl = $currentBase
}

if (-not $baseUrl -or $baseUrl -notmatch '^https?://') {
    throw "URL invalida."
}

$baseUrl = $baseUrl.TrimEnd('/')

$secureToken = Read-Host "EGOV_API_TOKEN" -AsSecureString
$ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureToken)

try {
    $apiToken = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
}
finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
}

if (-not $apiToken) {
    try {
        $apiToken = (Get-ItemProperty $ConfigKey -Name ApiToken -ErrorAction Stop).ApiToken
    }
    catch {
        throw "Token nao informado."
    }
}

$allowHttp = 0

if ($baseUrl.StartsWith("http://", [StringComparison]::OrdinalIgnoreCase)) {
    Write-Host ""
    Write-Host "ATENCAO: HTTP nao protege CPF nem token." -ForegroundColor Yellow

    $confirm = Read-Host "Digite SIM para permitir HTTP apenas em teste"

    if ($confirm -ne "SIM") {
        throw "Configuracao cancelada. Use HTTPS."
    }

    $allowHttp = 1
}

New-ItemProperty $ConfigKey -Name ApiBaseUrl -PropertyType String -Value $baseUrl -Force | Out-Null
New-ItemProperty $ConfigKey -Name ApiToken -PropertyType String -Value $apiToken -Force | Out-Null
New-ItemProperty $ConfigKey -Name AllowHttp -PropertyType DWord -Value $allowHttp -Force | Out-Null

# Mantem a chave restrita a SYSTEM + Administradores.
$acl = New-Object System.Security.AccessControl.RegistrySecurity
$acl.SetAccessRuleProtection($true, $false)

$systemSid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-18")
$adminsSid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")

$acl.AddAccessRule(
    (New-Object System.Security.AccessControl.RegistryAccessRule(
        $systemSid,
        "FullControl",
        "ContainerInherit,ObjectInherit",
        "None",
        "Allow"
    ))
)

$acl.AddAccessRule(
    (New-Object System.Security.AccessControl.RegistryAccessRule(
        $adminsSid,
        "FullControl",
        "ContainerInherit,ObjectInherit",
        "None",
        "Allow"
    ))
)

Set-Acl -Path $ConfigKey -AclObject $acl

Restart-Service -Name eGOVLabCPFAgent -ErrorAction Stop

Write-Host ""
Write-Host "API configurada:" -ForegroundColor Green
Write-Host "  $baseUrl"
Write-Host ""
Write-Host "Execute 03_TESTAR_API.cmd." -ForegroundColor Cyan
Read-Host "ENTER para fechar"
