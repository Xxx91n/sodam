# PROTOTYPE / THROWAWAY - issue #136 P2 re-verify on clean process. Do not ship.
. (Join-Path $PSScriptRoot 'probe136_lib.ps1')
$csv = Join-Path $script:EV 'p2b_clicks.csv'
Write-EvidenceRow $csv @('case', 'clickX', 'clickY', 'hitBefore', 'stateBefore', 'stateAfter', 'outcome')

function Ensure-Normal2 {
  $w = Get-SodamWindow
  $st = Get-SodamState $w.Hwnd
  if ($st.Iconic) { [W32]::ShowWindow($w.Hwnd, 9) | Out-Null; Wait-Ms 700 }
  if ($st.Zoomed) { [W32]::ShowWindow($w.Hwnd, 1) | Out-Null; Wait-Ms 700 }
  Get-SodamWindow
}

function Run-Case([string]$name, [string]$button, [int]$cx, [int]$cy, [bool]$hoverFirst) {
  $w = Ensure-Normal2
  $h = $w.Hwnd
  $r = $w.Rect
  $btns = Get-ButtonCenters $r
  Reset-Neutral $r
  if ($hoverFirst) {
    Set-Cursor2 $btns[$button][0] $btns[$button][1]
    Wait-Ms 500
    Set-Cursor2 $cx $cy
    Wait-Ms 400
  } else {
    Set-Cursor2 $cx $cy
    Wait-Ms 500
  }
  $code = ConvertFrom-HT (Test-NCHitTest $h $cx $cy)
  $before = Get-StateStr2 $h
  Click-Left
  Wait-Ms 900
  $after = Get-StateStr2 $h
  $outcome = 'no-change'
  if ($after -eq 'DEAD') { $outcome = 'WINDOW HIDDEN/CLOSED' }
  else {
    $sb = Get-SodamState $h
    if ($sb.Iconic) { $outcome = 'MINIMIZED' }
    elseif ($sb.Zoomed) { $outcome = 'MAXIMIZED' }
  }
  Write-EvidenceRow $csv @($name, $cx, $cy, $code, $before, $after, $outcome)
  "{0}: hitBefore={1} -> {2}" -f $name, $code, $outcome
  if ($after -eq 'DEAD') { Wait-Ms 2000 }   # Get-SodamWindow will relaunch next case
  else {
    $sb = Get-SodamState $h
    if ($sb.Iconic) { [W32]::ShowWindow($h, 9) | Out-Null; Wait-Ms 700 }
    if ($sb.Zoomed) { [W32]::ShowWindow($h, 1) | Out-Null; Wait-Ms 700 }
  }
}

function Get-StateStr2([IntPtr]$h) {
  $st = Get-SodamState $h
  if (-not $st.Alive) { return 'DEAD' }
  $r = Get-WindowRect2 $h
  "iconic={0} zoomed={1} rect={2},{3},{4},{5}" -f $st.Iconic, $st.Zoomed, $r.L, $r.T, $r.R, $r.B
}

Run-Case 'ctrl_below_button' 'close' 1428 230 $false
Run-Case 'stale_close_right5' 'close' 1433 205 $true
Run-Case 'stale_min_right5' 'min' 1345 205 $true
Run-Case 'stale_max_right5' 'max' 1389 205 $true
Run-Case 'stale_close_below25' 'close' 1428 230 $true
Run-Case 'stale_close_up12_topborder' 'close' 1428 193 $true
"done p2b"
