# 一次性探针 / 第 3 步：把「中键拖动到底滚不滚页面」钉死。
# 上一步画面变化其实是鼠标悬停高亮，这里用「鼠标回到原位再比」+「整块内容垂直位移」两种办法复核。
import os
import sys
import time

sys.dont_write_bytecode = True  # 别让一次性探针在目录里留 __pycache__
sys.path.insert(0, os.path.dirname(__file__))
from winprobe import *  # noqa
from importlib.machinery import SourceFileLoader

_m = SourceFileLoader('_p', os.path.join(os.path.dirname(__file__), '02_middle_probe.py')).load_module()
png_rgb, diff_ratio = _m.png_rgb, _m.diff_ratio


def row_profile(rgb, w, h):
    return [[rgb[(y * w + x) * 3] for x in range(0, w, 8)] for y in range(h)]


def best_shift(a, b, maxshift=90):
    wa, ha, ra = png_rgb(a)
    wb, hb, rb = png_rgb(b)
    if (wa, ha) != (wb, hb):
        return None
    pa, pb = row_profile(ra, wa, ha), row_profile(rb, wb, hb)
    best = (1e9, 0)
    for s in range(-maxshift, maxshift + 1):
        cost, n = 0, 0
        for y in range(maxshift, ha - maxshift):
            va, vb = pa[y], pb[y + s]
            cost += sum(abs(i - j) for i, j in zip(va, vb))
            n += len(va)
        avg = cost / n
        if avg < best[0]:
            best = (avg, s)
    return round(best[0], 2), best[1]


def main():
    w = start_sodam()
    hwnd, pid, _, _, r = w
    log('=== 第 3 步：中键拖动有没有滚页面（复核） ===')
    log(f'窗口 hwnd=0x{hwnd:x} pid={pid} rect={r.L},{r.T}-{r.R},{r.B}')
    box = (r.L + 130, r.T + 300, 840, 260)
    cx, cy = r.L + 700, r.T + 430

    def shot(tag):
        return screenshot(tag, *box)

    def calm(ms=700):
        time.sleep(ms / 1000)

    try:
        u.SetForegroundWindow(hwnd)
        calm()
        move(cx, cy)
        calm(1400)  # 等滚轮动画、悬停动画都停
        v1 = shot('v1_idle.png')

        middle_down()
        calm(350)
        v2 = shot('v2_down_only.png')
        log(f'只按下、不移动：画面变化={diff_ratio(v1, v2):.4f} '
            f'垂直位移={best_shift(v1, v2)}（0 表示按下本身没改画面）')

        for i in range(1, 13):
            move(cx, cy + i * 10)
            time.sleep(0.035)
            if i == 4:
                shot('v3a_drag_40.png')
            if i == 8:
                shot('v3b_drag_80.png')
        v3 = shot('v3c_drag_120.png')
        middle_up()
        calm(200)
        move(cx, cy)          # 鼠标回原位，让悬停状态也复原
        calm(900)
        v4 = shot('v4_back_after_drag.png')
        d_back = diff_ratio(v1, v4)
        s_back = best_shift(v1, v4)
        log(f'中键拖 120px、松开、鼠标回原位：画面变化={d_back:.4f} 垂直位移={s_back}')
        log('   （两个都接近 0 = 页面一格没滚；上一步那 0.1263 是「深色」那行的悬停底色）')

        # 对照：同一套判定，换成滚轮，必须测出非零位移，否则判定方法本身不成立
        for _ in range(3):
            wheel(-120)
            time.sleep(0.09)
        move(cx, cy)
        calm(1100)
        v5 = shot('v5_after_wheel.png')
        d_wheel = diff_ratio(v1, v5)
        s_wheel = best_shift(v1, v5)
        log(f'对照：滚轮往下 3 格、鼠标回原位：画面变化={d_wheel:.4f} 垂直位移={s_wheel}')
        log('   （这里必须非 0，证明这块内容确实能滚、上面那个判定法管用）')

        # 再拖一次更大的距离，排除「拖得不够远」
        for _ in range(3):
            wheel(120)
            time.sleep(0.09)
        move(cx, cy)
        calm(1300)
        v6 = shot('v6_reset.png')
        middle_down()
        for i in range(1, 21):
            move(cx, cy + i * 15)
            time.sleep(0.03)
        middle_up()
        calm(200)
        move(cx, cy)
        calm(900)
        v7 = shot('v7_back_after_300.png')
        log(f'中键拖 300px、松开、鼠标回原位：画面变化={diff_ratio(v6, v7):.4f} '
            f'垂直位移={best_shift(v6, v7)}')

        ok, info, _, _ = gui_info(hwnd)
        log(f'收尾状态：capture=0x{(info.hwndCapture or 0):x} 中键按住={middle_held()} '
            f'前台=0x{u.GetForegroundWindow():x}')
        log('=== 第 3 步完 ===')
    finally:
        if middle_held():
            middle_up()
        move(cx, cy)
        u.SetForegroundWindow(hwnd)


if __name__ == '__main__':
    main()
