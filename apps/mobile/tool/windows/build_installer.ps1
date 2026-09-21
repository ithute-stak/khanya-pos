param(
    [string]$ApiBaseUrl = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$appRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$bootstrap = Join-Path $PSScriptRoot 'bootstrap.ps1'
$installerScript = Join-Path $PSScriptRoot 'khanya_pos.iss'

Write-Host '==> Preparing Windows desktop project'
& $bootstrap
if ($LASTEXITCODE -ne 0) { throw 'Windows desktop bootstrap failed.' }

Push-Location $appRoot
try {
    $buildArgs = @('build', 'windows', '--release')
    if (-not [string]::IsNullOrWhiteSpace($ApiBaseUrl)) {
        $buildArgs += "--dart-define=KHANYA_API_BASE_URL=$ApiBaseUrl"
    }

    Write-Host '==> Building Khanya POS for Windows'
    & flutter @buildArgs
    if ($LASTEXITCODE -ne 0) { throw 'flutter build windows failed.' }

    $releaseDir = (Resolve-Path 'build\windows\x64\runner\Release').Path
    $installerDir = Join-Path $appRoot 'build\windows\installer'
    $iconFile = (Resolve-Path 'windows\runner\resources\app_icon.ico').Path
    New-Item -ItemType Directory -Force -Path $installerDir | Out-Null

    $isccCandidates = @()
    $isccCommand = Get-Command 'ISCC.exe' -ErrorAction SilentlyContinue
    if ($null -ne $isccCommand) {
        $isccCandidates += $isccCommand.Source
    }
    if (${env:ProgramFiles(x86)}) {
        $isccCandidates += (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe')
    }
    if ($env:ProgramFiles) {
        $isccCandidates += (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe')
    }
    $iscc = $isccCandidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
    if (-not $iscc) {
        throw 'Inno Setup 6 (ISCC.exe) was not found. Install Inno Setup 6 and retry.'
    }

    $versionMatch = Select-String -Path 'pubspec.yaml' -Pattern '^version:\s*([^\s+]+)'
    if (-not $versionMatch) { throw 'Could not read the app version from pubspec.yaml.' }
    $appVersion = $versionMatch.Matches[0].Groups[1].Value

    Write-Host "==> Packaging Khanya POS $appVersion installer"
    & $iscc "/DSourceDir=$releaseDir" "/DOutputDir=$installerDir" "/DMyAppVersion=$appVersion" "/DIconFile=$iconFile" $installerScript
    if ($LASTEXITCODE -ne 0) { throw 'Inno Setup packaging failed.' }

    $installer = Join-Path $installerDir 'KhanyaPOS-Setup.exe'
    if (-not (Test-Path $installer)) {
        throw "Expected installer was not created at $installer"
    }

    Write-Host "Installer created: $installer"
}
finally {
    Pop-Location
}
