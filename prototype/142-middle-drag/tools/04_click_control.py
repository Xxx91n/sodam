# 一次性探针 / 第 4 步：中键到底算不算「点」。
# 拿侧栏菜单当靶子：中键点一下应该啥也不发生，左键点一下必须切页，这样对照才站得住。
import os
import sys
import time

sys.dont_write_bytecode = True  # 别让一次性探针在目录里留 __pycache__
sys.path.insert(0, os.path.dirname(__file__))
from winprobe import *  # noqa
from importlib.machinery import SourceFileLoader

_m = SourceFileLoader('_p', os.path.join(os.path.dirname(__file__), '02_middle_probe.py')).load_module()
diff_ratio = _m.diff_ratio
LEFTDOWN, LEFTUP = 0x2, 0x4


def click(x, y, down, up, hold=0.06):
    move(x, y)
    time.sleep(0.35)
    u.mouse_event(down, 0, 0, 0, None)
    time.sleep(hold)
    u.mouse_event(up, 0, 0, 0, None)
    time.sleep(0.9)


def main():
    w = start_sodam()
    hwnd, pid, _, _, r = w
    log('=== 第 4 步：中键会不会被当成点击（Q4 误触） ===')
    log(f'窗口 hwnd=0x{hwnd:x} pid={pid} rect={r.L},{r.T}-{r.R},{r.B}')
    # 坐标按 20:21 实测的窗口布局量：侧栏宽 224，菜单 y 见 debug_current.png
    discover = (r.L + 70, r.T + 123)  # 侧栏「推荐」
    settings = (r.L + 70, r.T + 530)  # 侧栏「设置」
    login_btn = (r.L + 645, r.T + 235)  # 设置页「去登录」
    neutral = (r.L + 700, r.T + 430)

    def shot(tag):
        return snap(tag, hwnd)

    try:
        u.SetForegroundWindow(hwnd)
        time.sleep(0.8)
        click(*settings, LEFTDOWN, LEFTUP)  # 先回到设置页
        move(*neutral)
        time.sleep(0.9)
        c0 = shot('g0_settings.png')

        click(*discover, MIDDLEDOWN, MIDDLEUP)
        move(*neutral)
        time.sleep(0.8)
        c1 = shot('g1_after_middle_click.png')
        d_mid = diff_ratio(c0, c1)
        log(f'中键单击「推荐」：整窗画面变化={d_mid:.4f}（0 = 没切页、没弹东西）')

        click(*discover, LEFTDOWN, LEFTUP)
        move(*neutral)
        time.sleep(0.8)
        c2 = shot('g2_after_left_click.png')
        d_left = diff_ratio(c0, c2)
        log(f'左键单击「推荐」（对照）：整窗画面变化={d_left:.4f}（明显 >0 = 真的切页了）')

        click(*settings, LEFTDOWN, LEFTUP)
        move(*neutral)
        time.sleep(5)  # 等「请先登录」的小气泡自己消失，别把它算到下一条上
        c3 = shot('g3_back_settings.png')
        d_back = diff_ratio(c0, c3)
        log(f'左键点回「设置」：跟最开始比变化={d_back:.4f}（接近 0 = 实验没留下副作用）')

        # 再拿一个真按钮试试：中键点「去登录」不应该弹登录
        click(*login_btn, MIDDLEDOWN, MIDDLEUP)
        move(*neutral)
        time.sleep(0.8)
        c4 = shot('g4_middle_login.png')
        d_login = diff_ratio(c3, c4)
        log(f'中键单击「去登录」：画面变化={d_login:.4f}（0 = 没弹登录窗口）')

        import hashlib
        md5 = lambda p: hashlib.md5(open(p, 'rb').read()).hexdigest()[:10]
        log(f'字节级复核：基线={md5(c0)} 中键点推荐={md5(c1)} '
            f'左键点推荐={md5(c2)} 中键点去登录={md5(c4)}')
        ok, info, _, _ = gui_info(hwnd)
        log(f'收尾：capture=0x{(info.hwndCapture or 0):x} 中键按住={middle_held()} '
            f'前台=0x{u.GetForegroundWindow():x}')
        log(f'判定：中键={d_mid:.4f} vs 左键={d_left:.4f}；去登录中键={d_login:.4f}，'
            f'{"中键没被当成点击" if d_mid == 0 and d_login == 0 and d_left > 0 else "对照不成立，要看图再判断"}')
        log('=== 第 4 步完 ===')
    finally:
        if middle_held():
            middle_up()
        move(r.L + 700, r.T + 430)
        u.SetForegroundWindow(hwnd)


if __name__ == '__main__':
    main()
