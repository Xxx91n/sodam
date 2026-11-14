// PROBE: minimal export test — return a+b.
.assembly extern mscorlib { .ver 4:0:0:0 }
.assembly mini { .ver 1:0:0:0 }
.module mini.dll

.class public auto ansi beforefieldinit Mini extends [mscorlib]System.Object
{
  .method public static int32 TestAdd(int32 a, int32 b)
  {
    .vtentry 1 : 1
    .export [1]
    .maxstack 2
    ldarg.0
    ldarg.1
    add
    ret
  }

  .method public static native int TestPassthrough(int32 nCode, native int wp, native int lp)
  {
    .vtentry 2 : 1
    .export [2]
    .maxstack 4
    ldc.i4 0
    ldarg.0
    ldarg.1
    ldarg.2
    call native int Mini::CallNextHookEx(native int, int32, native int, native int)
    ret
  }

  .method public static pinvokeimpl("user32.dll" lasterr) native int CallNextHookEx(native int hhk, int32 nCode, native int wParam, native int lParam) {}
}
