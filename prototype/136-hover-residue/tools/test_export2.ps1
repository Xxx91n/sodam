# PROBE v2: call export with a REAL CWPRETSTRUCT. Throwaway.
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public delegate int HookCall(int code, IntPtr wp, IntPtr lp);
public struct CWPRETSTRUCT {
  public IntPtr lResult; public IntPtr wParam; public IntPtr lParam;
  public uint message; public IntPtr hwnd;
}
public static class EX2 {
  [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
  public static extern IntPtr LoadLibraryW(string path);
  [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Ansi)]
  public static extern IntPtr GetProcAddress(IntPtr h, string name);
  [DllImport("kernel32.dll")] public static extern int GetCurrentProcessId();
}
"@
$h = [EX2]::LoadLibraryW('C:\sodam\prototype\136-hover-residue\tools\probe_hook.dll')
$p = [EX2]::GetProcAddress($h, 'HookRetProc')
"proc=0x$($p.ToString('x'))"
$s = New-Object CWPRETSTRUCT
$s.message = 132            # WM_NCHITTEST
$s.lResult = [IntPtr]20     # HTCLOSE
$s.hwnd = [IntPtr]0x1234
$s.wParam = [IntPtr]0
$s.lParam = [IntPtr]0x00E00064  # x=100 y=224 packed
$buf = [Runtime.InteropServices.Marshal]::AllocHGlobal(64)
[Runtime.InteropServices.Marshal]::StructureToPtr($s, $buf, $false)
$size = [Runtime.InteropServices.Marshal]::SizeOf($s)
"struct size=$size"
$d = [Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($p, [HookCall])
$r = $d.Invoke(0, [IntPtr]::Zero, $buf)
"called ok ret=$r"
[Runtime.InteropServices.Marshal]::FreeHGlobal($buf)
"--- log ---"
Get-Content 'C:\sodam\prototype\136-hover-residue\evidence\hooklog.txt' -ErrorAction SilentlyContinue
"--- end ---"
