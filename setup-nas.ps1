# setup-nas.ps1
# Connects this machine to the NAS and points the screenshot tool at the shared
# pics folder. Safe to re-run: every step checks before it changes anything.
#
# The point of this script is that BOTH machines end up using the identical path
#     \\flexigearnas\home\appProjects\picToPowerShellServer\pics
# so a screenshot path copied on one machine can be opened by Claude on the other.
# That only works with the host NAME. The Tailscale IP (100.104.226.105) is not
# reachable from a machine that is not on the tailnet, so never bake it into paths.
#
# How each machine reaches that name:
#   - this machine  : Tailscale MagicDNS resolves flexigearnas -> 100.104.226.105
#   - the LAN machine: normal LAN DNS/NetBIOS, or a hosts entry added by -NasIp
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File setup-nas.ps1
#   powershell -ExecutionPolicy Bypass -File setup-nas.ps1 -NasIp 192.168.1.50   # if the name does not resolve
#
# Creating the workspace symlink needs an elevated shell (or Developer Mode).
# Everything else works unelevated.

[CmdletBinding()]
param(
    [string] $NasHost          = 'flexigearnas',
    [string] $NasIp            = '',                 # LAN IP, only if the name does not resolve
    [string] $Share            = 'home',
    [string] $User             = 'Flexigear',
    [string] $LinkPath         = 'D:\NasWorkSpace',
    [string] $WorkspaceSubPath = 'myWorkSpace',
    [string] $PicsSubPath      = 'appProjects\picToPowerShellServer\pics',
    [switch] $SkipLink,
    [switch] $SkipScreenshotConfig,
    [switch] $RestartTool,
    [switch] $NoPrompt          # never ask for a password, just report what is missing
)

$ErrorActionPreference = 'Stop'
$shareRoot = "\\$NasHost\$Share"
$picsPath  = Join-Path $shareRoot $PicsSubPath
$linkTarget = Join-Path $shareRoot $WorkspaceSubPath
$problems  = @()

function Say([string] $m)  { Write-Host $m }
function Ok ([string] $m)  { Write-Host "  [ok]   $m" }
function Warn([string] $m) { Write-Host "  [warn] $m" -ForegroundColor Yellow; $script:problems += $m }
function Step([string] $m) { Write-Host ""; Write-Host "== $m" -ForegroundColor Cyan }

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltinRole]::Administrator)
}

Say "NAS host   : $NasHost"
Say "Share root : $shareRoot"
Say "Pics folder: $picsPath"
Say "Elevated   : $(Test-Admin)"

# ---------------------------------------------------------------- name resolution
Step "1. Resolving $NasHost"
$resolved = $null
try { $resolved = ([Net.Dns]::GetHostAddresses($NasHost) | ForEach-Object { $_.IPAddressToString }) -join ', ' } catch { }

if ($resolved) {
    Ok "resolves to $resolved"
} elseif ($NasIp) {
    if (-not (Test-Admin)) {
        Warn "cannot add a hosts entry without an elevated shell - re-run as administrator, or fix DNS"
    } else {
        $hosts = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
        $line  = "$NasIp`t$NasHost"
        $have  = Select-String -Path $hosts -Pattern "\s$([regex]::Escape($NasHost))\s*$" -ErrorAction SilentlyContinue
        if ($have) {
            Ok "hosts already maps $NasHost"
        } else {
            Add-Content -Path $hosts -Value $line
            Ok "added to hosts: $line"
        }
        $resolved = $NasIp
    }
} else {
    Warn "$NasHost does not resolve. Re-run with -NasIp <LAN IP of the NAS> (as administrator) so the name works here too."
}

# ---------------------------------------------------------------- credentials
Step "2. Checking access to $shareRoot"
$canReach = $false
try { $canReach = Test-Path $shareRoot } catch { $canReach = $false }

if ($canReach) {
    Ok "share is reachable, credentials already stored"
} else {
    Say "  Windows stores SMB credentials per server NAME, so a credential saved for the IP"
    Say "  does not apply to '$NasHost'. Enter the NAS password to store one for the name."
    # Get-Credential does not reliably throw in a -NonInteractive shell; it can pop a
    # dialog and hand back a blank password, which would store a credential that
    # silently fails every later connection. So only accept a real password.
    $cred = $null
    if (-not $NoPrompt) {
        try {
            $cred = Get-Credential -UserName $User -Message "NAS account for \\$NasHost"
        } catch {
            $cred = $null
        }
    }
    if (-not $cred -or -not $cred.Password -or $cred.Password.Length -eq 0) {
        $cred = $null
        Warn "no password entered. Run this once, then re-run the script:"
        Say  "         cmdkey /add:$NasHost /user:$User /pass"
    }
    if ($cred) {
        # The Windows credential dialog hands back a lower-cased user name. The NAS
        # runs Linux, where user names are case sensitive, so "flexigear" is rejected
        # where "Flexigear" works. Keep the spelling that was asked for when the only
        # difference is case.
        $userName = $cred.UserName
        if ($userName -ne $User -and $userName -ieq $User) {
            Say "  using '$User' rather than '$userName' - the NAS is case sensitive"
            $userName = $User
        }
        $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($cred.Password))
        try {
            cmd /c "cmdkey /add:$NasHost /user:$userName /pass:$plain" | Out-Null
        } finally {
            $plain = $null
            [GC]::Collect()
        }
        Start-Sleep -Milliseconds 500
        try { $canReach = Test-Path $shareRoot } catch { $canReach = $false }
        if ($canReach) {
            Ok "credential stored, share is reachable"
        } else {
            # A stored-but-wrong credential makes every later attempt fail with the
            # same "user name or password is incorrect", so take it back out.
            cmd /c "cmdkey /delete:$NasHost" | Out-Null
            Warn "that credential did not work, so it was removed again - check the user name, the password, and that the share is called '$Share'"
        }
    }
}

# ---------------------------------------------------------------- workspace symlink
Step "3. Workspace link $LinkPath"
if ($SkipLink) {
    Ok "skipped (-SkipLink)"
} elseif (Test-Path $LinkPath) {
    $item = Get-Item $LinkPath -Force
    $tgt  = ($item.Target -join ' ')
    if ($item.LinkType) { Ok "already a $($item.LinkType) -> $tgt" }
    else { Warn "$LinkPath exists but is a real folder, not a link - leaving it alone" }
} elseif (-not $canReach) {
    Warn "skipping link creation until the share is reachable"
} else {
    $parent = Split-Path $LinkPath -Parent
    if (-not (Test-Path $parent)) {
        Warn "$parent does not exist on this machine - pass -LinkPath <somewhere that does>"
    } elseif (-not (Test-Admin)) {
        Warn "creating a symlink needs an elevated shell (or Developer Mode). Re-run as administrator, or:"
        Say  "         New-Item -ItemType SymbolicLink -Path '$LinkPath' -Target '$linkTarget'"
    } else {
        New-Item -ItemType SymbolicLink -Path $LinkPath -Target $linkTarget | Out-Null
        Ok "created symlink -> $linkTarget"
    }
}

# ---------------------------------------------------------------- screenshot tool
Step "4. Screenshot save folder"
if ($SkipScreenshotConfig) {
    Ok "skipped (-SkipScreenshotConfig)"
} else {
    $toolDir      = $PSScriptRoot
    $settingsFile = Join-Path $toolDir 'settings.txt'
    if (-not (Test-Path (Join-Path $toolDir 'ScreenCapture.ps1'))) {
        Warn "ScreenCapture.ps1 is not next to this script - skipping"
    } elseif (-not $canReach) {
        # Pointing the tool at an unreachable folder would break saving, so leave
        # settings.txt as it is until the share actually works.
        Warn "share not reachable yet - leaving settings.txt untouched so saving keeps working"
    } else {
        if (-not (Test-Path $picsPath)) {
            New-Item -ItemType Directory -Path $picsPath -Force | Out-Null
            Ok "created $picsPath"
        }
        Set-Content -Path $settingsFile -Encoding ASCII -Value @(
            '# ScreenCapture settings. Delete this file to restore defaults.',
            "SaveDir=$picsPath"
        )
        Ok "settings.txt -> SaveDir=$picsPath"

        if ($canReach) {
            $probe = Join-Path $picsPath ('_writetest_' + [guid]::NewGuid().ToString('N') + '.tmp')
            try {
                Set-Content -Path $probe -Value 'x'
                Remove-Item $probe -Force
                Ok "write test passed"
            } catch {
                Warn "cannot write to $picsPath : $($_.Exception.Message)"
            }
        }

        $running = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
            Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match 'ScreenCapture\.ps1' -and $_.CommandLine -notmatch 'CimInstance|Where-Object' })
        if ($running.Count -gt 0) {
            if ($RestartTool) {
                $running | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
                Start-Sleep -Seconds 2
                Start-Process wscript -ArgumentList ('"' + (Join-Path $toolDir 'launch.vbs') + '"')
                Ok "restarted the screenshot tool so it picks up the new folder"
            } else {
                Warn "the tool is running with the old folder - restart it (or re-run with -RestartTool)"
            }
        }
    }
}

# ---------------------------------------------------------------- summary
Write-Host ""
if ($problems.Count -eq 0) {
    Write-Host "All set. Screenshots save to $picsPath and that path opens on every machine set up this way." -ForegroundColor Green
} else {
    Write-Host "Finished with $($problems.Count) thing(s) to look at:" -ForegroundColor Yellow
    $problems | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
}
