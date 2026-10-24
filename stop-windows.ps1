$ErrorActionPreference = 'Stop'

$stateDir = Join-Path $env:LOCALAPPDATA 'Odysseus'

function Stop-ManagedProcess {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$ExpectedExecutable,
        [Parameter(Mandatory = $true)][string]$ExpectedCommand
    )

    $pidFile = Join-Path $stateDir "$Name.pid"
    if (-not (Test-Path $pidFile)) {
        Write-Host "$Name was not started by this launcher. Leaving it alone."
        return
    }

    $rawPid = (Get-Content -Path $pidFile -Raw).Trim()
    $processId = 0
    if (-not [int]::TryParse($rawPid, [ref]$processId) -or $processId -le 0) {
        Remove-Item -Path $pidFile -Force
        Write-Warning "Removed invalid $Name process record."
        return
    }

    $processInfo = Get-CimInstance Win32_Process -Filter "ProcessId = $processId" -ErrorAction SilentlyContinue
    if (-not $processInfo) {
        Remove-Item -Path $pidFile -Force
        Write-Host "Removed stale $Name process record."
        return
    }

    $executable = [System.IO.Path]::GetFileName([string]$processInfo.ExecutablePath)
    $commandLine = [string]$processInfo.CommandLine
    if ($executable -ine $ExpectedExecutable -or $commandLine -notlike $ExpectedCommand) {
        Remove-Item -Path $pidFile -Force
        Write-Warning "PID $processId no longer matches the recorded $Name process; it was not stopped."
        return
    }

    Write-Host "Stopping $Name (PID $processId)..."
    if ($Name -eq 'odysseus') {
        & taskkill.exe /PID $processId /T /F | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Could not stop the Odysseus process tree (PID $processId)."
        }
    } else {
        Stop-Process -Id $processId -Force
    }
    Remove-Item -Path $pidFile -Force -ErrorAction SilentlyContinue
}

if (-not (Test-Path $stateDir)) {
    Write-Host 'No managed Odysseus or Ollama processes are recorded. Nothing to stop.'
    exit 0
}

Stop-ManagedProcess -Name 'odysseus' -ExpectedExecutable 'powershell.exe' -ExpectedCommand '*launch-windows.ps1*'
$ollama = Get-Command ollama -ErrorAction SilentlyContinue
if ($ollama) {
    $ollamaExecutable = [System.IO.Path]::GetFileName($ollama.Source)
    Stop-ManagedProcess -Name 'ollama' -ExpectedExecutable $ollamaExecutable -ExpectedCommand '*serve*'
} else {
    Write-Host 'Ollama command is unavailable; any recorded Ollama process was left untouched.'
}
Write-Host 'Stop request complete. Any service not launched by this starter script was left running.'
