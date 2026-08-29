#requires -Version 5.1
$ErrorActionPreference = "Stop"

$ConfigKey = "HKLM:\SOFTWARE\e-GOV\LabCPFProvider"

$config = Get-ItemProperty $ConfigKey -ErrorAction Stop

$baseUrl = $config.ApiBaseUrl
$token = $config.ApiToken

Write-Host ""
Write-Host "Teste API e-GOV" -ForegroundColor Cyan
Write-Host ""

$health = Invoke-RestMethod `
    -Method Get `
    -Uri "$baseUrl/health" `
    -TimeoutSec 5

Write-Host "Health:" -ForegroundColor Green
$health | ConvertTo-Json

$cpf = Read-Host "CPF para preview"
$target = Read-Host "Tipo [student/admin]"

if (-not $target) {
    $target = "student"
}

$body = @{
    cpf = $cpf
    computer = $env:COMPUTERNAME
    target = $target
} | ConvertTo-Json -Compress

$response = Invoke-RestMethod `
    -Method Post `
    -Uri "$baseUrl/auth/preview" `
    -Headers @{ "X-eGOV-Token" = $token } `
    -ContentType "application/json" `
    -Body $body `
    -TimeoutSec 5

Write-Host ""
Write-Host "Preview:" -ForegroundColor Green
$response | ConvertTo-Json

Read-Host "ENTER para fechar"
