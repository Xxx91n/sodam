# PROBE: is probe_hook.dll's export callable in-process? Throwaway.
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public delegate int HookCall(int code, IntPtr wp, IntPtr lp);
public static class EX {
  [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
  public static extern IntPtr LoadLibraryW(string path);
  [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Ansi)]
  public static extern IntPtr GetProcAddress(IntPtr h, string name);
}
"@
$h = [EX]::LoadLibraryW('C:\sodam\prototype\136-hover-residue\tools\probe_hook.dll')
"hmod=0x$($h.ToString('x')) err=$([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
$p = [EX]::GetProcAddress($h, 'HookRetProc')
"proc=0x$($p.ToString('x')) err=$([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
if ($p -ne [IntPtr]::Zero) {
  $d = [Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($p, [HookCall])
  try {
    $r = $d.Invoke(0, [IntPtr]::Zero, [IntPtr]::Zero)
    "called ok ret=$r"
  } catch {
    "call failed: $($_.Exception.GetType().Name): $($_.Exception.Message)"
  }
}
Get-Content 'C:\sodam\prototype\136-hover-residue\evidence\hooklog.txt' -ErrorAction SilentlyContinue
