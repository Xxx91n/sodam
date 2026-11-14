# PROTOTYPE / THROWAWAY - issue #136 evidence lib. Do not ship.
. (Join-Path $PSScriptRoot 'win32lib.ps1')
Add-Type -AssemblyName System.Drawing

$script:EV = 'C:\sodam\prototype\136-hover-residue\evidence'
# button centers as offsets from window rect (measured at v0.3.8, dpi 96)
$script:BTN_OFF = @{
  min   = @(-118, 16)
  max   = @(-74, 16)
  close = @(-30, 16)
}
$script:HTNAMES = @{
  '-2' = 'HTERROR'; '-1' = 'HTTRANSPARENT'; '0' = 'HTNOWHERE'; '1' = 'HTCLIENT'
  '2' = 'HTCAPTION'; '3' = 'HTSYSMENU'; '4' = 'HTGROWBOX'; '5' = 'HTMENU'
  '6' = 'HTHSCROLL'; '7' = 'HTVSCROLL'; '8' = 'HTMINBUTTON'; '9' = 'HTMAXBUTTON'
  '10' = 'HTLEFT'; '11' = 'HTRIGHT'; '12' = 'HTTOP'; '13' = 'HTTOPLEFT'
  '14' = 'HTTOPRIGHT'; '15' = 'HTBOTTOM'; '16' = 'HTBOTTOMLEFT'; '17' = 'HTBOTTOMRIGHT'
  '18' = 'HTBORDER'; '19' = 'HTOBJECT'; '20' = 'HTCLOSE'
}

function Get-SodamWindow {
  $p = Get-Process sodam -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
  if (-not $p) {
    # close hides to tray and destroys the main window; kill and start clean
    Get-Process sodam -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Wait-Ms 1200
    Start-Process 'C:\Users\Administrator\AppData\Local\Programs\SodaM\sodam.exe'
    $deadline = (Get-Date).AddSeconds(20)
    while ((Get-Date) -lt $deadline) {
      Wait-Ms 800
      $p = Get-Process sodam -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
      if ($p) { break }
    }
  }
  if (-not $p) { throw 'sodam not running' }
  Wait-Ms 500
  $h = $p.MainWindowHandle
  $r = Get-WindowRect2 $h
  [pscustomobject]@{ Pid = $p.Id; Hwnd = $h; Rect = $r }
}

function Get-SodamState([IntPtr]$h) {
  [pscustomobject]@{
    Alive   = [W32]::IsWindow($h)
    Iconic  = [W32]::IsIconic($h)
    Zoomed  = [W32]::IsZoomed($h)
  }
}

function ConvertTo-LParam([int]$x, [int]$y) {
  $ux = $x -band 0xFFFF
  $uy = $y -band 0xFFFF
  [IntPtr][int](($uy -shl 16) -bor $ux)
}

# Synthetic WM_NCHITTEST: asks the framework the same question win32k asks.
function Test-NCHitTest([IntPtr]$h, [int]$x, [int]$y) {
  $lp = ConvertTo-LParam $x $y
  $res = [W32]::SendMessageW($h, 0x84, [IntPtr]::Zero, $lp)
  [int]$res
}

function ConvertFrom-HT([int]$code) {
  $n = $script:HTNAMES["$code"]
  if ($n) { $n } else { "HT?$code" }
}

function Get-ButtonCenters([W32+RECT]$r) {
  $out = @{}
  foreach ($k in $script:BTN_OFF.Keys) {
    $out[$k] = @(($r.R + $script:BTN_OFF[$k][0]), ($r.T + $script:BTN_OFF[$k][1]))
  }
  $out
}

# Capture the 3-button strip; save PNG; return mean RGB per button patch (12x12).
function Test-ButtonStrip([W32+RECT]$r, [string]$tag) {
  $w = 170
  $h2 = 44
  $x0 = $r.R - $w
  $bmp = Snap-Region $x0 $r.T $w $h2 (Join-Path $script:EV "$tag.png")
  $means = @{}
  foreach ($k in $script:BTN_OFF.Keys) {
    $bx = $script:BTN_OFF[$k][0] + $r.R - $x0
    $by = $script:BTN_OFF[$k][1]
    $sr = 0; $sg = 0; $sb = 0; $n = 0
    for ($dx = -6; $dx -le 6; $dx++) {
      for ($dy = -6; $dy -le 6; $dy++) {
        $px = $bmp.GetPixel($bx + $dx, $by + $dy)
        $sr += $px.R; $sg += $px.G; $sb += $px.B; $n++
      }
    }
    $means[$k] = @{ R = [int]($sr / $n); G = [int]($sg / $n); B = [int]($sb / $n) }
  }
  $bmp.Dispose()
  $means
}

function Compare-Means($a, $b) {
  # per-button max channel delta
  $out = @{}
  foreach ($k in $a.Keys) {
    $d = [Math]::Max([Math]::Abs($a[$k].R - $b[$k].R), [Math]::Max([Math]::Abs($a[$k].G - $b[$k].G), [Math]::Abs($a[$k].B - $b[$k].B)))
    $out[$k] = $d
  }
  $out
}

function Write-EvidenceRow([string]$csv, [object[]]$vals) {
  $line = ($vals -join ',')
  Add-Content -Path $csv -Value $line -Encoding UTF8
}

function Wait-Ms([int]$ms) { Start-Sleep -Milliseconds $ms }

# Standard experiment frame: neutral -> hover -> (action) -> capture
function Reset-Neutral([W32+RECT]$r) {
  $nx = [int](($r.L + $r.R) / 2)
  $ny = [int](($r.T + $r.B) / 2)
  Set-Cursor2 $nx $ny | Out-Null
  Wait-Ms 400
}
