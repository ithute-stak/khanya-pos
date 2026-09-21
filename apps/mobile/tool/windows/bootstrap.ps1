param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$appRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'Flutter was not found on PATH. Install Flutter before building Khanya POS for Windows.'
}

Push-Location $appRoot
try {
    Write-Host '==> Enabling Flutter Windows desktop support'
    flutter config --enable-windows-desktop
    if ($LASTEXITCODE -ne 0) { throw 'flutter config failed.' }

    if (-not (Test-Path 'windows\CMakeLists.txt')) {
        Write-Host '==> Generating the Windows runner'
        flutter create --platforms=windows --project-name khanya_pos .
        if ($LASTEXITCODE -ne 0) { throw 'Windows runner generation failed.' }
    }

    Write-Host '==> Installing Flutter dependencies'
    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed.' }

    Write-Host '==> Generating Drift sources'
    dart run build_runner build --delete-conflicting-outputs
    if ($LASTEXITCODE -ne 0) { throw 'Drift/build_runner generation failed.' }

    Write-Host 'Windows desktop bootstrap completed.'
}
finally {
    Pop-Location
}
