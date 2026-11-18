param(
    [switch]$SkipXtoolProbe
)

$ErrorActionPreference = 'Stop'
$packagePath = Join-Path $PSScriptRoot '..\simple_live_tvos_core'

if (-not $SkipXtoolProbe) {
    if (-not (Get-Command xtool -ErrorAction SilentlyContinue)) {
        throw 'xtool is required. Install it from https://github.com/xtool-org/xtool before running this script.'
    }
    xtool --help | Select-Object -First 3
}

swift test --package-path $packagePath --parallel
