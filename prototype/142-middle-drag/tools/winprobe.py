# 一次性探针，只给 issue #142 原型用，不要合进正式代码。
# 只用 Python 自带的 ctypes 调 Windows 现成的 API，不装包、不编译任何东西。
import ctypes
import ctypes.wintypes as wt
import os
import struct
import subprocess
import sys
import time
import zlib

EV = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'evidence'))
os.makedirs(EV, exist_ok=True)

try:
    ctypes.windll.shcore.SetProcessDpiAwareness(2)  # 坐标按屏幕物理像素算
except Exception:
    pass

u = ctypes.WinDLL('user32', use_last_error=True)
g = ctypes.WinDLL('gdi32', use_last_error=True)


class POINT(ctypes.Structure):
    _fields_ = [('x', ctypes.c_long), ('y', ctypes.c_long)]


class RECT(ctypes.Structure):
    _fields_ = [('L', ctypes.c_long), ('T', ctypes.c_long),
                ('R', ctypes.c_long), ('B', ctypes.c_long)]


class GUITHREADINFO(ctypes.Structure):
    _fields_ = [('cbSize', wt.DWORD), ('flags', wt.DWORD),
                ('hwndActive', wt.HWND), ('hwndFocus', wt.HWND),
                ('hwndCapture', wt.HWND), ('hwndMenuOwner', wt.HWND),
                ('hwndMoveSize', wt.HWND), ('hwndCaret', wt.HWND),
                ('rcCaret', RECT)]


class BITMAPINFOHEADER(ctypes.Structure):
    _fields_ = [('biSize', wt.DWORD), ('biWidth', ctypes.c_long),
                ('biHeight', ctypes.c_long), ('biPlanes', wt.WORD),
                ('biBitCount', wt.WORD), ('biCompression', wt.DWORD),
                ('biSizeImage', wt.DWORD), ('biXPelsPerMeter', ctypes.c_long),
                ('biYPelsPerMeter', ctypes.c_long), ('biClrUsed', wt.DWORD),
                ('biClrImportant', wt.DWORD)]


class BITMAPINFO(ctypes.Structure):
    _fields_ = [('bmiHeader', BITMAPINFOHEADER), ('bmiColors', wt.DWORD * 3)]


WNDENUMPROC = ctypes.WINFUNCTYPE(wt.BOOL, wt.HWND, wt.LPARAM)

u.GetSystemMetrics.argtypes = [ctypes.c_int]
u.GetDC.argtypes = [wt.HWND]
u.GetDC.restype = wt.HDC
u.ReleaseDC.argtypes = [wt.HWND, wt.HDC]
u.SetCursorPos.argtypes = [ctypes.c_int, ctypes.c_int]
u.GetCursorPos.argtypes = [ctypes.POINTER(POINT)]
u.mouse_event.argtypes = [wt.DWORD, wt.DWORD, wt.DWORD, wt.DWORD, ctypes.c_void_p]
u.GetAsyncKeyState.argtypes = [ctypes.c_int]
u.GetAsyncKeyState.restype = ctypes.c_short
u.GetWindowRect.argtypes = [wt.HWND, ctypes.POINTER(RECT)]
u.GetWindowThreadProcessId.argtypes = [wt.HWND, ctypes.POINTER(wt.DWORD)]
u.GetGUIThreadInfo.argtypes = [wt.DWORD, ctypes.POINTER(GUITHREADINFO)]
u.WindowFromPoint.argtypes = [POINT]
u.WindowFromPoint.restype = wt.HWND
u.GetForegroundWindow.restype = wt.HWND
u.SetForegroundWindow.argtypes = [wt.HWND]
u.ShowWindow.argtypes = [wt.HWND, ctypes.c_int]
u.IsIconic.argtypes = [wt.HWND]
u.IsWindowVisible.argtypes = [wt.HWND]
u.GetWindowTextW.argtypes = [wt.HWND, wt.LPWSTR, ctypes.c_int]
u.GetClassNameW.argtypes = [wt.HWND, wt.LPWSTR, ctypes.c_int]
u.EnumWindows.argtypes = [WNDENUMPROC, wt.LPARAM]
u.GetClassNameW.restype = ctypes.c_int
g.CreateCompatibleDC.argtypes = [wt.HDC]
g.CreateCompatibleDC.restype = wt.HDC
g.CreateCompatibleBitmap.argtypes = [wt.HDC, ctypes.c_int, ctypes.c_int]
g.CreateCompatibleBitmap.restype = wt.HBITMAP
g.SelectObject.argtypes = [wt.HDC, wt.HGDIOBJ]
g.SelectObject.restype = wt.HGDIOBJ
g.DeleteObject.argtypes = [wt.HGDIOBJ]
g.DeleteDC.argtypes = [wt.HDC]
g.BitBlt.argtypes = [wt.HDC, ctypes.c_int, ctypes.c_int, ctypes.c_int,
                     ctypes.c_int, wt.HDC, ctypes.c_int, ctypes.c_int, wt.DWORD]
g.GetDIBits.argtypes = [wt.HDC, wt.HBITMAP, wt.UINT, wt.UINT,
                        ctypes.c_void_p, ctypes.c_void_p, wt.UINT]

MIDDLEDOWN, MIDDLEUP, MOVE, WHEEL = 0x20, 0x40, 0x1, 0x800
VK_MBUTTON = 0x04
SRCCOPY = 0x00CC0020


def ev(name):
    return os.path.join(EV, name)


def log(line, name='run.log'):
    text = f'{time.strftime("%H:%M:%S")} {line}'
    with open(ev(name), 'a', encoding='utf-8') as f:
        f.write(text + '\n')
    print(text, flush=True)


def screenshot(name, x=0, y=0, w=None, h=None):
    """抓一块屏幕，存成 PNG；纯 ctypes + zlib，不用第三方库。"""
    if w is None:
        w = u.GetSystemMetrics(0)
    if h is None:
        h = u.GetSystemMetrics(1)
    hdc = u.GetDC(0)
    mem = g.CreateCompatibleDC(hdc)
    bmp = g.CreateCompatibleBitmap(hdc, w, h)
    old = g.SelectObject(mem, bmp)
    g.BitBlt(mem, 0, 0, w, h, hdc, x, y, SRCCOPY)
    bi = BITMAPINFO()
    bi.bmiHeader.biSize = ctypes.sizeof(BITMAPINFOHEADER)
    bi.bmiHeader.biWidth = w
    bi.bmiHeader.biHeight = -h  # 负数 = 从上往下排，省得再翻一遍
    bi.bmiHeader.biPlanes = 1
    bi.bmiHeader.biBitCount = 32
    bi.bmiHeader.biCompression = 0
    buf = ctypes.create_string_buffer(w * h * 4)
    g.GetDIBits(mem, bmp, 0, h, buf, ctypes.byref(bi), 0)
    data = buf.raw
    raw = bytearray()
    for row in range(h):
        src = row * w * 4
        raw.append(0)  # PNG 每行的过滤字节
        line = bytearray(w * 3)
        line[0::3] = data[src + 2:src + 2 + 4 * w:4]
        line[1::3] = data[src + 1:src + 1 + 4 * w:4]
        line[2::3] = data[src:src + 4 * w:4]
        raw += line

    def chunk(tag, payload):
        return struct.pack('>I', len(payload)) + tag + payload + \
            struct.pack('>I', zlib.crc32(tag + payload) & 0xffffffff)

    png = (b'\x89PNG\r\n\x1a\n'
           + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
           + chunk(b'IDAT', zlib.compress(bytes(raw), 6))
           + chunk(b'IEND', b''))
    path = ev(name) if not os.path.isabs(name) else name
    with open(path, 'wb') as f:
        f.write(png)
    g.SelectObject(mem, old)
    g.DeleteObject(bmp)
    g.DeleteDC(mem)
    u.ReleaseDC(0, hdc)
    return path


def cursor():
    p = POINT()
    u.GetCursorPos(ctypes.byref(p))
    return p.x, p.y


def move(x, y):
    u.SetCursorPos(int(x), int(y))


def middle_down():
    u.mouse_event(MIDDLEDOWN, 0, 0, 0, None)


def middle_up():
    u.mouse_event(MIDDLEUP, 0, 0, 0, None)


def wheel(delta):
    u.mouse_event(WHEEL, 0, 0, ctypes.c_int(delta).value & 0xffffffff, None)


def middle_held():
    return bool(u.GetAsyncKeyState(VK_MBUTTON) & 0x8000)


def rect(hwnd):
    r = RECT()
    u.GetWindowRect(hwnd, ctypes.byref(r))
    return r


def title(hwnd):
    b = ctypes.create_unicode_buffer(512)
    u.GetWindowTextW(hwnd, b, 512)
    return b.value


def classname(hwnd):
    b = ctypes.create_unicode_buffer(256)
    u.GetClassNameW(hwnd, b, 256)
    return b.value


def tid_of(hwnd):
    pid = wt.DWORD()
    return u.GetWindowThreadProcessId(hwnd, ctypes.byref(pid)), pid.value


def gui_info(hwnd):
    tid, pid = tid_of(hwnd)
    info = GUITHREADINFO()
    info.cbSize = ctypes.sizeof(GUITHREADINFO)
    ok = u.GetGUIThreadInfo(tid, ctypes.byref(info))
    return ok, info, tid, pid


def window_at(x, y):
    return u.WindowFromPoint(POINT(int(x), int(y)))


def sodam_pids():
    out = subprocess.check_output(
        ['tasklist', '/FI', 'IMAGENAME eq sodam.exe', '/FO', 'CSV', '/NH'],
        text=True, errors='ignore')
    pids = set()
    for line in out.splitlines():
        parts = [p.strip('"') for p in line.split('","')]
        if len(parts) > 1 and parts[1].isdigit():
            pids.add(int(parts[1]))
    return pids


def top_windows():
    found = []

    def cb(hwnd, _):
        if u.IsWindowVisible(hwnd):
            pid = wt.DWORD()
            u.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
            found.append((hwnd, pid.value, title(hwnd), classname(hwnd), rect(hwnd)))
        return True

    u.EnumWindows(WNDENUMPROC(cb), 0)
    return found


def sodam_window():
    pids = sodam_pids()
    wins = [w for w in top_windows() if w[1] in pids and w[4].R - w[4].L > 300]
    if not wins:
        return None
    wins.sort(key=lambda w: (w[4].R - w[4].L) * (w[4].B - w[4].T), reverse=True)
    return wins[0]


def start_sodam(exe=None, wait=8):
    if exe is None:
        exe = os.path.join(os.environ['LOCALAPPDATA'], 'Programs', 'SodaM', 'sodam.exe')
    if not sodam_pids():
        subprocess.Popen([exe], close_fds=True)
        time.sleep(wait)
    for _ in range(10):
        w = sodam_window()
        if w:
            return w
        time.sleep(1)
    raise RuntimeError('没找到 sodam 主窗口')


def snap(label, hwnd=None, pad=0):
    if hwnd is None:
        return screenshot(label)
    r = rect(hwnd)
    x, y = max(0, r.L - pad), max(0, r.T - pad)
    w = min(u.GetSystemMetrics(0) - x, r.R - r.L + 2 * pad)
    h = min(u.GetSystemMetrics(1) - y, r.B - r.T + 2 * pad)
    return screenshot(label, x, y, w, h)


def csv_row(name, header, row):
    path = ev(name)
    if not os.path.exists(path):
        with open(path, 'w', encoding='utf-8') as f:
            f.write(','.join(header) + '\n')
    with open(path, 'a', encoding='utf-8') as f:
        f.write(','.join(str(v).replace(',', ';') for v in row) + '\n')
