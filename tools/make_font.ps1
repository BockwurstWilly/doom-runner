# Renders Doom Runner's own big font (src/fonts/rrbig/XXXX.png, one PNG per character, 2x size).
# Used instead of the IWAD's BigFont when that lacks glyphs (e.g. Freedoom). Run once with PowerShell.
Add-Type -AssemblyName System.Drawing
$root = Split-Path -Parent $PSScriptRoot
$dir = Join-Path $root 'src\fonts\rrbig'
New-Item -ItemType Directory -Force $dir | Out-Null
Get-ChildItem $dir -Filter *.png | Remove-Item
$ff = New-Object System.Drawing.FontFamily 'Impact'
$H = 32          # cell height at 2x
$size = 30.0
$chars = @()
for ($c = 33; $c -le 126; $c++) { $chars += [char]$c }
$chars += [char]0xC4, [char]0xD6, [char]0xDC, [char]0xE4, [char]0xF6, [char]0xFC, [char]0xDF, [char]0xB7, [char]0x2019
$fmt = [System.Drawing.StringFormat]::GenericTypographic
foreach ($ch in $chars) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $p.AddString([string]$ch, $ff, 0, $size, (New-Object System.Drawing.PointF 0, 0), $fmt)
    $b = $p.GetBounds()
    if ($b.Width -le 0) { continue }
    $w = [int][Math]::Ceiling($b.Width * 1.12) + 6
    $bmp = New-Object System.Drawing.Bitmap $w, $H, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.Clear([System.Drawing.Color]::Transparent)
    $m = New-Object System.Drawing.Drawing2D.Matrix
    $m.Translate(3 - $b.X * 1.12, 0)
    $m.Scale(1.12, 1.0)
    $p.Transform($m)
    # dark outline, then a light-to-mid grey fill (font colour translations recolour the greys)
    $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 10, 10, 10)), 4
    $pen.LineJoin = 'Round'
    $g.DrawPath($pen, $p)
    $r = New-Object System.Drawing.RectangleF 0, 2, $w, ($H - 4)
    $br = New-Object System.Drawing.Drawing2D.LinearGradientBrush $r, ([System.Drawing.Color]::FromArgb(255, 255, 255, 255)), ([System.Drawing.Color]::FromArgb(255, 120, 120, 120)), 90.0
    $g.FillPath($br, $p)
    $g.Dispose()
    $name = '{0:X4}.png' -f [int]$ch
    $bmp.Save((Join-Path $dir $name), [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
}
Set-Content -Path (Join-Path $dir 'font.inf') -Value "SpaceWidth 16`nScale 2`nTranslationType console" -Encoding ascii
"font written: $((Get-ChildItem $dir -Filter *.png).Count) glyphs"
