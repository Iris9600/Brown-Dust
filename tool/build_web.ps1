param([string]$Flutter = 'flutter', [string]$Node = 'node')
$ErrorActionPreference = 'Stop'
Push-Location (Join-Path $PSScriptRoot '..')
try {
    & $Flutter build web --release --no-web-resources-cdn
    if ($LASTEXITCODE -ne 0) { throw 'Flutter web build failed.' }
    & $Node tool/prepare_web.mjs
    if ($LASTEXITCODE -ne 0) { throw 'Offline packaging failed.' }
    Write-Host 'Ready to host: build/web (HTTPS required for phone installation).'
} finally {
    Pop-Location
}
