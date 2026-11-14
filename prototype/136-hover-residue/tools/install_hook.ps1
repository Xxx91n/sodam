# PROTOTYPE / THROWAWAY - issue #136 probe. Do not ship.
# Installs the global WH_CALLWNDPROCRET probe hook, then idles until the stop
# flag file appears, unhooks and exits.
param(
  [Parameter(Mandatory=$true)][string]$DllPath,
  [Parameter(Mandatory=$true)][string]$StopFlag
)
$ErrorActionPreference = 'Stop'
$src = @"
using System;
using System.Runtime.InteropServices;
public static class HookLoader {
  [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
  public static extern IntPtr LoadLibraryW(string path);
  [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Ansi)]
  public static extern IntPtr GetProcAddress(IntPtr h, string name);
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern IntPtr GetProcAddressOrd(IntPtr h, UIntPtr ordinal);
  [DllImport("user32.dll", SetLastError=true)]
  public static extern IntPtr SetWindowsHookExW(int idHook, IntPtr lpfn, IntPtr hMod, uint dwThreadId);
  [DllImport("user32.dll", SetLastError=true)]
  public static extern bool UnhookWindowsHookEx(IntPtr hhk);
}
"@
Add-Type -TypeDefinition $src

$h = [HookLoader]::LoadLibraryW($DllPath)
if ($h -eq [IntPtr]::Zero) { throw "LoadLibrary failed err=$([Runtime.InteropServices.Marshal]::GetLastWin32Error())" }
$p = [HookLoader]::GetProcAddress($h, "HookRetProc")
if ($p -eq [IntPtr]::Zero) { $p = [HookLoader]::GetProcAddressOrd($h, [UIntPtr]1) }
if ($p -eq [IntPtr]::Zero) { throw "GetProcAddress failed err=$([Runtime.InteropServices.Marshal]::GetLastWin32Error())" }
$hhk = [HookLoader]::SetWindowsHookExW(12, $p, $h, 0)
if ($hhk -eq [IntPtr]::Zero) { throw "SetWindowsHookEx failed err=$([Runtime.InteropServices.Marshal]::GetLastWin32Error())" }
Set-Content -Path "$StopFlag.ready" -Value "hook=0x$($hhk.ToString('x')) pid=$PID"

while (-not (Test-Path $StopFlag)) { Start-Sleep -Milliseconds 300 }
[HookLoader]::UnhookWindowsHookEx($hhk) | Out-Null
Remove-Item "$StopFlag.ready" -ErrorAction SilentlyContinue
