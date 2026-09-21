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
        Write-Host '==> Generating the Windows runner in an isolated temporary project'
        $tempProject = Join-Path ([System.IO.Path]::GetTempPath()) ("khanya-pos-windows-$([guid]::NewGuid().ToString('N'))")
        try {
            flutter create --platforms=windows --project-name khanya_pos --no-pub $tempProject
            if ($LASTEXITCODE -ne 0) { throw 'Windows runner generation failed.' }
            Copy-Item -Path (Join-Path $tempProject 'windows') -Destination (Join-Path $appRoot 'windows') -Recurse -Force
        }
        finally {
            if (Test-Path $tempProject) {
                Remove-Item -Path $tempProject -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Write-Host '==> Installing Flutter dependencies'
    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed.' }

    Write-Host '==> Applying Khanya launcher icon to generated desktop runner'
    dart run flutter_launcher_icons
    if ($LASTEXITCODE -ne 0) { throw 'Khanya launcher icon generation failed.' }

    Write-Host '==> Generating Drift sources'
    dart run build_runner build
    if ($LASTEXITCODE -ne 0) { throw 'Drift/build_runner generation failed.' }

    Write-Host 'Windows desktop bootstrap completed.'
}
finally {
    Pop-Location
}
