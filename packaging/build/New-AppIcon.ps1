# Renders the UNLOCK DIGITAL app icon (PNG + ICO with a 256x256 frame)
param(
    [Parameter(Mandatory = $true)][string]$Png,
    [Parameter(Mandatory = $true)][string]$Ico
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

function New-RoundedPath([int]$w, [int]$h, [int]$r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $r * 2
    $p.AddArc(0, 0, $d, $d, 180, 90)
    $p.AddArc($w - $d, 0, $d, $d, 270, 90)
    $p.AddArc($w - $d, $h - $d, $d, $d, 0, 90)
    $p.AddArc(0, $h - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}

$s = 256
$bmp = New-Object System.Drawing.Bitmap($s, $s, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
$g.Clear([System.Drawing.Color]::Transparent)

$path = New-RoundedPath $s $s 54
$bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    (New-Object System.Drawing.Point(0, 0)),
    (New-Object System.Drawing.Point($s, $s)),
    [System.Drawing.Color]::FromArgb(255, 15, 23, 40),
    [System.Drawing.Color]::FromArgb(255, 4, 7, 14))
$g.FillPath($bg, $path)

$g.SetClip($path)
$acc = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    (New-Object System.Drawing.Point(0, 0)),
    (New-Object System.Drawing.Point($s, 0)),
    [System.Drawing.Color]::FromArgb(255, 76, 194, 255),
    [System.Drawing.Color]::FromArgb(255, 139, 92, 246))
$cb = New-Object System.Drawing.Drawing2D.ColorBlend(3)
$cb.Colors = [System.Drawing.Color[]]@(
    [System.Drawing.Color]::FromArgb(255, 76, 194, 255),
    [System.Drawing.Color]::FromArgb(255, 139, 92, 246),
    [System.Drawing.Color]::FromArgb(255, 52, 211, 153))
$cb.Positions = [single[]]@(0.0, 0.55, 1.0)
$acc.InterpolationColors = $cb
$g.FillRectangle($acc, 0, 0, $s, 11)
$g.ResetClip()

$pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(46, 255, 255, 255), 3)
$g.DrawPath($pen, $path)

$font = New-Object System.Drawing.Font('Segoe UI', 88, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
$sf = New-Object System.Drawing.StringFormat
$sf.Alignment = [System.Drawing.StringAlignment]::Center
$sf.LineAlignment = [System.Drawing.StringAlignment]::Center
$rect = New-Object System.Drawing.RectangleF(0, 12, $s, $s)
$g.DrawString('UD', $font, [System.Drawing.Brushes]::White, $rect, $sf)

$bmp.Save($Png, [System.Drawing.Imaging.ImageFormat]::Png)

# --- write a classic 32bpp ICO (BITMAPINFOHEADER + BGRA + AND mask) ---
$bd = $bmp.LockBits((New-Object System.Drawing.Rectangle(0, 0, $s, $s)), [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$stride = $bd.Stride
$pixels = New-Object byte[] ($stride * $s)
[System.Runtime.InteropServices.Marshal]::Copy($bd.Scan0, $pixels, 0, $pixels.Length)
$bmp.UnlockBits($bd)

$xorSize = $stride * $s
$andSize = [int]([math]::Ceiling($s / 8.0)) * $s
$imgSize = 40 + $xorSize + $andSize

$ms = New-Object System.IO.MemoryStream
$bw = New-Object System.IO.BinaryWriter($ms)
$bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]1)
$bw.Write([byte]0); $bw.Write([byte]0); $bw.Write([byte]0); $bw.Write([byte]0)
$bw.Write([uint16]1); $bw.Write([uint16]32)
$bw.Write([uint32]$imgSize); $bw.Write([uint32]22)
$bw.Write([uint32]40); $bw.Write([int32]$s); $bw.Write([int32]($s * 2))
$bw.Write([uint16]1); $bw.Write([uint16]32)
$bw.Write([uint32]0); $bw.Write([uint32]0)
$bw.Write([int32]0); $bw.Write([int32]0)
$bw.Write([uint32]0); $bw.Write([uint32]0)
for ($y = $s - 1; $y -ge 0; $y--) { $bw.Write($pixels, $y * $stride, $stride) }
$bw.Write((New-Object byte[] $andSize), 0, $andSize)
$bw.Flush()
[System.IO.File]::WriteAllBytes($Ico, $ms.ToArray())

$g.Dispose(); $bmp.Dispose()
Write-Output "icon written: $Ico"
