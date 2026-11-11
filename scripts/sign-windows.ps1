#Requires -Version 5.1
<# Sign with an installed certificate/hardware provider; no private keys or
   passwords are passed on the command line. Install the Windows SDK first. #>
param(
    [Parameter(Mandatory = $true)][string]$FilePath,
    [Parameter(Mandatory = $true)][string]$CertificateThumbprint,
    [string]$TimestampServer = "https://timestamp.digicert.com"
)
$ErrorActionPreference = "Stop"
if (-not $CertificateThumbprint -or $CertificateThumbprint -notmatch '^[0-9a-fA-F]{40}$') {
    throw "Provide the SHA-1 thumbprint of an installed Authenticode certificate."
}
if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
    throw "Signing input does not exist: $FilePath"
}
$certificate = Get-Item "Cert:\CurrentUser\My\$CertificateThumbprint" -ErrorAction Stop
if (-not $certificate.HasPrivateKey -or $certificate.NotAfter -le (Get-Date)) {
    throw "The signing certificate needs an accessible private key and must not be expired."
}
$signTool = Get-Command signtool.exe -ErrorAction SilentlyContinue
if (-not $signTool) {
    $sdk = Join-Path ${env:ProgramFiles(x86)} "Windows Kits\10\bin"
    $candidate = Get-ChildItem "$sdk\*\x64\signtool.exe" -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending | Select-Object -First 1
    if ($candidate) { $signToolPath = $candidate.FullName }
} else {
    $signToolPath = $signTool.Source
}
if (-not $signToolPath) { throw "signtool.exe is missing. Install the Windows SDK Signing Tools." }
& $signToolPath sign /sha1 $CertificateThumbprint /fd SHA256 /tr $TimestampServer /td SHA256 $FilePath
if ($LASTEXITCODE -ne 0) { throw "Authenticode signing failed (exit $LASTEXITCODE)." }
& $signToolPath verify /pa /all /tw $FilePath
if ($LASTEXITCODE -ne 0) { throw "Signature/timestamp verification failed (exit $LASTEXITCODE)." }
