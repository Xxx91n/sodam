# PROBE: patch COR20 flags to ILONLY (0x2000). Throwaway.
param([string]$Path)
$b = [IO.File]::ReadAllBytes($Path)
$pe = [BitConverter]::ToInt32($b, 0x3C)
$magic = [BitConverter]::ToUInt16($b, $pe + 24)
if ($magic -eq 0x20B) { $corDirOff = $pe + 24 + 112 + 14 * 8 } else { $corDirOff = $pe + 24 + 96 + 14 * 8 }
$corRva = [BitConverter]::ToInt32($b, $corDirOff)
$numSections = [BitConverter]::ToUInt16($b, $pe + 6)
$optSize = [BitConverter]::ToUInt16($b, $pe + 20)
$secStart = $pe + 24 + $optSize
for ($i = 0; $i -lt $numSections; $i++) {
  $s = $secStart + $i * 40
  $vSize = [BitConverter]::ToInt32($b, $s + 8)
  $vAddr = [BitConverter]::ToInt32($b, $s + 12)
  $rawSize = [BitConverter]::ToInt32($b, $s + 16)
  $rawPtr = [BitConverter]::ToInt32($b, $s + 20)
  if ($corRva -ge $vAddr -and $corRva -lt ($vAddr + [Math]::Max($vSize, $rawSize))) {
    $fileOff = $rawPtr + ($corRva - $vAddr); break
  }
}
$cur = [BitConverter]::ToUInt16($b, $fileOff + 16)
$b[$fileOff + 16] = 0x00
$b[$fileOff + 17] = 0x20
[IO.File]::WriteAllBytes($Path, $b)
"patched flags 0x{0:X4} -> 0x2000 at file offset 0x{1:X}" -f $cur, ($fileOff + 16)
