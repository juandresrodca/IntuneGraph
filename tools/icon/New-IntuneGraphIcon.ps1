<#
    Draws the module icon the PowerShell Gallery listing shows (the manifest's IconUri).
    Run: .\tools\icon\New-IntuneGraphIcon.ps1   (writes docs\img\icon.png)

    Windows only: it uses System.Drawing, which ships with Windows PowerShell, so the
    icon needs no package install. Colours are the node palette from the HTML viewer,
    and the two bright edges are the "via" path - device -> group -> policy - which is
    the one thing this tool shows that a flat list does not.
#>
[CmdletBinding()]
param(
    [string]$OutputPath,
    [int]$Size = 256
)
$ErrorActionPreference = 'Stop'
# Resolved here rather than as a parameter default: Windows PowerShell leaves
# $PSScriptRoot empty in parameter defaults when the script is started with -File.
if (-not $OutputPath) { $OutputPath = Join-Path $PSScriptRoot '..\..\docs\img\icon.png' }
Add-Type -AssemblyName System.Drawing

function New-IgColor([string]$Hex) { [System.Drawing.ColorTranslator]::FromHtml($Hex) }

$s = $Size / 256.0   # drawn on a 256 grid, scaled to $Size
$bmp = New-Object System.Drawing.Bitmap $Size, $Size
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.Clear([System.Drawing.Color]::Transparent)

# Rounded-square tile, inset so the border stroke is not clipped.
$inset = 3 * $s; $d = 2 * 52 * $s; $far = $Size - $inset - $d
$tile = New-Object System.Drawing.Drawing2D.GraphicsPath
$tile.AddArc($inset, $inset, $d, $d, 180, 90)
$tile.AddArc($far, $inset, $d, $d, 270, 90)
$tile.AddArc($far, $far, $d, $d, 0, 90)
$tile.AddArc($inset, $far, $d, $d, 90, 90)
$tile.CloseFigure()
$bg = New-IgColor '#0d1320'
$g.FillPath((New-Object System.Drawing.SolidBrush $bg), $tile)
$g.DrawPath((New-Object System.Drawing.Pen (New-IgColor '#27395a'), (4 * $s)), $tile)

# x, y, radius, colour - group hub in the middle, one of each workload kind around it.
$nodes = [ordered]@{
    group  = @(128, 128, 30, '#9fef00')
    config = @(194,  64, 19, '#ffb454')
    device = @(196, 192, 19, '#58a6ff')
    user   = @( 60, 192, 19, '#c792ea')
    app    = @( 62,  64, 19, '#ff7b72')
}
$edges = @(
    @('app', 'group', '#34496e'),
    @('user', 'group', '#34496e'),
    @('device', 'group', '#9fef00'),
    @('group', 'config', '#9fef00')
)

foreach ($e in $edges) {
    $a = $nodes[$e[0]]; $b = $nodes[$e[1]]
    $pen = New-Object System.Drawing.Pen (New-IgColor $e[2]), (8 * $s)
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $g.DrawLine($pen, $a[0] * $s, $a[1] * $s, $b[0] * $s, $b[1] * $s)
    $pen.Dispose()
}

# Each node sits in a ring of tile colour so edges stop short of it.
foreach ($n in $nodes.Values) {
    $x = $n[0] * $s; $y = $n[1] * $s; $r = $n[2] * $s; $ring = 7 * $s
    $g.FillEllipse((New-Object System.Drawing.SolidBrush $bg), ($x - $r - $ring), ($y - $r - $ring), (2 * ($r + $ring)), (2 * ($r + $ring)))
    $g.FillEllipse((New-Object System.Drawing.SolidBrush (New-IgColor $n[3])), ($x - $r), ($y - $r), (2 * $r), (2 * $r))
}

$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
$bmp.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Write-Host "Wrote $OutputPath ($Size x $Size)"
