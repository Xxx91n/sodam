# PROTOTYPE / THROWAWAY - issue #136 probe. Do not ship.
# Thread-specific WH_CALLWNDPROCRET hook on the target window's UI thread.
# Hook callback runs in THIS process (no DLL injection needed); we pump
# messages until the stop flag appears, logging filtered messages to LogPath.
# Line: timestamp|serverpid|msg|hwnd|lRes|wp|lp   (decimal)
param(
  [Parameter(Mandatory=$true)][int]$TargetPid,
  [Parameter(Mandatory=$true)][string]$StopFlag,
  [Parameter(Mandatory=$true)][string]$LogPath
)
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @"
using System;
using System.IO;
using System.Runtime.InteropServices;
public struct CWPRETSTRUCT {
  public IntPtr lResult; public IntPtr wParam; public IntPtr lParam;
  public uint message; public IntPtr hwnd;
}
public delegate IntPtr HookDel(int code, IntPtr wp, IntPtr lp);
public static class TH {
  [DllImport("user32.dll", SetLastError=true)]
  public static extern IntPtr SetWindowsHookExW(int idHook, IntPtr proc, IntPtr hMod, uint threadId);
  [DllImport("user32.dll")] public static extern bool UnhookWindowsHookEx(IntPtr hhk);
  [DllImport("user32.dll")] public static extern IntPtr CallNextHookEx(IntPtr hhk, int code, IntPtr wp, IntPtr lp);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("kernel32.dll")] public static extern int GetCurrentProcessId();
  public static IntPtr HHK = IntPtr.Zero;
  public static string LogPath = "";
  public static int[] Filter = {16,132,134,160,161,162,274,533,674,675};
  public static IntPtr HookProc(int code, IntPtr wp, IntPtr lp) {
    if (code >= 0 && lp != IntPtr.Zero) {
      CWPRETSTRUCT s = (CWPRETSTRUCT)Marshal.PtrToStructure(lp, typeof(CWPRETSTRUCT));
      for (int i = 0; i < Filter.Length; i++) {
        if (s.message == (uint)Filter[i]) {
          try {
            File.AppendAllText(LogPath, string.Format(
              "{0:yyyy-MM-dd HH:mm:ss.fff}|pid={1}|msg={2}|hwnd={3}|lRes={4}|wp={5}|lp={6}\r\n",
              DateTime.Now, GetCurrentProcessId(), s.message, s.hwnd, s.lResult, s.wParam, s.lParam));
          } catch {}
          break;
        }
      }
    }
    return CallNextHookEx(IntPtr.Zero, code, wp, lp);
  }
}
"@
Add-Type -AssemblyName System.Windows.Forms

$p = Get-Process -Id $TargetPid
$h = $p.MainWindowHandle
if ($h -eq [IntPtr]::Zero) { throw "target pid $TargetPid has no main window" }
$dummyPid = 0
$tid = [int][TH]::GetWindowThreadProcessId($h, [ref]$dummyPid)
if ($tid -eq 0) { throw "cannot resolve window thread" }

[TH]::LogPath = $LogPath
$global:hd = [HookDel]{ param($c, $w, $l) [TH]::HookProc($c, $w, $l) }
$ptr = [Runtime.InteropServices.Marshal]::GetFunctionPointerForDelegate($global:hd)
$hhk = [TH]::SetWindowsHookExW(12, $ptr, [IntPtr]::Zero, [uint32]$tid)
if ($hhk -eq [IntPtr]::Zero) { throw "SetWindowsHookEx failed err=$([Runtime.InteropServices.Marshal]::GetLastWin32Error())" }
[TH]::HHK = $hhk
Set-Content -Path "$StopFlag.ready" -Value "threadhook ok tid=$tid pid=$PID"

while (-not (Test-Path $StopFlag)) {
  [System.Windows.Forms.Application]::DoEvents()
  Start-Sleep -Milliseconds 5
}
[TH]::UnhookWindowsHookEx($hhk) | Out-Null
Remove-Item "$StopFlag.ready" -ErrorAction SilentlyContinue
