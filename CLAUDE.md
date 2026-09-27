# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Purpose

Custom screenshot tool for Claude Code. Press Ctrl+Alt+S to capture a screen region, mark it up in a
Windows 11 Snipping Tool style editor, then save manually. Saving writes the next sequentially numbered
PNG into the save folder and copies **the file path** to the clipboard — so the path can be pasted
directly into Claude Code for image analysis. Closing the editor without saving writes nothing at all
and leaves the clipboard untouched. The image itself only reaches the clipboard if the user presses the
editor's Copy button.

The save folder is configurable (tray menu "Save folder...", or the link in the editor's status bar)
and defaults to `screenshots\` next to the script.

## Architecture

**ScreenCapture.ps1** — Single file, embeds C# via `Add-Type`. Types:

- `Naming` — static, single source of truth for the file-naming rule. `TryIndex` defines what counts as
  a tool-generated file: a basename of **exactly six digits**. `GeneratedFiles(dir)` lists them for the
  clear command.
  `NextPath(dir, machineId)` splits that name: **first digit = machine, last five = that machine's own
  counter**, so machine 1 writes `100001, 100002, …` and machine 2 writes `200001, …`. It only looks at
  files in its own range. Counting across machines would be wrong twice over: this machine would jump to
  the other's count, and two machines saving in the same second would choose the same name and one would
  silently overwrite the other. Numbering is also **per folder**, so switching folders restarts from that
  folder's own highest number for this machine. Files written before machine ids existed start with `0`
  and are simply ignored by every machine.
- `AppSettings` — loads/stores `settings.txt` (plain `key=value`) next to the script. Holds `SaveDir`
  and owns the folder picker. A missing, locked, or malformed file silently falls back to the default —
  settings are never allowed to crash startup. `IsUsablePath` rejects relative and drive-relative paths
  (`\foo`), since those would resolve against the process working directory; accepted paths are
  normalized through `Path.GetFullPath`.
- `Icons` — draws every toolbar glyph with GDI at runtime, so the tool ships with no icon assets.
- `DrawItem` — one annotation: pen, highlighter, line, arrow, rectangle, ellipse, or text. Stored as
  **vectors in image-pixel coordinates**, so zooming and cropping never degrade the saved output.
  `Render()` paints it; `HitTest()` backs the eraser, which removes a whole stroke the way the real
  Snipping Tool eraser does.
- `UndoRec` — one undoable step (`ADD` / `REMOVE` / `CROP` / `CLEAR`). Crop records both bitmaps plus
  the rect, so undo restores the old bitmap and shifts every item back by the crop origin.
- `OverlayForm` — fullscreen region selector spanning all monitors (`SystemInformation.VirtualScreen`).
  Pre-captures the desktop via GDI `BitBlt` from the desktop DC (physical pixels, DPI-correct). Draws a
  darkened view with the selected region at original brightness. Returns a cropped `Bitmap` via
  `ResultBitmap`; Escape or right-click cancels.
  **Paint performance matters here**: this machine's virtual screen is 6400x1960 (12.5 MP). Repainting
  the whole form and alpha-blending the dim layer on every mouse move cost ~70 ms/frame (~14 fps). So:
  the darkened copy is prepared once in the constructor, both bitmaps are `Format32bppPArgb` (the only
  format GDI+ blits without per-draw conversion), `OnPaint` copies only `e.ClipRectangle` with
  `SourceCopy`, and `OnMouseMove` invalidates just old-rect ∪ new-rect (padded for the border). Result
  ~0.4 ms/frame. Never go back to `Invalidate()` of the whole form, and never union with an empty
  rectangle (that stretches the dirty box to the screen origin).
- `EditorForm` — the markup window. A `TableLayoutPanel` holds a tool `ToolStrip`, a style `ToolStrip`,
  the `CanvasPanel`, and a `StatusStrip`. Owns the bitmap (and every crop result) and disposes them all
  on close. `Flatten()` composites base image + items into the bitmap that gets saved or copied.
  `SavedPath` stays null unless the user actually saved.
- `HotkeyForm` — hidden form that registers the global hotkey (Ctrl+Alt+S) via Win32 `RegisterHotKey`
  and owns the tray `NotifyIcon`. On hotkey: overlay -> editor -> if `SavedPath` is set, `Clipboard.SetText(path)`
  on the STA UI thread plus a balloon tip. A `busy` flag blocks re-entrant captures.
  **Registration retries.** It used to try once and give up, which left a live process whose hotkey
  never worked — the "it won't start" symptom, since nothing visible is wrong with the process.
  Registration genuinely loses races (a previous copy still shutting down at logon, another app holding
  the combo briefly). So `TryRegisterHotkey` runs on a 2 s timer for ~30 s, the tray tooltip reports
  which state it is in, and `OnFormClosed` only unregisters when it actually owns the key.

DPI handling: `SetProcessDpiAwarenessContext(-4)` (Per-Monitor Aware V2) is called at startup for
correct multi-monitor scaling.

Startup (the PowerShell tail, after the C# here-string):

1. **Single instance** via a `Local\ScreenCaptureTool.SingleInstance` mutex, checked *before* compiling.
   Only one process can own the hotkey; a second copy used to pop a balloon blaming "another program",
   which was really the first copy. It now shows a brief "already running" balloon and exits.
2. **Compile cache** under `%LOCALAPPDATA%\ScreenCaptureTool\cache`, keyed by a hash of the C# source
   plus the PowerShell/.NET versions, with stale assemblies pruned and an in-memory fallback if the
   folder is unwritable. Measured: compiling is ~133 ms, loading the cached DLL ~8 ms, so full startup
   goes 0.66 s -> 0.45 s. Worth knowing the honest size of this: it is not what makes a restart feel
   slow, and it is not the reason a hotkey appears dead (see `HotkeyForm` retries).

The C# lives in a **single-quoted** here-string (`@'...'@`) so PowerShell cannot expand anything in it.

**install.ps1** / **uninstall.ps1** — Register/remove Windows Scheduled Task `ScreenCaptureTool` for
auto-start at logon. **launch.vbs** starts PowerShell hidden so no console window flashes.

**screenshots/** — Default output directory for numbered PNGs (000001.png, 000002.png, ...). Git-ignored.

**settings.txt** — Generated at runtime, holds the chosen save folder. Git-ignored; delete it to reset.

**setup-nas.ps1** / **NAS-SETUP.md** — Connect a machine to the NAS and point the screenshot tool at
the shared folder `\\flexigearnas\home\myWorkSpace\appProjects\picToPowerShellServer\pics`. Read
NAS-SETUP.md before touching anything NAS-related. Its traps, all three found the hard way: paths must
use the host **name** (the `100.104.226.105` Tailscale IP is unreachable from the LAN machine);
Windows stores SMB credentials **per server name as typed**, so a credential saved for the IP does
nothing for the name; and the NAS user name is **case sensitive** while the Windows credential dialog
lower-cases it. `D:\NasWorkSpace` is a directory symlink to a UNC path, not a mapped drive.

The pics folder must stay under **`myWorkSpace\appProjects`**: that is the directory the Debian VM has
NFS-mounted at `/mnt/projects`, so a folder anywhere else on the share is invisible from there. Claude
on Debian translates pasted Windows paths using a rule kept in `~/.claude/CLAUDE.md` on that machine.

## Commands

```powershell
# Run manually (foreground)
powershell -ExecutionPolicy Bypass -File ScreenCapture.ps1

# Install as startup task (requires admin)
powershell -ExecutionPolicy Bypass -File install.ps1

# Uninstall
powershell -ExecutionPolicy Bypass -File uninstall.ps1

# Manually trigger scheduled task
schtasks /run /tn ScreenCaptureTool
```

## Key Details

- Global hotkey: **Ctrl+Alt+S**. If registration fails (key occupied), a balloon tip error is shown.
- Editor shortcuts: Ctrl+S save (and copy path), Ctrl+C copy image, Ctrl+Z undo, Ctrl+Y redo, Esc close.
  Shift constrains shapes to square/circle and lines to 45-degree steps. Middle-drag pans, Ctrl+wheel zooms.
  Enter commits a text box, Shift+Enter adds a newline.
- Nothing is written to disk before Save. Closing with unsaved markup prompts Yes/No/Cancel.
- Save folder: tray menu "Save folder..." / "Open save folder", or the "Save to:" link in the editor
  status bar. Changing it from the editor affects that editor's next Save too, not just later captures.
  A folder that does not exist yet is created on first save.
- `MachineId` in `settings.txt` (1-9, default 1) is the first digit of every file this machine writes.
  Machines sharing a save folder must each get their own: 1 is the Tailscale desktop, 2 the LAN machine.
  `setup-nas.ps1 -MachineId 2` sets it. The editor's status bar shows which machine it is running as.
- Tray "Clear save folder..." empties the folder and resets numbering to `<id>00001`. It removes every
  machine's screenshots, not just this one's, since the folder is shared. It is deliberately conservative,
  because the save folder may be one the user keeps other images in: only `NNNNNN.png` files are removed
  (`holiday.png`, `12.png`, `000001 (1).png`, subfolders and non-PNGs all survive), files go to the
  **Recycle Bin** rather than being deleted outright, and the confirmation dialog defaults to No.
- The embedded C# references `Microsoft.VisualBasic` for `FileSystem.DeleteFile` — the only .NET API
  that moves a file to the Recycle Bin without writing SHFileOperation interop by hand.
- Supports multi-monitor setups via `SystemInformation.VirtualScreen` + GDI `BitBlt`.
- Minimum selection size is 5x5 pixels to avoid accidental clicks.
- All C# string literals are ASCII-only to avoid encoding issues on non-UTF-8 system locales
  (this machine reports errors in Japanese, so the rule is load-bearing).
- `PixelOffsetMode` has no `HalfPixel` member — it is `PixelOffsetMode.Half`.
- Requires Windows PowerShell 5.1 (ships with Windows 10/11). The embedded C# must stay C# 5 compatible:
  no string interpolation, no `?.`, no expression-bodied members. The C# also must not contain `$` or
  backticks, since it lives in an expandable PowerShell here-string.
- Scheduled task name: `ScreenCaptureTool`.
