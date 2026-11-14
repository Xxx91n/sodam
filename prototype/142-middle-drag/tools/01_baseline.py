# 一次性探针 / 第 1 步：把发行版跑起来，记下环境，截个底图。
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from winprobe import *  # noqa

log('=== 第 1 步：启动发行版，记基线 ===')
log(f'python={sys.version.split()[0]} 屏幕={u.GetSystemMetrics(0)}x{u.GetSystemMetrics(1)}')
exe = os.path.join(os.environ['LOCALAPPDATA'], 'Programs', 'SodaM', 'sodam.exe')
log(f'exe={exe}')
ver = subprocess.check_output(
    ['powershell', '-NoProfile', '-Command',
     f'(Get-Item "{exe}").VersionInfo.FileVersion'], text=True).strip()
log(f'发行版文件版本={ver}（安装包 v0.3.9，未在本地编译 sodam）')

w = start_sodam(exe)
hwnd, pid, ttl, cls, r = w
log(f'主窗口 hwnd=0x{hwnd:x} pid={pid} title={ttl!r} class={cls!r} rect={r.L},{r.T}-{r.R},{r.B}')
ok, info, tid, gpid = gui_info(hwnd)
log(f'UI 线程 tid={tid} GetGUIThreadInfo ok={ok} capture=0x{(info.hwndCapture or 0):x} '
    f'focus=0x{(info.hwndFocus or 0):x} active=0x{(info.hwndActive or 0):x}')

# 把窗口摆到屏幕里，别让它压在别的东西下面
screen_w, screen_h = u.GetSystemMetrics(0), u.GetSystemMetrics(1)
win_w, win_h = r.R - r.L, r.B - r.T
if r.L < 0 or r.T < 0 or r.R > screen_w or r.B > screen_h:
    u.MoveWindow.argtypes = [wt.HWND, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int, wt.BOOL]
    u.MoveWindow(hwnd, 60, 60, min(win_w, screen_w - 120), min(win_h, screen_h - 120), True)
    time.sleep(1)
    r = rect(hwnd)
    log(f'挪过窗口，新 rect={r.L},{r.T}-{r.R},{r.B}')

u.SetForegroundWindow(hwnd)
time.sleep(1)
move((r.L + r.R) // 2, (r.T + r.B) // 2)
time.sleep(0.5)
snap('baseline_full.png')
log(f'截图=evidence/baseline_full.png 鼠标位置={cursor()} 前台窗口=0x{u.GetForegroundWindow():x}')
log(f'窗口内一点归谁: WindowFromPoint -> 0x{window_at((r.L+r.R)//2, (r.T+r.B)//2):x} '
    f'class={classname(window_at((r.L+r.R)//2, (r.T+r.B)//2))!r}')
log('=== 第 1 步完 ===')
