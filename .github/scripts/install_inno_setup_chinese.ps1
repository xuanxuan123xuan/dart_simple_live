[CmdletBinding()]
param(
  [string]$SourcePath = (Join-Path $PSScriptRoot '..\installer\ChineseSimplified.isl')
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
  throw "Chinese language file was not found: $SourcePath"
}

$candidateRoots = @(
  (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6'),
  (Join-Path $env:ProgramFiles 'Inno Setup 6')
) | Where-Object { $_ -and (Test-Path -LiteralPath (Join-Path $_ 'ISCC.exe')) }

$innoRoot = $candidateRoots | Select-Object -First 1
if (-not $innoRoot) {
  $iscc = Get-Command 'ISCC.exe' -ErrorAction SilentlyContinue
  if ($iscc) {
    $innoRoot = Split-Path -Parent $iscc.Source
  }
}

if (-not $innoRoot) {
  throw 'Inno Setup compiler (ISCC.exe) was not found.'
}

$languageDirectory = Join-Path $innoRoot 'Languages'
New-Item -ItemType Directory -Force -Path $languageDirectory | Out-Null
$destinationPath = Join-Path $languageDirectory 'ChineseSimplified.isl'
Copy-Item -LiteralPath $SourcePath -Destination $destinationPath -Force

if (-not (Test-Path -LiteralPath $destinationPath -PathType Leaf)) {
  throw "Failed to install Chinese language file: $destinationPath"
}

Write-Host "Installed Inno Setup Chinese language file: $destinationPath"
