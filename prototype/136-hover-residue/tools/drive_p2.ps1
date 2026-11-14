# PROTOTYPE / THROWAWAY - issue #136 P2 driver. Do not ship.
# Question: do clicks near/outside the visible edge actually reach SodaM's
# buttons while the stale hover state is active? Real clicks + state checks.
. (Join-Path $PSScriptRoot 'probe136_lib.ps1')

$csv = Join-Path $script:EV 'p2_clicks.csv'
Write-EvidenceRow $csv @('case', 'button', 'clickX', 'clickY', 'hitTestBefore', 'wfTarget', 'stateBefore', 'stateAfter', 'outcome')

function Ensure-Normal {
  $w = Get-SodamWindow
  $st = Get-SodamState $w.Hwnd
  if (-not $st.Alive) { throw 'window dead unexpectedly' }
  if ($st.Iconic) { [W32]::ShowWindow($w.Hwnd, 9) | Out-Null; Wait-Ms 600 }   # SW_RESTORE
  if ($st.Zoomed) { [W32]::ShowWindow($w.Hwnd, 1) | Out-Null; Wait-Ms 600 }   # SW_SHOWNORMAL
  $w = Get-SodamWindow
  return $w
}

function Get-StateStr([IntPtr]$h) {
  $st = Get-SodamState $h
  if (-not $st.Alive) { return 'DEAD' }
  $r = Get-WindowRect2 $h
  "alive iconic={0} zoomed={1} rect={2},{3},{4},{5}" -f $st.Iconic, $st.Zoomed, $r.L, $r.T, $r.R, $r.B
}

function Invoke-Case([string]$name, [string]$button, [int]$cx, [int]$cy, [bool]$hoverFirst, [bool]$dryRun) {
  $w = Ensure-Normal
  $h = $w.Hwnd
  $r = $w.Rect
  $btns = Get-ButtonCenters $r
  Reset-Neutral $r
  if ($hoverFirst) {
    Set-Cursor2 $btns[$button][0] $btns[$button][1]
    Wait-Ms 500
    # fling to the click point (same as handoff: hover then leave quickly)
    Set-Cursor2 $cx $cy
    Wait-Ms 400
  } else {
    Set-Cursor2 $cx $cy
    Wait-Ms 400
  }
  $code = Test-NCHitTest $h $cx $cy
  $wf = Window-At $cx $cy
  $wfpid = Get-WindowPid $wf
  $wfp = Get-Process -Id $wfpid -ErrorAction SilentlyContinue
  $before = Get-StateStr $h
  if ($dryRun) {
    Write-EvidenceRow $csv @($name, $button, $cx, $cy, "$code($(ConvertFrom-HT $code))", "$($wfp.ProcessName)", $before, '(dry)', 'skipped: target not sodam/desktop')
    return
  }
  Click-Left
  Wait-Ms 900
  $after = Get-StateStr $h
  $outcome = 'no-change'
  if ($after -eq 'DEAD') { $outcome = 'WINDOW CLOSED' }
  else {
    $sb = Get-SodamState $h
    if ($sb.Iconic) { $outcome = 'MINIMIZED' }
    elseif ($sb.Zoomed) { $outcome = 'MAXIMIZED' }
  }
  Write-EvidenceRow $csv @($name, $button, $cx, $cy, "$code($(ConvertFrom-HT $code))", "$($wfp.ProcessName)", $before, $after, $outcome)
  # recover for next case
  if ($after -eq 'DEAD') { Start-Sleep -Seconds 2; $w2 = Get-SodamWindow; Wait-Ms 1500 }
  else {
    $sb = Get-SodamState $h
    if ($sb.Iconic) { [W32]::ShowWindow($h, 9) | Out-Null; Wait-Ms 700 }
    if ($sb.Zoomed) { [W32]::ShowWindow($h, 1) | Out-Null; Wait-Ms 700 }
  }
}

function Invoke-FarClick([string]$name, [string]$button, [int]$cx, [int]$cy) {
  # only click when the point is bare desktop, never on another app's window
  $wf = Window-At $cx $cy
  $wfp = Get-Process -Id (Get-WindowPid $wf) -ErrorAction SilentlyContinue
  if ($wfp -and $wfp.ProcessName -notin @('explorer')) {
    Write-EvidenceRow $csv @($name, $button, $cx, $cy, '-', "$($wfp.ProcessName)", '-', '-', 'skipped: target not desktop')
    return
  }
  Invoke-Case $name $button $cx $cy $true $false
}

# --- controls: fresh state, no stale hover ---
$w = Ensure-Normal
$r = $w.Rect
$btns = Get-ButtonCenters $r
Invoke-Case 'ctrl_close_right5' 'close' ($btns['close'][0] + 5) $btns['close'][1] $false $false
Invoke-Case 'ctrl_min_right5' 'min' ($btns['min'][0] + 5) $btns['min'][1] $false $false

# --- stale hover + click inside window rect (right of button, 5px / 15px) ---
Invoke-Case 'stale_close_right5' 'close' ($btns['close'][0] + 5) $btns['close'][1] $true $false
Invoke-Case 'stale_close_right15' 'close' ($btns['close'][0] + 15) $btns['close'][1] $true $false
Invoke-Case 'stale_max_right5' 'max' ($btns['max'][0] + 5) $btns['max'][1] $true $false
Invoke-Case 'stale_min_right5' 'min' ($btns['min'][0] + 5) $btns['min'][1] $true $false

# --- stale hover + click above button (within top border rows) ---
Invoke-Case 'stale_close_up3' 'close' $btns['close'][0] ($btns['close'][1] - 3) $true $false
Invoke-Case 'stale_close_up12' 'close' $btns['close'][0] ($btns['close'][1] - 12) $true $false

# --- stale hover + click truly outside the window rect (safety-gated) ---
$w = Ensure-Normal
$r = $w.Rect
$belowY = $r.B + 15
Invoke-FarClick 'stale_close_below15' 'close' $btns['close'][0] $belowY
Invoke-FarClick 'stale_close_below80' 'close' $btns['close'][0] ($r.B + 80)

Reset-Neutral ((Get-SodamWindow).Rect)
"done p2"
Get-Content $csv
