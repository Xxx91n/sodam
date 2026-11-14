# PROBE: call mini.dll exports. Throwaway.
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public delegate int AddDel(int a, int b);
public delegate IntPtr HookCall(int code, IntPtr wp, IntPtr lp);
public static class EXM {
  [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
  public static extern IntPtr LoadLibraryW(string path);
  [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Ansi)]
  public static extern IntPtr GetProcAddress(IntPtr h, string name);
}
"@
$h = [EXM]::LoadLibraryW('C:\sodam\prototype\136-hover-residue\tools\mini.dll')
"hmod=0x$($h.ToString('x'))"
$p1 = [EXM]::GetProcAddress($h, 'TestAdd')
$p2 = [EXM]::GetProcAddress($h, 'TestPassthrough')
"TestAdd=0x$($p1.ToString('x'))  TestPassthrough=0x$($p2.ToString('x'))"
if ($p1 -ne [IntPtr]::Zero) {
  $d1 = [Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($p1, [AddDel])
  "TestAdd(2,3)=" + $d1.Invoke(2, 3)
}
if ($p2 -ne [IntPtr]::Zero) {
  $d2 = [Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($p2, [HookCall])
  $r = $d2.Invoke(0, [IntPtr]::Zero, [IntPtr]::Zero)
  "TestPassthrough(0,0,0)=0x$($r.ToString('x'))"
}
