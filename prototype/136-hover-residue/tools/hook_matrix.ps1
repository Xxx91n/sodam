# PROBE: which hook type/thread combos are allowed? Throwaway.
param([int]$TargetPid)
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public delegate IntPtr HookDel(int code, IntPtr wp, IntPtr lp);
public static class TM {
  [DllImport("user32.dll", SetLastError=true)]
  public static extern IntPtr SetWindowsHookExW(int idHook, IntPtr proc, IntPtr hMod, uint threadId);
  [DllImport("user32.dll")] public static extern bool UnhookWindowsHookEx(IntPtr hhk);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindowW(string cls, string title);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("kernel32.dll")] public static extern IntPtr GetModuleHandleW(string name);
  [DllImport("user32.dll")] public static extern IntPtr CallNextHookEx(IntPtr hhk, int code, IntPtr wp, IntPtr lp);
  public static IntPtr Dummy(int code, IntPtr wp, IntPtr lp) { return CallNextHookEx(IntPtr.Zero, code, wp, lp); }
}
"@
$global:d = [HookDel]{ param([int]$c, [IntPtr]$w, [IntPtr]$l) [TM]::Dummy($c, $w, $l) }
$ptr = [Runtime.InteropServices.Marshal]::GetFunctionPointerForDelegate($global:d)
$nullh = [IntPtr]::Zero
$user32 = [TM]::GetModuleHandleW("user32.dll")

$p = Get-Process -Id $TargetPid
$h = $p.MainWindowHandle
$dummy = 0
$tid = [TM]::GetWindowThreadProcessId($h, [ref]$dummy)
"target tid=$tid hwnd=0x{0:x}" -f $h.ToInt64()

# own thread id via a message-only window? use current thread P/Invoke
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class KV { [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId(); }
"@
$mytid = [KV]::GetCurrentThreadId()
"my tid=$mytid"

foreach ($spec in @(@(4,'CALLWNDPROC'), @(12,'CALLWNDPROCRET'), @(3,'GETMESSAGE'), @(5,'CBT'))) {
  $idHook = $spec[0]; $name = $spec[1]
  # cross-thread, NULL hMod
  $hhk = [TM]::SetWindowsHookExW($idHook, $ptr, $nullh, [uint32]$tid)
  $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
  "{0} xthread nullhmod -> hhk=0x{1:x} err={2}" -f $name, $hhk.ToInt64(), $err
  if ($hhk -ne [IntPtr]::Zero) { [TM]::UnhookWindowsHookEx($hhk) | Out-Null }
  # cross-thread, user32 hMod
  $hhk = [TM]::SetWindowsHookExW($idHook, $ptr, $user32, [uint32]$tid)
  $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
  "{0} xthread user32mod -> hhk=0x{1:x} err={2}" -f $name, $hhk.ToInt64(), $err
  if ($hhk -ne [IntPtr]::Zero) { [TM]::UnhookWindowsHookEx($hhk) | Out-Null }
  # own thread, NULL hMod (control)
  $hhk = [TM]::SetWindowsHookExW($idHook, $ptr, $nullh, [uint32]$mytid)
  $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
  "{0} ownthread nullhmod -> hhk=0x{1:x} err={2}" -f $name, $hhk.ToInt64(), $err
  if ($hhk -ne [IntPtr]::Zero) { [TM]::UnhookWindowsHookEx($hhk) | Out-Null }
}
