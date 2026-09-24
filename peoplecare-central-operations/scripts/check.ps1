<#
.SYNOPSIS
  Controlli di qualità: formattazione, analisi statica e test.
  Sono gli stessi controlli eseguiti dalla pipeline CI.
#>
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Push-Location (Split-Path -Parent $PSScriptRoot)
try {
  $steps = @(
    @{ Title = 'flutter pub get'; Args = @('pub', 'get') },
    @{ Title = 'dart format (verifica)'; Args = @('format', '--output=none', '--set-exit-if-changed', 'lib', 'test') },
    @{ Title = 'flutter analyze'; Args = @('analyze') },
    @{ Title = 'flutter test'; Args = @('test') }
  )
  foreach ($step in $steps) {
    Write-Host ''
    Write-Host "==> $($step.Title)" -ForegroundColor Cyan
    $tool = 'flutter'
    if ($step.Args[0] -eq 'format') { $tool = 'dart' }
    $stepArgs = $step.Args
    & $tool @stepArgs
    if ($LASTEXITCODE -ne 0) { throw "Controllo non superato: $($step.Title)" }
  }
  Write-Host ''
  Write-Host 'Tutti i controlli sono stati superati.' -ForegroundColor Green
}
finally {
  Pop-Location
}
