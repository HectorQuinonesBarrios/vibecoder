#Requires -Version 5.1
param(
    [string]$Model = 'qwen2.5-coder:3b',
    [switch]$ScheduleWeekly,
    [switch]$RemoveSchedule
)

$ErrorActionPreference = 'Stop'
$taskName = 'OdysseusCodingModelRefresh'

if ($Model -notmatch '^[A-Za-z0-9._:/-]+$') {
    throw 'Model must be a simple Ollama model tag.'
}

if ($RemoveSchedule) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host 'Weekly coding-model refresh schedule removed.'
    exit 0
}

$ollama = Get-Command ollama -ErrorAction SilentlyContinue
if (-not $ollama) {
    throw 'Ollama is not installed. Install it from https://ollama.com/download, then rerun this updater.'
}

try {
    Invoke-WebRequest -Uri 'http://127.0.0.1:11434/api/tags' -TimeoutSec 3 -UseBasicParsing | Out-Null
} catch {
    throw 'Ollama is not running. Start Ollama, then rerun this updater.'
}

if ($ScheduleWeekly) {
    $scriptPath = $PSCommandPath
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -Model `"$Model`""
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arguments
    $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At '3:00 AM'
    $principal = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 2)
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description 'Refresh the selected Odysseus Ollama coding model weekly while this user is signed in.' -Force | Out-Null
    Write-Host "Weekly refresh scheduled for '$Model' on Sunday at 3:00 AM while you are signed in."
}

Write-Host "Refreshing coding model '$Model' from its current Ollama tag..."
Write-Host 'This may download several gigabytes; it does not run automatically at app startup.'
& $ollama.Source pull $Model
if ($LASTEXITCODE -ne 0) {
    throw "Ollama failed to refresh '$Model'."
}

Write-Host "Model '$Model' is ready. Restart or reselect it in Odysseus if it was already loaded."