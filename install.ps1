# install.ps1
# Register scheduled task to run ScreenCapture.ps1 at user logon.
# Usage: Run as admin - powershell -ExecutionPolicy Bypass -File install.ps1

$taskName   = "ScreenCaptureTool"
$scriptPath = Join-Path $PSScriptRoot "ScreenCapture.ps1"

# Remove old task if exists
if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-Host "Removed old scheduled task."
}

$action  = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""

$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1)

Register-ScheduledTask `
    -TaskName    $taskName `
    -Action      $action `
    -Trigger     $trigger `
    -Settings    $settings `
    -Description "Screenshot tool Ctrl+Alt+S, saves to $PSScriptRoot\screenshots" `
    -RunLevel    Limited | Out-Null

Write-Host "Scheduled task '$taskName' registered."
Write-Host "Will auto-start at next logon. To start now:"
Write-Host "  schtasks /run /tn $taskName"
