<#
.SYNOPSIS
  Avvia PeopleCare Central Operations in modalità sviluppo (flutter run -d windows).

.PARAMETER LatencyMs
  Ritardo simulato delle chiamate ai repository demo, in millisecondi (predefinito 180).

.PARAMETER NoSimulation
  Disattiva la simulazione degli eventi dall'app mobile (inizio/fine servizi,
  richieste di modifica, documenti) nella modalità demo.

.PARAMETER Release
  Avvia la build release invece di quella di debug.

.EXAMPLE
  .\scripts\run_windows_dev.ps1 -LatencyMs 0 -NoSimulation
#>
[CmdletBinding()]
param(
  [int] $LatencyMs = 180,
  [switch] $NoSimulation,
  [switch] $Release
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  throw 'Flutter non trovato nel PATH.'
}

$simulation = if ($NoSimulation) { 'false' } else { 'true' }
$runArgs = @(
  'run', '-d', 'windows',
  '--dart-define=PEOPLECARE_DATA_SOURCE=mock',
  "--dart-define=PEOPLECARE_DEMO_LATENCY_MS=$LatencyMs",
  "--dart-define=PEOPLECARE_DEMO_SIMULATION=$simulation"
)
if ($Release) { $runArgs += '--release' }

Push-Location (Split-Path -Parent $PSScriptRoot)
try {
  # Solo il codice di uscita decide (vedi build_windows.ps1).
  $ErrorActionPreference = 'Continue'
  flutter pub get
  if ($LASTEXITCODE -ne 0) { throw 'flutter pub get non riuscito' }
  flutter @runArgs
}
finally {
  $ErrorActionPreference = 'Stop'
  Pop-Location
}
