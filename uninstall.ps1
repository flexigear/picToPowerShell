# uninstall.ps1
# Remove scheduled task and stop running ScreenCapture processes.
# Usage: powershell -ExecutionPolicy Bypass -File uninstall.ps1

$taskName = "ScreenCaptureTool"

# Stop running ScreenCapture processes
Get-Process powershell, pwsh -ErrorAction SilentlyContinue |
    Where-Object {
        try {
            $cmdLine = (Get-CimInstance Win32_Process -Filter "ProcessId=$($_.Id)").CommandLine
            $cmdLine -and $cmdLine -like "*ScreenCapture.ps1*"
        } catch { $false }
    } |
    ForEach-Object {
        Write-Host "Stopping PID $($_.Id) ..."
        Stop-Process -Id $_.Id -Force
    }

# Remove scheduled task
if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-Host "Scheduled task '$taskName' removed."
} else {
    Write-Host "Scheduled task '$taskName' not found."
}

Write-Host "Uninstall complete."
