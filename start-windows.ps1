$ErrorActionPreference = 'Stop'

$installDir = if ($env:ODYSSEUS_HOME) { $env:ODYSSEUS_HOME } else { Join-Path $HOME 'odysseus' }
$ollamaUrl = 'http://127.0.0.1:11434/api/tags'
$odysseusUrl = 'http://127.0.0.1:7000'
$logDir = Join-Path $env:LOCALAPPDATA 'Odysseus\logs'
$ollamaLog = Join-Path $logDir 'ollama.stdout.log'
$ollamaErrorLog = Join-Path $logDir 'ollama.stderr.log'
$odysseusLog = Join-Path $logDir 'odysseus.stdout.log'
$odysseusErrorLog = Join-Path $logDir 'odysseus.stderr.log'

if (-not (Test-Path (Join-Path $installDir 'launch-windows.ps1'))) {
    throw "Odysseus was not found at $installDir. Run setup-windows.ps1 first."
}

$ollama = Get-Command ollama -ErrorAction SilentlyContinue
if (-not $ollama) {
    throw 'Ollama was not found. Install it from https://ollama.com/download, then run this script again.'
}

New-Item -ItemType Directory -Force -Path $logDir | Out-Null

try {
    Invoke-WebRequest -Uri $ollamaUrl -TimeoutSec 2 -UseBasicParsing | Out-Null
    Write-Host 'Ollama is already online.'
} catch {
    Write-Host 'Starting Ollama...'
    Start-Process -FilePath $ollama.Source -ArgumentList 'serve' -WindowStyle Hidden -RedirectStandardOutput $ollamaLog -RedirectStandardError $ollamaErrorLog | Out-Null
    $ollamaReady = $false
    for ($attempt = 0; $attempt -lt 45; $attempt++) {
        Start-Sleep -Seconds 1
        try {
            Invoke-WebRequest -Uri $ollamaUrl -TimeoutSec 2 -UseBasicParsing | Out-Null
            $ollamaReady = $true
            break
        } catch { }
    }
    if (-not $ollamaReady) {
        throw "Ollama did not start. Check $ollamaLog and $ollamaErrorLog"
    }
}

$modelOutput = ollama list
if ($LASTEXITCODE -ne 0) { throw 'Could not list Ollama models.' }
$modelRows = @($modelOutput | Select-Object -Skip 1 | Where-Object { $_.Trim() })
if ($modelRows.Count -eq 0) {
    $answer = Read-Host 'No Ollama models are installed. Download qwen2.5-coder:3b (~2 GB)? [Y/n]'
    if ($answer -notmatch '^[Nn]$') {
        ollama pull qwen2.5-coder:3b
        if ($LASTEXITCODE -ne 0) { throw 'Model download failed.' }
    } else {
        Write-Warning 'No model is installed; Odysseus can start, but chat will not work until you add a model.'
    }
}

$odysseusReady = $false
try {
    Invoke-WebRequest -Uri $odysseusUrl -TimeoutSec 2 -UseBasicParsing | Out-Null
    $odysseusReady = $true
    Write-Host 'Odysseus is already online.'
} catch { }

if (-not $odysseusReady) {
    Write-Host 'Starting Odysseus...'
    Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', '.\launch-windows.ps1') -WorkingDirectory $installDir -WindowStyle Hidden -RedirectStandardOutput $odysseusLog -RedirectStandardError $odysseusErrorLog | Out-Null
    for ($attempt = 0; $attempt -lt 90; $attempt++) {
        Start-Sleep -Seconds 1
        try {
            Invoke-WebRequest -Uri $odysseusUrl -TimeoutSec 2 -UseBasicParsing | Out-Null
            $odysseusReady = $true
            break
        } catch { }
    }
    if (-not $odysseusReady) {
        throw "Odysseus did not start. Check $odysseusLog and $odysseusErrorLog"
    }
}

Write-Host "Ollama and Odysseus are ready. Opening $odysseusUrl"
Write-Host 'If Odysseus still reports no model, add/select the Ollama provider at http://localhost:11434/v1 in Settings.'
Start-Process $odysseusUrl