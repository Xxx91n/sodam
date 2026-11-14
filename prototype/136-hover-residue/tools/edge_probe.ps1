# PROBE: sample edge pixels. Throwaway.
. C:\sodam\prototype\136-hover-residue\tools\win32lib.ps1
Add-Type -AssemblyName System.Drawing
$h = [IntPtr]0x30414
$r = Get-WindowRect2 $h
foreach ($y in @(220, 300, 500, 830)) {
  $line = ""
  foreach ($x in @(($r.R - 10), ($r.R - 6), ($r.R - 3), ($r.R - 1))) {
    $bmp = Snap-Region $x $y 1 1 $null
    $px = $bmp.GetPixel(0, 0)
    $bmp.Dispose()
    $line += ("({0},{1})={2:X2}{3:X2}{4:X2} " -f $x, $y, $px.R, $px.G, $px.B)
  }
  $line
}
"left edge:"
foreach ($x in @($r.L, ($r.L + 1), ($r.L + 2), ($r.L + 3))) {
  $bmp = Snap-Region $x 500 1 1 $null
  $px = $bmp.GetPixel(0, 0)
  $bmp.Dispose()
  "x=$x {0:X2}{1:X2}{2:X2}" -f $px.R, $px.G, $px.B
}
"top edge:"
foreach ($y in @($r.T, ($r.T + 1), ($r.T + 2), ($r.T + 3))) {
  $bmp = Snap-Region 700 $y 1 1 $null
  $px = $bmp.GetPixel(0, 0)
  $bmp.Dispose()
  "y=$y {0:X2}{1:X2}{2:X2}" -f $px.R, $px.G, $px.B
}
"bottom edge:"
foreach ($y in @(($r.B - 1), ($r.B - 2), ($r.B - 3))) {
  $bmp = Snap-Region 700 $y 1 1 $null
  $px = $bmp.GetPixel(0, 0)
  $bmp.Dispose()
  "y=$y {0:X2}{1:X2}{2:X2}" -f $px.R, $px.G, $px.B
}
