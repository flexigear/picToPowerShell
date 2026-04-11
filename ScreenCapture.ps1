# ScreenCapture.ps1
# Ctrl+Alt+S to capture a screen region directly to file.
# Image never touches the clipboard - only the file path is copied.
# Usage: powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File ScreenCapture.ps1

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Windows.Forms;
using System.Runtime.InteropServices;
using System.IO;
using System.Collections.Generic;

public class OverlayForm : Form {
    [DllImport("user32.dll")]
    private static extern IntPtr GetDC(IntPtr hWnd);
    [DllImport("user32.dll")]
    private static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);
    [DllImport("gdi32.dll")]
    private static extern bool BitBlt(IntPtr hdcDest, int xDst, int yDst, int w, int h,
                                      IntPtr hdcSrc, int xSrc, int ySrc, int rop);
    [DllImport("gdi32.dll")]
    private static extern IntPtr CreateCompatibleDC(IntPtr hdc);
    [DllImport("gdi32.dll")]
    private static extern IntPtr CreateCompatibleBitmap(IntPtr hdc, int w, int h);
    [DllImport("gdi32.dll")]
    private static extern IntPtr SelectObject(IntPtr hdc, IntPtr obj);
    [DllImport("gdi32.dll")]
    private static extern bool DeleteObject(IntPtr obj);
    [DllImport("gdi32.dll")]
    private static extern bool DeleteDC(IntPtr hdc);
    private const int SRCCOPY = 0x00CC0020;

    private Bitmap screenCapture;
    private Point startPoint;
    private Rectangle currentRect;
    private bool isSelecting;
    private Rectangle virtualBounds;
    public Bitmap ResultBitmap { get; private set; }

    public OverlayForm() {
        // Capture the entire virtual screen using GDI (DPI-correct)
        virtualBounds = SystemInformation.VirtualScreen;
        screenCapture = CaptureVirtualScreen(virtualBounds);

        this.StartPosition   = FormStartPosition.Manual;
        this.Location         = virtualBounds.Location;
        this.Size             = virtualBounds.Size;
        this.FormBorderStyle  = FormBorderStyle.None;
        this.TopMost          = true;
        this.Cursor           = Cursors.Cross;
        this.DoubleBuffered   = true;
        this.ShowInTaskbar    = false;
    }

    private static Bitmap CaptureVirtualScreen(Rectangle bounds) {
        IntPtr desktopDC = GetDC(IntPtr.Zero);
        IntPtr memDC     = CreateCompatibleDC(desktopDC);
        IntPtr hBitmap   = CreateCompatibleBitmap(desktopDC, bounds.Width, bounds.Height);
        IntPtr oldBmp    = SelectObject(memDC, hBitmap);

        BitBlt(memDC, 0, 0, bounds.Width, bounds.Height,
               desktopDC, bounds.X, bounds.Y, SRCCOPY);

        SelectObject(memDC, oldBmp);
        Bitmap bmp = Image.FromHbitmap(hBitmap);
        DeleteObject(hBitmap);
        DeleteDC(memDC);
        ReleaseDC(IntPtr.Zero, desktopDC);
        return bmp;
    }

    protected override void OnPaint(PaintEventArgs e) {
        e.Graphics.DrawImage(screenCapture, 0, 0,
                             screenCapture.Width, screenCapture.Height);
        using (var brush = new SolidBrush(Color.FromArgb(100, 0, 0, 0))) {
            e.Graphics.FillRectangle(brush, 0, 0,
                                     screenCapture.Width, screenCapture.Height);
        }
        if (currentRect.Width > 0 && currentRect.Height > 0) {
            e.Graphics.DrawImage(screenCapture, currentRect, currentRect, GraphicsUnit.Pixel);
            using (var pen = new Pen(Color.FromArgb(200, 0, 174, 255), 2)) {
                e.Graphics.DrawRectangle(pen, currentRect);
            }
        }
    }

    protected override void OnMouseDown(MouseEventArgs e) {
        if (e.Button == MouseButtons.Left) {
            isSelecting = true;
            startPoint  = e.Location;
            currentRect = Rectangle.Empty;
        }
    }

    protected override void OnMouseMove(MouseEventArgs e) {
        if (isSelecting) {
            int x = Math.Min(startPoint.X, e.X);
            int y = Math.Min(startPoint.Y, e.Y);
            int w = Math.Abs(e.X - startPoint.X);
            int h = Math.Abs(e.Y - startPoint.Y);
            currentRect = new Rectangle(x, y, w, h);
            Invalidate();
        }
    }

    protected override void OnMouseUp(MouseEventArgs e) {
        if (e.Button == MouseButtons.Right) {
            this.DialogResult = DialogResult.Cancel;
            this.Close();
            return;
        }
        if (isSelecting && e.Button == MouseButtons.Left) {
            isSelecting = false;
            if (currentRect.Width > 5 && currentRect.Height > 5) {
                ResultBitmap      = screenCapture.Clone(currentRect, screenCapture.PixelFormat);
                this.DialogResult = DialogResult.OK;
                this.Close();
            }
            // Selection too small: ignore, let user try again
        }
    }

    protected override void OnKeyDown(KeyEventArgs e) {
        if (e.KeyCode == Keys.Escape) {
            this.DialogResult = DialogResult.Cancel;
            this.Close();
        }
    }

    protected override void Dispose(bool disposing) {
        if (disposing && screenCapture != null) { screenCapture.Dispose(); screenCapture = null; }
        base.Dispose(disposing);
    }
}

public class HotkeyForm : Form {
    [DllImport("user32.dll")]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
    [DllImport("user32.dll")]
    private static extern bool UnregisterHotKey(IntPtr hWnd, int id);
    [DllImport("user32.dll")]
    private static extern bool SetProcessDpiAwarenessContext(IntPtr value);

    private const int  WM_HOTKEY    = 0x0312;
    private const uint MOD_CTRL_ALT = 0x0002 | 0x0001;
    private const uint VK_S         = 0x53;
    private const int  HOTKEY_ID    = 9000;

    private string     saveDir;
    private NotifyIcon trayIcon;

    public HotkeyForm(string saveDir) {
        // Per-Monitor DPI Awareness V2 (Windows 10 1703+)
        try { SetProcessDpiAwarenessContext(new IntPtr(-4)); } catch {}

        this.saveDir         = saveDir;
        this.ShowInTaskbar   = false;
        this.WindowState     = FormWindowState.Minimized;
        this.FormBorderStyle = FormBorderStyle.None;
        this.Size            = new Size(1, 1);

        trayIcon = new NotifyIcon();
        trayIcon.Icon    = SystemIcons.Application;
        trayIcon.Text    = "Screenshot Tool (Ctrl+Alt+S)";
        trayIcon.Visible = true;

        var menu = new ContextMenuStrip();
        menu.Items.Add("Capture (Ctrl+Alt+S)", null, (s, e) => TakeScreenshot());
        menu.Items.Add("Exit",                 null, (s, e) => Application.Exit());
        trayIcon.ContextMenuStrip = menu;
    }

    protected override void OnLoad(EventArgs e) {
        base.OnLoad(e);
        if (!RegisterHotKey(this.Handle, HOTKEY_ID, MOD_CTRL_ALT, VK_S)) {
            trayIcon.ShowBalloonTip(3000, "Error",
                "Failed to register Ctrl+Alt+S. It may be occupied by another program.",
                ToolTipIcon.Error);
        }
        this.Hide();
    }

    protected override void WndProc(ref Message m) {
        if (m.Msg == WM_HOTKEY && m.WParam.ToInt32() == HOTKEY_ID) {
            TakeScreenshot();
        }
        base.WndProc(ref m);
    }

    private void TakeScreenshot() {
        using (var overlay = new OverlayForm()) {
            if (overlay.ShowDialog() == DialogResult.OK && overlay.ResultBitmap != null) {
                if (!Directory.Exists(saveDir)) Directory.CreateDirectory(saveDir);

                int    index    = GetNextIndex();
                string fileName = index.ToString("D6") + ".png";
                string filePath = Path.Combine(saveDir, fileName);

                overlay.ResultBitmap.Save(filePath, ImageFormat.Png);
                Clipboard.SetText(filePath);

                trayIcon.ShowBalloonTip(2000, "Saved", filePath, ToolTipIcon.Info);
            }
        }
    }

    private int GetNextIndex() {
        int max = 0;
        if (Directory.Exists(saveDir)) {
            foreach (var file in Directory.GetFiles(saveDir, "*.png")) {
                string name = Path.GetFileNameWithoutExtension(file);
                int num;
                if (int.TryParse(name, out num) && num > max) max = num;
            }
        }
        return max + 1;
    }

    protected override void OnFormClosed(FormClosedEventArgs e) {
        UnregisterHotKey(this.Handle, HOTKEY_ID);
        if (trayIcon != null) { trayIcon.Visible = false; trayIcon.Dispose(); }
        base.OnFormClosed(e);
    }
}
"@

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$saveDir   = Join-Path $scriptDir "screenshots"

Write-Host "[ScreenCapture] Started. Press Ctrl+Alt+S to capture."
Write-Host "[ScreenCapture] Save dir: $saveDir"
Write-Host "[ScreenCapture] Right-click tray icon to exit."

[System.Windows.Forms.Application]::Run((New-Object HotkeyForm($saveDir)))
