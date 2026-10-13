param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$FlutterArguments
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$envPath = Join-Path $projectRoot '.env'
$flutter = 'D:\tools\flutter\bin\flutter.bat'

if (-not (Test-Path -LiteralPath $envPath)) {
    throw "Missing $envPath. Copy .env.example to .env and configure it first."
}

$allowedKeys = @(
    'AnilistClientName',
    'AnilistClientId',
    'AnilistOAuthUrl',
    'AnilistOauhUrl',
    'AnilistRedirectUrl'
)
$defines = [System.Collections.Generic.List[string]]::new()

foreach ($line in Get-Content -LiteralPath $envPath) {
    $trimmed = $line.Trim()
    if (-not $trimmed -or $trimmed.StartsWith('#')) { continue }
    $separator = $trimmed.IndexOf('=')
    if ($separator -lt 1) { continue }
    $key = $trimmed.Substring(0, $separator).Trim()
    if ($allowedKeys -notcontains $key) { continue }
    $value = $trimmed.Substring($separator + 1).Trim().Trim('"').Trim("'")
    if ($value) { $defines.Add("--dart-define=$key=$value") }
}

if (-not ($defines | Where-Object { $_ -like '--dart-define=AnilistClientId=*' })) {
    throw 'AnilistClientId is missing from .env.'
}

Push-Location -LiteralPath $projectRoot
try {
    # Keep native plugin registration in sync with pubspec changes before the
    # caller uses --no-pub or launches an incremental Android build.
    & $flutter pub get
    if ($LASTEXITCODE -ne 0) {
        $flutterExitCode = $LASTEXITCODE
    } else {
        & $flutter @FlutterArguments @defines
        $flutterExitCode = $LASTEXITCODE
    }
} finally {
    Pop-Location
}

exit $flutterExitCode
