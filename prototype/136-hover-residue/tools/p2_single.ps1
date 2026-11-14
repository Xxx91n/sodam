# PROBE: rerun single stale-click case with full instrumentation. Throwaway.
. (Join-Path $PSScriptRoot 'probe136_lib.ps1')
$w = Get-SodamWindow
$h = $w.Hwnd
$r = $w.Rect
$btns = Get-ButtonCenters $r
"rect $($r.L),$($r.T)-$($r.R),$($r.B) hwnd=0x$($h.ToString('x'))"

# fresh control: move to click point only
Reset-Neutral $r
Set-Cursor2 1433 205
Wait-Ms 500
"fresh @1433,205 query: $(ConvertFrom-HT (Test-NCHitTest $h 1433 205))"

# stale: hover close, fling right 5
Reset-Neutral $r
Set-Cursor2 $btns['close'][0] $btns['close'][1]
Wait-Ms 600
"hover query: $(ConvertFrom-HT (Test-NCHitTest $h 1428 205))"
Set-Cursor2 1433 205
Wait-Ms 400
$c = Get-Cursor
"stale cursor=($($c.X),$($c.Y)) query@1433,205: $(ConvertFrom-HT (Test-NCHitTest $h 1433 205))"
"stale query@1428,205: $(ConvertFrom-HT (Test-NCHitTest $h 1428 205))"
$strip = Test-ButtonStrip $r 'p2_single_stale'
"stale strip closeRGB=$($strip.close.R),$($strip.close.G),$($strip.close.B)"
# now click
Click-Left
Wait-Ms 900
$st = Get-SodamState $h
"after click alive=$($st.Alive) iconic=$($st.Iconic) zoomed=$($st.Zoomed)"
