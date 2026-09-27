# ScreenCapture.ps1
# Ctrl+Alt+S to capture a screen region, then edit it in a Windows 11 Snipping Tool
# style editor (pen, highlighter, eraser, shapes, text, crop, undo/redo, zoom).
# Nothing is written to disk until you click Save. Saving writes the next numbered
# PNG into the save folder and copies that file path to the clipboard.
# Closing the editor without saving leaves no file behind.
# The save folder defaults to screenshots\ next to this script and can be changed
# from the tray menu or the editor status bar; it persists in settings.txt.
# Usage: powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File ScreenCapture.ps1

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Single-quoted here-string: the C# is taken literally, so a stray $ or backtick
# in it can never be expanded by PowerShell. Compiled (or loaded from cache) below.
$csharp = @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Windows.Forms;
using System.Runtime.InteropServices;
using System.IO;
using System.Diagnostics;
using System.Collections.Generic;

// ------------------------------------------------------------------
// File naming: screenshots\000001.png, 000002.png, ...
// ------------------------------------------------------------------
public static class Naming {
    // A file belongs to this tool only if its name is exactly six digits.
    // NextPath and the folder-clearing command share this rule, which is what
    // guarantees that clearing the folder really does restart at 000001.
    public static bool TryIndex(string path, out int index) {
        index = 0;
        string name = Path.GetFileNameWithoutExtension(path);
        if (name == null || name.Length != 6) return false;
        foreach (char c in name) if (c < '0' || c > '9') return false;
        return int.TryParse(name, out index);
    }

    public static List<string> GeneratedFiles(string dir) {
        List<string> list = new List<string>();
        if (!Directory.Exists(dir)) return list;
        foreach (string file in Directory.GetFiles(dir, "*.png")) {
            int n;
            if (TryIndex(file, out n)) list.Add(file);
        }
        return list;
    }

    public static string NextPath(string dir) {
        int max = 0;
        if (Directory.Exists(dir)) {
            foreach (string file in Directory.GetFiles(dir, "*.png")) {
                int num;
                if (TryIndex(file, out num) && num > max) max = num;
            }
        }
        return Path.Combine(dir, (max + 1).ToString("D6") + ".png");
    }
}

// ------------------------------------------------------------------
// Persisted settings. Plain key=value text in settings.txt next to the
// script, so it can be inspected or deleted by hand. A missing or broken
// file simply falls back to the default folder - never fatal.
// ------------------------------------------------------------------
public class AppSettings {
    private string filePath;
    private string defaultDir;
    public  string SaveDir;

    public AppSettings(string scriptDir) {
        filePath   = Path.Combine(scriptDir, "settings.txt");
        defaultDir = Path.Combine(scriptDir, "screenshots");
        SaveDir    = defaultDir;
        Load();
    }

    public string DefaultDir { get { return defaultDir; } }
    public string FilePath   { get { return filePath; } }

    private void Load() {
        try {
            if (!File.Exists(filePath)) return;
            foreach (string raw in File.ReadAllLines(filePath)) {
                string line = raw.Trim();
                if (line.Length == 0 || line.StartsWith("#")) continue;
                int eq = line.IndexOf('=');
                if (eq <= 0) continue;
                string key = line.Substring(0, eq).Trim();
                string val = line.Substring(eq + 1).Trim();
                if (string.Equals(key, "SaveDir", StringComparison.OrdinalIgnoreCase) && IsUsablePath(val))
                    SaveDir = Path.GetFullPath(val);
            }
        } catch {
            SaveDir = defaultDir;
        }
    }

    // Must be absolute and syntactically legal. A relative path would resolve
    // against whatever the process working directory happens to be, so reject it.
    // GetPathRoot is longer than one char only for "C:\..." and "\\server\share",
    // which rules out drive-relative forms like "\foo". The folder itself may not
    // exist yet; it gets created on the first save.
    public static bool IsUsablePath(string p) {
        if (string.IsNullOrEmpty(p)) return false;
        try {
            if (!Path.IsPathRooted(p)) return false;
            string root = Path.GetPathRoot(p);
            if (root == null || root.Length <= 1) return false;
            Path.GetFullPath(p);
            return true;
        } catch {
            return false;
        }
    }

    public bool Persist() {
        try {
            File.WriteAllText(filePath,
                "# ScreenCapture settings. Delete this file to restore defaults." + Environment.NewLine +
                "SaveDir=" + SaveDir + Environment.NewLine);
            return true;
        } catch {
            return false;
        }
    }

    // Returns true if the user picked a folder (and it was stored).
    public bool ChooseFolder(IWin32Window owner) {
        using (FolderBrowserDialog dlg = new FolderBrowserDialog()) {
            dlg.Description         = "Choose the folder screenshots are saved to";
            dlg.ShowNewFolderButton = true;
            if (Directory.Exists(SaveDir)) dlg.SelectedPath = SaveDir;
            if (dlg.ShowDialog(owner) != DialogResult.OK) return false;
            SaveDir = dlg.SelectedPath;
            if (!Persist()) {
                MessageBox.Show(owner,
                    "The folder is set for this session, but settings.txt could not be written:" +
                    Environment.NewLine + filePath,
                    "Screenshot Tool", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
            return true;
        }
    }

    public void OpenInExplorer(IWin32Window owner) {
        try {
            if (!Directory.Exists(SaveDir)) Directory.CreateDirectory(SaveDir);
            Process.Start("explorer.exe", "\"" + SaveDir + "\"");
        } catch (Exception ex) {
            MessageBox.Show(owner, "Cannot open the folder: " + ex.Message,
                            "Screenshot Tool", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }
}

// ------------------------------------------------------------------
// Toolbar glyphs, drawn with GDI so no icon files are needed.
// ------------------------------------------------------------------
public static class Icons {
    public static Bitmap Make(string kind) {
        Bitmap bmp = new Bitmap(20, 20);
        using (Graphics g = Graphics.FromImage(bmp)) {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            Color c = Color.FromArgb(45, 45, 48);
            using (Pen p = new Pen(c, 1.6f))
            using (SolidBrush b = new SolidBrush(c)) {
                p.StartCap = LineCap.Round;
                p.EndCap   = LineCap.Round;
                p.LineJoin = LineJoin.Round;

                if (kind == "pen") {
                    g.DrawLine(p, 5f, 15f, 13f, 6f);
                    g.DrawLine(p, 11.5f, 4f, 16f, 8f);
                    g.FillPolygon(b, new PointF[] {
                        new PointF(2.5f, 17.5f), new PointF(6.5f, 16.5f), new PointF(4.5f, 13f) });
                } else if (kind == "highlight") {
                    using (Pen hp = new Pen(Color.FromArgb(180, 250, 200, 40), 6f)) {
                        hp.StartCap = LineCap.Square;
                        hp.EndCap   = LineCap.Square;
                        g.DrawLine(hp, 5f, 12f, 14f, 4f);
                    }
                    g.DrawLine(p, 3f, 17.5f, 17f, 17.5f);
                } else if (kind == "eraser") {
                    g.DrawPolygon(p, new PointF[] {
                        new PointF(4f, 12f), new PointF(11f, 4f),
                        new PointF(16f, 9f), new PointF(9f, 16f) });
                    g.DrawLine(p, 3f, 17.5f, 17f, 17.5f);
                } else if (kind == "line") {
                    g.DrawLine(p, 4f, 16f, 16f, 4f);
                } else if (kind == "arrow") {
                    g.DrawLine(p, 4f, 16f, 13f, 7f);
                    g.FillPolygon(b, new PointF[] {
                        new PointF(17f, 3f), new PointF(9.5f, 5f), new PointF(15f, 10.5f) });
                } else if (kind == "rect") {
                    g.DrawRectangle(p, 3.5f, 5.5f, 13f, 9f);
                } else if (kind == "ellipse") {
                    g.DrawEllipse(p, 3f, 5f, 14f, 10f);
                } else if (kind == "text") {
                    using (Font f = new Font("Segoe UI", 13f, FontStyle.Bold, GraphicsUnit.Pixel))
                        g.DrawString("A", f, b, new PointF(3.5f, 2.5f));
                    g.DrawLine(p, 4f, 17f, 16f, 17f);
                } else if (kind == "crop") {
                    g.DrawLine(p, 6f, 2f, 6f, 14f);
                    g.DrawLine(p, 6f, 14f, 18f, 14f);
                    g.DrawLine(p, 2f, 6f, 14f, 6f);
                    g.DrawLine(p, 14f, 6f, 14f, 18f);
                } else if (kind == "undo") {
                    g.DrawArc(p, 4f, 6f, 12f, 10f, 180f, 180f);
                    g.FillPolygon(b, new PointF[] {
                        new PointF(4f, 15.5f), new PointF(0.8f, 9.5f), new PointF(7.2f, 9.5f) });
                } else if (kind == "redo") {
                    g.DrawArc(p, 4f, 6f, 12f, 10f, 180f, 180f);
                    g.FillPolygon(b, new PointF[] {
                        new PointF(16f, 15.5f), new PointF(12.8f, 9.5f), new PointF(19.2f, 9.5f) });
                } else if (kind == "save") {
                    g.DrawRectangle(p, 3.5f, 3.5f, 13f, 13f);
                    g.DrawRectangle(p, 7f, 3.5f, 6f, 4f);
                    g.FillRectangle(b, 6f, 10.5f, 8f, 6f);
                } else if (kind == "copy") {
                    g.DrawRectangle(p, 3.5f, 2.5f, 9f, 11f);
                    using (SolidBrush w = new SolidBrush(Color.FromArgb(245, 245, 245)))
                        g.FillRectangle(w, 7f, 6f, 10f, 12f);
                    g.DrawRectangle(p, 7.5f, 6.5f, 9f, 11f);
                } else if (kind == "zoomin" || kind == "zoomout") {
                    g.DrawEllipse(p, 3f, 3f, 11f, 11f);
                    g.DrawLine(p, 12.5f, 12.5f, 17f, 17f);
                    g.DrawLine(p, 6f, 8.5f, 11f, 8.5f);
                    if (kind == "zoomin") g.DrawLine(p, 8.5f, 6f, 8.5f, 11f);
                } else if (kind == "fit") {
                    g.DrawRectangle(p, 2.5f, 4.5f, 15f, 11f);
                    g.DrawLine(p, 5.5f, 7.5f, 9f, 10f);
                    g.DrawLine(p, 14.5f, 12.5f, 11f, 10f);
                } else if (kind == "clear") {
                    g.DrawLine(p, 3f, 6f, 17f, 6f);
                    g.DrawLine(p, 8f, 3.5f, 12f, 3.5f);
                    g.DrawRectangle(p, 5.5f, 6.5f, 9f, 11f);
                    g.DrawLine(p, 8.5f, 9.5f, 8.5f, 15f);
                    g.DrawLine(p, 11.5f, 9.5f, 11.5f, 15f);
                }
            }
        }
        return bmp;
    }

    public static Bitmap Swatch(Color c) {
        Bitmap bmp = new Bitmap(18, 18);
        using (Graphics g = Graphics.FromImage(bmp)) {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            using (SolidBrush b = new SolidBrush(c)) g.FillEllipse(b, 1.5f, 1.5f, 14f, 14f);
            using (Pen p = new Pen(Color.FromArgb(140, 0, 0, 0), 1f)) g.DrawEllipse(p, 1.5f, 1.5f, 14f, 14f);
        }
        return bmp;
    }
}

// ------------------------------------------------------------------
// One annotation. Coordinates are always in image pixels, so zooming
// and cropping never change what gets rendered into the saved PNG.
// ------------------------------------------------------------------
public class DrawItem {
    public const int PEN       = 0;
    public const int HIGHLIGHT = 1;
    public const int LINE      = 2;
    public const int ARROW     = 3;
    public const int RECT      = 4;
    public const int ELLIPSE   = 5;
    public const int TEXT      = 6;

    public int    Tool;
    public Color  Ink;
    public float  Width;
    public bool   Filled;
    public string Text;
    public float  FontSize;
    public SizeF  TextSize;
    public Point  P1;
    public Point  P2;
    public List<Point> Points = new List<Point>();

    public Color EffectiveColor() {
        if (Tool == HIGHLIGHT) return Color.FromArgb(110, Ink);
        return Ink;
    }

    public float EffectiveWidth() {
        if (Tool == HIGHLIGHT) return Width * 4f;
        return Width;
    }

    public Rectangle Norm() {
        return Rectangle.FromLTRB(Math.Min(P1.X, P2.X), Math.Min(P1.Y, P2.Y),
                                  Math.Max(P1.X, P2.X), Math.Max(P1.Y, P2.Y));
    }

    public void Offset(int dx, int dy) {
        P1 = new Point(P1.X + dx, P1.Y + dy);
        P2 = new Point(P2.X + dx, P2.Y + dy);
        for (int i = 0; i < Points.Count; i++)
            Points[i] = new Point(Points[i].X + dx, Points[i].Y + dy);
    }

    public void Render(Graphics g) {
        using (Pen pen = new Pen(EffectiveColor(), EffectiveWidth())) {
            pen.StartCap = LineCap.Round;
            pen.EndCap   = LineCap.Round;
            pen.LineJoin = LineJoin.Round;

            if (Tool == PEN || Tool == HIGHLIGHT) {
                if (Tool == HIGHLIGHT) {
                    pen.StartCap = LineCap.Square;
                    pen.EndCap   = LineCap.Square;
                }
                if (Points.Count == 1) {
                    float r = EffectiveWidth() / 2f;
                    using (SolidBrush b = new SolidBrush(EffectiveColor()))
                        g.FillEllipse(b, Points[0].X - r, Points[0].Y - r, r * 2f, r * 2f);
                } else if (Points.Count > 1) {
                    g.DrawLines(pen, Points.ToArray());
                }
            } else if (Tool == LINE) {
                g.DrawLine(pen, P1, P2);
            } else if (Tool == ARROW) {
                RenderArrow(g, pen);
            } else if (Tool == RECT) {
                Rectangle r = Norm();
                if (r.Width > 0 && r.Height > 0) {
                    if (Filled)
                        using (SolidBrush b = new SolidBrush(Color.FromArgb(70, Ink)))
                            g.FillRectangle(b, r);
                    g.DrawRectangle(pen, r);
                }
            } else if (Tool == ELLIPSE) {
                Rectangle r = Norm();
                if (r.Width > 0 && r.Height > 0) {
                    if (Filled)
                        using (SolidBrush b = new SolidBrush(Color.FromArgb(70, Ink)))
                            g.FillEllipse(b, r);
                    g.DrawEllipse(pen, r);
                }
            } else if (Tool == TEXT) {
                if (!string.IsNullOrEmpty(Text)) {
                    using (Font f = new Font("Segoe UI", FontSize, FontStyle.Regular, GraphicsUnit.Pixel))
                    using (SolidBrush b = new SolidBrush(Ink))
                        g.DrawString(Text, f, b, P1);
                }
            }
        }
    }

    private void RenderArrow(Graphics g, Pen pen) {
        float dx = P2.X - P1.X;
        float dy = P2.Y - P1.Y;
        double len = Math.Sqrt(dx * dx + dy * dy);
        if (len < 1) return;
        float head = Math.Max(9f, Width * 4f);
        if (head > len) head = (float)len;
        double ux = dx / len, uy = dy / len;
        PointF root = new PointF((float)(P2.X - ux * head), (float)(P2.Y - uy * head));
        float nx = (float)(-uy), ny = (float)ux;
        float hw = head * 0.45f;
        g.DrawLine(pen, P1.X, P1.Y, root.X, root.Y);
        using (SolidBrush b = new SolidBrush(EffectiveColor()))
            g.FillPolygon(b, new PointF[] {
                new PointF(P2.X, P2.Y),
                new PointF(root.X + nx * hw, root.Y + ny * hw),
                new PointF(root.X - nx * hw, root.Y - ny * hw) });
    }

    // Eraser removes a whole stroke, the way the Snipping Tool eraser does.
    public bool HitTest(Point p) {
        float tol = Math.Max(5f, EffectiveWidth() / 2f + 3f);
        if (Tool == PEN || Tool == HIGHLIGHT) {
            if (Points.Count == 1) return Dist(p, Points[0]) <= tol;
            for (int i = 1; i < Points.Count; i++)
                if (DistToSeg(p, Points[i - 1], Points[i]) <= tol) return true;
            return false;
        }
        if (Tool == LINE || Tool == ARROW) return DistToSeg(p, P1, P2) <= tol;
        if (Tool == TEXT) {
            RectangleF tb = new RectangleF(P1.X, P1.Y, TextSize.Width, TextSize.Height);
            tb.Inflate(3f, 3f);
            return tb.Contains(p);
        }
        Rectangle n = Norm();
        if (n.Width <= 0 || n.Height <= 0) return false;
        using (GraphicsPath gp = new GraphicsPath()) {
            if (Tool == ELLIPSE) gp.AddEllipse(n); else gp.AddRectangle(n);
            if (Filled) return gp.IsVisible(p);
            using (Pen tp = new Pen(Color.Black, tol * 2f)) return gp.IsOutlineVisible(p, tp);
        }
    }

    private static float Dist(Point a, Point b) {
        float dx = a.X - b.X, dy = a.Y - b.Y;
        return (float)Math.Sqrt(dx * dx + dy * dy);
    }

    private static float DistToSeg(Point p, Point a, Point b) {
        float vx = b.X - a.X, vy = b.Y - a.Y;
        float wx = p.X - a.X, wy = p.Y - a.Y;
        float len2 = vx * vx + vy * vy;
        if (len2 <= 0.0001f) return Dist(p, a);
        float t = (wx * vx + wy * vy) / len2;
        if (t < 0f) t = 0f; else if (t > 1f) t = 1f;
        float px = a.X + t * vx, py = a.Y + t * vy;
        float dx = p.X - px, dy = p.Y - py;
        return (float)Math.Sqrt(dx * dx + dy * dy);
    }
}

// One undoable step.
public class UndoRec {
    public const int ADD    = 0;
    public const int REMOVE = 1;
    public const int CROP   = 2;
    public const int CLEAR  = 3;

    public int       Kind;
    public DrawItem  Item;
    public int       Index;
    public Bitmap    OldImage;
    public Bitmap    NewImage;
    public Rectangle CropRect;
    public List<DrawItem> OldItems;
}

public class CanvasPanel : Panel {
    public CanvasPanel() {
        this.SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint |
                      ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        this.BackColor = Color.FromArgb(64, 64, 68);
    }
}

// ------------------------------------------------------------------
// OverlayForm - region selection, unchanged behaviour.
// ------------------------------------------------------------------
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
    private Bitmap dimmed;          // screenCapture pre-darkened once, so painting never alpha-blends
    private Point startPoint;
    private Rectangle currentRect;
    private bool isSelecting;
    private Rectangle virtualBounds;
    public Bitmap ResultBitmap { get; private set; }

    public OverlayForm() {
        // Capture the entire virtual screen using GDI (DPI-correct)
        virtualBounds = SystemInformation.VirtualScreen;

        // Multi-monitor virtual screens are easily 10+ megapixels. Darkening that on
        // every mouse move costs ~70 ms a frame, so do it once up front. Both bitmaps
        // are PArgb: the only format GDI+ blits without a per-draw conversion. Copying
        // a 2560x1440 region from the raw 32bppRgb capture takes ~13 ms, from PArgb ~2 ms.
        using (Bitmap raw = CaptureVirtualScreen(virtualBounds)) {
            screenCapture = new Bitmap(raw.Width, raw.Height, PixelFormat.Format32bppPArgb);
            using (Graphics g = Graphics.FromImage(screenCapture)) {
                g.CompositingMode = CompositingMode.SourceCopy;
                g.DrawImageUnscaled(raw, 0, 0);
            }
        }

        dimmed = new Bitmap(screenCapture.Width, screenCapture.Height, PixelFormat.Format32bppPArgb);
        using (Graphics g = Graphics.FromImage(dimmed)) {
            g.CompositingMode = CompositingMode.SourceCopy;
            g.DrawImageUnscaled(screenCapture, 0, 0);
            g.CompositingMode = CompositingMode.SourceOver;
            using (var brush = new SolidBrush(Color.FromArgb(100, 0, 0, 0)))
                g.FillRectangle(brush, 0, 0, dimmed.Width, dimmed.Height);
        }

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

    // OnPaint covers every pixel of the clip rectangle, so skip the background erase.
    protected override void OnPaintBackground(PaintEventArgs e) { }

    // Only the invalidated area is repainted: straight pixel copies from the two
    // prepared bitmaps, no scaling and no blending except the thin border.
    protected override void OnPaint(PaintEventArgs e) {
        Graphics g     = e.Graphics;
        Rectangle clip = e.ClipRectangle;
        g.InterpolationMode = InterpolationMode.NearestNeighbor;
        g.PixelOffsetMode   = PixelOffsetMode.Half;
        g.CompositingMode   = CompositingMode.SourceCopy;

        g.DrawImage(dimmed, clip, clip, GraphicsUnit.Pixel);

        if (currentRect.Width > 0 && currentRect.Height > 0) {
            Rectangle lit = Rectangle.Intersect(clip, currentRect);
            if (lit.Width > 0 && lit.Height > 0)
                g.DrawImage(screenCapture, lit, lit, GraphicsUnit.Pixel);

            g.CompositingMode = CompositingMode.SourceOver;
            using (var pen = new Pen(Color.FromArgb(200, 0, 174, 255), 2)) {
                g.DrawRectangle(pen, currentRect);
            }
        }
    }

    // The 2 px border straddles the rectangle edge, so pad the dirty area.
    private void InvalidateSelection(Rectangle r) {
        if (r.Width <= 0 && r.Height <= 0) return;
        r.Inflate(3, 3);
        Invalidate(r);
    }

    protected override void OnMouseDown(MouseEventArgs e) {
        if (e.Button == MouseButtons.Left) {
            InvalidateSelection(currentRect);   // clear a leftover too-small selection
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
            Rectangle next = new Rectangle(x, y, w, h);
            if (next == currentRect) return;

            // Repaint old and new selection only. Union with an empty rectangle
            // would stretch the box to the screen origin, hence the check.
            Rectangle dirty = currentRect.Width > 0 || currentRect.Height > 0
                ? Rectangle.Union(currentRect, next) : next;
            currentRect = next;
            InvalidateSelection(dirty);
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
                ResultBitmap      = screenCapture.Clone(currentRect, PixelFormat.Format32bppArgb);
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
        if (disposing && dimmed != null)        { dimmed.Dispose();        dimmed = null; }
        base.Dispose(disposing);
    }
}

// ------------------------------------------------------------------
// EditorForm - the Snipping Tool style markup window.
// ------------------------------------------------------------------
public class EditorForm : Form {
    private const int TOOL_ERASER = 100;
    private const int TOOL_CROP   = 101;

    private static readonly Color[] Palette = new Color[] {
        Color.FromArgb(232,  17,  35), Color.FromArgb(255, 140,   0),
        Color.FromArgb(255, 214,   0), Color.FromArgb( 16, 124,  16),
        Color.FromArgb(  0, 120, 212), Color.FromArgb(136,  23, 152),
        Color.FromArgb(  0,   0,   0), Color.FromArgb(255, 255, 255)
    };

    private Bitmap      image;
    private AppSettings settings;
    public  string      SavedPath;

    private List<DrawItem> items  = new List<DrawItem>();
    private List<UndoRec>  undo   = new List<UndoRec>();
    private List<UndoRec>  redo   = new List<UndoRec>();
    private List<Bitmap>   owned  = new List<Bitmap>();

    private int   tool     = DrawItem.PEN;
    private Color inkColor = Color.FromArgb(232, 17, 35);
    private float inkWidth = 4f;
    private bool  fillShapes;

    private DrawItem  current;
    private bool      dragging, erasing, cropping, panning;
    private Point     dragStartImg, panOrigin;
    private Rectangle cropRect;

    private float scale = 1f;
    private int   panX, panY, offX, offY;

    private CanvasPanel canvas;
    private TextBox     textBox;
    private Point       textAnchor;

    private List<ToolStripButton> toolButtons  = new List<ToolStripButton>();
    private List<ToolStripButton> colorButtons = new List<ToolStripButton>();
    private ToolStripButton undoBtn, redoBtn, fillBtn;
    private ToolStripLabel  zoomLabel, widthLabel;
    private ToolStripStatusLabel statusLabel, folderLink;
    private TrackBar widthBar;

    public EditorForm(Bitmap shot, AppSettings settings) {
        this.image    = shot;
        this.settings = settings;
        owned.Add(shot);

        this.Text          = "Screenshot Editor";
        this.Icon          = SystemIcons.Application;
        this.StartPosition = FormStartPosition.CenterScreen;
        this.KeyPreview    = true;
        this.BackColor     = Color.White;

        Rectangle wa = Screen.PrimaryScreen.WorkingArea;
        int w = Math.Min(image.Width  + 40,  (int)(wa.Width  * 0.92));
        int h = Math.Min(image.Height + 170, (int)(wa.Height * 0.92));
        this.ClientSize = new Size(Math.Max(820, w), Math.Max(500, h));

        BuildUi();
        UpdateUi();
    }

    // ---------------- UI ----------------

    private void BuildUi() {
        TableLayoutPanel root = new TableLayoutPanel();
        root.Dock        = DockStyle.Fill;
        root.ColumnCount = 1;
        root.RowCount    = 4;
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 100f));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));

        ToolStrip tools = new ToolStrip();
        tools.Dock      = DockStyle.Fill;
        tools.GripStyle = ToolStripGripStyle.Hidden;
        tools.ImageScalingSize = new Size(20, 20);
        tools.Padding   = new Padding(6, 4, 6, 4);

        tools.Items.Add(MakeToolButton("pen",       "Ballpoint pen",   DrawItem.PEN));
        tools.Items.Add(MakeToolButton("highlight", "Highlighter",     DrawItem.HIGHLIGHT));
        tools.Items.Add(MakeToolButton("eraser",    "Eraser",          TOOL_ERASER));
        tools.Items.Add(new ToolStripSeparator());
        tools.Items.Add(MakeToolButton("line",      "Line",            DrawItem.LINE));
        tools.Items.Add(MakeToolButton("arrow",     "Arrow",           DrawItem.ARROW));
        tools.Items.Add(MakeToolButton("rect",      "Rectangle",       DrawItem.RECT));
        tools.Items.Add(MakeToolButton("ellipse",   "Ellipse",         DrawItem.ELLIPSE));
        tools.Items.Add(MakeToolButton("text",      "Text",            DrawItem.TEXT));
        tools.Items.Add(new ToolStripSeparator());
        tools.Items.Add(MakeToolButton("crop",      "Crop",            TOOL_CROP));
        tools.Items.Add(new ToolStripSeparator());

        undoBtn = MakeCommandButton("undo", "Undo (Ctrl+Z)", new EventHandler(OnUndoClick));
        redoBtn = MakeCommandButton("redo", "Redo (Ctrl+Y)", new EventHandler(OnRedoClick));
        tools.Items.Add(undoBtn);
        tools.Items.Add(redoBtn);
        tools.Items.Add(new ToolStripSeparator());

        tools.Items.Add(MakeCommandButton("zoomout", "Zoom out", new EventHandler(OnZoomOutClick)));
        zoomLabel = new ToolStripLabel("100%");
        zoomLabel.AutoSize  = false;
        zoomLabel.Width     = 46;
        zoomLabel.TextAlign = ContentAlignment.MiddleCenter;
        tools.Items.Add(zoomLabel);
        tools.Items.Add(MakeCommandButton("zoomin", "Zoom in",       new EventHandler(OnZoomInClick)));
        tools.Items.Add(MakeCommandButton("fit",    "Fit to window", new EventHandler(OnFitClick)));

        ToolStripButton copyBtn = MakeCommandButton("copy", "Copy image to clipboard (Ctrl+C)",
                                                    new EventHandler(OnCopyClick));
        copyBtn.DisplayStyle = ToolStripItemDisplayStyle.ImageAndText;
        copyBtn.Text         = "Copy";
        copyBtn.Alignment    = ToolStripItemAlignment.Right;
        tools.Items.Add(copyBtn);

        ToolStripButton saveBtn = MakeCommandButton("save", "Save and copy the file path (Ctrl+S)",
                                                    new EventHandler(OnSaveClick));
        saveBtn.DisplayStyle = ToolStripItemDisplayStyle.ImageAndText;
        saveBtn.Text         = "Save";
        saveBtn.Alignment    = ToolStripItemAlignment.Right;
        saveBtn.Font         = new Font(saveBtn.Font, FontStyle.Bold);
        tools.Items.Add(saveBtn);

        ToolStrip style = new ToolStrip();
        style.Dock      = DockStyle.Fill;
        style.GripStyle = ToolStripGripStyle.Hidden;
        style.ImageScalingSize = new Size(18, 18);
        style.Padding   = new Padding(6, 2, 6, 2);

        for (int i = 0; i < Palette.Length; i++) {
            ToolStripButton cb = new ToolStripButton();
            cb.Image        = Icons.Swatch(Palette[i]);
            cb.DisplayStyle = ToolStripItemDisplayStyle.Image;
            cb.ToolTipText  = "Color";
            cb.Tag          = Palette[i];
            cb.Click       += new EventHandler(OnColorClick);
            colorButtons.Add(cb);
            style.Items.Add(cb);
        }
        ToolStripButton customBtn = new ToolStripButton("More...");
        customBtn.ToolTipText = "Pick a custom color";
        customBtn.Click += new EventHandler(OnCustomColorClick);
        style.Items.Add(customBtn);
        style.Items.Add(new ToolStripSeparator());

        widthLabel = new ToolStripLabel("Size 4");
        widthLabel.AutoSize  = false;
        widthLabel.Width     = 56;
        widthLabel.TextAlign = ContentAlignment.MiddleLeft;
        style.Items.Add(widthLabel);

        widthBar = new TrackBar();
        widthBar.Minimum       = 1;
        widthBar.Maximum       = 24;
        widthBar.Value         = (int)inkWidth;
        widthBar.TickStyle     = TickStyle.None;
        widthBar.AutoSize      = false;
        widthBar.Size          = new Size(120, 26);
        widthBar.ValueChanged += new EventHandler(OnWidthChanged);
        style.Items.Add(new ToolStripControlHost(widthBar));
        style.Items.Add(new ToolStripSeparator());

        fillBtn = new ToolStripButton("Fill");
        fillBtn.ToolTipText  = "Fill rectangles and ellipses";
        fillBtn.CheckOnClick = true;
        fillBtn.Click       += new EventHandler(OnFillClick);
        style.Items.Add(fillBtn);
        style.Items.Add(new ToolStripSeparator());

        ToolStripButton clearBtn = MakeCommandButton("clear", "Erase all markup",
                                                     new EventHandler(OnClearClick));
        clearBtn.DisplayStyle = ToolStripItemDisplayStyle.ImageAndText;
        clearBtn.Text         = "Erase all";
        style.Items.Add(clearBtn);

        canvas = new CanvasPanel();
        canvas.Dock         = DockStyle.Fill;
        canvas.Paint       += new PaintEventHandler(OnCanvasPaint);
        canvas.MouseDown   += new MouseEventHandler(OnCanvasMouseDown);
        canvas.MouseMove   += new MouseEventHandler(OnCanvasMouseMove);
        canvas.MouseUp     += new MouseEventHandler(OnCanvasMouseUp);
        canvas.MouseWheel  += new MouseEventHandler(OnCanvasMouseWheel);
        canvas.Resize      += new EventHandler(OnCanvasResize);
        canvas.Cursor       = Cursors.Cross;

        StatusStrip status = new StatusStrip();
        status.Dock = DockStyle.Fill;
        statusLabel = new ToolStripStatusLabel("");
        statusLabel.Spring    = true;
        statusLabel.TextAlign = ContentAlignment.MiddleLeft;
        status.Items.Add(statusLabel);

        folderLink = new ToolStripStatusLabel("");
        folderLink.IsLink      = true;
        folderLink.TextAlign   = ContentAlignment.MiddleRight;
        folderLink.ToolTipText = "Click to change the folder screenshots are saved to";
        folderLink.Click      += new EventHandler(OnFolderClick);
        status.Items.Add(folderLink);

        root.Controls.Add(tools,  0, 0);
        root.Controls.Add(style,  0, 1);
        root.Controls.Add(canvas, 0, 2);
        root.Controls.Add(status, 0, 3);
        this.Controls.Add(root);
    }

    private ToolStripButton MakeToolButton(string icon, string tip, int toolId) {
        ToolStripButton b = new ToolStripButton();
        b.Image        = Icons.Make(icon);
        b.DisplayStyle = ToolStripItemDisplayStyle.Image;
        b.ToolTipText  = tip;
        b.Tag          = toolId;
        b.Click       += new EventHandler(OnToolClick);
        toolButtons.Add(b);
        return b;
    }

    private ToolStripButton MakeCommandButton(string icon, string tip, EventHandler handler) {
        ToolStripButton b = new ToolStripButton();
        b.Image        = Icons.Make(icon);
        b.DisplayStyle = ToolStripItemDisplayStyle.Image;
        b.ToolTipText  = tip;
        b.Click       += handler;
        return b;
    }

    private void UpdateUi() {
        foreach (ToolStripButton b in toolButtons)  b.Checked = ((int)b.Tag == tool);
        foreach (ToolStripButton b in colorButtons) b.Checked = ((Color)b.Tag).ToArgb() == inkColor.ToArgb();
        if (undoBtn    != null) undoBtn.Enabled = undo.Count > 0;
        if (redoBtn    != null) redoBtn.Enabled = redo.Count > 0;
        if (fillBtn    != null) fillBtn.Checked = fillShapes;
        if (zoomLabel  != null) zoomLabel.Text  = ((int)Math.Round(scale * 100f)) + "%";
        if (widthLabel != null) widthLabel.Text = "Size " + (int)inkWidth;
        if (statusLabel != null)
            statusLabel.Text = image.Width + " x " + image.Height + " px    -    " +
                               items.Count + " markup item(s)";
        if (folderLink != null) {
            folderLink.Text        = "Save to: " + Shorten(settings.SaveDir, 64);
            folderLink.ToolTipText = settings.SaveDir + Environment.NewLine +
                                     "Click to change the folder screenshots are saved to";
        }
    }

    // Keep long paths from pushing the status bar wider than the window.
    private static string Shorten(string path, int max) {
        if (string.IsNullOrEmpty(path) || path.Length <= max) return path;
        return "..." + path.Substring(path.Length - (max - 3));
    }

    private void OnFolderClick(object sender, EventArgs e) {
        CommitText();
        if (settings.ChooseFolder(this)) UpdateUi();
    }

    // ---------------- toolbar handlers ----------------

    private void OnToolClick(object sender, EventArgs e) {
        CommitText();
        tool = (int)((ToolStripButton)sender).Tag;
        if (tool == TOOL_ERASER)        canvas.Cursor = Cursors.Hand;
        else if (tool == DrawItem.TEXT) canvas.Cursor = Cursors.IBeam;
        else                            canvas.Cursor = Cursors.Cross;
        UpdateUi();
    }

    private void OnColorClick(object sender, EventArgs e) {
        CommitText();
        inkColor = (Color)((ToolStripButton)sender).Tag;
        UpdateUi();
    }

    private void OnCustomColorClick(object sender, EventArgs e) {
        CommitText();
        using (ColorDialog dlg = new ColorDialog()) {
            dlg.Color    = inkColor;
            dlg.FullOpen = true;
            if (dlg.ShowDialog(this) == DialogResult.OK) { inkColor = dlg.Color; UpdateUi(); }
        }
    }

    private void OnWidthChanged(object sender, EventArgs e) {
        inkWidth = widthBar.Value;
        UpdateUi();
    }

    private void OnFillClick(object sender, EventArgs e) {
        fillShapes = fillBtn.Checked;
        UpdateUi();
    }

    private void OnUndoClick(object sender, EventArgs e)  { DoUndo(); }
    private void OnRedoClick(object sender, EventArgs e)  { DoRedo(); }
    private void OnClearClick(object sender, EventArgs e) { ClearAll(); }
    private void OnSaveClick(object sender, EventArgs e)  { SaveAndClose(); }
    private void OnCopyClick(object sender, EventArgs e)  { CopyImage(); }

    private void OnZoomInClick(object sender, EventArgs e)  { Zoom(scale * 1.25f); }
    private void OnZoomOutClick(object sender, EventArgs e) { Zoom(scale / 1.25f); }
    private void OnFitClick(object sender, EventArgs e)     { FitToWindow(); }

    // ---------------- view ----------------

    private void Zoom(float target) {
        CommitText();
        if (target < 0.1f) target = 0.1f;
        if (target > 8f)   target = 8f;
        scale = target;
        panX  = 0;
        panY  = 0;
        canvas.Invalidate();
        UpdateUi();
    }

    private void FitToWindow() {
        CommitText();
        if (canvas == null || canvas.ClientSize.Width < 10 || canvas.ClientSize.Height < 10) return;
        float sx = (float)(canvas.ClientSize.Width  - 24) / image.Width;
        float sy = (float)(canvas.ClientSize.Height - 24) / image.Height;
        float s  = Math.Min(sx, sy);
        if (s > 1f)   s = 1f;
        if (s < 0.1f) s = 0.1f;
        scale = s;
        panX  = 0;
        panY  = 0;
        canvas.Invalidate();
        UpdateUi();
    }

    private void RecalcOffsets() {
        int dw = (int)Math.Round(image.Width  * scale);
        int dh = (int)Math.Round(image.Height * scale);
        int cw = canvas.ClientSize.Width;
        int ch = canvas.ClientSize.Height;

        if (dw <= cw) { panX = 0; offX = (cw - dw) / 2; }
        else {
            if (panX > 0)       panX = 0;
            if (panX < cw - dw) panX = cw - dw;
            offX = panX;
        }
        if (dh <= ch) { panY = 0; offY = (ch - dh) / 2; }
        else {
            if (panY > 0)       panY = 0;
            if (panY < ch - dh) panY = ch - dh;
            offY = panY;
        }
    }

    private Point ToImage(Point canvasPt) {
        RecalcOffsets();
        return new Point((int)Math.Round((canvasPt.X - offX) / scale),
                         (int)Math.Round((canvasPt.Y - offY) / scale));
    }

    private Point ToCanvas(Point imagePt) {
        RecalcOffsets();
        return new Point((int)Math.Round(imagePt.X * scale) + offX,
                         (int)Math.Round(imagePt.Y * scale) + offY);
    }

    private Point ClampToImage(Point p) {
        int x = p.X, y = p.Y;
        if (x < 0) x = 0;
        if (y < 0) y = 0;
        if (x > image.Width)  x = image.Width;
        if (y > image.Height) y = image.Height;
        return new Point(x, y);
    }

    private void OnCanvasResize(object sender, EventArgs e) {
        CommitText();
        canvas.Invalidate();
    }

    private void OnCanvasMouseWheel(object sender, MouseEventArgs e) {
        if ((ModifierKeys & Keys.Control) == Keys.Control) {
            Zoom(e.Delta > 0 ? scale * 1.15f : scale / 1.15f);
        } else {
            panY += e.Delta > 0 ? 60 : -60;
            canvas.Invalidate();
        }
    }

    // ---------------- painting ----------------

    private void OnCanvasPaint(object sender, PaintEventArgs e) {
        Graphics g = e.Graphics;
        RecalcOffsets();

        int dw = (int)Math.Round(image.Width  * scale);
        int dh = (int)Math.Round(image.Height * scale);
        using (SolidBrush shadow = new SolidBrush(Color.FromArgb(70, 0, 0, 0)))
            g.FillRectangle(shadow, offX + 4, offY + 4, dw, dh);

        g.InterpolationMode = scale < 1f ? InterpolationMode.HighQualityBicubic
                                         : InterpolationMode.NearestNeighbor;
        g.PixelOffsetMode   = PixelOffsetMode.Half;

        GraphicsState st = g.Save();
        g.TranslateTransform(offX, offY);
        g.ScaleTransform(scale, scale);
        g.DrawImage(image, 0, 0, image.Width, image.Height);

        g.SmoothingMode     = SmoothingMode.AntiAlias;
        g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAlias;
        foreach (DrawItem it in items) it.Render(g);
        if (current != null) current.Render(g);
        if (cropping) DrawCropOverlay(g);
        g.Restore(st);

        using (Pen border = new Pen(Color.FromArgb(120, 255, 255, 255), 1f))
            g.DrawRectangle(border, offX - 1, offY - 1, dw + 1, dh + 1);
    }

    private void DrawCropOverlay(Graphics g) {
        Rectangle full = new Rectangle(0, 0, image.Width, image.Height);
        Rectangle r    = Rectangle.Intersect(cropRect, full);
        using (SolidBrush b = new SolidBrush(Color.FromArgb(130, 0, 0, 0))) {
            g.FillRectangle(b, full.X, full.Y, full.Width, r.Y - full.Y);
            g.FillRectangle(b, full.X, r.Bottom, full.Width, full.Bottom - r.Bottom);
            g.FillRectangle(b, full.X, r.Y, r.X - full.X, r.Height);
            g.FillRectangle(b, r.Right, r.Y, full.Right - r.Right, r.Height);
        }
        if (r.Width > 0 && r.Height > 0) {
            using (Pen p = new Pen(Color.White, 1f / scale)) {
                p.DashStyle = DashStyle.Dash;
                g.DrawRectangle(p, r);
            }
        }
    }

    // ---------------- drawing ----------------

    private DrawItem NewItem() {
        DrawItem it = new DrawItem();
        it.Tool   = tool;
        it.Ink    = inkColor;
        it.Width  = inkWidth;
        it.Filled = fillShapes;
        return it;
    }

    private float FontSizeForWidth() { return Math.Max(12f, inkWidth * 6f); }

    private Point Constrain(Point start, Point p, bool shift) {
        if (!shift) return p;
        int dx = p.X - start.X, dy = p.Y - start.Y;
        if (tool == DrawItem.LINE || tool == DrawItem.ARROW) {
            double ang  = Math.Atan2(dy, dx);
            double step = Math.PI / 4.0;
            double snap = Math.Round(ang / step) * step;
            double len  = Math.Sqrt((double)dx * dx + (double)dy * dy);
            return new Point(start.X + (int)Math.Round(Math.Cos(snap) * len),
                             start.Y + (int)Math.Round(Math.Sin(snap) * len));
        }
        int m = Math.Max(Math.Abs(dx), Math.Abs(dy));
        return new Point(start.X + Math.Sign(dx) * m, start.Y + Math.Sign(dy) * m);
    }

    private void OnCanvasMouseDown(object sender, MouseEventArgs e) {
        canvas.Focus();
        if (e.Button == MouseButtons.Middle) { panning = true; panOrigin = e.Location; return; }
        if (e.Button != MouseButtons.Left) return;

        if (textBox != null) { CommitText(); return; }
        Point p = ToImage(e.Location);

        if (tool == TOOL_ERASER) { erasing = true; EraseAt(p); return; }

        if (tool == TOOL_CROP) {
            cropping     = true;
            dragStartImg = ClampToImage(p);
            cropRect     = new Rectangle(dragStartImg, Size.Empty);
            canvas.Invalidate();
            return;
        }

        if (tool == DrawItem.TEXT) { BeginText(p); return; }

        dragging     = true;
        dragStartImg = p;
        current      = NewItem();
        if (tool == DrawItem.PEN || tool == DrawItem.HIGHLIGHT) current.Points.Add(p);
        else { current.P1 = p; current.P2 = p; }
        canvas.Invalidate();
    }

    private void OnCanvasMouseMove(object sender, MouseEventArgs e) {
        if (panning) {
            panX += e.X - panOrigin.X;
            panY += e.Y - panOrigin.Y;
            panOrigin = e.Location;
            canvas.Invalidate();
            return;
        }

        bool shift = (ModifierKeys & Keys.Shift) == Keys.Shift;
        Point p = ToImage(e.Location);

        if (erasing) { EraseAt(p); return; }

        if (cropping) {
            Point q = ClampToImage(Constrain(dragStartImg, p, shift));
            cropRect = Rectangle.FromLTRB(Math.Min(dragStartImg.X, q.X), Math.Min(dragStartImg.Y, q.Y),
                                          Math.Max(dragStartImg.X, q.X), Math.Max(dragStartImg.Y, q.Y));
            canvas.Invalidate();
            return;
        }

        if (!dragging || current == null) return;

        if (current.Tool == DrawItem.PEN || current.Tool == DrawItem.HIGHLIGHT) {
            Point last = current.Points[current.Points.Count - 1];
            if (last != p) current.Points.Add(p);
        } else {
            current.P2 = Constrain(dragStartImg, p, shift);
        }
        canvas.Invalidate();
    }

    private void OnCanvasMouseUp(object sender, MouseEventArgs e) {
        if (e.Button == MouseButtons.Middle) { panning = false; return; }
        if (e.Button != MouseButtons.Left) return;

        if (erasing) { erasing = false; return; }

        if (cropping) {
            cropping = false;
            Rectangle r = cropRect;
            cropRect = Rectangle.Empty;
            ApplyCrop(r);
            canvas.Invalidate();
            return;
        }

        if (!dragging) return;
        dragging = false;
        DrawItem it = current;
        current = null;

        if (it != null) {
            bool keep;
            if (it.Tool == DrawItem.PEN || it.Tool == DrawItem.HIGHLIGHT) keep = it.Points.Count > 0;
            else { Rectangle n = it.Norm(); keep = (n.Width > 2 || n.Height > 2); }
            if (keep) AddItem(it);
        }
        canvas.Invalidate();
    }

    // ---------------- text ----------------

    private void BeginText(Point imgPt) {
        CommitText();
        textAnchor = imgPt;
        Point c = ToCanvas(imgPt);

        textBox = new TextBox();
        textBox.Multiline   = true;
        textBox.BorderStyle = BorderStyle.FixedSingle;
        textBox.ForeColor   = inkColor;
        textBox.BackColor   = Color.White;
        textBox.Font        = new Font("Segoe UI", Math.Max(9f, FontSizeForWidth() * scale),
                                       FontStyle.Regular, GraphicsUnit.Pixel);
        textBox.Location    = new Point(c.X - 2, c.Y - 2);
        textBox.Size        = new Size(Math.Max(140, (int)(260 * scale)),
                                       Math.Max(24, (int)(textBox.Font.Height * 1.7f)));
        textBox.KeyDown    += new KeyEventHandler(OnTextKeyDown);
        canvas.Controls.Add(textBox);
        textBox.BringToFront();
        textBox.Focus();
    }

    private void OnTextKeyDown(object sender, KeyEventArgs e) {
        if (e.KeyCode == Keys.Enter && !e.Shift) {
            e.SuppressKeyPress = true;
            CommitText();
        } else if (e.KeyCode == Keys.Escape) {
            e.SuppressKeyPress = true;
            CancelText();
        }
    }

    private void CancelText() {
        if (textBox == null) return;
        TextBox tb = textBox;
        textBox = null;
        canvas.Controls.Remove(tb);
        tb.Dispose();
        canvas.Invalidate();
    }

    private void CommitText() {
        if (textBox == null) return;
        string txt = textBox.Text;
        TextBox tb = textBox;
        textBox = null;
        canvas.Controls.Remove(tb);
        tb.Dispose();

        if (txt != null && txt.Trim().Length > 0) {
            DrawItem it = new DrawItem();
            it.Tool     = DrawItem.TEXT;
            it.Ink      = inkColor;
            it.Width    = inkWidth;
            it.FontSize = FontSizeForWidth();
            it.P1       = textAnchor;
            it.Text     = txt;
            using (Graphics g = canvas.CreateGraphics())
            using (Font f = new Font("Segoe UI", it.FontSize, FontStyle.Regular, GraphicsUnit.Pixel))
                it.TextSize = g.MeasureString(txt, f);
            AddItem(it);
        }
        canvas.Invalidate();
    }

    // ---------------- edits and undo ----------------

    private void AddItem(DrawItem it) {
        items.Add(it);
        UndoRec r = new UndoRec();
        r.Kind  = UndoRec.ADD;
        r.Item  = it;
        r.Index = items.Count - 1;
        Push(r);
    }

    private void EraseAt(Point p) {
        for (int i = items.Count - 1; i >= 0; i--) {
            if (items[i].HitTest(p)) {
                UndoRec r = new UndoRec();
                r.Kind  = UndoRec.REMOVE;
                r.Item  = items[i];
                r.Index = i;
                items.RemoveAt(i);
                Push(r);
                canvas.Invalidate();
                return;
            }
        }
    }

    private void ClearAll() {
        CommitText();
        if (items.Count == 0) return;
        UndoRec r = new UndoRec();
        r.Kind     = UndoRec.CLEAR;
        r.OldItems = new List<DrawItem>(items);
        items.Clear();
        Push(r);
        canvas.Invalidate();
    }

    private void ApplyCrop(Rectangle r) {
        r = Rectangle.Intersect(r, new Rectangle(0, 0, image.Width, image.Height));
        if (r.Width < 5 || r.Height < 5) return;

        Bitmap nb = image.Clone(r, PixelFormat.Format32bppArgb);
        owned.Add(nb);

        UndoRec rec = new UndoRec();
        rec.Kind     = UndoRec.CROP;
        rec.OldImage = image;
        rec.NewImage = nb;
        rec.CropRect = r;

        image = nb;
        foreach (DrawItem it in items) it.Offset(-r.X, -r.Y);
        Push(rec);
        FitToWindow();
    }

    private void Push(UndoRec r) {
        undo.Add(r);
        redo.Clear();
        UpdateUi();
    }

    private void DoUndo() {
        CommitText();
        if (undo.Count == 0) return;
        UndoRec r = undo[undo.Count - 1];
        undo.RemoveAt(undo.Count - 1);

        if (r.Kind == UndoRec.ADD)         items.RemoveAt(r.Index);
        else if (r.Kind == UndoRec.REMOVE) items.Insert(r.Index, r.Item);
        else if (r.Kind == UndoRec.CLEAR)  items = new List<DrawItem>(r.OldItems);
        else if (r.Kind == UndoRec.CROP) {
            image = r.OldImage;
            foreach (DrawItem it in items) it.Offset(r.CropRect.X, r.CropRect.Y);
            FitToWindow();
        }

        redo.Add(r);
        UpdateUi();
        canvas.Invalidate();
    }

    private void DoRedo() {
        CommitText();
        if (redo.Count == 0) return;
        UndoRec r = redo[redo.Count - 1];
        redo.RemoveAt(redo.Count - 1);

        if (r.Kind == UndoRec.ADD)         items.Insert(r.Index, r.Item);
        else if (r.Kind == UndoRec.REMOVE) items.RemoveAt(r.Index);
        else if (r.Kind == UndoRec.CLEAR)  items.Clear();
        else if (r.Kind == UndoRec.CROP) {
            image = r.NewImage;
            foreach (DrawItem it in items) it.Offset(-r.CropRect.X, -r.CropRect.Y);
            FitToWindow();
        }

        undo.Add(r);
        UpdateUi();
        canvas.Invalidate();
    }

    // ---------------- output ----------------

    private Bitmap Flatten() {
        Bitmap bmp = new Bitmap(image.Width, image.Height, PixelFormat.Format32bppArgb);
        using (Graphics g = Graphics.FromImage(bmp)) {
            g.InterpolationMode = InterpolationMode.NearestNeighbor;
            g.PixelOffsetMode   = PixelOffsetMode.Half;
            g.DrawImage(image, 0, 0, image.Width, image.Height);
            g.SmoothingMode     = SmoothingMode.AntiAlias;
            g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAlias;
            foreach (DrawItem it in items) it.Render(g);
        }
        return bmp;
    }

    private bool DoSave() {
        CommitText();
        try {
            if (!Directory.Exists(settings.SaveDir)) Directory.CreateDirectory(settings.SaveDir);
            string path = Naming.NextPath(settings.SaveDir);
            using (Bitmap flat = Flatten()) flat.Save(path, ImageFormat.Png);
            SavedPath = path;
            return true;
        } catch (Exception ex) {
            MessageBox.Show(this, "Failed to save the image: " + ex.Message,
                            "Screenshot Editor", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return false;
        }
    }

    private void SaveAndClose() {
        if (!DoSave()) return;
        this.DialogResult = DialogResult.OK;
        this.Close();
    }

    private void CopyImage() {
        CommitText();
        try {
            using (Bitmap flat = Flatten())
                Clipboard.SetDataObject(new Bitmap(flat), true);
        } catch (Exception ex) {
            MessageBox.Show(this, "Failed to copy the image: " + ex.Message,
                            "Screenshot Editor", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    // ---------------- form plumbing ----------------

    protected override void OnShown(EventArgs e) {
        base.OnShown(e);
        FitToWindow();
        this.TopMost = true;
        this.Activate();
        this.TopMost = false;
        canvas.Focus();
    }

    protected override bool ProcessCmdKey(ref Message msg, Keys keyData) {
        if (textBox == null) {
            if (keyData == (Keys.Control | Keys.Z)) { DoUndo();       return true; }
            if (keyData == (Keys.Control | Keys.Y)) { DoRedo();       return true; }
            if (keyData == (Keys.Control | Keys.S)) { SaveAndClose(); return true; }
            if (keyData == (Keys.Control | Keys.C)) { CopyImage();    return true; }
            if (keyData == Keys.Escape)             { this.Close();   return true; }
        }
        return base.ProcessCmdKey(ref msg, keyData);
    }

    protected override void OnFormClosing(FormClosingEventArgs e) {
        if (SavedPath == null && undo.Count > 0) {
            DialogResult r = MessageBox.Show(this,
                "Save this snip before closing?", "Screenshot Editor",
                MessageBoxButtons.YesNoCancel, MessageBoxIcon.Question);
            if (r == DialogResult.Cancel) { e.Cancel = true; return; }
            if (r == DialogResult.Yes && !DoSave()) { e.Cancel = true; return; }
        }
        base.OnFormClosing(e);
    }

    protected override void Dispose(bool disposing) {
        if (disposing) {
            foreach (Bitmap b in owned) { if (b != null) b.Dispose(); }
            owned.Clear();
            image = null;
        }
        base.Dispose(disposing);
    }
}

// ------------------------------------------------------------------
// HotkeyForm - tray icon, global hotkey, orchestration.
// ------------------------------------------------------------------
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

    private AppSettings settings;
    private NotifyIcon  trayIcon;
    private bool        busy;
    private Timer       hotkeyRetry;
    private int         hotkeyAttempts;
    private bool        hotkeyOwned;

    public HotkeyForm(AppSettings settings) {
        // Per-Monitor DPI Awareness V2 (Windows 10 1703+)
        try { SetProcessDpiAwarenessContext(new IntPtr(-4)); } catch {}

        this.settings        = settings;
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
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Save folder...",       null, (s, e) => ChangeFolder());
        menu.Items.Add("Open save folder",     null, (s, e) => settings.OpenInExplorer(this));
        menu.Items.Add("Clear save folder...", null, (s, e) => ClearFolder());
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Exit",                 null, (s, e) => Application.Exit());
        trayIcon.ContextMenuStrip = menu;
    }

    private void ChangeFolder() {
        if (busy) return;
        if (settings.ChooseFolder(this))
            trayIcon.ShowBalloonTip(2500, "Save folder changed", settings.SaveDir, ToolTipIcon.Info);
    }

    // Empties the save folder and resets numbering back to 000001.
    // Deliberately conservative: only NNNNNN.png files are touched, because the
    // save folder may be a folder the user keeps other images in. Files go to the
    // Recycle Bin, not straight to oblivion.
    private void ClearFolder() {
        if (busy) return;
        string nl = Environment.NewLine;

        List<string> files = Naming.GeneratedFiles(settings.SaveDir);
        if (files.Count == 0) {
            MessageBox.Show(this,
                "There are no numbered screenshots to remove in:" + nl + settings.SaveDir,
                "Clear save folder", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        DialogResult answer = MessageBox.Show(this,
            "Move " + files.Count + " screenshot(s) to the Recycle Bin?" + nl + nl +
            settings.SaveDir + nl + nl +
            "Only files named NNNNNN.png are removed - anything else in the folder is left alone." + nl +
            "Numbering restarts at 000001.",
            "Clear save folder", MessageBoxButtons.YesNo, MessageBoxIcon.Warning,
            MessageBoxDefaultButton.Button2);
        if (answer != DialogResult.Yes) return;

        int removed = 0;
        string firstError = null;
        foreach (string file in files) {
            try {
                Microsoft.VisualBasic.FileIO.FileSystem.DeleteFile(file,
                    Microsoft.VisualBasic.FileIO.UIOption.OnlyErrorDialogs,
                    Microsoft.VisualBasic.FileIO.RecycleOption.SendToRecycleBin);
                removed++;
            } catch (Exception ex) {
                if (firstError == null) firstError = ex.Message;
            }
        }

        if (firstError != null) {
            MessageBox.Show(this,
                "Removed " + removed + " of " + files.Count + " file(s)." + nl +
                "The rest could not be deleted, the first error was:" + nl + firstError,
                "Clear save folder", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        } else {
            trayIcon.ShowBalloonTip(2500, "Save folder cleared",
                removed + " file(s) moved to the Recycle Bin. Next capture will be 000001.png.",
                ToolTipIcon.Info);
        }
    }

    // Registration can lose a race - a previous copy still shutting down, or another
    // app holding the combo for a moment. It used to fail once and give up, leaving a
    // live process whose hotkey never worked. Keep retrying quietly for ~30 s instead.
    protected override void OnLoad(EventArgs e) {
        base.OnLoad(e);
        if (!TryRegisterHotkey()) {
            hotkeyRetry          = new Timer();
            hotkeyRetry.Interval = 2000;
            hotkeyRetry.Tick    += new EventHandler(OnHotkeyRetry);
            hotkeyRetry.Start();
        }
        this.Hide();
    }

    private bool TryRegisterHotkey() {
        hotkeyOwned   = RegisterHotKey(this.Handle, HOTKEY_ID, MOD_CTRL_ALT, VK_S);
        trayIcon.Text = hotkeyOwned ? "Screenshot Tool (Ctrl+Alt+S)"
                                    : "Screenshot Tool (waiting for Ctrl+Alt+S)";
        return hotkeyOwned;
    }

    private void OnHotkeyRetry(object sender, EventArgs e) {
        hotkeyAttempts++;
        if (TryRegisterHotkey()) {
            hotkeyRetry.Stop();
            trayIcon.ShowBalloonTip(2000, "Screenshot Tool", "Ctrl+Alt+S is ready.", ToolTipIcon.Info);
            return;
        }
        if (hotkeyAttempts >= 15) {
            hotkeyRetry.Stop();
            trayIcon.ShowBalloonTip(5000, "Ctrl+Alt+S is unavailable",
                "Another program is holding it. Capture from this tray menu instead.",
                ToolTipIcon.Warning);
        }
    }

    protected override void WndProc(ref Message m) {
        if (m.Msg == WM_HOTKEY && m.WParam.ToInt32() == HOTKEY_ID) {
            TakeScreenshot();
        }
        base.WndProc(ref m);
    }

    private void TakeScreenshot() {
        if (busy) return;
        busy = true;
        try {
            Bitmap shot = null;
            using (var overlay = new OverlayForm()) {
                if (overlay.ShowDialog() == DialogResult.OK) shot = overlay.ResultBitmap;
            }
            if (shot == null) return;   // cancelled: nothing captured, nothing saved

            using (var editor = new EditorForm(shot, settings)) {
                editor.ShowDialog();
                if (editor.SavedPath != null) {
                    Clipboard.SetText(editor.SavedPath);
                    trayIcon.ShowBalloonTip(2000, "Saved (path copied)",
                                            editor.SavedPath, ToolTipIcon.Info);
                }
                // Closed without saving: no file written, clipboard untouched.
            }
        } finally {
            busy = false;
        }
    }

    protected override void OnFormClosed(FormClosedEventArgs e) {
        if (hotkeyRetry != null) { hotkeyRetry.Stop(); hotkeyRetry.Dispose(); hotkeyRetry = null; }
        if (hotkeyOwned) UnregisterHotKey(this.Handle, HOTKEY_ID);
        if (trayIcon != null) { trayIcon.Visible = false; trayIcon.Dispose(); }
        base.OnFormClosed(e);
    }
}
'@

# ------------------------------------------------------------------
# Single instance. Only one process can own Ctrl+Alt+S, and a second
# copy used to pop a balloon blaming "another program" for the clash -
# which was really just the first copy. Bow out quietly instead.
# Checked before compiling, so a stray double-click costs nothing.
# ------------------------------------------------------------------
$mutex   = New-Object System.Threading.Mutex($false, "Local\ScreenCaptureTool.SingleInstance")
$isFirst = $false
try     { $isFirst = $mutex.WaitOne(0) }
catch [System.Threading.AbandonedMutexException] { $isFirst = $true }   # previous owner crashed

if (-not $isFirst) {
    Write-Host "[ScreenCapture] Already running - this copy is exiting."
    $note = New-Object System.Windows.Forms.NotifyIcon
    $note.Icon    = [System.Drawing.SystemIcons]::Information
    $note.Text    = "Screenshot Tool"
    $note.Visible = $true
    $note.ShowBalloonTip(3000, "Screenshot Tool is already running",
                         "Press Ctrl+Alt+S, or right-click the tray icon.",
                         [System.Windows.Forms.ToolTipIcon]::Info)
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 3500
    $timer.Add_Tick({ [System.Windows.Forms.Application]::Exit() })
    $timer.Start()
    [System.Windows.Forms.Application]::Run()
    $timer.Dispose()
    $note.Visible = $false
    $note.Dispose()
    exit
}

# ------------------------------------------------------------------
# Compile cache. Building this much C# costs seconds on every start,
# during which the hotkey is dead. Cache the assembly under a hash of
# the source, so only the first run after an edit pays for it.
# ------------------------------------------------------------------
$refs     = @('System.Windows.Forms', 'System.Drawing', 'Microsoft.VisualBasic')
$cacheDir = Join-Path $env:LOCALAPPDATA 'ScreenCaptureTool\cache'
$sha      = [System.Security.Cryptography.SHA256]::Create()
try {
    $key = $csharp + '|' + $PSVersionTable.PSVersion + '|' + [Environment]::Version
    $stamp = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($key))).Replace('-', '').Substring(0, 16)
} finally { $sha.Dispose() }
$dll = Join-Path $cacheDir "ScreenCapture_$stamp.dll"

$loaded = $false
if (Test-Path $dll) {
    try { Add-Type -Path $dll -ErrorAction Stop; $loaded = $true } catch { $loaded = $false }
}
if (-not $loaded) {
    try {
        if (-not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null }
        # Drop assemblies built from older versions of the source.
        Get-ChildItem (Join-Path $cacheDir 'ScreenCapture_*.dll') -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -ne $dll } |
            ForEach-Object { try { Remove-Item $_.FullName -Force -ErrorAction Stop } catch { } }
        Add-Type -ReferencedAssemblies $refs -TypeDefinition $csharp -OutputAssembly $dll -OutputType Library -ErrorAction Stop
        Add-Type -Path $dll -ErrorAction Stop
    } catch {
        # Cache folder unwritable or the cached file is unusable: just build in memory.
        Write-Host "[ScreenCapture] Compile cache unavailable, building in memory."
        Add-Type -ReferencedAssemblies $refs -TypeDefinition $csharp -ErrorAction Stop
    }
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$settings  = New-Object AppSettings($scriptDir)

Write-Host "[ScreenCapture] Started. Press Ctrl+Alt+S to capture."
Write-Host "[ScreenCapture] Save dir: $($settings.SaveDir)"
Write-Host "[ScreenCapture] Settings: $($settings.FilePath)"
Write-Host "[ScreenCapture] Right-click tray icon to change the folder or exit."

[System.Windows.Forms.Application]::Run((New-Object HotkeyForm($settings)))
$mutex.ReleaseMutex()
