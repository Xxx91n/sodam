# PROBE: enumerate sodam top-level windows; try to reshow. Throwaway.
. C:\sodam\prototype\136-hover-residue\tools\win32lib.ps1
Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class EW {
  public delegate bool EnumProc(IntPtr hwnd, IntPtr lparam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, StringBuilder sb, int max);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h, StringBuilder sb, int max);
  [DllImport("user32.dll")] public static extern int GetWindowThreadProcessId(IntPtr h, out uint pid);
}
"@
$found = @()
$cb = [EW+EnumProc]{
  param($h, $lp)
  $pid2 = 0
  [EW]::GetWindowThreadProcessId($h, [ref]$pid2) | Out-Null
  if ($pid2 -eq 5752) {
    $t = New-Object System.Text.StringBuilder 256
    [EW]::GetWindowTextW($h, $t, 256) | Out-Null
    $c = New-Object System.Text.StringBuilder 256
    [EW]::GetClassNameW($h, $c, 256) | Out-Null
    $script:found += [pscustomobject]@{ H = $h; Title = $t.ToString(); Cls = $c.ToString(); Vis = [EW]::IsWindowVisible($h) }
  }
  $true
}
[EW]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
$found | Format-Table -AutoSize | Out-String
# try re-launching sodam.exe to trigger single-instance show
Start-Process 'C:\Users\Administrator\AppData\Local\Programs\SodaM\sodam.exe'
Start-Sleep -Seconds 5
$found2 = $found | ForEach-Object { $_ }
"after relaunch attempt:"
foreach ($f in $found2) { "hwnd=0x{0:x} cls={1} title={2} vis={3}" -f $f.H.ToInt64(), $f.Cls, $f.Title, $f.Vis }
