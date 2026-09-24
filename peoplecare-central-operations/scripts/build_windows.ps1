<#
.SYNOPSIS
  Compila PeopleCare Central Operations per Windows x64 e ne crea il pacchetto ZIP.

.DESCRIPTION
  Passi eseguiti, dalla cartella del progetto:
    1. flutter pub get
    2. flutter analyze e flutter test (saltati con -SkipChecks)
    3. flutter build windows --release con le --dart-define richieste
    4. compressione della cartella Release in dist\ (saltata con -NoZip)

  Lo script non accetta e non salva credenziali: l'autenticazione verso il
  sistema PeopleCare è compito dei repository API (vedi HANDOFF.md).

.PARAMETER DataSource
  'mock' (predefinito): dati dimostrativi in memoria.
  'api': repository HTTP verso le API PeopleCare (da implementare, HANDOFF.md).

.PARAMETER ApiBaseUrl
  Indirizzo base delle API PeopleCare, usato solo con -DataSource api.

.PARAMETER BuildName
  Versione (es. 1.2.0). Predefinita: quella di pubspec.yaml.

.PARAMETER BuildNumber
  Numero di build (es. il numero della pipeline).

.EXAMPLE
  .\scripts\build_windows.ps1

.EXAMPLE
  .\scripts\build_windows.ps1 -SkipChecks -BuildName 1.0.1 -BuildNumber 42
#>
[CmdletBinding()]
param(
  [ValidateSet('mock', 'api')]
  [string] $DataSource = 'mock',
  [string] $ApiBaseUrl = '',
  [string] $BuildName = '',
  [string] $BuildNumber = '',
  [switch] $SkipChecks,
  [switch] $NoZip
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$BinaryName = 'PeopleCareCentralOperations'

function Invoke-Step {
  param([string] $Title, [scriptblock] $Action)
  Write-Host ''
  Write-Host "==> $Title" -ForegroundColor Cyan
  # Windows PowerShell 5.1 trasforma in errori le righe che i comandi nativi
  # scrivono su stderr quando l'output è rediretto (es. in CI): durante il
  # comando vale solo il codice di uscita.
  $previous = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    & $Action
  }
  finally {
    $ErrorActionPreference = $previous
  }
  if ($LASTEXITCODE -ne 0) {
    throw "Passo non riuscito: $Title (codice $LASTEXITCODE)"
  }
}

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  throw 'Flutter non trovato nel PATH. Installare Flutter (canale stable) con il supporto Windows desktop e riaprire il terminale.'
}
if ($DataSource -eq 'api' -and -not $ApiBaseUrl) {
  throw 'Con -DataSource api occorre indicare -ApiBaseUrl.'
}

Push-Location $ProjectRoot
try {
  Invoke-Step 'flutter pub get' { flutter pub get }

  if (-not $SkipChecks) {
    Invoke-Step 'flutter analyze' { flutter analyze }
    Invoke-Step 'flutter test' { flutter test }
  }

  $buildArgs = @('build', 'windows', '--release', "--dart-define=PEOPLECARE_DATA_SOURCE=$DataSource")
  if ($ApiBaseUrl) { $buildArgs += "--dart-define=PEOPLECARE_API_BASE_URL=$ApiBaseUrl" }
  if ($BuildName) { $buildArgs += "--build-name=$BuildName" }
  if ($BuildNumber) { $buildArgs += "--build-number=$BuildNumber" }
  Invoke-Step 'flutter build windows --release' { flutter @buildArgs }

  $releaseDir = Join-Path $ProjectRoot 'build\windows\x64\runner\Release'
  $exe = Join-Path $releaseDir "$BinaryName.exe"
  if (-not (Test-Path $exe)) {
    throw "Eseguibile non trovato: $exe"
  }
  Write-Host ''
  Write-Host "Eseguibile: $exe" -ForegroundColor Green

  if (-not $NoZip) {
    $version = $BuildName
    if (-not $version) {
      $match = Select-String -Path (Join-Path $ProjectRoot 'pubspec.yaml') -Pattern '^version:\s*([^+\s]+)'
      $version = $match.Matches[0].Groups[1].Value
    }
    $dist = Join-Path $ProjectRoot 'dist'
    New-Item -ItemType Directory -Force -Path $dist | Out-Null
    $zip = Join-Path $dist "$BinaryName-$version-windows-x64-$DataSource.zip"
    if (Test-Path $zip) { Remove-Item $zip -Force }
    Compress-Archive -Path (Join-Path $releaseDir '*') -DestinationPath $zip
    Write-Host "Pacchetto: $zip" -ForegroundColor Green
    Write-Host 'Distribuire l''intera cartella (o lo ZIP): l''eseguibile richiede le DLL e la cartella data accanto.'
  }
}
finally {
  Pop-Location
}
