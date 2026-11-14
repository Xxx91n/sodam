# PROBE: hit-test answer grid in stale vs fresh-hover state. Throwaway.
. (Join-Path $PSScriptRoot 'probe136_lib.ps1')
$csv = Join-Path $script:EV 'p1c_grid.csv'
Write-EvidenceRow $csv @('state', 'queryX', 'queryY', 'insideRect', 'hit', 'cursorX', 'cursorY')

$w = Get-SodamWindow
$h = $w.Hwnd
$r = $w.Rect
$btns = Get-ButtonCenters $r

function Grid([string]$state) {
  foreach ($x in @(1288, 1300, 1312, 1324, 1336, 1348, 1360, 1372, 1384, 1396, 1408, 1420, 1432, 1444, 1456, 1468, 1490, 1520)) {
    $code = Test-NCHitTest $h $x 205
    $c = Get-Cursor
    $inside = ($x -ge $r.L -and $x -le $r.R)
    Write-EvidenceRow $csv @($state, $x, 205, $inside, (ConvertFrom-HT $code), $c.X, $c.Y)
  }
  foreach ($y in @(150, 170, 185, 191, 197, 203, 215, 227, 239, 260, 300)) {
    $code = Test-NCHitTest $h 1428 $y
    $c = Get-Cursor
    $inside = ($y -ge $r.T -and $y -le $r.B)
    Write-EvidenceRow $csv @($state, 1428, $y, $inside, (ConvertFrom-HT $code), $c.X, $c.Y)
  }
}

# state A: stale (hover close, fling right 5)
Reset-Neutral $r
Set-Cursor2 $btns['close'][0] $btns['close'][1]
Wait-Ms 500
Set-Cursor2 ($btns['close'][0] + 5) $btns['close'][1]
Wait-Ms 500
Grid 'stale_right5'

# state B: fresh hover on close center
Reset-Neutral $r
Set-Cursor2 $btns['close'][0] $btns['close'][1]
Wait-Ms 700
Grid 'hover_center'

# state C: neutral (cursor center)
Reset-Neutral $r
Grid 'neutral'
Reset-Neutral $r
"done"
