# Renders the "DOOM RUNNER" logo (src/graphics/RLOGOHI.png, 3x resolution of 200x62 menu units).
# Run once with Windows PowerShell; build.py only packs the result.
Add-Type -AssemblyName System.Drawing
$root = Split-Path -Parent $PSScriptRoot
$W = 600; $H = 186
$bmp = New-Object System.Drawing.Bitmap $W, $H, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = 'AntiAlias'; $g.InterpolationMode = 'HighQualityBicubic'; $g.PixelOffsetMode = 'HighQuality'
$g.Clear([System.Drawing.Color]::Transparent)
$ff = New-Object System.Drawing.FontFamily 'Impact'
$fmt = New-Object System.Drawing.StringFormat
$fmt.Alignment = 'Center'

function TextPath($text, $size, $cx, $top, $sx, $skew, $spacing) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $x = 0.0
    $widths = @()
    foreach ($ch in $text.ToCharArray()) {
        $q = New-Object System.Drawing.Drawing2D.GraphicsPath
        $q.AddString([string]$ch, $ff, 0, $size, (New-Object System.Drawing.PointF 0, 0), [System.Drawing.StringFormat]::GenericTypographic)
        $b = $q.GetBounds()
        $m = New-Object System.Drawing.Drawing2D.Matrix
        $m.Translate($x - $b.X, 0)
        $q.Transform($m)
        $p.AddPath($q, $false)
        $x += $b.Width + $spacing
    }
    $b = $p.GetBounds()
    $m = New-Object System.Drawing.Drawing2D.Matrix
    $m.Translate($cx, $top)
    $m.Shear($skew, 0)
    $m.Scale($sx, 1.0)
    $m.Translate(-($b.X + $b.Width / 2), -$b.Y)
    $p.Transform($m)
    return $p
}

function Paint($path, $c1, $c2, $c3, $outline, $ow) {
    $b = $path.GetBounds()
    # drop shadow
    $sh = $path.Clone()
    $m = New-Object System.Drawing.Drawing2D.Matrix; $m.Translate(5, 7); $sh.Transform($m)
    $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(170, 0, 0, 0)), ($ow + 4)
    $pen.LineJoin = 'Round'
    $g.DrawPath($pen, $sh); $g.FillPath((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(170, 0, 0, 0))), $sh)
    # outline
    $pen = New-Object System.Drawing.Pen $outline, $ow
    $pen.LineJoin = 'Miter'
    $g.DrawPath($pen, $path)
    # gradient fill
    $r = New-Object System.Drawing.RectangleF $b.X, ($b.Y - 1), $b.Width, ($b.Height + 2)
    $br = New-Object System.Drawing.Drawing2D.LinearGradientBrush $r, $c1, $c3, 90.0
    $blend = New-Object System.Drawing.Drawing2D.ColorBlend 3
    $blend.Colors = @($c1, $c2, $c3); $blend.Positions = @(0.0, 0.48, 1.0)
    $br.InterpolationColors = $blend
    $g.FillPath($br, $path)
    # bevel highlight on the upper edge
    $hl = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(120, 255, 255, 220)), 2
    $g.SetClip($path)
    $up = $path.Clone(); $m = New-Object System.Drawing.Drawing2D.Matrix; $m.Translate(0, 3); $up.Transform($m)
    $g.DrawPath($hl, $up)
    $g.ResetClip()
}

$C = [System.Drawing.Color]
# speed streaks behind RUNNER
for ($i = 0; $i -lt 7; $i++) {
    $y = 140 + $i * 6
    $len = 60 + (($i * 37) % 70)
    $br = New-Object System.Drawing.Drawing2D.LinearGradientBrush (New-Object System.Drawing.PointF 0, 0), (New-Object System.Drawing.PointF ($len + 1), 0), $C::FromArgb(0, 255, 120, 20), $C::FromArgb(220, 255, 170, 40)
    $g.FillRectangle($br, (40 + (($i * 53) % 40)), $y, $len, 3)
    $g.FillRectangle($br, ($W - 40 - $len - (($i * 29) % 40)), $y, $len, 3)
}

$doom = TextPath 'DOOM' 128 ($W / 2) 4 1.32 0 6
Paint $doom $C::FromArgb(255, 255, 236, 120) $C::FromArgb(255, 246, 128, 22) $C::FromArgb(255, 120, 12, 4) $C::FromArgb(255, 48, 6, 0) 9

$run = TextPath 'RUNNER' 58 ($W / 2 - 6) 126 1.0 -0.22 7
Paint $run $C::FromArgb(255, 250, 250, 250) $C::FromArgb(255, 170, 170, 176) $C::FromArgb(255, 70, 70, 80) $C::FromArgb(255, 140, 14, 4) 7

$g.Dispose()
$bmp.Save((Join-Path $root 'src\graphics\RLOGOHI.png'), [System.Drawing.Imaging.ImageFormat]::Png)
"logo written"
