# PROBE: sanity - does clicking the close button center actually close? Throwaway.
. (Join-Path $PSScriptRoot 'probe136_lib.ps1')
$w = Get-SodamWindow
$h = $w.Hwnd
$r = $w.Rect
$btns = Get-ButtonCenters $r
"rect $($r.L),$($r.T)-$($r.R),$($r.B) close=$($btns['close'] -join ',')"
Reset-Neutral $r
Set-Cursor2 $btns['close'][0] $btns['close'][1]
Wait-Ms 700
$strip = Test-ButtonStrip $r 'p2b_hover_center'
"strip after hover: close=$($strip.close.R),$($strip.close.G),$($strip.close.B)"
"synthetic HT at close center: $(ConvertFrom-HT (Test-NCHitTest $h $btns['close'][0] $btns['close'][1]))"
Click-Left
Wait-Ms 1200
$st = Get-SodamState $h
"after click: alive=$($st.Alive) iconic=$($st.Iconic)"
if (-not $st.Alive) { "WINDOW CLOSED by center click"; Start-Sleep 2; $w2 = Get-SodamWindow; Wait-Ms 1500; "relaunched hwnd=0x$($w2.Hwnd.ToString('x'))" }
