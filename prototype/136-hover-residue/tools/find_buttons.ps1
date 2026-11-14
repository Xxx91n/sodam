# PROBE: locate title bar button glyphs by scanning dark pixels. Throwaway.
. C:\sodam\prototype\136-hover-residue\tools\win32lib.ps1
Add-Type -AssemblyName System.Drawing
$h = [IntPtr]0x30414
$r = Get-WindowRect2 $h
$bmp = Snap-Region ($r.R - 200) $r.T 200 40 $null
"scan line y=$($r.T+17), x from $($r.R-200) to $($r.R):"
$runStart = -1
for ($i = 0; $i -lt 200; $i++) {
  $px = $bmp.GetPixel($i, 17)
  $dark = ($px.R + $px.G + $px.B) -lt 450
  if ($dark -and $runStart -lt 0) { $runStart = $i }
  if (-not $dark -and $runStart -ge 0) {
    "glyph run screen x={0}..{1} center={2}" -f (($r.R - 200) + $runStart), (($r.R - 200) + $i - 1), (((($r.R - 200) + $runStart) + (($r.R - 200) + $i - 1)) / 2)
    $runStart = -1
  }
}
if ($runStart -ge 0) { "glyph run screen x={0}..{1}" -f (($r.R - 200) + $runStart), (($r.R - 200) + 199) }
$bmp.Dispose()
"window rect: $($r.L),$($r.T) - $($r.R),$($r.B)"
