$ErrorActionPreference = "Stop"

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
# Credential header: flag contra reentrada ao aplicar mascara.
# ---------------------------------------------------------------------------
$credHeaderPath = Join-Path $out "CSampleCredential.h"
$h = Get-Content $credHeaderPath -Raw

$headerNeedle = 'bool                                    _fIsLocalUser;                                  // If the cred prov is assosiating with a local user tile'

if (-not $h.Contains($headerNeedle)) {
    throw "Campo _fIsLocalUser nao encontrado em CSampleCredential.h."
}

$h = $h.Replace(
    $headerNeedle,
    $headerNeedle + "`r`n    bool                                    _fUpdatingCpf;                                  // Prevent recursive UI update while applying CPF mask")

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
    "_fShowControls(false),`r`n    _fUpdatingCpf(false),")

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
        PCWSTR tileTitle =
            LabIsAccount(_pszQualifiedUserName, L"AdminEGOV")
                ? L"Admin e-GOV"
                : L"Aluno e-GOV";

        CoTaskMemFree(_rgFieldStrings[SFI_LARGE_TEXT]);
        _rgFieldStrings[SFI_LARGE_TEXT] = nullptr;
        hr = SHStrDupW(tileTitle, &_rgFieldStrings[SFI_LARGE_TEXT]);
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
        if (_fUpdatingCpf)
        {
            return S_OK;
        }

        // Mantem uma copia do ultimo valor valido para poder rejeitar
        // caracteres nao numericos, pontuacao digitada manualmente e
        // o 12o digito sem deixar lixo visual no campo.
        wchar_t previousFormatted[15] = {};
        wchar_t previousDigits[12] = {};
        size_t previousDigitCount = 0;

        if (_rgFieldStrings[SFI_EDIT_TEXT] != nullptr)
        {
            StringCchCopyW(
                previousFormatted,
                ARRAYSIZE(previousFormatted),
                _rgFieldStrings[SFI_EDIT_TEXT]);

            for (PCWSTR p = previousFormatted;
                 *p != L'\0' && previousDigitCount < 11;
                 ++p)
            {
                if (*p >= L'0' && *p <= L'9')
                {
                    previousDigits[previousDigitCount++] = *p;
                }
            }
        }

        wchar_t digits[12] = {};
        size_t digitCount = 0;
        bool invalidCharacter = false;
        bool tooManyDigits = false;

        for (PCWSTR p = pwz; *p != L'\0'; ++p)
        {
            if (*p >= L'0' && *p <= L'9')
            {
                if (digitCount >= 11)
                {
                    tooManyDigits = true;
                    break;
                }

                digits[digitCount++] = *p;
            }
            else if (*p == L'.' || *p == L'-')
            {
                // Pontuacao existente da propria mascara pode aparecer em pwz.
                // Abaixo identificamos se ponto/traco foi digitado pelo usuario.
            }
            else
            {
                // Letras, espacos e qualquer outro caractere sao proibidos.
                invalidCharacter = true;
                break;
            }
        }

        auto restorePreviousValue =
            [&]()
            {
                if (_pCredProvCredentialEvents &&
                    wcscmp(previousFormatted, pwz) != 0)
                {
                    _fUpdatingCpf = true;

                    _pCredProvCredentialEvents->SetFieldString(
                        this,
                        SFI_EDIT_TEXT,
                        previousFormatted);

                    _fUpdatingCpf = false;
                }
            };

        if (invalidCharacter || tooManyDigits)
        {
            restorePreviousValue();

            if (_pCredProvCredentialEvents)
            {
                _pCredProvCredentialEvents->SetFieldString(
                    this,
                    SFI_DISPLAYNAME_TEXT,
                    invalidCharacter
                        ? L"Digite somente numeros."
                        : L"O CPF deve ter exatamente 11 digitos.");
            }

            return S_OK;
        }

        // Descobre apenas o trecho efetivamente alterado pelo usuario.
        // Isso permite diferenciar a pontuacao que ja fazia parte da mascara
        // de um '.' ou '-' digitado manualmente.
        size_t oldLength = wcslen(previousFormatted);
        size_t newLength = wcslen(pwz);

        size_t prefixLength = 0;

        while (prefixLength < oldLength &&
               prefixLength < newLength &&
               previousFormatted[prefixLength] == pwz[prefixLength])
        {
            ++prefixLength;
        }

        size_t suffixLength = 0;

        while (suffixLength < (oldLength - prefixLength) &&
               suffixLength < (newLength - prefixLength) &&
               previousFormatted[oldLength - 1 - suffixLength] ==
                   pwz[newLength - 1 - suffixLength])
        {
            ++suffixLength;
        }

        const size_t changedStart = prefixLength;
        const size_t changedEnd =
            newLength - suffixLength;

        bool punctuationTypedByUser = false;

        for (size_t i = changedStart;
             i < changedEnd;
             ++i)
        {
            if (pwz[i] == L'.' || pwz[i] == L'-')
            {
                punctuationTypedByUser = true;
                break;
            }
        }

        if (punctuationTypedByUser)
        {
            restorePreviousValue();

            if (_pCredProvCredentialEvents)
            {
                _pCredProvCredentialEvents->SetFieldString(
                    this,
                    SFI_DISPLAYNAME_TEXT,
                    L"Digite somente numeros. A mascara e automatica.");
            }

            return S_OK;
        }

        // Formata sempre a partir dos 0..11 digitos puros.
        // Resultado: 000.000.000-00
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

        const bool digitsChanged =
            (digitCount != previousDigitCount) ||
            (wcscmp(digits, previousDigits) != 0);

        PWSTR* stored = &_rgFieldStrings[SFI_EDIT_TEXT];
        CoTaskMemFree(*stored);
        *stored = nullptr;

        HRESULT hr = SHStrDupW(
            formatted,
            stored);

        if (FAILED(hr))
        {
            return hr;
        }

        if (_pCredProvCredentialEvents)
        {
            _fUpdatingCpf = true;
            _pCredProvCredentialEvents->BeginFieldUpdates();

            // Ponto importante:
            // nao reescreve o campo a cada tecla. Isso evita que o LogonUI
            // reposicione o cursor desnecessariamente. So atualiza o controle
            // quando realmente e necessario inserir/remover pontuacao.
            if (wcscmp(formatted, pwz) != 0)
            {
                _pCredProvCredentialEvents->SetFieldString(
                    this,
                    SFI_EDIT_TEXT,
                    formatted);
            }

            if (digitCount < 11)
            {
                _pCredProvCredentialEvents->SetFieldString(
                    this,
                    SFI_DISPLAYNAME_TEXT,
                    L"");
            }
            else if (digitsChanged)
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

                if (previewResult == LAB_AUTH_OK)
                {
                    if (preview.allowed &&
                        !preview.name.empty())
                    {
                        previewText =
                            preview.name.c_str();
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
                        L"Servico de autenticacao indisponivel.";
                }
                else if (previewResult ==
                         LAB_AUTH_NOT_CONFIGURED)
                {
                    previewText =
                        L"API nao configurada.";
                }
                else if (previewResult ==
                         LAB_AUTH_CLIENT_UNAUTHORIZED)
                {
                    previewText =
                        L"Computador nao autorizado.";
                }

                _pCredProvCredentialEvents->SetFieldString(
                    this,
                    SFI_DISPLAYNAME_TEXT,
                    previewText);
            }

            _pCredProvCredentialEvents->EndFieldUpdates();
            _fUpdatingCpf = false;
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
        SHStrDupW(L"Conta e-GOV local nao encontrada.", ppwszOptionalStatusText);
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
        SHStrDupW(L"Conta e-GOV invalida.", ppwszOptionalStatusText);
        *pcpsiOptionalStatusIcon = CPSI_ERROR;
        return S_OK;
    }

    wchar_t normalizedCpf[12] = {};
    size_t cpfPos = 0;
    bool invalidCpfChar = false;

    if (_rgFieldStrings[SFI_EDIT_TEXT] != nullptr)
    {
        for (PCWSTR p = _rgFieldStrings[SFI_EDIT_TEXT];
             *p != L'\0';
             ++p)
        {
            if (*p >= L'0' && *p <= L'9')
            {
                if (cpfPos >= 11)
                {
                    cpfPos = 12;
                    break;
                }

                normalizedCpf[cpfPos++] = *p;
            }
            else if (*p == L'.' || *p == L'-')
            {
                // Mascara.
            }
            else
            {
                invalidCpfChar = true;
                break;
            }
        }
    }

    if (invalidCpfChar || cpfPos != 11)
    {
        SHStrDupW(L"CPF invalido.", ppwszOptionalStatusText);
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
        PCWSTR statusText = L"CPF nao autorizado.";

        if (!authResponse.message.empty())
        {
            statusText = authResponse.message.c_str();
        }
        else if (authResult == LAB_AUTH_SERVICE_UNAVAILABLE)
        {
            statusText = L"Servico de autenticacao indisponivel.";
        }
        else if (authResult == LAB_AUTH_NOT_CONFIGURED)
        {
            statusText = L"API de autenticacao nao configurada.";
        }
        else if (authResult == LAB_AUTH_CLIENT_UNAUTHORIZED)
        {
            statusText = L"Este computador nao foi autorizado.";
        }

        SHStrDupW(statusText, ppwszOptionalStatusText);
        *pcpsiOptionalStatusIcon = CPSI_ERROR;

        if (_pCredProvCredentialEvents)
        {
            _pCredProvCredentialEvents->SetFieldString(
                this,
                SFI_EDIT_TEXT,
                L"");
        }

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
        SHStrDupW(L"Perfil retornado pela API e invalido.", ppwszOptionalStatusText);
        *pcpsiOptionalStatusIcon = CPSI_ERROR;
        return S_OK;
    }

    std::wstring localPassword;

    if (!LabReadLocalPassword(
            adminTarget,
            localPassword))
    {
        SHStrDupW(L"Segredo local e-GOV nao encontrado.", ppwszOptionalStatusText);
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
    'LabPreviewCpf(',
    'LabAuthorizeCpf(',
    'LabReadLocalPassword(',
    'LabNotifyAgent(',
    'L"AdminEGOV"',
    'L"AlunoEGOV"',
    'Digite somente numeros.'
    'A mascara e automatica.'
    'wcscmp(formatted, pwz) != 0'
)

foreach ($needle in $requiredCredential) {
    if (-not $checkCredential.Contains($needle)) {
        throw "Validacao falhou em CSampleCredential.cpp: $needle"
    }
}

if ($checkCredential.Contains('Lab@Teste2026!')) {
    throw "Senha fixa antiga encontrada no Credential Provider."
}

if ($checkCredential.Contains('wcscmp(normalizedCpf, L"')) {
    throw "Validacao de CPF fixa encontrada."
}

if (-not $checkProvider.Contains('L"AlunoEGOV"') -or
    -not $checkProvider.Contains('L"AdminEGOV"')) {
    throw "Provider nao enumera as duas contas e-GOV."
}

if (-not $checkSupport.Contains('CryptUnprotectData')) {
    throw "DPAPI nao esta sendo usada."
}

Write-Host ""
Write-Host "e-GOV Login v8.9 preparado." -ForegroundColor Green
Write-Host "Tiles: Aluno e-GOV / Admin e-GOV" -ForegroundColor Green
Write-Host "CPF: mascara automatica + API" -ForegroundColor Green
Write-Host "Senha: DPAPI LocalMachine (nao embutida na DLL)" -ForegroundColor Green
