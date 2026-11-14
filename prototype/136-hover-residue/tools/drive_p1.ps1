# PROTOTYPE / THROWAWAY - issue #136 P1 driver. Do not ship.
# Question: what does the framework answer to WM_NCHITTEST after the mouse
# left the window? Synthetic SendMessage probe + hover-state control.
. (Join-Path $PSScriptRoot 'probe136_lib.ps1')

$csv = Join-Path $script:EV 'p1_hittest.csv'
if (-not (Test-Path $csv)) {
  Write-EvidenceRow $csv @('step', 'queryX', 'queryY', 'insideRect', 'hitCode', 'hitName', 'cursorX', 'cursorY', 'rect', 'note')
}

$w = Get-SodamWindow
$h = $w.Hwnd
$r = $w.Rect
"window pid=$($w.Pid) hwnd=0x$($h.ToString('x')) rect $($r.L),$($r.T)-$($r.R),$($r.B)"
$btns = Get-ButtonCenters $r

function Map-Row([string]$step, [int]$y, [int]$xFrom, [int]$xTo, [int]$stepX, [string]$note) {
  for ($x = $xFrom; $x -le $xTo; $x += $stepX) {
    $code = Test-NCHitTest $h $x $y
    $c = Get-Cursor
    $inside = ($x -ge $r.L -and $x -le $r.R -and $y -ge $r.T -and $y -le $r.B)
    Write-EvidenceRow $csv @($step, $x, $y, $inside, $code, (ConvertFrom-HT $code), $c.X, $c.Y, "$($r.L),$($r.T),$($r.R),$($r.B)", $note)
  }
}

function Map-Column([string]$step, [int]$x, [int]$yFrom, [int]$yTo, [int]$stepY, [string]$note) {
  for ($y = $yFrom; $y -le $yTo; $y += $stepY) {
    $code = Test-NCHitTest $h $x $y
    $c = Get-Cursor
    $inside = ($x -ge $r.L -and $x -le $r.R -and $y -ge $r.T -and $y -le $r.B)
    Write-EvidenceRow $csv @($step, $x, $y, $inside, $code, (ConvertFrom-HT $code), $c.X, $c.Y, "$($r.L),$($r.T),$($r.R),$($r.B)", $note)
  }
}

# ---- step 1: neutral state (cursor in content area), baseline maps ----
Reset-Neutral $r
$base = Test-ButtonStrip $r 'p1_base_neutral'
"baseline strip means: " + (($base.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value.R),$($_.Value.G),$($_.Value.B)" }) -join ' ')

Map-Row 'neutral_row' ($btns['close'][1]) ($r.R - 150) ($r.R + 60) 6 'cursor at content center'
Map-Column 'neutral_col_close' $btns['close'][0] ($r.T - 60) ($r.T + 60) 6 'cursor at content center'

# control: does the synthetic query itself change visuals?
$after = Test-ButtonStrip $r 'p1_base_after_map'
$diff = Compare-Means $base $after
"strip delta after maps (control): " + (($diff.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ' ')

# ---- step 2: hover close button (real cursor), then map while hovering ----
Set-Cursor2 $btns['close'][0] $btns['close'][1]
Wait-Ms 600
$hover = Test-ButtonStrip $r 'p1_hover_close'
"hover close strip means: " + (($hover.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value.R),$($_.Value.G),$($_.Value.B)" }) -join ' ')

Map-Row 'hover_row' ($btns['close'][1]) ($r.R - 150) ($r.R + 60) 6 'cursor on close button'
Map-Column 'hover_col_close' $btns['close'][0] ($r.T - 60) ($r.T + 60) 6 'cursor on close button'

# ---- step 3: fling out right, then map with stale state ----
foreach ($d in @(5, 15, 60, 200)) {
  Reset-Neutral $r
  Set-Cursor2 $btns['close'][0] $btns['close'][1]
  Wait-Ms 500
  $ex = $btns['close'][0] + $d
  Set-Cursor2 $ex ($btns['close'][1])
  Wait-Ms 800
  $res = Test-ButtonStrip $r ("p1_fling_right_d$d")
  $resid = Compare-Means $base $res
  "fling right d=$d strip delta vs baseline: " + (($resid.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ' ')
  $wf = Window-At $ex ($btns['close'][1])
  $wfp = Get-Process -Id (Get-WindowPid $wf) -ErrorAction SilentlyContinue
  "WindowFromPoint($ex,$($btns['close'][1])) -> hwnd=0x{0:x} proc={1}" -f $wf.ToInt64(), $wfp.ProcessName
  Map-Row "flingright_row_d$d" ($btns['close'][1]) ($r.R - 40) ($r.R + 40) 4 "cursor flung right d=$d"
}

# ---- step 4: fling out up and up-right ----
foreach ($d in @(5, 15, 60, 200)) {
  Reset-Neutral $r
  Set-Cursor2 $btns['close'][0] $btns['close'][1]
  Wait-Ms 500
  $ey = $btns['close'][1] - $d
  Set-Cursor2 ($btns['close'][0]) $ey
  Wait-Ms 800
  $res = Test-ButtonStrip $r ("p1_fling_up_d$d")
  $resid = Compare-Means $base $res
  "fling up d=$d strip delta vs baseline: " + (($resid.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ' ')
  Map-Column "flingup_col_d$d" $btns['close'][0] ($r.T - 40) ($r.T + 40) 4 "cursor flung up d=$d"
}

# ---- step 5: re-enter from outside: does hover relight normally? ----
Reset-Neutral $r
Set-Cursor2 ($r.R + 30) ($btns['close'][1])   # start outside right
Wait-Ms 400
Set-Cursor2 ($btns['close'][0] - 100) ($btns['close'][1])   # cross border into titlebar, stop left of close
Wait-Ms 600
$reenter = Test-ButtonStrip $r 'p1_reenter'
$delta = Compare-Means $base $reenter
"re-enter strip delta vs baseline: " + (($delta.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ' ')
Reset-Neutral $r
"done p1"
