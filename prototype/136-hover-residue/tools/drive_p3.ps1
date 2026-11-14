# PROTOTYPE / THROWAWAY - issue #136 P3 driver. Do not ship.
# Residue matrix: button x direction x distance x window state.
. (Join-Path $PSScriptRoot 'probe136_lib.ps1')
$csv = Join-Path $script:EV 'p3_residue.csv'
Write-EvidenceRow $csv @('winState', 'button', 'dir', 'dist', 'residueClose', 'residueMax', 'residueMin', 'closeRGB', 'maxRGB', 'minRGB')

function Residue-Case([string]$winState, [string]$button, [string]$dir, [int]$dist) {
  $w = Get-SodamWindow
  $h = $w.Hwnd
  $r = $w.Rect
  $btns = Get-ButtonCenters $r
  Reset-Neutral $r
  $base = Test-ButtonStrip $r ("p3_base_{0}" -f $winState)
  $bx = $btns[$button][0]
  $by = $btns[$button][1]
  switch ($dir) {
    'right' { $ex = $bx + $dist; $ey = $by }
    'up' { $ex = $bx; $ey = $by - $dist }
    'upright' { $ex = $bx + [int]($dist * 0.707); $ey = $by - [int]($dist * 0.707) }
  }
  Set-Cursor2 $bx $by
  Wait-Ms 500
  Set-Cursor2 $ex $ey
  Wait-Ms 900
  $res = Test-ButtonStrip $r ("p3_res_{0}_{1}_{2}_{3}" -f $winState, $button, $dir, $dist)
  $d = Compare-Means $base $res
  $lit = if ($d[$button] -gt 15) { 'YES' } else { 'no' }
  Write-EvidenceRow $csv @($winState, $button, $dir, $dist, $lit, "close=$($d['close'])", "max=$($d['max'])", "min=$($d['min'])", "$($res.close.R),$($res.close.G),$($res.close.B)", "$($res.max.R),$($res.max.G),$($res.max.B)", "$($res.min.R),$($res.min.G),$($res.min.B)")
  "{0,-10} {1,-5} {2,-8} d={3,-4} residue[{4}]={5} closeDelta={6} maxDelta={7} minDelta={8}" -f $winState, $button, $dir, $dist, $button, $lit, $d['close'], $d['max'], $d['min']
  Reset-Neutral $r
}

# ensure normal window
$w = Get-SodamWindow
[W32]::ShowWindow($w.Hwnd, 1) | Out-Null
Wait-Ms 800

foreach ($btn in @('min', 'max', 'close')) {
  foreach ($dir in @('right', 'up', 'upright')) {
    foreach ($dist in @(5, 15, 60, 200)) {
      Residue-Case 'normal' $btn $dir $dist
    }
  }
}

# maximized
$w = Get-SodamWindow
[W32]::ShowWindow($w.Hwnd, 3) | Out-Null   # SW_MAXIMIZE
Wait-Ms 1200
$w = Get-SodamWindow
$r = $w.Rect
"maximized rect $($r.L),$($r.T)-$($r.R),$($r.B)"
$btns = Get-ButtonCenters $r
# verify button position by glyph scan at maximized size
foreach ($btn in @('min', 'max', 'close')) {
  foreach ($dir in @('right', 'up', 'upright')) {
    foreach ($dist in @(5, 15, 60, 200)) {
      Residue-Case 'maximized' $btn $dir $dist
    }
  }
}
[W32]::ShowWindow($w.Hwnd, 1) | Out-Null
Wait-Ms 800
"done p3"
