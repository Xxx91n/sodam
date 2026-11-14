# 一次性探针 / 第 2 步：拿发行版真机走一遍中键。
# 只往窗口里发中键和滚轮，看 Windows 和 GPUI 平台层怎么接，不改客户端一个字节。
import os
import sys
import time
import zlib
import struct
from datetime import datetime

sys.path.insert(0, os.path.dirname(__file__))
from winprobe import *  # noqa

HEADER = ['time', 'step', 'cursorX', 'cursorY', 'capture_is_sodam', 'captureHwnd',
          'middleHeld', 'foregroundHwnd', 'windowAtPoint', 'classAtPoint', 'titleAtPoint', 'note']


def png_rgb(path):
    data = open(path, 'rb').read()
    pos, idat, w, h = 8, b'', 0, 0
    while pos < len(data):
        ln = struct.unpack('>I', data[pos:pos + 4])[0]
        tag = data[pos + 4:pos + 8]
        payload = data[pos + 8:pos + 8 + ln]
        pos += 12 + ln
        if tag == b'IHDR':
            w, h = struct.unpack('>II', payload[:8])
        elif tag == b'IDAT':
            idat += payload
    raw = zlib.decompress(idat)
    stride = w * 3 + 1
    return w, h, b''.join(raw[i * stride + 1:(i + 1) * stride] for i in range(h))


def diff_ratio(a, b, threshold=10):
    wa, ha, ra = png_rgb(a)
    wb, hb, rb = png_rgb(b)
    if (wa, ha) != (wb, hb):
        return -1.0
    changed = 0
    for i in range(0, len(ra), 3):
        if abs(ra[i] - rb[i]) + abs(ra[i + 1] - rb[i + 1]) + abs(ra[i + 2] - rb[i + 2]) > threshold * 3:
            changed += 1
    return changed / (wa * ha)


def main():
    w = start_sodam()
    hwnd, pid, _, _, r = w
    tid, _ = tid_of(hwnd)
    log('=== 第 2 步：中键真机探针 ===')
    log(f'窗口 hwnd=0x{hwnd:x} pid={pid} tid={tid} rect={r.L},{r.T}-{r.R},{r.B}')

    # 只看设置页主内容的一块，避开侧栏、播放条、任务栏时钟
    box = (r.L + 130, r.T + 300, 840, 260)
    cx, cy = r.L + 700, r.T + 430
    outx, outy = min(r.R + 70, u.GetSystemMetrics(0) - 10), r.T + 300

    def shot(tag):
        return screenshot(tag, *box)

    def state(step, note=''):
        ok, info, _, _ = gui_info(hwnd)
        cap = info.hwndCapture or 0
        fg = u.GetForegroundWindow()
        px, py = cursor()
        wp = window_at(px, py)
        held = middle_held()
        csv_row('middle_events.csv', HEADER,
                [datetime.now().strftime('%H:%M:%S.%f')[:-3], step, px, py, int(cap == hwnd),
                 f'0x{cap:x}', int(held), f'0x{fg:x}', f'0x{wp:x}',
                 classname(wp), title(wp)[:40].replace(',', ';'), note])
        return cap, held, fg, wp

    def settle(ms=250):
        time.sleep(ms / 1000)

    try:
        u.SetForegroundWindow(hwnd)
        settle(700)
        move(cx, cy)
        settle(300)
        cap, held, fg, _ = state('00_初始', '前台是 SodaM，光标在设置页内容区')
        log(f'初始：capture=0x{cap:x} 中键按住={held} 前台=0x{fg:x}')

        # --- A. 先证明这块内容真的能滚：用滚轮 ---
        before_wheel = shot('a1_before_wheel.png')
        for _ in range(4):
            wheel(-120)
            settle(90)
        settle(500)
        after_wheel = shot('a2_after_wheel.png')
        d_wheel = diff_ratio(before_wheel, after_wheel)
        log(f'A 滚轮对照：往下滚 4 格，画面变化像素占比={d_wheel:.4f}（>0 说明这块能滚）')
        state('01_滚轮之后', '滚轮对照')
        for _ in range(4):
            wheel(120)
            settle(90)
        settle(400)
        shot('a3_wheel_back.png')

        # --- B. 中键拖 120 像素，看发行版有没有反应 ---
        before_drag = shot('b1_before_drag.png')
        move(cx, cy)
        settle(200)
        middle_down()
        settle(150)
        state('02_中键按下', '窗口内按下')
        for i in range(1, 13):
            move(cx, cy + i * 10)
            settle(35)
            if i in (3, 6, 9, 12):
                state(f'03_拖动_{i}', f'往下拖 {i * 10}px，仍在窗口内')
        during = shot('b2_during_drag.png')
        middle_up()
        settle(400)
        after_drag = shot('b3_after_drag.png')
        d_drag = diff_ratio(before_drag, after_drag)
        d_drag_during = diff_ratio(before_drag, during)
        state('04_中键松开_窗口内', '窗口内松开')
        log(f'B 中键拖动基线：拖动中画面变化={d_drag_during:.4f} 松开后变化={d_drag:.4f}')
        log('   （发行版没有中键拖动功能，预期都是 0；这只是基线，不是原型验证）')

        # --- C. 拖出窗口再松手：问题 2 的平台层 ---
        move(cx, cy)
        settle(200)
        middle_down()
        settle(150)
        cap_down, _, _, _ = state('10_中键按下_准备拖出', '在内容区按下')
        log(f'C 按下瞬间 capture=0x{cap_down:x}（等于 0x{hwnd:x} 才是 SetCapture 生效）')
        for i in range(1, 7):
            x = int(cx + (outx - cx) * i / 6)
            move(x, cy)
            settle(90)
            cap, held, fg, wp = state(f'11_拖出_{i}', '光标在窗口外' if x > r.R else '光标还在窗口内')
        log(f'   松手前光标=({cursor()[0]},{cursor()[1]})，WindowFromPoint=0x{wp:x} class={classname(wp)!r}')
        shot('c1_outside_before_up.png')
        middle_up()
        settle(400)
        cap_up, held_up, _, _ = state('12_窗口外松开', '在窗口外松开中键')
        log(f'C 窗口外松开后：capture=0x{cap_up:x} 中键仍按住={held_up}')
        for i, dy in enumerate((20, 60, 120), 1):
            move(outx, cy + dy)
            settle(120)
            state(f'13_松开后继续移动_{i}', '不按键，只是移动鼠标')
        shot('c2_after_outside_up.png')

        # --- D. 中键按下时失焦：切到别的窗口 ---
        move(cx, cy)
        u.SetForegroundWindow(hwnd)
        settle(400)
        middle_down()
        settle(150)
        state('20_按下后失焦前', '准备切走')
        others = [x for x in top_windows()
                  if x[0] != hwnd and x[2] and (x[4].R - x[4].L) > 400 and x[1] != pid]
        if others:
            other = others[0]
            moved = u.SetForegroundWindow(other[0])
            settle(600)
            cap, held, fg, _ = state('21_切到别的窗口', f'目标=0x{other[0]:x} {other[2][:30]} SetForegroundWindow={moved}')
            log(f'D 失焦：前台=0x{fg:x} capture=0x{cap:x} 中键仍按住={held}')
            middle_up()
            settle(250)
            state('22_失焦后松开', '清理')
        else:
            log('D 失焦：没找到别的可见窗口，跳过')
        u.SetForegroundWindow(hwnd)
        settle(400)
        if middle_held():
            middle_up()

        # --- E. 中键按下时最小化 ---
        move(cx, cy)
        settle(200)
        middle_down()
        settle(150)
        state('30_按下后最小化前', '准备最小化')
        u.ShowWindow(hwnd, 6)  # SW_MINIMIZE
        settle(700)
        cap, held, fg, _ = state('31_已最小化', '窗口最小化，中键还按着')
        log(f'E 最小化：capture=0x{cap:x} 中键仍按住={held} 前台=0x{fg:x}')
        middle_up()
        settle(250)
        u.ShowWindow(hwnd, 9)  # SW_RESTORE
        settle(700)
        u.SetForegroundWindow(hwnd)
        state('32_恢复后', '窗口恢复')
        shot('e1_after_restore.png')

        # --- F. 中键只点一下，会不会误触发按钮（Q4 基线）---
        btn = (r.L + 575, r.T + 152)  # 设置页「去登录」黑色按钮中心
        move(*btn)
        settle(300)
        before_click = shot('f1_before_click.png')
        middle_down()
        settle(60)
        middle_up()
        settle(700)
        after_click = shot('f2_after_click.png')
        d_click = diff_ratio(before_click, after_click)
        state('40_中键单击登录按钮', f'点了「去登录」一下，画面变化={d_click:.4f}')
        log(f'F 中键单击「去登录」：画面变化像素占比={d_click:.4f}（0 表示没触发点击）')

        # --- G. 指针有没有变（只作基线）---
        # 记一下按下前后的全局光标句柄
        log('G 指针/滚动条/惯性：依赖原型实现，发行版里没有这套逻辑，这一项标「没验成」')

        log('=== 第 2 步完 ===')
    finally:
        if middle_held():
            middle_up()
        u.ShowWindow(hwnd, 9)
        u.SetForegroundWindow(hwnd)
        move(cx, cy)
        log('清理：松开中键、恢复窗口、把鼠标挪回内容区')


if __name__ == '__main__':
    main()
