#Requires -Version 5.1
<#
  Build a portable Windows distribution for Odysseus.

  Output layout:
    dist\windows\Odysseus\Odysseus.exe
    dist\windows\Odysseus\_internal\... (bundled runtime and assets)
        dist\windows\Odysseus-windows-unsigned.zip
        dist\windows\Odysseus-Setup-unsigned.exe

  The app then keeps using its normal filesystem layout when frozen.

  Usage:
    powershell -ExecutionPolicy Bypass -File .\build-windows-portable.ps1
#>
param(
    [switch]$Sign,
    [switch]$SkipInstaller,
    [string]$CertificateThumbprint = $env:ODYSSEUS_WINDOWS_CERT_THUMBPRINT,
    [string]$TimestampServer = "https://timestamp.digicert.com"
)

$ErrorActionPreference = "Stop"
Set-Location -Path $PSScriptRoot

function Write-Step($msg) { Write-Host ""; Write-Host ("==> " + $msg) -ForegroundColor Cyan }
function Fail($msg) {
    Write-Host ""
    Write-Host ("ERROR: " + $msg) -ForegroundColor Red
    exit 1
}

Write-Step "Checking for Python"
$pyExe = $null
if (Test-Path ".\.venv\Scripts\python.exe") {
    $pyExe = (Resolve-Path ".\.venv\Scripts\python.exe").Path
} else {
    foreach ($c in @("python", "py")) {
        $cmd = Get-Command $c -ErrorAction SilentlyContinue
        if ($cmd) { $pyExe = $cmd.Source; break }
    }
    if ($pyExe -like "*WindowsApps*python.exe") {
        $pyCmd = Get-Command py -ErrorAction SilentlyContinue
        if ($pyCmd) {
            $pyExe = $pyCmd.Source
        }
    }
}
if (-not $pyExe) {
    Fail "Python not found on PATH. Install Python 3.11+ first."
}
Write-Host ("Using Python: " + $pyExe)

& $pyExe -c "import sys; raise SystemExit(0 if sys.version_info[:2] >= (3, 11) else 1)"
if ($LASTEXITCODE -ne 0) { Fail "Python 3.11+ is required." }

Write-Step "Preparing isolated build environment"
$buildPython = Join-Path $PSScriptRoot ".venv-build-windows\Scripts\python.exe"
if (-not (Test-Path $buildPython)) {
    & $pyExe -m venv .venv-build-windows
    if ($LASTEXITCODE -ne 0) { Fail "Could not create the build environment." }
}
$pyExe = $buildPython

Write-Step "Installing build dependencies"
& $pyExe -m pip install --quiet --require-hashes --only-binary=:all: --no-deps -r requirements-bootstrap.txt
if ($LASTEXITCODE -ne 0) { Fail "TLS build dependency bootstrap failed." }
& $pyExe -m pip install -r requirements.txt -r requirements-desktop-build.txt
if ($LASTEXITCODE -ne 0) { Fail "Dependency install failed." }

Write-Step "Building portable exe bundle"
# Odysseus.spec owns all assets, including licenses,
# THIRD_PARTY_PROVENANCE.json and ACKNOWLEDGMENTS.md. Building from the spec
# avoids silently overwriting it with PyInstaller's generated defaults.
& $pyExe -m PyInstaller --noconfirm --clean --workpath build/windows --distpath dist/windows Odysseus.spec
if ($LASTEXITCODE -ne 0) { Fail "PyInstaller build failed." }

if ($Sign) {
    Write-Step "Signing Windows executable"
    & "$PSScriptRoot\scripts\sign-windows.ps1" -FilePath "$PSScriptRoot\dist\windows\Odysseus\Odysseus.exe" -CertificateThumbprint $CertificateThumbprint -TimestampServer $TimestampServer
    if ($LASTEXITCODE -ne 0) { Fail "Windows signing failed." }
}

Write-Step "Testing packaged startup and account persistence"
& $pyExe scripts/smoke_desktop.py --executable dist/windows/Odysseus/Odysseus.exe
if ($LASTEXITCODE -ne 0) { Fail "Packaged application smoke test failed." }

Write-Step "Creating distribution zip"
$suffix = if ($Sign) { "signed" } else { "unsigned" }
$archive = "dist\windows\Odysseus-windows-$suffix.zip"
Compress-Archive -Path "dist\windows\Odysseus" -DestinationPath $archive -Force
$hash = (Get-FileHash -Algorithm SHA256 $archive).Hash.ToLowerInvariant()
Set-Content -Path "$archive.sha256" -Value "$hash  $(Split-Path $archive -Leaf)" -Encoding ASCII

if (-not $SkipInstaller) {
    Write-Step "Building per-user Windows installer"
    $iscc = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($iscc) {
        $isccPath = $iscc.Source
    } else {
        $candidates = @(
            (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
            (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe')
        ) | Where-Object { $_ -and (Test-Path $_) }
        $isccPath = $candidates | Select-Object -First 1
    }
    if (-not $isccPath) {
        Fail "Inno Setup 6 is required to create the installer. Install it from https://jrsoftware.org/isinfo.php or use -SkipInstaller to build only the portable ZIP."
    }
    $installerArgs = @(
        "/DAppSourceDir=$((Join-Path $PSScriptRoot 'dist\windows\Odysseus'))",
        "/DOutputDir=$((Join-Path $PSScriptRoot 'dist\windows'))",
        "/DInstallerSuffix=$suffix",
        '/DAppVersion=1.0.3',
        (Join-Path $PSScriptRoot 'installer\windows\Odysseus.iss')
    )
    & $isccPath @installerArgs
    if ($LASTEXITCODE -ne 0) { Fail "Inno Setup failed (exit $LASTEXITCODE)." }
    $installer = Join-Path $PSScriptRoot "dist\windows\Odysseus-Setup-$suffix.exe"
    if ($Sign) {
        Write-Step "Signing Windows installer"
        & "$PSScriptRoot\scripts\sign-windows.ps1" -FilePath $installer -CertificateThumbprint $CertificateThumbprint -TimestampServer $TimestampServer
        if ($LASTEXITCODE -ne 0) { Fail "Windows installer signing failed." }
    }
    $installerHash = (Get-FileHash -Algorithm SHA256 $installer).Hash.ToLowerInvariant()
    Set-Content -Path "$installer.sha256" -Value "$installerHash  $(Split-Path $installer -Leaf)" -Encoding ASCII
}

Write-Host ""
Write-Host "Build complete." -ForegroundColor Green
Write-Host "Portable app folder: $PSScriptRoot\dist\windows\Odysseus" -ForegroundColor Green
Write-Host "Downloadable zip: $PSScriptRoot\$archive" -ForegroundColor Green
if (-not $SkipInstaller) { Write-Host "Windows installer: $PSScriptRoot\dist\windows\Odysseus-Setup-$suffix.exe" -ForegroundColor Green }
Write-Host "Distribute the whole folder (or zip it) so static assets and scripts stay with the exe." -ForegroundColor Green
