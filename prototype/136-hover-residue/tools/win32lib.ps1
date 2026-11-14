# PROTOTYPE / THROWAWAY - issue #136 probe helpers. Dot-source from drivers.
$ErrorActionPreference = 'Stop'
$src = @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class W32 {
  public struct POINT { public int X; public int Y; }
  public struct RECT { public int L; public int T; public int R; public int B; }
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, StringBuilder sb, int max);
  [DllImport("user32.dll")] public static extern int GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr h);
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr GetModuleHandleW(string name);
  [DllImport("user32.dll")] public static extern IntPtr SendMessageW(IntPtr h, uint msg, IntPtr wp, IntPtr lp);
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int hgt, bool repaint);
  [DllImport("user32.dll")] public static extern bool PostMessageW(IntPtr h, uint msg, IntPtr wp, IntPtr lp);
  [DllImport("user32.dll")] public static extern int GetWindowLongW(IntPtr h, int idx);
}
"@
if (-not ('W32' -as [type])) { Add-Type -TypeDefinition $src }

function Get-Cursor { $p = New-Object W32+POINT; [W32]::GetCursorPos([ref]$p) | Out-Null; $p }
function Set-Cursor2([int]$x, [int]$y) { [W32]::SetCursorPos($x, $y) | Out-Null }
function Click-Left {
  [W32]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero)   # LEFTDOWN
  Start-Sleep -Milliseconds 60
  [W32]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero)   # LEFTUP
}
function Get-WindowRect2([IntPtr]$h) {
  $r = New-Object W32+RECT
  [W32]::GetWindowRect($h, [ref]$r) | Out-Null
  $r
}
function Get-WindowTitle([IntPtr]$h) {
  $sb = New-Object System.Text.StringBuilder 256
  [W32]::GetWindowTextW($h, $sb, 256) | Out-Null
  $sb.ToString()
}
function Get-WindowPid([IntPtr]$h) { $dummy = 0; $tid = [W32]::GetWindowThreadProcessId($h, [ref]$dummy); $dummy }
function Window-At([int]$x, [int]$y) {
  $p = New-Object W32+POINT
  $p.X = $x; $p.Y = $y
  [W32]::WindowFromPoint($p)
}
# Screenshot a region of the screen; returns the Bitmap (caller disposes).
function Snap-Region([int]$x, [int]$y, [int]$w, [int]$h, [string]$file) {
  Add-Type -AssemblyName System.Drawing
  $bmp = New-Object System.Drawing.Bitmap $w, $h
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($x, $y, 0, 0, $bmp.Size)
  $g.Dispose()
  if ($file) { $bmp.Save($file, [System.Drawing.Imaging.ImageFormat]::Png) }
  $bmp
}
