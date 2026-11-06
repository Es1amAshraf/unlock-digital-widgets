# New-Win11Wallpaper.ps1 — premium dark wallpaper with the Windows 11 mark integrated
# into the composition (watermark + licensing badge) for UNLOCK DIGITAL branding.
#
# Examples:
#   powershell -File .\New-Win11Wallpaper.ps1 -All -Apply     # 4 variants + apply the first
#   powershell -File .\New-Win11Wallpaper.ps1 -Accent "#5B8DEF" -Accent2 "#22D3EE" -Name azure -Apply
#   powershell -File .\New-Win11Wallpaper.ps1 -Badge "WINDOWS 11 PRO" -Tagline "IT SOLUTIONS & LICENSING"

param(
    [int]$Width = 1920,
    [int]$Height = 1080,
    [string]$Word1 = "UNLOCK",
    [string]$Word2 = "DIGITAL",
    [string]$Tagline = "IT SOLUTIONS & LICENSING",
    [string]$Badge = "WINDOWS 11 PRO",
    [string]$OutDir = "$([Environment]::GetFolderPath('MyPictures'))\Wallpapers",
    [string]$Accent = "#5B8DEF",
    [string]$Accent2 = "#22D3EE",
    [string]$Name = "azure",
    [double]$SigLift = 0.092,
    [switch]$NoBadge,
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

public static class Win11Wall
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
        r = Math.Min(r, Math.Min(w, h) / 2f);
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

    // ---------- the Windows 11 mark: four rounded panes ----------
    static void WinMark(Graphics g, float x, float y, float size, float gapRatio, float radiusRatio, Brush br)
    {
        float gap = size * gapRatio;
        float s = (size - gap) / 2f;
        float r = s * radiusRatio;
        using (GraphicsPath p = RoundRect(x, y, s, s, r)) g.FillPath(br, p);
        using (GraphicsPath p = RoundRect(x + s + gap, y, s, s, r)) g.FillPath(br, p);
        using (GraphicsPath p = RoundRect(x, y + s + gap, s, s, r)) g.FillPath(br, p);
        using (GraphicsPath p = RoundRect(x + s + gap, y + s + gap, s, s, r)) g.FillPath(br, p);
    }

    static void WinMarkOutline(Graphics g, float x, float y, float size, float gapRatio, float radiusRatio, Pen pen)
    {
        float gap = size * gapRatio;
        float s = (size - gap) / 2f;
        float r = s * radiusRatio;
        using (GraphicsPath p = RoundRect(x, y, s, s, r)) g.DrawPath(pen, p);
        using (GraphicsPath p = RoundRect(x + s + gap, y, s, s, r)) g.DrawPath(pen, p);
        using (GraphicsPath p = RoundRect(x, y + s + gap, s, s, r)) g.DrawPath(pen, p);
        using (GraphicsPath p = RoundRect(x + s + gap, y + s + gap, s, s, r)) g.DrawPath(pen, p);
    }

    // ---------- main generator ----------
    public static string Generate(int W, int H, string outPath, string hexA, string hexB,
                                  string word1, string word2, string tagline, string badge, double sigLift)
    {
        Color A = HC(hexA);
        Color B = HC(hexB);
        Color WIN1 = HC("#3AA9F5");
        Color WIN2 = HC("#0B63CE");
        float k = H / 1440f;

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

                // 1) deep four-stop base gradient (diagonal, cooler at the top)
                {
                    using (LinearGradientBrush bg = new LinearGradientBrush(rect, HC("#0C1526"), HC("#04060C"), 62f))
                        g.FillRectangle(bg, rect);
                    using (LinearGradientBrush top = new LinearGradientBrush(
                        new Rectangle(0, 0, W, (int)(H * 0.62f)), Color.FromArgb(46, 28, 44, 78), Color.FromArgb(0, 4, 6, 12), 90f))
                        g.FillRectangle(top, 0, 0, W, H * 0.62f);
                }

                // 2) aurora blooms (two depths for a softer, more organic falloff)
                using (Bitmap layer = new Bitmap(W, H, PixelFormat.Format32bppPArgb))
                {
                    using (Graphics lg = Graphics.FromImage(layer))
                    {
                        lg.SmoothingMode = SmoothingMode.AntiAlias;
                        Glow(lg, W * 0.78f, H * 0.10f, H * 0.62f, Color.FromArgb(86, A));
                        Glow(lg, W * 0.46f, H * -0.08f, H * 0.44f, Color.FromArgb(48, B));
                        Glow(lg, W * 0.02f, H * 0.96f, H * 0.46f, Color.FromArgb(30, A));
                        Glow(lg, W * 1.02f, H * 0.74f, H * 0.34f, Color.FromArgb(28, B));
                    }
                    Blur(layer, (int)(50 * k), 3);
                    g.DrawImage(layer, 0, 0);
                }

                // 3) the Windows 11 mark, embedded: soft halo, then the mark itself
                float markSize = H * 0.315f;
                float markX = W * 0.640f;
                float markY = H * 0.098f;
                if (markX + markSize > W * 0.985f) { markX = W * 0.985f - markSize; }
                float mcx = markX + markSize / 2f, mcy = markY + markSize / 2f;
                float mr = markSize / 2f;

                using (Bitmap halo = new Bitmap(W, H, PixelFormat.Format32bppPArgb))
                {
                    using (Graphics lg = Graphics.FromImage(halo))
                    {
                        lg.SmoothingMode = SmoothingMode.AntiAlias;
                        using (SolidBrush hb = new SolidBrush(Color.FromArgb(104, A)))
                            WinMark(lg, markX, markY, markSize, 0.085f, 0.085f, hb);
                    }
                    Blur(halo, (int)(46 * k), 3);
                    g.DrawImage(halo, 0, 0);
                }
                using (LinearGradientBrush mb = new LinearGradientBrush(
                    new RectangleF(markX, markY, markSize, markSize), Color.FromArgb(78, WIN1), Color.FromArgb(60, WIN2), 48f))
                    WinMark(g, markX, markY, markSize, 0.085f, 0.085f, mb);
                using (Pen mp = new Pen(Color.FromArgb(44, 255, 255, 255), 1.7f * k))
                    WinMarkOutline(g, markX, markY, markSize, 0.085f, 0.085f, mp);

                // 4) technical grid + node dots, faded away from the mark (so the mark sits inside it)
                using (Bitmap grid = new Bitmap(W, H, PixelFormat.Format32bppPArgb))
                {
                    using (Graphics lg = Graphics.FromImage(grid))
                    {
                        lg.SmoothingMode = SmoothingMode.None;
                        int minor = (int)(64 * k), major = (int)(320 * k);
                        for (int x = 0; x < W; x += minor)
                        {
                            int a = (x % major == 0) ? 13 : 7;
                            using (Pen pen = new Pen(Color.FromArgb(a, 255, 255, 255), 1f))
                                lg.DrawLine(pen, x + 0.5f, 0f, x + 0.5f, H);
                        }
                        for (int y = 0; y < H; y += minor)
                        {
                            int a = (y % major == 0) ? 13 : 7;
                            using (Pen pen = new Pen(Color.FromArgb(a, 255, 255, 255), 1f))
                                lg.DrawLine(pen, 0f, y + 0.5f, W, y + 0.5f);
                        }
                        lg.SmoothingMode = SmoothingMode.AntiAlias;
                        for (int x = 0; x < W; x += major)
                            for (int y = 0; y < H; y += major)
                            {
                                using (SolidBrush db = new SolidBrush(Color.FromArgb(34, 255, 255, 255)))
                                    lg.FillEllipse(db, x - 1.9f, y - 1.9f, 3.8f, 3.8f);
                            }
                    }
                    BitmapData gd = grid.LockBits(rect, ImageLockMode.ReadWrite, PixelFormat.Format32bppPArgb);
                    byte[] buf = new byte[gd.Stride * H];
                    Marshal.Copy(gd.Scan0, buf, 0, buf.Length);
                    float fx = mcx, fy = mcy, fr = W * 1.04f;
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

                // 5) soft light sweep from the top-right
                using (Bitmap sweep = new Bitmap(W, H, PixelFormat.Format32bppPArgb))
                {
                    using (Graphics lg = Graphics.FromImage(sweep))
                    {
                        lg.SmoothingMode = SmoothingMode.AntiAlias;
                        Glow(lg, W * 1.02f, H * 0.08f, H * 0.56f, Color.FromArgb(28, 255, 255, 255));
                    }
                    Blur(sweep, (int)(62 * k), 3);
                    g.DrawImage(sweep, 0, 0);
                }

                // 6) concentric rings centred on the mark + accent arcs
                {
                    float[] radii = { mr * 1.30f, mr * 1.86f, mr * 2.62f };
                    int[] alphas = { 15, 12, 9 };
                    for (int i = 0; i < radii.Length; i++)
                    {
                        using (Pen pen = new Pen(Color.FromArgb(alphas[i], 255, 255, 255), 1.5f * k))
                            g.DrawEllipse(pen, mcx - radii[i], mcy - radii[i], radii[i] * 2, radii[i] * 2);
                    }
                    using (Pen pen = new Pen(Color.FromArgb(150, A), 2.6f * k))
                    {
                        pen.StartCap = LineCap.Round; pen.EndCap = LineCap.Round;
                        g.DrawArc(pen, mcx - radii[0], mcy - radii[0], radii[0] * 2, radii[0] * 2, 196, 112);
                    }
                    using (Pen pen = new Pen(Color.FromArgb(84, B), 1.8f * k))
                    {
                        pen.StartCap = LineCap.Round; pen.EndCap = LineCap.Round;
                        g.DrawArc(pen, mcx - radii[1], mcy - radii[1], radii[1] * 2, radii[1] * 2, 28, 54);
                    }
                    using (Pen pen = new Pen(Color.FromArgb(58, A), 1.6f * k))
                    {
                        pen.StartCap = LineCap.Round; pen.EndCap = LineCap.Round;
                        g.DrawArc(pen, mcx - radii[2], mcy - radii[2], radii[2] * 2, radii[2] * 2, 244, 38);
                    }
                }

                // 7) accent nodes on the grid
                {
                    float[][] nodes = new float[][] {
                        new float[] { W * 0.285f, H * 0.640f }, new float[] { W * 0.520f, H * 0.300f },
                        new float[] { W * 0.185f, H * 0.855f }, new float[] { W * 0.760f, H * 0.780f }
                    };
                    foreach (float[] n in nodes)
                    {
                        using (SolidBrush sb = new SolidBrush(Color.FromArgb(130, A)))
                            g.FillEllipse(sb, n[0] - 3.4f * k, n[1] - 3.4f * k, 6.8f * k, 6.8f * k);
                        using (Pen pen = new Pen(Color.FromArgb(44, A), 1.2f * k))
                            g.DrawEllipse(pen, n[0] - 11f * k, n[1] - 11f * k, 22f * k, 22f * k);
                    }
                }

                // 8) corner brackets
                {
                    float inset = W * 0.026f, arm = W * 0.042f;
                    using (Pen pen = new Pen(Color.FromArgb(26, 255, 255, 255), 2f * k))
                    {
                        g.DrawLines(pen, new PointF[] { new PointF(inset, inset + arm), new PointF(inset, inset), new PointF(inset + arm, inset) });
                        g.DrawLines(pen, new PointF[] { new PointF(W - inset - arm, inset), new PointF(W - inset, inset), new PointF(W - inset, inset + arm) });
                        g.DrawLines(pen, new PointF[] { new PointF(inset, H - inset - arm), new PointF(inset, H - inset), new PointF(inset + arm, H - inset) });
                        g.DrawLines(pen, new PointF[] { new PointF(W - inset - arm, H - inset), new PointF(W - inset, H - inset), new PointF(W - inset, H - inset - arm) });
                    }
                }

                float M = W * 0.075f;
                float Bm = H * 0.090f;

                // 9) signature block (bottom-left)
                {
                    float barY = H - Bm - 212f * k - (float)(H * sigLift);
                    float barW = 120f * k, barH = 5f * k;

                    using (LinearGradientBrush lgb = new LinearGradientBrush(
                        new RectangleF(M - 1f, barY, barW + 2f, barH), A, B, 0f))
                    using (GraphicsPath p = RoundRect(M, barY, barW, barH, 2.5f))
                        g.FillPath(lgb, p);

                    float fs = H * 0.052f;
                    float tracking = fs * 0.22f;
                    float ty = barY + 40f * k;
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

                        float divY = ty + fs * 1.62f;
                        float divW = Math.Min(total, W * 0.40f);
                        using (LinearGradientBrush db = new LinearGradientBrush(
                            new RectangleF(M, divY, divW, 2f), Color.FromArgb(72, 255, 255, 255), Color.FromArgb(0, 255, 255, 255), 0f))
                            g.FillRectangle(db, M, divY, divW, 2f);

                        float ts = H * 0.0173f;
                        using (Font f3 = MakeFont(ts, false))
                        using (SolidBrush tb = new SolidBrush(Color.FromArgb(134, 214, 226, 240)))
                            DrawTracked(g, tagline, f3, tb, M, divY + 27f * k, ts * 0.34f);
                    }
                }

                // 10) windows 11 licence badge (bottom-right) — optional
                if (!string.IsNullOrEmpty(badge))
                {
                    float bs = 34f * k;
                    float ts = 17f * k;
                    float pad = 18f * k;
                    using (Font bf = MakeFont(ts, false))
                    {
                        float track = ts * 0.20f;
                        float tw = MeasureTracked(g, badge, bf, track);
                        float bw = pad + bs + 13f * k + tw + pad;
                        float bh = bs + 24f * k;
                        float bx = W - M - bw;
                        float by = H - Bm - bh + 42f * k;
                        using (GraphicsPath pp = RoundRect(bx, by, bw, bh, bh / 2f))
                        {
                            using (SolidBrush pb = new SolidBrush(Color.FromArgb(18, 255, 255, 255)))
                                g.FillPath(pb, pp);
                            using (Pen bp = new Pen(Color.FromArgb(30, 255, 255, 255), 1f))
                                g.DrawPath(bp, pp);
                        }
                        float mx = bx + pad, my = by + (bh - bs) / 2f;
                        using (LinearGradientBrush mb2 = new LinearGradientBrush(
                            new RectangleF(mx, my, bs, bs), WIN1, WIN2, 55f))
                            WinMark(g, mx, my, bs, 0.09f, 0.085f, mb2);
                        using (SolidBrush tb = new SolidBrush(Color.FromArgb(198, 226, 236, 248)))
                            DrawTracked(g, badge, bf, tb, mx + bs + 12f * k, by + (bh - ts * 1.42f) / 2f + 0.5f, track);
                    }
                }

                // 11) cinematic grain
                using (Bitmap grain = new Bitmap(W, H, PixelFormat.Format32bppPArgb))
                {
                    BitmapData nd = grain.LockBits(rect, ImageLockMode.WriteOnly, PixelFormat.Format32bppPArgb);
                    byte[] nb = new byte[nd.Stride * H];
                    Random rnd = new Random(20261021);
                    for (int i = 0; i < nb.Length; i += 4)
                    {
                        byte v = (byte)rnd.Next(0, 9);
                        nb[i] = v; nb[i + 1] = v; nb[i + 2] = v; nb[i + 3] = v;
                    }
                    Marshal.Copy(nb, 0, nd.Scan0, nb.Length);
                    grain.UnlockBits(nd);
                    g.DrawImage(grain, 0, 0);
                }

                // 12) vignette
                {
                    GraphicsPath path = new GraphicsPath();
                    float r = H * 1.16f;
                    path.AddEllipse(W * 0.5f - r, H * 0.46f - r, r * 2, r * 2);
                    PathGradientBrush pgb = new PathGradientBrush(path);
                    pgb.CenterColor = Color.FromArgb(0, 0, 0, 0);
                    pgb.SurroundColors = new Color[] { Color.FromArgb(132, 0, 0, 0) };
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
    Add-Type -Namespace Win32 -Name WallApi2 -MemberDefinition '[DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Unicode)] public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);' -ErrorAction SilentlyContinue
    return ([Win32.WallApi2]::SystemParametersInfo(20, 0, $path, 3) -eq 1)
}

$variantSets = @(
    @{ n = 'azure';   a = '#5B8DEF'; b = '#22D3EE' },
    @{ n = 'violet';  a = '#8B6CF6'; b = '#F472B6' },
    @{ n = 'gold';    a = '#E2B15C'; b = '#F7D98F' },
    @{ n = 'emerald'; a = '#10B981'; b = '#22D3EE' }
)

$badgeText = $(if ($NoBadge) { '' } else { $Badge })

if ($All) {
    $paths = @(); $labels = @()
    foreach ($v in $variantSets) {
        $p = Join-Path $OutDir ("win11-{0}.png" -f $v.n)
        [Win11Wall]::Generate($Width, $Height, $p, $v.a, $v.b, $Word1, $Word2, $Tagline, $badgeText, $SigLift) | Out-Null
        $paths += $p
        $labels += ("{0}  ·  {1} -> {2}" -f $v.n.ToUpper(), $v.a, $v.b)
        Write-Output "generated: $p"
    }
    $sheet = Join-Path $OutDir 'win11-preview.png'
    [Win11Wall]::ContactSheet($paths, $labels, 860, 484, 52, $sheet) | Out-Null
    Write-Output "contact sheet: $sheet"
    $target = $paths[0]
} else {
    $target = Join-Path $OutDir ("win11-{0}.png" -f $Name)
    [Win11Wall]::Generate($Width, $Height, $target, $Accent, $Accent2, $Word1, $Word2, $Tagline, $badgeText, $SigLift) | Out-Null
    Write-Output "generated: $target"
}

if ($Apply) {
    $ok = Set-Wallpaper $target
    Write-Output "wallpaper applied = $ok  ($target)"
} else {
    Write-Output "(not applied — use -Apply to set it as the desktop wallpaper)"
}
