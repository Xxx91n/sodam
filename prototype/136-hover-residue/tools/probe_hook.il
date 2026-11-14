// PROTOTYPE / THROWAWAY — issue #136 evidence probe. Do not ship.
// Global WH_CALLWNDPROCRET logger. Injected into every GUI process while the
// hook is set; writes one pipe-separated line per interesting message.
// Line format: timestamp|pid|msg|hwnd|lRes|wp|lp   (all decimal)
// CWPRETSTRUCT offsets: x64 lResult@0 wp@8 lp@16 msg@24 hwnd@32
//                       x86 lResult@0 wp@4 lp@8  msg@12 hwnd@16
.assembly extern mscorlib
{
  .ver 4:0:0:0
}

.assembly probe_hook
{
  .ver 1:0:0:0
}

.module probe_hook.dll

.class public auto ansi beforefieldinit ProbeHook extends [mscorlib]System.Object
{
  .field private static string _path

  .method public static native int HookRetProc(int32 nCode, native int wParam, native int lParam)
  {
    .vtentry 1 : 1
    .export [1]
    .maxstack 8
    .locals init (
      [0] int32 msg,
      [1] bool is64,
      [2] native int vHwnd,
      [3] native int vLres,
      [4] native int vWp,
      [5] native int vLp
    )

    // nCode < 0 -> pass through untouched
    ldarg.0
    ldc.i4.0
    bge L_MSG

    ldc.i4 0
    ldarg.0
    ldarg.1
    ldarg.2
    call native int ProbeHook::CallNextHookEx(native int, int32, native int, native int)
    ret

L_MSG:
    call int32 [mscorlib]System.IntPtr::get_Size()
    ldc.i4.s 8
    beq L_IS64
    ldc.i4.0
    br L_HAS64
L_IS64:
    ldc.i4.1
L_HAS64:
    stloc.1

    // msg = *(int*)(lParam + off)
    ldarg.2
    ldloc.1
    brtrue L_M64
    ldc.i4.s 12
    br L_MGO
L_M64:
    ldc.i4.s 24
L_MGO:
    call int32 [mscorlib]System.Runtime.InteropServices.Marshal::ReadInt32(native int, int32)
    stloc.0

    // interesting: WM_CLOSE(16) WM_NCHITTEST(132) WM_ACTIVATE(134)
    // WM_NCMOUSEMOVE(160) WM_NCLBUTTONDOWN(161) WM_NCLBUTTONUP(162)
    // WM_SYSCOMMAND(274) WM_CAPTURECHANGED(533) WM_NCMOUSELEAVE(674) WM_MOUSELEAVE(675)
    ldloc.0
    ldc.i4 16
    beq L_HIT
    ldloc.0
    ldc.i4 132
    beq L_HIT
    ldloc.0
    ldc.i4 134
    beq L_HIT
    ldloc.0
    ldc.i4 160
    beq L_HIT
    ldloc.0
    ldc.i4 161
    beq L_HIT
    ldloc.0
    ldc.i4 162
    beq L_HIT
    ldloc.0
    ldc.i4 274
    beq L_HIT
    ldloc.0
    ldc.i4 533
    beq L_HIT
    ldloc.0
    ldc.i4 674
    beq L_HIT
    ldloc.0
    ldc.i4 675
    beq L_HIT

    // not interesting
    ldc.i4 0
    ldarg.0
    ldarg.1
    ldarg.2
    call native int ProbeHook::CallNextHookEx(native int, int32, native int, native int)
    ret

L_HIT:
    // hwnd
    ldarg.2
    ldloc.1
    brtrue L_H64
    ldc.i4.s 16
    br L_HGO
L_H64:
    ldc.i4.s 32
L_HGO:
    call native int [mscorlib]System.Runtime.InteropServices.Marshal::ReadIntPtr(native int, int32)
    stloc.2
    // lResult (always @0)
    ldarg.2
    ldc.i4.s 0
    call native int [mscorlib]System.Runtime.InteropServices.Marshal::ReadIntPtr(native int, int32)
    stloc.3
    // wParam field
    ldarg.2
    ldloc.1
    brtrue L_W64
    ldc.i4.s 4
    br L_WGO
L_W64:
    ldc.i4.s 8
L_WGO:
    call native int [mscorlib]System.Runtime.InteropServices.Marshal::ReadIntPtr(native int, int32)
    stloc.s 4
    // lParam field
    ldarg.2
    ldloc.1
    brtrue L_P64
    ldc.i4.s 8
    br L_PGO
L_P64:
    ldc.i4.s 16
L_PGO:
    call native int [mscorlib]System.Runtime.InteropServices.Marshal::ReadIntPtr(native int, int32)
    stloc.s 5

    ldloc.0
    ldloc.2
    ldloc.3
    ldloc.s 4
    ldloc.s 5
    call void ProbeHook::Log(int32, native int, native int, native int, native int)

    ldc.i4 0
    ldarg.0
    ldarg.1
    ldarg.2
    call native int ProbeHook::CallNextHookEx(native int, int32, native int, native int)
    ret
  }

  .method private static void Log(int32 msg, native int hwnd, native int lResult, native int wp, native int lp)
  {
    .maxstack 8
    .locals init (
      [0] valuetype [mscorlib]System.DateTime dt,
      [1] string[] arr,
      [2] string line,
      [3] int32 pid
    )
    .try
    {
      call valuetype [mscorlib]System.DateTime [mscorlib]System.DateTime::get_Now()
      stloc.0
      call int32 ProbeHook::GetCurrentProcessId()
      stloc.3

      ldc.i4.s 13
      newarr [mscorlib]System.String
      stloc.1

      ldloc.1
      ldc.i4.s 0
      ldloc.0
      ldstr "yyyy-MM-dd HH:mm:ss.fff"
      call instance string [mscorlib]System.DateTime::ToString(string)
      stelem.ref

      ldloc.1
      ldc.i4.s 1
      ldstr "|pid="
      stelem.ref

      ldloc.1
      ldc.i4.s 2
      ldloc.3
      box [mscorlib]System.Int32
      stelem.ref

      ldloc.1
      ldc.i4.s 3
      ldstr "|msg="
      stelem.ref

      ldloc.1
      ldc.i4.s 4
      ldarg.0
      box [mscorlib]System.Int32
      stelem.ref

      ldloc.1
      ldc.i4.s 5
      ldstr "|hwnd="
      stelem.ref

      ldloc.1
      ldc.i4.s 6
      ldarg.1
      box [mscorlib]System.IntPtr
      stelem.ref

      ldloc.1
      ldc.i4.s 7
      ldstr "|lRes="
      stelem.ref

      ldloc.1
      ldc.i4.s 8
      ldarg.2
      box [mscorlib]System.IntPtr
      stelem.ref

      ldloc.1
      ldc.i4.s 9
      ldstr "|wp="
      stelem.ref

      ldloc.1
      ldc.i4.s 10
      ldarg.3
      box [mscorlib]System.IntPtr
      stelem.ref

      ldloc.1
      ldc.i4.s 11
      ldstr "|lp="
      stelem.ref

      ldloc.1
      ldc.i4.s 12
      ldarg.s 4
      box [mscorlib]System.IntPtr
      stelem.ref

      ldloc.1
      call string [mscorlib]System.String::Concat(object[])
      stloc.2

      call string ProbeHook::GetLogPath()
      ldloc.2
      call void [mscorlib]System.IO.File::AppendAllText(string, string)
      leave L_LOGDONE
    }
    catch [mscorlib]System.Exception
    {
      pop
      leave L_LOGDONE
    }
L_LOGDONE:
    ret
  }

  .method private static string GetLogPath()
  {
    .maxstack 8
    ldsfld string ProbeHook::_path
    brtrue L_PTH
    ldstr "C:\\sodam\\prototype\\136-hover-residue\\evidence\\hooklog.txt"
    stsfld string ProbeHook::_path
L_PTH:
    ldsfld string ProbeHook::_path
    ret
  }

  .method public static pinvokeimpl("user32.dll" lasterr) native int CallNextHookEx(native int hhk, int32 nCode, native int wParam, native int lParam) {}

  .method public static pinvokeimpl("kernel32.dll" lasterr) int32 GetCurrentProcessId() {}

  .method public specialname rtspecialname instance void .ctor()
  {
    .maxstack 8
    ldarg.0
    call instance void [mscorlib]System.Object::.ctor()
    ret
  }
}
