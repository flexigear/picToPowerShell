# NAS setup

How this machine reaches the NAS, and how to reproduce it anywhere else.

## What to tell Claude on a new machine

> Set up the NAS mapping for this project — read NAS-SETUP.md and run setup-nas.ps1.

If the machine is on the same LAN as the NAS and the name `flexigearnas` does not
resolve there, add the NAS LAN IP:

> Set up the NAS mapping, the NAS LAN IP is 192.168.x.x

That is the whole job. The script is idempotent, so re-running it is harmless.

## The facts

| | |
|---|---|
| NAS Tailscale name | `flexigearnas` |
| NAS Tailscale IP | `100.104.226.105` |
| SMB share | `home` |
| SMB user | `Flexigear` |
| Workspace link | `D:\NasWorkSpace` → `\\…\home\myWorkSpace` (directory symlink, `SYMLINKD`) |
| Screenshot folder | `\\flexigearnas\home\appProjects\picToPowerShellServer\pics` |

There is **no mapped drive letter and no `net use` entry**. `D:\NasWorkSpace` is a
directory symbolic link whose target is a UNC path; Windows resolves it on access.

## Always use the host name, never the IP

`100.104.226.105` is a Tailscale address. It only works from a machine on the
tailnet, so a path containing it is useless on the LAN machine. Both machines must
use `\\flexigearnas\…`, which is what makes one copied screenshot path openable
everywhere:

- **this machine** — Tailscale MagicDNS resolves `flexigearnas` → `100.104.226.105`
- **LAN machine** — normal LAN DNS/NetBIOS resolves it to the NAS LAN IP; if that
  fails, `setup-nas.ps1 -NasIp <lan ip>` adds a `hosts` entry so the same name works

## The credential gotcha

Windows stores SMB credentials **per server name as typed**. This machine had a
credential saved for the target `100.104.226.105`, which is why `\\100.104.226.105\home`
worked while `\\flexigearnas\home` failed with "The user name or password is
incorrect" — same server, different target string, no credential.

So every machine needs a credential stored against the **name**:

```powershell
cmdkey /add:flexigearnas /user:Flexigear /pass    # prompts, nothing echoed
```

`setup-nas.ps1` does this for you when it finds the share unreachable. Check what is
stored with `cmdkey /list | findstr flexigearnas`.

### The user name is case sensitive

The NAS runs Linux, so `Flexigear` and `flexigear` are different accounts — and the
Windows credential dialog hands back the name **lower-cased**, which is rejected.
That is worth knowing because the failure looks identical to a wrong password:
"The user name or password is incorrect."

`setup-nas.ps1` keeps the spelling from `-User` when the dialog's answer differs only
by case. If you store the credential by hand, type the name exactly:

```powershell
cmdkey /add:flexigearnas /user:Flexigear /pass
```

## What setup-nas.ps1 does

1. Resolves `flexigearnas`; with `-NasIp` it adds a `hosts` entry when DNS cannot.
2. Tests `\\flexigearnas\home`; if unreachable, prompts for the password and stores
   it with `cmdkey`.
3. Creates `D:\NasWorkSpace` as a symlink to `\\flexigearnas\home\myWorkSpace` when
   missing. An existing link is left alone. **Needs an elevated shell** (or Developer
   Mode); everything else works unelevated.
4. Writes `settings.txt` so the screenshot tool saves to the shared pics folder,
   creates that folder if needed, and runs a write test.

Useful switches: `-LinkPath` (if the machine has no `D:`), `-SkipLink`,
`-SkipScreenshotConfig`, `-RestartTool`.

## Shared screenshots

Both machines save into the same folder, so numbering (`000001.png`, `000002.png`, …)
is shared and continues across machines — `Naming.NextPath` scans the folder each
time. Two machines saving in the same instant could pick the same number and one
would overwrite the other; in practice captures are seconds apart, and the fix if it
ever matters is a per-machine prefix.

The tool reads `settings.txt` only at startup, so restart it after changing folders.

If the NAS is unreachable when you press Save, the editor shows the error and keeps
your markup — nothing is lost, and you can retry or point the folder back at a local
directory from the tray menu.
