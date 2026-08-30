$ErrorActionPreference = "Stop"

# Preflight: o proprio script nao pode conter byte NUL literal.
$SelfBytes = [System.IO.File]::ReadAllBytes($PSCommandPath)
if ($SelfBytes -contains 0) {
    throw "prepare-source.ps1 contem byte NUL literal."
}


$repo = "https://raw.githubusercontent.com/microsoft/Windows-classic-samples/main/Samples/CredentialProvider/cpp"
$out = Join-Path $PSScriptRoot "..\generated"

if (Test-Path $out) {
    Remove-Item $out -Recurse -Force
}

New-Item -ItemType Directory -Force $out | Out-Null

$download = @(
    "CSampleCredential.cpp",
    "CSampleCredential.h",
    "Dll.cpp",
    "Dll.h",
    "helpers.cpp",
    "helpers.h",
    "guid.cpp",
    "guid.h",
    "resource.h",
    "resources.rc",
    "samplev2credentialprovider.def",
    "SampleV2CredentialProvider.vcxproj",
    "tileimage.bmp"
)

foreach ($file in $download) {
    Write-Host "Downloading $file"
    Invoke-WebRequest `
        -UseBasicParsing `
        -Uri "$repo/$file" `
        -OutFile (Join-Path $out $file)
}

Copy-Item `
    (Join-Path $PSScriptRoot "CSampleProvider.cpp.template") `
    (Join-Path $out "CSampleProvider.cpp") `
    -Force

Copy-Item `
    (Join-Path $PSScriptRoot "CSampleProvider.h.template") `
    (Join-Path $out "CSampleProvider.h") `
    -Force

Copy-Item `
    (Join-Path $PSScriptRoot "common.h.template") `
    (Join-Path $out "common.h") `
    -Force

Copy-Item `
    (Join-Path $PSScriptRoot "LabSupport.cpp.template") `
    (Join-Path $out "LabSupport.cpp") `
    -Force

Copy-Item `
    (Join-Path $PSScriptRoot "LabSupport.h.template") `
    (Join-Path $out "LabSupport.h") `
    -Force

# ---------------------------------------------------------------------------
# GUID exclusivo do e-GOV Login.
# ---------------------------------------------------------------------------
$guidPath = Join-Path $out "guid.h"

$guidText = @'
// e-GOV Login Credential Provider
// {D2D9E531-8DB1-4C83-ABF9-810F70A1EB09}
DEFINE_GUID(CLSID_CSample,
    0xd2d9e531, 0x8db1, 0x4c83,
    0xab, 0xf9, 0x81, 0x0f, 0x70, 0xa1, 0xeb, 0x09);
'@

Set-Content $guidPath $guidText -Encoding UTF8

# ---------------------------------------------------------------------------
# Projeto VS: toolset atual + LabSupport.
# ---------------------------------------------------------------------------
$projPath = Join-Path $out "SampleV2CredentialProvider.vcxproj"
$proj = Get-Content $projPath -Raw

$proj = $proj.Replace(
    "<PlatformToolset>v110</PlatformToolset>",
    "<PlatformToolset>v143</PlatformToolset>")

$proj = $proj.Replace(
    "<PrecompiledHeader>NotUsing</PrecompiledHeader>",
    "<PrecompiledHeader>NotUsing</PrecompiledHeader>`r`n      <LanguageStandard>stdcpp17</LanguageStandard>")

$compileAnchor = '<ClCompile Include="CSampleCredential.cpp" />'
$headerAnchor = '<ClInclude Include="CSampleCredential.h" />'

if (-not $proj.Contains($compileAnchor)) {
    throw "Anchor ClCompile nao encontrado."
}

if (-not $proj.Contains($headerAnchor)) {
    throw "Anchor ClInclude nao encontrado."
}

$proj = $proj.Replace(
    $compileAnchor,
    $compileAnchor + "`r`n    <ClCompile Include=`"LabSupport.cpp`" />")

$proj = $proj.Replace(
    $headerAnchor,
    $headerAnchor + "`r`n    <ClInclude Include=`"LabSupport.h`" />")

Set-Content $projPath $proj -Encoding UTF8

# ---------------------------------------------------------------------------
# Credential header: memoria do ultimo estado invalido digitado no campo CPF.
# ---------------------------------------------------------------------------
$credHeaderPath = Join-Path $out "CSampleCredential.h"
$h = Get-Content $credHeaderPath -Raw

$headerNeedle = 'bool                                    _fIsLocalUser;                                  // If the cred prov is assosiating with a local user tile'

if (-not $h.Contains($headerNeedle)) {
    throw "Campo _fIsLocalUser nao encontrado em CSampleCredential.h."
}

$h = $h.Replace(
    $headerNeedle,
    $headerNeedle + "`r`n    bool                                    _fCpfInvalidChars;                              // Last CPF input had invalid characters or extra digits")

Set-Content $credHeaderPath $h -Encoding UTF8

# ---------------------------------------------------------------------------
# Credential implementation.
# ---------------------------------------------------------------------------
$credPath = Join-Path $out "CSampleCredential.cpp"
$x = Get-Content $credPath -Raw

$x = $x.Replace(
    '#include "guid.h"',
    "#include `"guid.h`"`r`n#include `"LabSupport.h`"")

$ctorNeedle = '_fShowControls(false),'
if (-not $x.Contains($ctorNeedle)) {
    throw "Constructor anchor nao encontrado."
}

$x = $x.Replace(
    $ctorNeedle,
    "_fShowControls(false),`r`n    _fCpfInvalidChars(false),")

$x = $x.Replace(
    'SHStrDupW(L"Sample Credential", &_rgFieldStrings[SFI_LABEL])',
    'SHStrDupW(L"e-GOV Login", &_rgFieldStrings[SFI_LABEL])')

$x = $x.Replace(
    'SHStrDupW(L"Sample Credential Provider", &_rgFieldStrings[SFI_LARGE_TEXT])',
    'SHStrDupW(L"Acesso e-GOV", &_rgFieldStrings[SFI_LARGE_TEXT])')

$x = $x.Replace(
    'SHStrDupW(L"Edit Text", &_rgFieldStrings[SFI_EDIT_TEXT])',
    'SHStrDupW(L"", &_rgFieldStrings[SFI_EDIT_TEXT])')

$x = $x.Replace(
    'SHStrDupW(L"Submit", &_rgFieldStrings[SFI_SUBMIT_BUTTON])',
    'SHStrDupW(L"Entrar", &_rgFieldStrings[SFI_SUBMIT_BUTTON])')

$x = $x.Replace(
    '*pdwAdjacentTo = SFI_PASSWORD;',
    '*pdwAdjacentTo = SFI_EDIT_TEXT;')

# Limpa o campo que sera usado para mostrar o nome retornado pela API.
$fullNamePattern = '(?s)    if \(SUCCEEDED\(hr\)\)\s*\{\s*PWSTR pszUserName;.*?    \}\s*(?=    if \(SUCCEEDED\(hr\)\)\s*\{\s*PWSTR pszDisplayName;)'

$fullNameReplacement = @'
    if (SUCCEEDED(hr))
    {
        hr = SHStrDupW(L"", &_rgFieldStrings[SFI_FULLNAME_TEXT]);
    }

'@

$x2 = [regex]::Replace(
    $x,
    $fullNamePattern,
    $fullNameReplacement)

if ($x2 -eq $x) {
    throw "Bloco FullName nao encontrado."
}

$x = $x2

$displayPattern = '(?s)    if \(SUCCEEDED\(hr\)\)\s*\{\s*PWSTR pszDisplayName;.*?    \}\s*(?=    if \(SUCCEEDED\(hr\)\)\s*\{\s*PWSTR pszLogonStatus;)'

$displayReplacement = @'
    if (SUCCEEDED(hr))
    {
        hr = SHStrDupW(L"", &_rgFieldStrings[SFI_DISPLAYNAME_TEXT]);
    }

'@

$x2 = [regex]::Replace(
    $x,
    $displayPattern,
    $displayReplacement)

if ($x2 -eq $x) {
    throw "Bloco DisplayName nao encontrado."
}

$x = $x2

# Depois de obter o usuario qualificado, personaliza o titulo da tile.
# Usa regex em vez de Contains/Replace exato para nao depender de CRLF/LF
# do arquivo baixado pelo Invoke-WebRequest no runner do GitHub Actions.
$qualifiedPattern = '(?ms)^[ \t]*if \(SUCCEEDED\(hr\)\)\s*\{\s*hr = pcpUser->GetStringValue\(PKEY_Identity_QualifiedUserName, &_pszQualifiedUserName\);\s*\}'

$qualifiedMatch = [regex]::Match(
    $x,
    $qualifiedPattern)

if (-not $qualifiedMatch.Success) {
    throw "Bloco QualifiedUserName nao encontrado."
}

$titleBlock = @'

    if (SUCCEEDED(hr))
    {
        const bool adminTarget =
            LabIsAccount(_pszQualifiedUserName, L"AdminEGOV");

        PCWSTR tileTitle = adminTarget ? L"Admin e-GOV" : L"";
        std::wstring maintenanceText;

        if (!adminTarget)
        {
            LAB_AUTH_RESPONSE status;

            if (LabGetStatus(&status) == LAB_AUTH_OK && status.maintenance)
            {
                tileTitle = L"Manutenção";
                maintenanceText = status.maintenanceMessage;
            }
        }

        CoTaskMemFree(_rgFieldStrings[SFI_LARGE_TEXT]);
        _rgFieldStrings[SFI_LARGE_TEXT] = nullptr;
        hr = SHStrDupW(tileTitle, &_rgFieldStrings[SFI_LARGE_TEXT]);

        if (SUCCEEDED(hr) && !maintenanceText.empty())
        {
            CoTaskMemFree(_rgFieldStrings[SFI_DISPLAYNAME_TEXT]);
            _rgFieldStrings[SFI_DISPLAYNAME_TEXT] = nullptr;
            hr = SHStrDupW(
                maintenanceText.c_str(),
                &_rgFieldStrings[SFI_DISPLAYNAME_TEXT]);
        }
    }
'@

$qualifiedReplacement =
    $qualifiedMatch.Value +
    $titleBlock

$x =
    $x.Substring(0, $qualifiedMatch.Index) +
    $qualifiedReplacement +
    $x.Substring(
        $qualifiedMatch.Index +
        $qualifiedMatch.Length)

# ---------------------------------------------------------------------------
# Mascara CPF + preview do nome ao completar 11 digitos.
# ---------------------------------------------------------------------------
$setStringPattern = '(?s)HRESULT CSampleCredential::SetStringValue\(DWORD dwFieldID, _In_ PCWSTR pwz\)\s*\{.*?\n\}\s*(?=// Returns whether a checkbox)'

$newSetString = @'
HRESULT CSampleCredential::SetStringValue(DWORD dwFieldID, _In_ PCWSTR pwz)
{
    if (pwz == nullptr)
    {
        return E_INVALIDARG;
    }

    if (dwFieldID == SFI_EDIT_TEXT)
    {
        // Campo CPF: pontos, hifens, barras e espacos sao ignorados, de modo
        // que um CPF colado ja formatado seja aceito. Letras, simbolos e
        // digitos alem do 11o invalidam a entrada.
        //
        // O controle nunca e reescrito: o LogonUI devolve o cursor para o
        // inicio sempre que SetFieldString altera o proprio input. A
        // confirmacao visual fica no eco mascarado em SFI_FULLNAME_TEXT.
        wchar_t digits[12] = {};
        size_t digitCount = 0;
        bool invalidChars = false;
        size_t excessDigits = 0;

        LabCpfExtractDigits(
            pwz,
            digits,
            &digitCount,
            &invalidChars,
            &excessDigits);

        const bool invalidInput =
            invalidChars || excessDigits > 0;

        // Lembrado para o GetSerialization distinguir "digitou lixo"
        // de "digitou poucos numeros".
        _fCpfInvalidChars = invalidInput;

        wchar_t previousDigits[12] = {};

        if (_rgFieldStrings[SFI_EDIT_TEXT] != nullptr)
        {
            StringCchCopyW(
                previousDigits,
                ARRAYSIZE(previousDigits),
                _rgFieldStrings[SFI_EDIT_TEXT]);
        }

        PCWSTR validatedDigits = invalidInput ? L"" : digits;

        const bool changed =
            wcscmp(previousDigits, validatedDigits) != 0;

        PWSTR* stored =
            &_rgFieldStrings[SFI_EDIT_TEXT];

        CoTaskMemFree(*stored);
        *stored = nullptr;

        HRESULT hr =
            SHStrDupW(
                validatedDigits,
                stored);

        if (FAILED(hr))
        {
            return hr;
        }

        wchar_t formatted[15] = {};
        size_t outPos = 0;

        for (size_t i = 0; i < digitCount; ++i)
        {
            if (i == 3 || i == 6)
            {
                formatted[outPos++] = L'.';
            }
            else if (i == 9)
            {
                formatted[outPos++] = L'-';
            }

            formatted[outPos++] = digits[i];
        }

        formatted[outPos] = L'\0';

        wchar_t formattedLine[32] = {};

        // O eco continua visivel mesmo com entrada invalida: e a unica
        // confirmacao que o usuario tem de quais numeros foram entendidos,
        // justamente quando ele precisa corrigir alguma coisa.
        if (digitCount > 0)
        {
            StringCchPrintfW(
                formattedLine,
                ARRAYSIZE(formattedLine),
                L"CPF: %s",
                formatted);
        }

        // Confere os digitos verificadores localmente. Erro de digitacao
        // e respondido na hora, sem a chamada HTTP sincrona do preview.
        const bool checkDigitsOk =
            !invalidInput &&
            digitCount == 11 &&
            LabCpfCheckDigitsOk(digits);

        PCWSTR hintText = L"";

        if (invalidChars)
        {
            hintText = L"Digite apenas números. Pontos e traços são opcionais.";
        }
        else if (excessDigits > 0)
        {
            hintText = L"CPF inválido. Confira os números digitados.";
        }
        else if (digitCount == 11 && !checkDigitsOk)
        {
            hintText = L"CPF inválido. Confira os números digitados.";
        }

        if (_pCredProvCredentialEvents)
        {
            _pCredProvCredentialEvents->BeginFieldUpdates();

            _pCredProvCredentialEvents->SetFieldString(
                this,
                SFI_FULLNAME_TEXT,
                formattedLine);

            if (!checkDigitsOk)
            {
                const bool adminTarget =
                    LabIsAccount(
                        _pszQualifiedUserName,
                        L"AdminEGOV");

                const bool showingMaintenance =
                    !adminTarget &&
                    _rgFieldStrings[SFI_LARGE_TEXT] != nullptr &&
                    wcscmp(
                        _rgFieldStrings[SFI_LARGE_TEXT],
                        L"Manutenção") == 0;

                if (!showingMaintenance)
                {
                    _pCredProvCredentialEvents->SetFieldString(
                        this,
                        SFI_LARGE_TEXT,
                        adminTarget ? L"Admin e-GOV" : L"");

                    _pCredProvCredentialEvents->SetFieldString(
                        this,
                        SFI_DISPLAYNAME_TEXT,
                        hintText);
                }
            }
            else if (changed)
            {
                const bool adminTarget =
                    LabIsAccount(
                        _pszQualifiedUserName,
                        L"AdminEGOV");

                LAB_AUTH_RESPONSE preview;

                LAB_AUTH_RESULT previewResult =
                    LabPreviewCpf(
                        digits,
                        adminTarget,
                        &preview);

                PCWSTR previewText = L"";
                std::wstring greeting;
                std::wstring courseLine;

                if (previewResult == LAB_AUTH_OK)
                {
                    if (preview.maintenance)
                    {
                        courseLine = L"Manutenção";
                        previewText = preview.maintenanceMessage.empty()
                            ? preview.message.c_str()
                            : preview.maintenanceMessage.c_str();
                    }
                    else if (preview.allowed &&
                        !preview.name.empty())
                    {
                        greeting = L"Olá, " + preview.name + L"!";
                        previewText = greeting.c_str();

                        if (!adminTarget && !preview.course.empty())
                        {
                            courseLine = L"Curso: " + preview.course;
                        }
                    }
                    else if (!preview.message.empty())
                    {
                        previewText =
                            preview.message.c_str();
                    }
                }
                else if (previewResult ==
                         LAB_AUTH_SERVICE_UNAVAILABLE)
                {
                    previewText =
                        L"Serviço de autenticação indisponível.";
                }
                else if (previewResult ==
                         LAB_AUTH_NOT_CONFIGURED)
                {
                    previewText =
                        L"API de autenticação não configurada.";
                }
                else if (previewResult ==
                         LAB_AUTH_CLIENT_UNAUTHORIZED)
                {
                    previewText =
                        L"Este computador não foi autorizado.";
                }

                _pCredProvCredentialEvents->SetFieldString(
                    this,
                    SFI_DISPLAYNAME_TEXT,
                    previewText);

                _pCredProvCredentialEvents->SetFieldString(
                    this,
                    SFI_LARGE_TEXT,
                    adminTarget
                        ? L"Admin e-GOV"
                        : courseLine.c_str());
            }

            _pCredProvCredentialEvents->EndFieldUpdates();
        }

        return S_OK;
    }

    if (dwFieldID < ARRAYSIZE(_rgCredProvFieldDescriptors) &&
        CPFT_PASSWORD_TEXT ==
            _rgCredProvFieldDescriptors[dwFieldID].cpft)
    {
        PWSTR* stored =
            &_rgFieldStrings[dwFieldID];

        CoTaskMemFree(*stored);
        *stored = nullptr;

        return SHStrDupW(
            pwz,
            stored);
    }

    return E_INVALIDARG;
}

'@

$x2 = [regex]::Replace(
    $x,
    $setStringPattern,
    $newSetString)

if ($x2 -eq $x) {
    throw "SetStringValue nao foi substituido."
}

$x = $x2

# ---------------------------------------------------------------------------
# GetSerialization: consulta a API em tempo real e usa segredo DPAPI local.
# ---------------------------------------------------------------------------
$serializationAnchor = 'ZeroMemory(pcpcs, sizeof(*pcpcs));'
$anchorIndex = $x.IndexOf($serializationAnchor)

if ($anchorIndex -lt 0) {
    throw "GetSerialization anchor nao encontrado."
}

$authBlock = @'

    if (!_fIsLocalUser)
    {
        SHStrDupW(L"Conta e-GOV local não encontrada.", ppwszOptionalStatusText);
        *pcpsiOptionalStatusIcon = CPSI_ERROR;
        return S_OK;
    }

    const bool adminTarget =
        LabIsAccount(
            _pszQualifiedUserName,
            L"AdminEGOV");

    const bool studentTarget =
        LabIsAccount(
            _pszQualifiedUserName,
            L"AlunoEGOV");

    if (!adminTarget && !studentTarget)
    {
        SHStrDupW(L"Conta e-GOV inválida.", ppwszOptionalStatusText);
        *pcpsiOptionalStatusIcon = CPSI_ERROR;
        return S_OK;
    }

    // Mesma normalizacao usada durante a digitacao, para que o erro
    // apresentado aqui corresponda ao que o usuario viu na tela.
    wchar_t normalizedCpf[12] = {};
    size_t cpfCount = 0;
    bool invalidCpfChars = false;
    size_t excessCpfDigits = 0;

    LabCpfExtractDigits(
        _rgFieldStrings[SFI_EDIT_TEXT],
        normalizedCpf,
        &cpfCount,
        &invalidCpfChars,
        &excessCpfDigits);

    if (_fCpfInvalidChars || invalidCpfChars || excessCpfDigits > 0)
    {
        SHStrDupW(L"CPF inválido.", ppwszOptionalStatusText);
        *pcpsiOptionalStatusIcon = CPSI_ERROR;
        return S_OK;
    }

    if (cpfCount != 11)
    {
        SHStrDupW(L"CPF inválido.", ppwszOptionalStatusText);
        *pcpsiOptionalStatusIcon = CPSI_ERROR;
        return S_OK;
    }

    if (!LabCpfCheckDigitsOk(normalizedCpf))
    {
        SHStrDupW(L"CPF inválido. Confira os números digitados.", ppwszOptionalStatusText);
        *pcpsiOptionalStatusIcon = CPSI_ERROR;
        return S_OK;
    }

    LAB_AUTH_RESPONSE authResponse;

    LAB_AUTH_RESULT authResult =
        LabAuthorizeCpf(
            normalizedCpf,
            adminTarget,
            &authResponse);

    if (authResult != LAB_AUTH_OK ||
        !authResponse.authorized)
    {
        PCWSTR statusText = L"CPF não autorizado.";

        if (!authResponse.message.empty())
        {
            statusText = authResponse.message.c_str();
        }
        else if (authResult == LAB_AUTH_SERVICE_UNAVAILABLE)
        {
            statusText = L"Serviço de autenticação indisponível.";
        }
        else if (authResult == LAB_AUTH_NOT_CONFIGURED)
        {
            statusText = L"API de autenticação não configurada.";
        }
        else if (authResult == LAB_AUTH_CLIENT_UNAUTHORIZED)
        {
            statusText = L"Este computador não foi autorizado.";
        }

        SHStrDupW(statusText, ppwszOptionalStatusText);
        *pcpsiOptionalStatusIcon = CPSI_ERROR;

        // Mantem o CPF digitado em caso de negacao.
        // Nao reescreve CPFT_EDIT_TEXT, pois isso altera o caret no LogonUI.
        return S_OK;
    }

    PCWSTR expectedAccount =
        adminTarget
            ? L"AdminEGOV"
            : L"AlunoEGOV";

    if (authResponse.windowsAccount.empty() ||
        _wcsicmp(
            authResponse.windowsAccount.c_str(),
            expectedAccount) != 0)
    {
        SHStrDupW(L"Perfil retornado pela API é inválido.", ppwszOptionalStatusText);
        *pcpsiOptionalStatusIcon = CPSI_ERROR;
        return S_OK;
    }

    std::wstring localPassword;

    if (!LabReadLocalPassword(
            adminTarget,
            localPassword))
    {
        SHStrDupW(L"Segredo local e-GOV não encontrado.", ppwszOptionalStatusText);
        *pcpsiOptionalStatusIcon = CPSI_ERROR;
        return S_OK;
    }
'@

$insertAt =
    $anchorIndex +
    $serializationAnchor.Length

$x = $x.Insert(
    $insertAt,
    $authBlock)

$oldProtect =
    'ProtectIfNecessaryAndCopyPassword(_rgFieldStrings[SFI_PASSWORD], _cpus, &pwzProtectedPassword)'

$newProtect =
    'ProtectIfNecessaryAndCopyPassword(localPassword.c_str(), _cpus, &pwzProtectedPassword)'

if (-not $x.Contains($oldProtect)) {
    throw "ProtectIfNecessaryAndCopyPassword nao encontrado."
}

$x = $x.Replace(
    $oldProtect,
    $newProtect)

# Final de GetSerialization: regex tolerante a CRLF/LF.
$serializationEndPattern =
    '(?ms)^[ \t]*return hr;\s*\}\s*(?=struct REPORT_RESULT_STATUS_INFO)'

$serializationEndMatch = [regex]::Match(
    $x,
    $serializationEndPattern)

if (-not $serializationEndMatch.Success) {
    throw "Final de GetSerialization nao encontrado."
}

$serializationEndReplacement = @'
    if (*pcpgsr == CPGSR_RETURN_CREDENTIAL_FINISHED)
    {
        LabNotifyAgent(authResponse);
    }

    if (!localPassword.empty())
    {
        SecureZeroMemory(
            &localPassword[0],
            localPassword.size() * sizeof(wchar_t));
        localPassword.clear();
    }

    return hr;
}

'@

$x =
    $x.Substring(0, $serializationEndMatch.Index) +
    $serializationEndReplacement +
    $x.Substring(
        $serializationEndMatch.Index +
        $serializationEndMatch.Length)


# Nao permite NUL literal no C++ gerado. Ele deve aparecer textualmente como L'\0'.
if ($x.IndexOf([char]0) -ge 0) {
    throw "CSampleCredential.cpp contem byte NUL literal. Esperado L'\0'."
}

if ($x.Contains("L''")) {
    throw "CSampleCredential.cpp contem literal de caractere vazio L''."
}

Set-Content $credPath $x -Encoding UTF8

# ---------------------------------------------------------------------------
# Validacoes para impedir build de uma versao incompleta.
# ---------------------------------------------------------------------------
$checkCredential = Get-Content $credPath -Raw
$checkProvider = Get-Content (Join-Path $out "CSampleProvider.cpp") -Raw
$checkSupport = Get-Content (Join-Path $out "LabSupport.cpp") -Raw

$requiredCredential = @(
    'LabCpfExtractDigits(',
    'LabCpfCheckDigitsOk(',
    'LabPreviewCpf(',
    'LabAuthorizeCpf(',
    'LabReadLocalPassword(',
    'LabNotifyAgent(',
    'L"AdminEGOV"',
    'L"AlunoEGOV"'
)

foreach ($needle in $requiredCredential) {
    if (-not $checkCredential.Contains($needle)) {
        throw "Validacao estrutural falhou em CSampleCredential.cpp: $needle"
    }
}

$cpfInputChecks = @(
    @{
        Name = "buffer CPF com 11 digitos"
        Pattern = 'wchar_t\s+digits\[12\]\s*=\s*\{\s*\}\s*;'
    },
    @{
        Name = "normalizacao centralizada em LabSupport"
        Pattern = 'LabCpfExtractDigits\(\s*pwz\s*,'
    },
    @{
        Name = "excesso de digitos invalida a entrada"
        Pattern = 'invalidChars\s*\|\|\s*excessDigits\s*>\s*0'
    },
    @{
        Name = "nao armazena CPF quando entrada for invalida"
        Pattern = 'validatedDigits\s*=\s*invalidInput\s*\?\s*L""\s*:\s*digits'
    },
    @{
        Name = "armazena somente CPF validado"
        Pattern = 'SHStrDupW\(\s*validatedDigits\s*,\s*stored\s*\)'
    },
    @{
        Name = "eco do CPF permanece visivel na entrada invalida"
        Pattern = 'if\s*\(\s*digitCount\s*>\s*0\s*\)'
    },
    @{
        Name = "confere digitos verificadores antes do preview"
        Pattern = 'LabCpfCheckDigitsOk\(\s*digits\s*\)'
    },
    @{
        Name = "preview so ocorre com CPF conferido"
        Pattern = 'if\s*\(\s*!checkDigitsOk\s*\)'
    },
    @{
        Name = "preview usa somente digitos"
        Pattern = 'LabPreviewCpf\(\s*digits\s*,'
    },
    @{
        Name = "submit reusa a normalizacao da digitacao"
        Pattern = 'LabCpfExtractDigits\(\s*\r?\n?\s*_rgFieldStrings\[SFI_EDIT_TEXT\]'
    },
    @{
        Name = "submit confere digitos verificadores"
        Pattern = 'LabCpfCheckDigitsOk\(\s*normalizedCpf\s*\)'
    }
)

foreach ($check in $cpfInputChecks) {
    if (-not [regex]::IsMatch($checkCredential, $check.Pattern)) {
        throw "Validacao CPF falhou: $($check.Name)"
    }
}

# O parsing e o calculo dos digitos verificadores vivem em LabSupport.cpp.
$cpfSupportChecks = @(
    @{
        Name = "aceita somente 0-9"
        Pattern = '\*p\s*>=\s*L''0''\s*&&\s*\*p\s*<=\s*L''9'''
    },
    @{
        Name = "limite de 11 digitos"
        Pattern = 'count\s*<\s*11'
    },
    @{
        Name = "ignora separadores do CPF"
        Pattern = '\*p\s*==\s*L''\.''[\s\S]{0,120}\*p\s*==\s*L''-'''
    },
    @{
        Name = "invalida caracteres nao numericos"
        Pattern = 'invalid\s*=\s*true\s*;'
    },
    @{
        Name = "rejeita sequencias de digitos iguais"
        Pattern = 'allSame'
    },
    @{
        Name = "calcula os digitos verificadores"
        Pattern = '\(\s*total\s*\*\s*10\s*\)\s*%\s*11'
    }
)

foreach ($check in $cpfSupportChecks) {
    if (-not [regex]::IsMatch($checkSupport, $check.Pattern)) {
        throw "Validacao CPF falhou em LabSupport.cpp: $($check.Name)"
    }
}

if (-not $checkCredential.Contains('SFI_FULLNAME_TEXT')) {
    throw "Campo visual da mascara CPF nao foi gerado."
}

if ($checkCredential.Contains('Lab@Teste2026!')) {
    throw "Senha fixa antiga encontrada no Credential Provider."
}

if ($checkCredential.Contains('wcscmp(normalizedCpf, L"')) {
    throw "Validacao de CPF fixa encontrada."
}

$rewriteMatches = [regex]::Matches(
    $checkCredential,
    '(?s)SetFieldString\(\s*this,\s*SFI_EDIT_TEXT\s*,'
)

if ($rewriteMatches.Count -ne 0) {
    throw "Validacao CPF falhou: o input nao deve ser reescrito, pois o LogonUI move o cursor para o inicio."
}

if (-not $checkProvider.Contains('L"AlunoEGOV"') -or
    -not $checkProvider.Contains('L"AdminEGOV"')) {
    throw "Provider nao enumera as duas contas e-GOV."
}

if (-not $checkSupport.Contains('CryptUnprotectData')) {
    throw "DPAPI nao esta sendo usada."
}

Write-Host ""
Write-Host "e-GOV Login v9.5 preparado." -ForegroundColor Green
Write-Host "Tiles: Aluno e-GOV / Admin e-GOV" -ForegroundColor Green
Write-Host "CPF: 11 numeros obrigatorios + API" -ForegroundColor Green
Write-Host "Senha: DPAPI LocalMachine (nao embutida na DLL)" -ForegroundColor Green
