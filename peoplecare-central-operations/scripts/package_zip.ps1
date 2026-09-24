<#
.SYNOPSIS
  Crea lo ZIP del codice sorgente del progetto (senza build, cache e pacchetti).

.PARAMETER Output
  File di destinazione. Predefinito: dist\peoplecare-central-operations-<versione>-src.zip
#>
[CmdletBinding()]
param([string] $Output = '')

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
$name = 'peoplecare-central-operations'
$match = Select-String -Path (Join-Path $root 'pubspec.yaml') -Pattern '^version:\s*([^+\s]+)'
$version = $match.Matches[0].Groups[1].Value
if (-not $Output) { $Output = Join-Path $root "dist\$name-$version-src.zip" }

$excluded = @('build', 'dist', '.dart_tool', '.idea', '.flutter-plugins', '.flutter-plugins-dependencies')
$staging = Join-Path ([System.IO.Path]::GetTempPath()) ("pcco-" + [guid]::NewGuid())
$target = Join-Path $staging $name
try {
  New-Item -ItemType Directory -Force -Path $target | Out-Null
  Get-ChildItem -Path $root -Force | Where-Object { $excluded -notcontains $_.Name -and $_.Extension -ne '.iml' } |
    ForEach-Object { Copy-Item -Path $_.FullName -Destination $target -Recurse -Force }
  $ephemeral = Join-Path $target 'windows\flutter\ephemeral'
  if (Test-Path $ephemeral) { Remove-Item $ephemeral -Recurse -Force }

  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Output) | Out-Null
  if (Test-Path $Output) { Remove-Item $Output -Force }
  Compress-Archive -Path $target -DestinationPath $Output
  Write-Host "Creato: $Output" -ForegroundColor Green
}
finally {
  if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
}
