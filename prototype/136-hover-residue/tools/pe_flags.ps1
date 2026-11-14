# PROBE: parse PE + COR20 flags. Throwaway.
param([string]$Path)
$b = [IO.File]::ReadAllBytes($Path)
$pe = [BitConverter]::ToInt32($b, 0x3C)
$machine = [BitConverter]::ToUInt16($b, $pe + 4)
$magic = [BitConverter]::ToUInt16($b, $pe + 24)
"machine=0x{0:X4} magic=0x{1:X4}" -f $machine, $magic
$corDirIdx = 14
if ($magic -eq 0x20B) { $corDirOff = $pe + 24 + 112 + $corDirIdx * 8 } else { $corDirOff = $pe + 24 + 96 + $corDirIdx * 8 }
$corRva = [BitConverter]::ToInt32($b, $corDirOff)
"cor20 RVA=0x{0:X}" -f $corRva
$numSections = [BitConverter]::ToUInt16($b, $pe + 6)
$optSize = [BitConverter]::ToUInt16($b, $pe + 20)
$secStart = $pe + 24 + $optSize
$fileOff = 0
for ($i = 0; $i -lt $numSections; $i++) {
  $s = $secStart + $i * 40
  $vSize = [BitConverter]::ToInt32($b, $s + 8)
  $vAddr = [BitConverter]::ToInt32($b, $s + 12)
  $rawSize = [BitConverter]::ToInt32($b, $s + 16)
  $rawPtr = [BitConverter]::ToInt32($b, $s + 20)
  if ($corRva -ge $vAddr -and $corRva -lt ($vAddr + [Math]::Max($vSize, $rawSize))) {
    $fileOff = $rawPtr + ($corRva - $vAddr)
    break
  }
}
"cor20 file offset=0x{0:X}" -f $fileOff
$flags = [BitConverter]::ToUInt16($b, $fileOff + 16)
"corflags=0x{0:X4}  (ILONLY=0x1 32BITREQ=0x8 32BITPREF=0x20000)" -f $flags
