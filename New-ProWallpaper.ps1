# Generates a clean, professional dark wallpaper.
# Usage: powershell -ExecutionPolicy Bypass -File New-ProWallpaper.ps1 [-Width 2560] [-Height 1440] [-Name "ESLAM ASHRAF"] [-Out "path.png"]

param(
    [int]$Width = 2560,
    [int]$Height = 1440,
    [string]$Name = "ESLAM ASHRAF",
    [string]$Out = "$([Environment]::GetFolderPath('MyPictures'))\Wallpapers\eslam-pro-dark.png"
)

Add-Type -AssemblyName System.Drawing

$dir = Split-Path -Parent $Out
if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

$bmp = New-Object System.Drawing.Bitmap($Width, $Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

$rect = New-Object System.Drawing.Rectangle(0, 0, $Width, $Height)

function Add-Glow([System.Drawing.Graphics]$g, [int]$cx, [int]$cy, [int]$radius, [System.Drawing.Color]$color) {
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddEllipse($cx - $radius, $cy - $radius, $radius * 2, $radius * 2)
    $pgb = New-Object System.Drawing.Drawing2D.PathGradientBrush($path)
    $pgb.CenterColor = $color
    $pgb.SurroundColors = @([System.Drawing.Color]::FromArgb(0, $color.R, $color.G, $color.B))
    $g.FillPath($pgb, $path)
    $pgb.Dispose(); $path.Dispose()
}

function Draw-TrackedText([System.Drawing.Graphics]$g, [string]$text, [float]$x, [float]$y, [System.Drawing.Font]$font, [System.Drawing.Brush]$brush, [float]$tracking) {
    $sf = [System.Drawing.StringFormat]::GenericTypographic
    $cx = $x
    foreach ($ch in $text.ToCharArray()) {
        $s = [string]$ch
        if ($s -ne ' ') { $g.DrawString($s, $font, $brush, $cx, $y, $sf) }
        $cx += $g.MeasureString($s, $font, [System.Drawing.PointF]::new(0, 0), $sf).Width + $tracking
    }
}

# 1) Base diagonal gradient
$c1 = [System.Drawing.Color]::FromArgb(255, 12, 18, 30)   # deep navy
$c2 = [System.Drawing.Color]::FromArgb(255, 5, 7, 12)     # near black
$bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $c1, $c2, 62.0)
$g.FillRectangle($bg, $rect)
$bg.Dispose()

# 2) Soft blue "bloom" glows
Add-Glow $g ([int]($Width * 0.74)) ([int]($Height * 0.24)) ([int]($Height * 0.62)) ([System.Drawing.Color]::FromArgb(46, 59, 130, 246))
Add-Glow $g ([int]($Width * 0.18)) ([int]($Height * 0.86)) ([int]($Height * 0.45)) ([System.Drawing.Color]::FromArgb(26, 34, 211, 238))

# 3) Faint technical grid
$gridPen  = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(7, 255, 255, 255)), 1
$gridPen2 = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(11, 255, 255, 255)), 1
$step = 80
for ($x = 0; $x -lt $Width; $x += $step) {
    if (($x % ($step * 5)) -eq 0) { $g.DrawLine($gridPen2, $x, 0, $x, $Height) } else { $g.DrawLine($gridPen, $x, 0, $x, $Height) }
}
for ($y = 0; $y -lt $Height; $y += $step) {
    if (($y % ($step * 5)) -eq 0) { $g.DrawLine($gridPen2, 0, $y, $Width, $y) } else { $g.DrawLine($gridPen, 0, $y, $Width, $y) }
}
$gridPen.Dispose(); $gridPen2.Dispose()

# 4) Vignette (darken edges)
$topH  = [int]($Height * 0.30)
$sideW = [int]($Width * 0.22)
$dark  = [System.Drawing.Color]::FromArgb(130, 0, 0, 0)
$clear = [System.Drawing.Color]::FromArgb(0, 0, 0, 0)
$sides = @(
    @{ r = [System.Drawing.Rectangle]::new(0, 0, $Width, $topH);                         a = [single]90  },
    @{ r = [System.Drawing.Rectangle]::new(0, ($Height - $topH), $Width, $topH);         a = [single]270 },
    @{ r = [System.Drawing.Rectangle]::new(0, 0, $sideW, $Height);                        a = [single]0   },
    @{ r = [System.Drawing.Rectangle]::new(($Width - $sideW), 0, $sideW, $Height);        a = [single]180 }
)
foreach ($s in $sides) {
    $brush = [System.Drawing.Drawing2D.LinearGradientBrush]::new($s.r, $dark, $clear, $s.a)
    $g.FillRectangle($brush, $s.r)
    $brush.Dispose()
}

# 5) Signature block: accent bar + name
$margin   = [int]($Width * 0.072)
$fontSize = [int]($Height * 0.040)
$accentW  = [int]($Width * 0.040)
$accentH  = [int]($Height * 0.0034) + 3
$accentY  = $Height - $margin - [int]($Height * 0.115)

$accentBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    (New-Object System.Drawing.Rectangle($margin, $accentY, $accentW, $accentH)),
    ([System.Drawing.Color]::FromArgb(255, 96, 165, 250)),
    ([System.Drawing.Color]::FromArgb(255, 34, 211, 238)),
    [System.Drawing.Drawing2D.LinearGradientMode]::Horizontal)
$g.FillRectangle($accentBrush, $margin, $accentY, $accentW, $accentH)
$accentBrush.Dispose()

$family = 'Segoe UI Semibold'
try { $font = New-Object System.Drawing.Font($family, $fontSize, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel) }
catch { $font = New-Object System.Drawing.Font('Segoe UI', $fontSize, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel) }

$nameBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(232, 232, 238, 246))
Draw-TrackedText $g $Name ([float]$margin) ([float]($accentY + [int]($Height * 0.035))) $font $nameBrush ([float]([int]($Height * 0.012)))

# 6) Save
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Write-Output "Saved: $Out  ($Width x $Height)"
