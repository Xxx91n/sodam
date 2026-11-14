# PROBE: time course of hit-test answer after fling. Throwaway.
. (Join-Path $PSScriptRoot 'probe136_lib.ps1')
$csv = Join-Path $script:EV 'p1b_timecourse.csv'
Write-EvidenceRow $csv @('case', 'msAfterFling', 'queryX', 'queryY', 'hit', 'closeRGB')

function TimeCourse([string]$case, [int]$ex, [int]$ey) {
  $w = Get-SodamWindow
  $h = $w.Hwnd
  $r = $w.Rect
  $btns = Get-ButtonCenters $r
  Reset-Neutral $r
  Set-Cursor2 $btns['close'][0] $btns['close'][1]
  Wait-Ms 500
  Set-Cursor2 $ex $ey
  $t0 = Get-Date
  foreach ($ms in @(200, 500, 1000, 2000, 3500)) {
    $elapsed = [int]((Get-Date) - $t0).TotalMilliseconds
    while (((Get-Date) - $t0).TotalMilliseconds -lt $ms) { Wait-Ms 20 }
    $code = Test-NCHitTest $h $btns['close'][0] $btns['close'][1]
    $strip = Test-ButtonStrip $r ("p1b_{0}_t{1}" -f $case, $ms)
    Write-EvidenceRow $csv @($case, $elapsed, $btns['close'][0], $btns['close'][1], (ConvertFrom-HT $code), "$($strip.close.R),$($strip.close.G),$($strip.close.B)")
    "case=$case t=${elapsed}ms hit=$(ConvertFrom-HT $code) closeRGB=$($strip.close.R),$($strip.close.G),$($strip.close.B)"
  }
}

TimeCourse 'right5' ((Get-SodamWindow).Rect.R - 30 + 5) 205
TimeCourse 'right60' ((Get-SodamWindow).Rect.R - 30 + 60) 205
TimeCourse 'up5' 1428 200
TimeCourse 'below230' 1428 230
"done"
