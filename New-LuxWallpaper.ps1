# New-LuxWallpaper.ps1 — premium dark wallpapers for UNLOCK DIGITAL style branding
#
# Examples:
#   powershell -File .\New-LuxWallpaper.ps1                     # blue variant + apply as wallpaper
#   powershell -File .\New-LuxWallpaper.ps1 -All                # all 4 variants + contact sheet
#   powershell -File .\New-LuxWallpaper.ps1 -Accent "#10B981" -Accent2 "#22D3EE" -Name emerald
#   powershell -File .\New-LuxWallpaper.ps1 -Tagline "AUTODESK LICENSING EXPERTS"

param(
    [int]$Width = 2560,
    [int]$Height = 1440,
    [string]$Word1 = "UNLOCK",
    [string]$Word2 = "DIGITAL",
    [string]$Tagline = "IT SOLUTIONS & LICENSING",
    [string]$OutDir = "$([Environment]::GetFolderPath('MyPictures'))\Wallpapers",
    [string]$Accent = "#5B8DEF",
    [string]$Accent2 = "#22D3EE",
    [string]$Name = "blue",
    [switch]$All,
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$csharp = @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.Runtime.InteropServices;

public static class ProWallpaper
{
    // ---------- helpers ----------
    static Color HC(string hex)
    {
        hex = hex.TrimStart('#');
        return Color.FromArgb(255,
            Convert.ToInt32(hex.Substring(0, 2), 16),
            Convert.ToInt32(hex.Substring(2, 2), 16),
            Convert.ToInt32(hex.Substring(4, 2), 16));
    }

    static Font MakeFont(float size, bool bold)
    {
        string[] names = { "Segoe UI Semibold", "Segoe UI", "Arial" };
        foreach (string n in names)
        {
            try
            {
                FontFamily fam = new FontFamily(n);
                return new Font(fam, size, bold ? FontStyle.Bold : FontStyle.Regular, GraphicsUnit.Pixel);
            }
            catch { }
        }
        return new Font(FontFamily.GenericSansSerif, size, FontStyle.Regular, GraphicsUnit.Pixel);
    }

    static GraphicsPath RoundRect(float x, float y, float w, float h, float r)
    {
        GraphicsPath p = new GraphicsPath();
        if (r <= 0f) { p.AddRectangle(new RectangleF(x, y, w, h)); return p; }
        p.AddArc(x, y, r * 2, r * 2, 180, 90);
        p.AddArc(x + w - r * 2, y, r * 2, r * 2, 270, 90);
        p.AddArc(x + w - r * 2, y + h - r * 2, r * 2, r * 2, 0, 90);
        p.AddArc(x, y + h - r * 2, r * 2, r * 2, 90, 90);
        p.CloseFigure();
        return p;
    }

    static void Glow(Graphics g, float cx, float cy, float radius, Color color)
    {
        GraphicsPath path = new GraphicsPath();
        path.AddEllipse(cx - radius, cy - radius, radius * 2, radius * 2);
        PathGradientBrush pgb = new PathGradientBrush(path);
        pgb.CenterColor = color;
        pgb.SurroundColors = new Color[] { Color.FromArgb(0, color.R, color.G, color.B) };
        g.FillPath(pgb, path);
        pgb.Dispose();
        path.Dispose();
    }

    // separable box blur (3 passes ~ gaussian), premultiplied ARGB
    static void Blur(Bitmap bmp, int radius, int passes)
    {
        int w = bmp.Width, h = bmp.Height;
        BitmapData data = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadWrite, PixelFormat.Format32bppPArgb);
        int stride = data.Stride;
        int bytes = stride * h;
        byte[] dst = new byte[bytes];
        Marshal.Copy(data.Scan0, dst, 0, bytes);
        byte[] src = new byte[bytes];
        int win = radius * 2 + 1;

        for (int pass = 0; pass < passes; pass++)
        {
            // horizontal: src -> dst
            Buffer.BlockCopy(dst, 0, src, 0, bytes);
            for (int y = 0; y < h; y++)
            {
                int row = y * stride;
                int s0 = 0, s1 = 0, s2 = 0, s3 = 0;
                for (int x = -radius; x <= radius; x++)
                {
                    int xi = x < 0 ? 0 : (x >= w ? w - 1 : x);
                    int i = row + xi * 4;
                    s0 += src[i]; s1 += src[i + 1]; s2 += src[i + 2]; s3 += src[i + 3];
                }
                for (int x = 0; x < w; x++)
                {
                    int o = row + x * 4;
                    dst[o] = (byte)(s0 / win); dst[o + 1] = (byte)(s1 / win);
                    dst[o + 2] = (byte)(s2 / win); dst[o + 3] = (byte)(s3 / win);

                    int xo = x - radius; xo = xo < 0 ? 0 : xo;
                    int xin = x + radius + 1; xin = xin >= w ? w - 1 : xin;
                    int io = row + xo * 4, ii = row + xin * 4;
                    s0 += src[ii] - src[io]; s1 += src[ii + 1] - src[io + 1];
                    s2 += src[ii + 2] - src[io + 2]; s3 += src[ii + 3] - src[io + 3];
                }
            }
            // vertical: dst -> dst (with src copy)
            Buffer.BlockCopy(dst, 0, src, 0, bytes);
            for (int x = 0; x < w; x++)
            {
                int col = x * 4;
                int s0 = 0, s1 = 0, s2 = 0, s3 = 0;
                for (int y = -radius; y <= radius; y++)
                {
                    int yi = y < 0 ? 0 : (y >= h ? h - 1 : y);
                    int i = yi * stride + col;
                    s0 += src[i]; s1 += src[i + 1]; s2 += src[i + 2]; s3 += src[i + 3];
                }
                for (int y = 0; y < h; y++)
                {
                    int o = y * stride + col;
                    dst[o] = (byte)(s0 / win); dst[o + 1] = (byte)(s1 / win);
                    dst[o + 2] = (byte)(s2 / win); dst[o + 3] = (byte)(s3 / win);

                    int yo = y - radius; yo = yo < 0 ? 0 : yo;
                    int yin = y + radius + 1; yin = yin >= h ? h - 1 : yin;
                    int io = yo * stride + col, ii = yin * stride + col;
                    s0 += src[ii] - src[io]; s1 += src[ii + 1] - src[io + 1];
                    s2 += src[ii + 2] - src[io + 2]; s3 += src[ii + 3] - src[io + 3];
                }
            }
        }
        Marshal.Copy(dst, 0, data.Scan0, bytes);
        bmp.UnlockBits(data);
    }

    static float MeasureTracked(Graphics g, string text, Font f, float tracking)
    {
        StringFormat sf = StringFormat.GenericTypographic;
        float w = 0f;
        foreach (char c in text) w += g.MeasureString(c.ToString(), f, new PointF(0, 0), sf).Width + tracking;
        return w;
    }

    static float DrawTracked(Graphics g, string text, Font f, Brush br, float x, float y, float tracking)
    {
        StringFormat sf = StringFormat.GenericTypographic;
        float cx = x;
        foreach (char c in text)
        {
            string s = c.ToString();
            if (c != ' ') g.DrawString(s, f, br, cx, y, sf);
            cx += g.MeasureString(s, f, new PointF(0, 0), sf).Width + tracking;
        }
        return cx - x;
    }

    // ---------- main generator ----------
    public static string Generate(int W, int H, string outPath, string hexA, string hexB,
                                  string word1, string word2, string tagline)
    {
        Color A = HC(hexA);
        Color B = HC(hexB);

        using (Bitmap bmp = new Bitmap(W, H, PixelFormat.Format32bppArgb))
        {
            using (Graphics g = Graphics.FromImage(bmp))
            {
                g.SmoothingMode = SmoothingMode.AntiAlias;
                g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                g.CompositingQuality = CompositingQuality.HighQuality;
                g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;

                Rectangle rect = new Rectangle(0, 0, W, H);

                // 1) base gradient
                using (LinearGradientBrush bg = new LinearGradientBrush(rect, HC("#0A1120"), HC("#03050A"), 66f))
                    g.FillRectangle(bg, rect);

                // 2) aurora layer (soft blurred blooms)
                using (Bitmap layer = new Bitmap(W, H, PixelFormat.Format32bppPArgb))
                {
                    using (Graphics lg = Graphics.FromImage(layer))
                    {
                        lg.SmoothingMode = SmoothingMode.AntiAlias;
                        Glow(lg, W * 0.80f, H * 0.12f, H * 0.56f, Color.FromArgb(92, A));
                        Glow(lg, W * 0.44f, H * -0.06f, H * 0.46f, Color.FromArgb(54, B));
                        Glow(lg, W * 0.04f, H * 0.94f, H * 0.44f, Color.FromArgb(34, A));
                        Glow(lg, W * 1.00f, H * 0.80f, H * 0.36f, Color.FromArgb(34, B));
                        Glow(lg, W * 0.30f, H * 0.40f, H * 0.30f, Color.FromArgb(14, B));
                    }
                    Blur(layer, 46, 3);
                    g.DrawImage(layer, 0, 0);
                }

                // 3) technical grid, softly faded away from the focal point
                using (Bitmap grid = new Bitmap(W, H, PixelFormat.Format32bppPArgb))
                {
                    using (Graphics lg = Graphics.FromImage(grid))
                    {
                        lg.SmoothingMode = SmoothingMode.None;
                        int minor = 64, major = 320;
                        for (int x = 0; x < W; x += minor)
                        {
                            int a = (x % major == 0) ? 12 : 7;
                            using (Pen pen = new Pen(Color.FromArgb(a, 255, 255, 255), 1f))
                                lg.DrawLine(pen, x + 0.5f, 0f, x + 0.5f, H);
                        }
                        for (int y = 0; y < H; y += minor)
                        {
                            int a = (y % major == 0) ? 12 : 7;
                            using (Pen pen = new Pen(Color.FromArgb(a, 255, 255, 255), 1f))
                                lg.DrawLine(pen, 0f, y + 0.5f, W, y + 0.5f);
                        }
                    }
                    BitmapData gd = grid.LockBits(rect, ImageLockMode.ReadWrite, PixelFormat.Format32bppPArgb);
                    byte[] buf = new byte[gd.Stride * H];
                    Marshal.Copy(gd.Scan0, buf, 0, buf.Length);
                    float fx = W * 0.80f, fy = H * 0.18f, fr = W * 1.02f;
                    for (int y = 0; y < H; y++)
                    {
                        int row = y * gd.Stride;
                        for (int x = 0; x < W; x++)
                        {
                            float dx = x - fx, dy = y - fy;
                            float d = (float)Math.Sqrt(dx * dx + dy * dy) / fr;
                            float f = 1f - d;
                            if (f < 0f) f = 0f;
                            f = f * f * (3f - 2f * f);
                            byte a = (byte)(buf[row + x * 4 + 3] * f);
                            int i = row + x * 4;
                            buf[i] = a; buf[i + 1] = a; buf[i + 2] = a; buf[i + 3] = a;
                        }
                    }
                    Marshal.Copy(buf, 0, gd.Scan0, buf.Length);
                    grid.UnlockBits(gd);
                    g.DrawImage(grid, 0, 0);
                }

                // 4) soft light sweep, blurred so it never shows hard edges
                using (Bitmap sweep = new Bitmap(W, H, PixelFormat.Format32bppPArgb))
                {
                    using (Graphics lg = Graphics.FromImage(sweep))
                    {
                        lg.SmoothingMode = SmoothingMode.AntiAlias;
                        Glow(lg, W * 1.02f, H * 0.10f, H * 0.52f, Color.FromArgb(30, 255, 255, 255));
                    }
                    Blur(sweep, 60, 3);
                    g.DrawImage(sweep, 0, 0);
                }

                // 5) concentric technical rings + accent arcs (top-right)
                {
                    float ccx = W * 0.875f, ccy = H * 0.145f;
                    float[] radii = { H * 0.20f, H * 0.285f, H * 0.385f, H * 0.505f };
                    int[] alphas = { 15, 13, 11, 8 };
                    for (int i = 0; i < radii.Length; i++)
                    {
                        using (Pen pen = new Pen(Color.FromArgb(alphas[i], 255, 255, 255), 1.5f))
                            g.DrawEllipse(pen, ccx - radii[i], ccy - radii[i], radii[i] * 2, radii[i] * 2);
                    }
                    using (Pen pen = new Pen(Color.FromArgb(140, A), 2.4f))
                    {
                        pen.StartCap = LineCap.Round; pen.EndCap = LineCap.Round;
                        g.DrawArc(pen, ccx - radii[1], ccy - radii[1], radii[1] * 2, radii[1] * 2, 198, 116);
                    }
                    using (Pen pen = new Pen(Color.FromArgb(80, B), 1.8f))
                    {
                        pen.StartCap = LineCap.Round; pen.EndCap = LineCap.Round;
                        g.DrawArc(pen, ccx - radii[2], ccy - radii[2], radii[2] * 2, radii[2] * 2, 24, 52);
                    }
                    using (Pen pen = new Pen(Color.FromArgb(60, A), 1.6f))
                    {
                        pen.StartCap = LineCap.Round; pen.EndCap = LineCap.Round;
                        g.DrawArc(pen, ccx - radii[3], ccy - radii[3], radii[3] * 2, radii[3] * 2, 250, 40);
                    }
                }

                // 6) accent nodes on the grid
                {
                    float[][] nodes = new float[][] {
                        new float[] { 768f, 896f }, new float[] { 1360f, 432f },
                        new float[] { 1680f, 1120f }, new float[] { 2240f, 800f }
                    };
                    foreach (float[] n in nodes)
                    {
                        using (SolidBrush sb = new SolidBrush(Color.FromArgb(130, A)))
                            g.FillEllipse(sb, n[0] - 3.4f, n[1] - 3.4f, 6.8f, 6.8f);
                        using (Pen pen = new Pen(Color.FromArgb(46, A), 1.2f))
                            g.DrawEllipse(pen, n[0] - 11f, n[1] - 11f, 22f, 22f);
                    }
                }

                // 7) corner brackets
                {
                    float inset = W * 0.026f, arm = W * 0.042f;
                    using (Pen pen = new Pen(Color.FromArgb(26, 255, 255, 255), 2f))
                    {
                        g.DrawLines(pen, new PointF[] { new PointF(inset, inset + arm), new PointF(inset, inset), new PointF(inset + arm, inset) });
                        g.DrawLines(pen, new PointF[] { new PointF(W - inset - arm, inset), new PointF(W - inset, inset), new PointF(W - inset, inset + arm) });
                        g.DrawLines(pen, new PointF[] { new PointF(inset, H - inset - arm), new PointF(inset, H - inset), new PointF(inset + arm, H - inset) });
                        g.DrawLines(pen, new PointF[] { new PointF(W - inset - arm, H - inset), new PointF(W - inset, H - inset), new PointF(W - inset, H - inset - arm) });
                    }
                }

                // 8) signature block
                {
                    float M = W * 0.075f;
                    float Bm = H * 0.090f;
                    float barY = H - Bm - 212f;
                    float barW = 120f, barH = 5f;

                    using (LinearGradientBrush lgb = new LinearGradientBrush(
                        new RectangleF(M - 1f, barY, barW + 2f, barH), A, B, 0f))
                    using (GraphicsPath p = RoundRect(M, barY, barW, barH, 2.5f))
                        g.FillPath(lgb, p);

                    float fs = H * 0.052f;
                    float tracking = fs * 0.22f;
                    float ty = barY + 40f;
                    using (Font f1 = MakeFont(fs, true))
                    using (Font f2 = MakeFont(fs, true))
                    {
                        float w1 = MeasureTracked(g, word1, f1, tracking);
                        float w2 = MeasureTracked(g, word2, f2, tracking);
                        float gap = tracking * 1.4f;
                        float total = w1 + gap + w2;

                        using (SolidBrush wb = new SolidBrush(Color.FromArgb(240, 244, 250, 255)))
                            DrawTracked(g, word1, f1, wb, M, ty, tracking);

                        RectangleF gr = new RectangleF(M + w1 + gap - 6f, ty, w2 + 12f, fs * 1.45f);
                        using (LinearGradientBrush gb = new LinearGradientBrush(gr, A, B, 0f))
                            DrawTracked(g, word2, f2, gb, M + w1 + gap, ty, tracking);

                        // divider
                        float divY = ty + fs * 1.62f;
                        float divW = Math.Min(total, W * 0.40f);
                        using (LinearGradientBrush db = new LinearGradientBrush(
                            new RectangleF(M, divY, divW, 2f), Color.FromArgb(72, 255, 255, 255), Color.FromArgb(0, 255, 255, 255), 0f))
                            g.FillRectangle(db, M, divY, divW, 2f);

                        // tagline
                        float ts = H * 0.0173f;
                        using (Font f3 = MakeFont(ts, false))
                        using (SolidBrush tb = new SolidBrush(Color.FromArgb(128, 214, 226, 240)))
                            DrawTracked(g, tagline, f3, tb, M, divY + 27f, ts * 0.34f);
                    }
                }

                // 9) cinematic grain
                using (Bitmap grain = new Bitmap(W, H, PixelFormat.Format32bppPArgb))
                {
                    BitmapData nd = grain.LockBits(rect, ImageLockMode.WriteOnly, PixelFormat.Format32bppPArgb);
                    byte[] nb = new byte[nd.Stride * H];
                    Random rnd = new Random(20261021);
                    for (int i = 0; i < nb.Length; i += 4)
                    {
                        byte v = (byte)rnd.Next(0, 10);
                        nb[i] = v; nb[i + 1] = v; nb[i + 2] = v; nb[i + 3] = v;
                    }
                    Marshal.Copy(nb, 0, nd.Scan0, nb.Length);
                    grain.UnlockBits(nd);
                    g.DrawImage(grain, 0, 0);
                }

                // 10) vignette
                {
                    GraphicsPath path = new GraphicsPath();
                    float r = H * 1.18f;
                    path.AddEllipse(W * 0.5f - r, H * 0.47f - r, r * 2, r * 2);
                    PathGradientBrush pgb = new PathGradientBrush(path);
                    pgb.CenterColor = Color.FromArgb(0, 0, 0, 0);
                    pgb.SurroundColors = new Color[] { Color.FromArgb(135, 0, 0, 0) };
                    g.FillPath(pgb, path);
                    pgb.Dispose();
                    path.Dispose();
                }
            }
            bmp.Save(outPath, ImageFormat.Png);
        }
        return outPath;
    }

    // ---------- contact sheet for comparing variants ----------
    public static string ContactSheet(string[] files, string[] labels, int tileW, int tileH, int gap, string outPath)
    {
        int cols = 2;
        int rows = (files.Length + 1) / 2;
        int W = cols * tileW + (cols + 1) * gap;
        int H = rows * tileH + (rows + 1) * gap;

        using (Bitmap bmp = new Bitmap(W, H, PixelFormat.Format32bppArgb))
        {
            using (Graphics g = Graphics.FromImage(bmp))
            {
                g.SmoothingMode = SmoothingMode.AntiAlias;
                g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
                g.Clear(HC("#06080D"));

                using (Font lf = MakeFont(19f, false))
                for (int i = 0; i < files.Length; i++)
                {
                    int cx = i % cols, cy = i / cols;
                    int x = gap + cx * (tileW + gap), y = gap + cy * (tileH + gap);
                    using (Image img = Image.FromFile(files[i]))
                        g.DrawImage(img, new Rectangle(x, y, tileW, tileH));
                    using (Pen pen = new Pen(Color.FromArgb(34, 255, 255, 255), 1f))
                        g.DrawRectangle(pen, x, y, tileW - 1, tileH - 1);

                    float tw = MeasureTracked(g, labels[i], lf, 1.1f);
                    using (GraphicsPath pill = RoundRect(x + 20f, y + 20f, tw + 30f, 36f, 18f))
                    using (SolidBrush pb = new SolidBrush(Color.FromArgb(160, 4, 6, 10)))
                        g.FillPath(pb, pill);
                    using (SolidBrush tb = new SolidBrush(Color.FromArgb(232, 255, 255, 255)))
                        DrawTracked(g, labels[i], lf, tb, x + 35f, y + 28f, 1.1f);
                }
            }
            bmp.Save(outPath, ImageFormat.Png);
        }
        return outPath;
    }
}
'@

Add-Type -TypeDefinition $csharp -ReferencedAssemblies 'System.Drawing'

if (-not (Test-Path -LiteralPath $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }

function Set-Wallpaper([string]$path) {
    Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name Wallpaper -Value $path
    Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name WallpaperStyle -Value '10' -Type String
    Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name TileWallpaper -Value '0' -Type String
    Add-Type -Namespace Win32 -Name WallApi -MemberDefinition '[DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Unicode)] public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);'
    return ([Win32.WallApi]::SystemParametersInfo(20, 0, $path, 3) -eq 1)
}

$variantSets = @(
    @{ n = 'blue';    a = '#5B8DEF'; b = '#22D3EE' },
    @{ n = 'violet';  a = '#8B6CF6'; b = '#F472B6' },
    @{ n = 'gold';    a = '#E2B15C'; b = '#F7D98F' },
    @{ n = 'emerald'; a = '#10B981'; b = '#22D3EE' }
)

if ($All) {
    $paths = @(); $labels = @()
    foreach ($v in $variantSets) {
        $p = Join-Path $OutDir ("unlock-digital-{0}.png" -f $v.n)
        [ProWallpaper]::Generate($Width, $Height, $p, $v.a, $v.b, $Word1, $Word2, $Tagline) | Out-Null
        $paths += $p
        $labels += ("{0}  ·  {1} -> {2}" -f $v.n.ToUpper(), $v.a, $v.b)
        Write-Output "generated: $p"
    }
    $sheet = Join-Path $OutDir 'variants-preview.png'
    [ProWallpaper]::ContactSheet($paths, $labels, 960, 540, 56, $sheet) | Out-Null
    Write-Output "contact sheet: $sheet"
    $target = $paths[0]
} else {
    $target = Join-Path $OutDir ("unlock-digital-{0}.png" -f $Name)
    [ProWallpaper]::Generate($Width, $Height, $target, $Accent, $Accent2, $Word1, $Word2, $Tagline) | Out-Null
    Write-Output "generated: $target"
}

if ($Apply) {
    $ok = Set-Wallpaper $target
    Write-Output "wallpaper applied = $ok  ($target)"
} else {
    Write-Output "(not applied — use -Apply to set it as the desktop wallpaper)"
}
