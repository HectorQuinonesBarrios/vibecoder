$ErrorActionPreference = 'Stop'

$repoUrl = 'https://github.com/odysseus-dev/odysseus.git'
$installDir = if ($env:ODYSSEUS_HOME) { $env:ODYSSEUS_HOME } else { Join-Path $HOME 'odysseus' }

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'Git is required. Install Git for Windows, then run this script again.'
}

if (-not (Test-Path (Join-Path $installDir '.git'))) {
    if (Test-Path $installDir) {
        throw "Install path already exists and is not an Odysseus Git checkout: $installDir"
    }
    Write-Host "Cloning the stable main branch into $installDir"
    git clone --branch main --single-branch $repoUrl $installDir
    if ($LASTEXITCODE -ne 0) { throw 'Git clone failed.' }
} else {
    Write-Host "Using existing checkout at $installDir (not changing its branch or local files)."
    $remoteUrl = git -C $installDir remote get-url origin
    if ($LASTEXITCODE -ne 0) { throw 'Could not read the existing checkout origin.' }
    if ($remoteUrl -notin @($repoUrl, 'https://github.com/odysseus-dev/odysseus')) {
        throw "The existing checkout origin is not the official Odysseus repository: $remoteUrl"
    }
}

$ollama = Get-Command ollama -ErrorAction SilentlyContinue
if ($ollama) {
    Write-Host ''
    Write-Host 'Choose a coding model to download (requires free disk space):'
    Write-Host '  1) qwen2.5-coder:3b  (small, suitable for limited memory)'
    Write-Host '  2) qwen2.5-coder:7b  (better coding, 16 GB system memory recommended)'
    Write-Host '  3) qwen2.5-coder:14b (stronger, 32 GB system memory recommended)'
    $choice = Read-Host 'Model [1/2/3, default 1]'
    if ([string]::IsNullOrWhiteSpace($choice)) { $choice = '1' }
    $model = switch ($choice) {
        '1' { 'qwen2.5-coder:3b' }
        '2' { 'qwen2.5-coder:7b' }
        '3' { 'qwen2.5-coder:14b' }
        default { throw 'Invalid model choice.' }
    }
    ollama pull $model
    if ($LASTEXITCODE -ne 0) { throw 'Ollama could not download the model. Check that Ollama is running.' }
} else {
    Write-Host ''
    Write-Host 'Ollama is not installed or not on PATH. Install it from https://ollama.com/download, then run:'
    Write-Host '  ollama pull qwen2.5-coder:3b'
}

Write-Host ''
Write-Host 'Starting Odysseus. Keep this PowerShell window open while it runs.'
Push-Location $installDir
try {
    powershell.exe -ExecutionPolicy Bypass -File .\launch-windows.ps1
    if ($LASTEXITCODE -ne 0) { throw 'Odysseus launcher failed.' }
} finally {
    Pop-Location
}