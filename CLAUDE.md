# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Purpose

Custom screenshot tool for Claude Code. Press Ctrl+Alt+S to capture a screen region, auto-save as a sequentially numbered PNG, and copy the file path to clipboard — so the path can be pasted directly into Claude Code for image analysis. The image never touches the clipboard; only the text path is placed there.

## Architecture

**ScreenCapture.ps1** — Single file, embeds C# via `Add-Type`. Two WinForms classes:

- `HotkeyForm`: Hidden form that registers global hotkey (Ctrl+Alt+S) via Win32 `RegisterHotKey`. Manages a system tray `NotifyIcon`. On hotkey, creates an `OverlayForm`, saves the result, and calls `Clipboard.SetText(filePath)` on the STA UI thread.
- `OverlayForm`: Fullscreen overlay spanning all monitors (`SystemInformation.VirtualScreen`). Pre-captures the desktop via GDI `BitBlt` from the desktop DC (physical pixels, DPI-correct). Draws a darkened view with the selected region shown at original brightness. Returns cropped `Bitmap` via `ResultBitmap`. Escape cancels.

DPI handling: `SetProcessDpiAwarenessContext(-4)` (Per-Monitor Aware V2) is called at startup for correct multi-monitor scaling.

**install.ps1** / **uninstall.ps1** — Register/remove Windows Scheduled Task `ScreenCaptureTool` for auto-start at logon.

**screenshots/** — Output directory for numbered PNGs (000001.png, 000002.png, ...). Git-ignored.

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
- Supports multi-monitor setups via `SystemInformation.VirtualScreen` + GDI `BitBlt`.
- Minimum selection size is 5x5 pixels to avoid accidental clicks.
- All C# string literals are ASCII-only to avoid encoding issues on non-UTF-8 system locales.
- Requires Windows PowerShell 5.1 (ships with Windows 10/11).
- Scheduled task name: `ScreenCaptureTool`.
