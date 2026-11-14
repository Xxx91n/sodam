# 中键拖动原型（issue #142）验证记录

**状态：一次性的原型，只留证据，不进主干。等确认。**

## 这个原型本来要回答三件事

1. 队列抽屉用 `base_handle.set_offset()` 能不能按像素滚，下一帧会不会被 `uniform_list` 拽回去。
2. 按住中键拖出窗口、在窗口外松手，应用能不能收到松开、把拖动停掉。Windows / Linux X11 / Wayland 都要真机；macOS 由另一位作者用三键鼠标验。
3. 手感：1:1 跟手、方向、2px 死区、嵌套只滚最里层、不改指针、不加滚动条、没有惯性。

**做法按交接文件来：不本地编译，直接下发行版跑。** Windows 是本机真机，Linux 按补充信息放到了 WSLg 模拟 GUI 里跑（**是模拟环境，不是裸机真机**）。下面每条都写「通过 / 不通过 / 没验成」，不用「应该可以」糊过去。

## 一句话结论

三条问题里，**没有一条能判「通过」**。发行版里根本没有中键拖动这个功能，能测的只是「系统怎么把中键消息送给窗口」这一层：Windows 本机和 WSLg 里的 X11 路径都拿到了平台层证据，原生 Wayland 没起成，macOS 没验。剩下需要原型代码的，一律标「没验成」，没有拿静态读源码或推测顶替。

## 环境与怎么跑的

| 项 | 值 |
| --- | --- |
| 机器 | Windows，屏幕 1920x1026，桌面会话可交互 |
| 发行版 | GitHub Release `v0.3.9`，`sodam-0.3.9-windows-x64-setup.exe` |
| 校验 | SHA256 `f544a83a…5e172ccbc8b31e21b2ab65f`，跟 Release 的 `SHA256SUMS` 对得上 |
| 安装 | Inno Setup 静默安装，退出码 0，文件版本 `0.3.8 → 0.3.9`（`evidence/install.log`） |
| 应用窗口 | `Zed::Window`，`462,189-1458,837`；跑起来是「设置」页，**未登录** |
| 探针 | Windows：Python 3.13 + 自带 `ctypes`，零第三方包，零编译。Linux：`xdotool` 注入，`xev` / `xinput test-xi2` 看事件，`import` 截图 |
| Linux 环境 | WSL 3.0.3.0 / WSLg 1.0.79，`sodam-arch`（官方 Arch bootstrap rootfs），glibc 2.44，`DISPLAY=:0` + `WAYLAND_DISPLAY=wayland-0`；跑的是 v0.3.8 Arch 包 |
| 没做的事 | 没有 cargo / build / check，没改 sodam 任何一行，没动依赖版本，没提交主干，没开 PR |

复跑（Windows，装好 v0.3.9，Python 3，脚本会自己起窗口）：

```
python tools/01_baseline.py       # 起窗口、记环境、截底图
python tools/02_middle_probe.py   # 中键按下/拖出/窗口外松手/失焦/最小化
python tools/03_drag_verify.py    # 复核「中键拖到底滚不滚页面」
python tools/04_click_control.py  # 中键会不会被当成点击（带左键对照）
```

Linux 侧（WSLg，先保证 `sodam-arch` 里 SodaM 已经跑起来）：

```
wsl -d sodam-arch -- bash /mnt/c/sodam-142/prototype/142-middle-drag/tools/linux/x11_middle_probe.sh
wsl -d sodam-arch -- bash /mnt/c/sodam-142/prototype/142-middle-drag/tools/linux/pkg_verify.sh
```

脚本里的路径写死了这轮的 worktree，换地方要改 `EV=`。`install_tools.sh` 只装了 5 个只读的 X11 观察工具，不编译任何东西。

证据都在 `evidence/`：`run.log` 是 Windows 四步的完整输出（含失败重跑），`middle_events.csv` 是每一步的捕获 / 按键 / 前台窗口，PNG 是各步截图；Linux 的在 `evidence/linux/`。

> 两个坑先说清楚：脚本里的点击坐标是这轮实测的，换机器或换缩放要先跑 01、看 `baseline_window.png` 量一下；PowerShell 那条 `Add-Type` 被环境的安全策略拦了，所以整套探针改成 Python `ctypes`，没有绕过策略去编译任何东西。

---

## 问题 1：队列抽屉能不能按像素滚 —— **没验成**

**为什么没验成**：这条要在客户端里插一段代码，调 `base_handle.set_offset()`，再看下一帧 `uniform_list` 布局把偏移怎么处理。v0.3.9 里没有这段代码；本轮禁止本地编译，也没有带插桩的现成包。发行版上中键拖 120px、300px，页面一格都不动（第 3 步实测），所以连「偏移被拉回 / 只按整项跳」这种现象都读不到。

| 证据 | 命令 / 步骤 | 现象 |
| --- | --- | --- |
| 发行版没这功能 | `python tools/03_drag_verify.py`，退出码 0 | 只按下不拖：画面变化 `0.0000`、垂直位移 `0`；拖 120px 和 300px 松开、鼠标回原位：都是 `0.0000`、位移 `0` |
| 这块内容本身能滚 | 同上，滚轮往下 3 格做对照 | 画面变化 `0.3144`，量出垂直位移 **20 像素** —— 判定方法管用，也反证中键拖动是真没反应 |
| 02 里那个 `0.1263` 不是滚动 | `b1_before_drag.png` vs `b2_during_drag.png` | 是「深色」那行的鼠标悬停底色变了；第 3 步把鼠标挪回原位再比，差异归零 |

**读上游源码拿到的线索（只是线索，不是真机结论）**：

锁的是 `sodahub-org/gpui` 的 `5ff26c7`：

- `crates/gpui/src/elements/uniform_list.rs:683` 的 `track_scroll()` 把 `base_handle` 挂到 `interactivity.tracked_scroll_handle`。
- `prepaint`（同文件 `:331` 起）对 `scroll_offset` 只做范围夹取（`scroll_offset.y < max_scroll_offset` 时夹住），**没看到按整项吸附**，所以「每帧被拽回」从源码看不像。
- 但 `DeferredScrollToItem`（`:411` 起）会按项覆盖偏移；本仓 `crates/sodam/src/app_actions.rs:447` 的 `anchor_queue_scroll()` 在每次打开抽屉时调 `scroll_to_item(row, Center)`，也就是会按项重定位。

这三行只是说明「值得继续验」，**不能写成通过**。

**换成 `ListState` 要改哪些地方（静态核对，范围确定）**：

- `crates/sodam/src/app.rs:384`：`queue_scroll` 从 `UniformListScrollHandle` 改成 `ListState`；`:693` 的初始化跟着换成 `ListState::new(...)`，要给定 item 数和对齐方式。
- `crates/sodam/src/ui/player_bar.rs:1108`：去掉 `.track_scroll(&root.queue_scroll)`，队列列表从 `uniform_list(...)` 换成 `list(...)`，行渲染闭包按 `ListState` 的接口改（现在队列行是定高的，主要改渲染入口和索引语义）。
- `crates/sodam/src/app_actions.rs:447`：`anchor_queue_scroll()` 里的 `scroll_to_item(row, Center)` 换成 `ListState` 的对应方法；`player_bar.rs:802` 打开抽屉时的调用点跟着走。
- `app.rs:355-361` 那六个现成的 `ListState`、`app.rs:380` 的 `liked_scroll` 都不用动。
- 改完要重新真机验一次抽屉的按项锚定，别只过编译。

**要验成还差什么**：一个带插桩的临时构建（要么放开本地编译，要么远端 CI 出一个只给原型用的包），然后按交接文件原定的标准真机拖一遍：连续跟手、不跳项、不回弹、不越界。

---

## 问题 2：拖出窗口再松手能不能可靠停 —— **没验成**（Windows 平台层这一小节通过）

按交接文件的标准，「松手后页面立刻停住、之后移动不再滚」必须有拖动状态才谈得上。发行版没有这个状态，所以整条不能判通过。能验的只是「窗口外的松开消息送没送到应用」这一层。

### Windows 平台层：通过（真机 + 源码对得上）

`python tools/02_middle_probe.py` 退出码 0，逐步记录见 `middle_events.csv`：

| 时刻 | 操作 | 看到什么 |
| --- | --- | --- |
| 20:11:38.773 | 在设置页内容区按下中键 | `GetGUIThreadInfo.hwndCapture = 0xf0394`，就是 SodaM 主窗口本身 —— `SetCapture` 生效 |
| 20:11:39.238 / .329 | 光标移到 `1467,619` / `1528,619`，已经在窗口外 | 捕获**还在** `0xf0394`；`WindowFromPoint` 变成 `Chrome_RenderWidgetHostHWND`（别的进程的窗口） |
| 20:11:39.793 | 在窗口外松开中键 | 捕获立刻变 `0`，`GetAsyncKeyState(VK_MBUTTON)` 清零 |
| 20:11:39.917–40.162 | 不按键继续移动三下 | 捕获一直是 `0`，没有残留 |

源码也对得上（`sodahub-org/gpui@5ff26c7`，`crates/gpui_windows/src/events.rs`）：

- `:137` / `:143` 认 `WM_MBUTTONDOWN` / `WM_MBUTTONUP`；`:359` 移动时把 `MK_MBUTTON` 填成 `MouseButton::Middle`。
- `:471` `handle_mouse_down_msg` **无条件** `SetCapture(handle)`；`:501` `handle_mouse_up_msg` **无条件** `ReleaseCapture()`。

连起来就是：Windows 上中键一按就捕获鼠标，光标跑出窗口消息照样送到 SodaM 窗口，松手时平台层把捕获放掉。**这是必要条件，不是充分条件** —— GPUI 会不会把这个 MouseUp 派给元素的 `on_mouse_up_out`、原型里的拖动状态会不会清掉，发行版里读不到，要插桩才能验。

### 失焦和最小化

| 场景 | 步骤 | 现象 |
| --- | --- | --- |
| 切走应用 | 中键按下 → `SetForegroundWindow` 到别的窗口 | 捕获变 `0`，前台 `0x20029c`，中键异步状态当时仍显示按着（还没松手） |
| 最小化 | 中键按下 → `SW_MINIMIZE` | 捕获变 `0`，前台 `0x20029c` |
| 恢复 | `SW_RESTORE` | 捕获保持 `0`，中键已松开 |

系统在这两种情况下主动撤了捕获，但**应用层的拖动状态没有对应事件 observable**。原型里仍该按交接文件补一条兜底（失焦 / 鼠标离开时清状态），并在报告里记用了哪条。

### 其它平台

| 平台 | 结论 |
| --- | --- |
| Linux X11（WSLg / XWayland） | **平台层通过（模拟环境）**，整条问题 2 仍没验成。下面单开一节讲 |
| Linux Wayland（原生） | **没验成**。两次尝试都没把原生 Wayland 实例拉起来 |
| macOS | **未验证**。按 Q7 由仓库另一位作者用带中键的鼠标验，这里不替他写结论 |

### Linux（WSLg 模拟）补充验证

先把用户给的环境信息坐实，再测。命令 `tools/linux/pkg_verify.sh`，退出码 0，日志 `evidence/linux/pkg_verify.log`：

| 项 | 结果 |
| --- | --- |
| v0.3.8 包哈希 | 官方 `bea875eb…d778be`，本地下载一致 |
| 跑的二进制 | 解包出来的 `usr/bin/sodam` 是 `df11c9df…bb9e`，跟 WSL 里 `/opt/s038/usr/bin/sodam`、`/usr/bin/sodam` **三个一模一样** —— 确实就是官方 v0.3.8 Arch 包 |
| v0.3.9 deb 交叉 | 官方 `143f8bdd…7866`，本地一致；解包 control 写着 `Version: 0.3.9-1`，里面二进制 `356db624…b551`，跟 0.3.8 不是同一个文件 |
| Ubuntu 24.04 为什么跑不了 | 两个二进制里要求最高的 GLIBC 符号都是 **GLIBC_2.43**；Arch 这边 glibc 2.44 够，Ubuntu 24.04 的 2.39 不够。跟用户说的原因对上了 |

**当前 WSLg 里跑的是 X11 客户端，不是原生 Wayland**（`evidence/linux/backend.log`、`env.log`）：`/proc/2811/environ` 只有 `DISPLAY=:0`、没有 `WAYLAND_DISPLAY`；`xinput list` 里是 `xwayland-pointer` / `xwayland-keyboard`；窗口树是 `0x200420`（Weston 的框）包着 `0x600001 "SodaM"`，`478,220 980x640`，`Map State: IsViewable`。

**X11 路径实测**：`tools/linux/x11_middle_probe.sh`，退出码 0，时间线在 `evidence/linux/x11_steps.log`。步骤是：内容区 `(1213,540)` 按下中键 → 六步拖到 `(1538,540)`（窗口右边界 `1458`，第 5、6 步已在窗口外）→ 窗口外松开 → 不按键再移动三下 → 对照：窗口内按下松开一次、以及按下后把窗口最小化再松开。

看到的现象：

- `xinput test-xi2 --root` 抓到三组 `RawButtonPress` / `ButtonPress` / `RawButtonRelease` / `ButtonRelease`，`detail: 2` 都是中键。第一组松开在 `root:(1538,540)`，就是窗口外，那行 `child 0x0`（指针底下没有任何窗口）；窗口内那两组 `child 0x200420`。日志 `evidence/linux/x11_xi2.log`。
- `xev -id 0x600001` 在窗口外松手后收到 `LeaveNotify … mode NotifyUngrab`，坐标正好 `root:(1538,540)`。**NotifyUngrab 只会在 X11 隐式指针 grab 解除时发**，说明按下时 X server 抓住了指针、松手时放开了；按 X11 的规矩，抓住期间松开的 ButtonRelease 会送回最初按下那个窗口。
- 所以 **X11 平台层这一小节判「通过（模拟环境）」**。但要说清楚：`xev` 没直接抓到送到 `0x600001` 的核心 ButtonPress/ButtonRelease（GPUI 的 X11 后端多半走 XI2，核心事件掩码收不到），`xinput test-xi2` 不带 `--root` 时监听的也是它自己的窗口。这条证据是**间接的**，不是直接看着事件进的窗口。
- 发行版没有拖动状态，「应用会不会把拖动清掉」照样读不到；整条问题 2 还是没验成。最小化那步 XI2 里有 ButtonRelease，但看不出应用收没收到，也标没验成。

**原生 Wayland 没验成**：试了两次起原生 Wayland 实例（去掉 `DISPLAY`、留 `WAYLAND_DISPLAY=wayland-0`、独立 HOME、`WAYLAND_DEBUG=1`，第二次还加了独立 dbus 会话），两次都在 7 秒内退出，`WAYLAND_DEBUG` 一行没打出来，也没留下 sodam 进程。第二次 stderr 只有 dbus 一句 `XDG_RUNTIME_DIR … is owned by uid 1000, not our uid 0` —— X11 那个实例也有这句但照常跑，所以不是致命原因。没继续追根因，更没下结论说 GPUI 的 Wayland 后端不行。日志 `evidence/linux/wayland_try.log`、`wayland_try2.log`。

要补 Wayland，得先解决两件事：怎么在 WSLg 里把原生 Wayland 客户端拉起来；`xdotool` 管不到原生 Wayland 窗口，输入注入得换路子（从 Windows 侧经 RDP rail 发，或者用 `WAYLAND_DEBUG=1` 直接看 `wl_pointer.button`）。

**这不算裸机真机**：X11 是跑在 Weston 上的 XWayland，Wayland 是 Weston + RDP rail。Q7 要的「Linux 真机拖一遍」这次没被替代。

---

## 问题 3：手感和边界 —— **没验成**

1:1 跟手、方向、2px 死区、嵌套只滚最里层、不改指针、不加滚动条、没有惯性，全都要原型实现之后才存在，发行版测不了。别拿下面这些基线当通过。

**顺手量到的现状（只是基线）**：

| 项 | 证据 | 结果 |
| --- | --- | --- |
| 中键只按不拖，什么都不发生 | `v2_down_only.png` vs `v1_idle.png` | 画面变化 `0.0000`，垂直位移 `0` |
| 中键不会触发播放 / 点赞 / 菜单这类普通点击 | `04_click_control.py`，退出码 0 | 中键点侧栏「推荐」和「去登录」，截图跟基线 **md5 完全一样**（`8ed47e4abd`）；左键点同一位置会弹「请先在设置→账户扫码登录」提示（`0b9547db92`，画面变化 `0.0059`）—— 对照成立，说明点击确实发出去了，只是中键不被认 |
| 滚轮能滚同一块内容 | `03_drag_verify.py` | 3 格 → 垂直位移 20px |
| 指针 / 滚动条 / 惯性 | 无 | 发行版没这套逻辑，测了也没意义 |

**新发现的一个卡点，得先解决**：这台机器上的客户端**未登录**，队列抽屉、歌词、歌单、各详情页都没有内容。就算有了带插桩的包，Q3 里「队列打开时只滚队列」「菜单/弹窗打开不误滚背景」这些嵌套场景也没数据可拖。要么准备一个能登录的测试号，要么在插桩包里造一批假数据。这条交接文件里没写，是本轮实测才碰到的。

---

## 本轮新加的测量口径（请确认）

交接文件第五节说，原型里新加的判定标准要先报给你确认。下面四条是**测量办法**，没有改交接文件里任何一条「怎么算通过」，请过一下：

1. 用 `GetGUIThreadInfo.hwndCapture == 主窗口` 当作「SetCapture 生效、窗口外消息会送到这个窗口」。
2. 用「松开后鼠标挪回原位，截图跟基线字节级一样」当作「页面一格没滚」，避开鼠标悬停底色造成的假变化。
3. 用「滚轮 3 格能量出 20px 垂直位移」当作「这块内容能滚、上面那个判定法有效」的对照。
4. 用「左键点同一位置会弹出登录提示」当作「这次点击确实发出去了」的对照，用来证明中键的「没反应」不是坐标点歪了。
5. Linux 侧用 `xinput test-xi2 --root` 的 ButtonPress/Release，加上 `xev -id` 的 `LeaveNotify mode=NotifyUngrab`，当作「X11 隐式 grab 生效、窗口外松手会送回原窗口」。**这条是间接证据**，不是直接看着事件进了窗口，认不认请一并说。

## 干扰和限制（不藏着）

- 测试期间屏幕上还有另一个会话的窗口（`ZCode` / `Chrome_RenderWidgetHostHWND`）。SodaM 实例在第 1 步和第 2 步之间换过一次（pid `7904 → 4676`），窗口内布局在第 3、4 步之间也变过（侧栏从 110 宽变 224 宽）。脚本每步都记前台窗口和捕获状态，SodaM 相关步骤前台都是它自己。
- 第 2 步第一次跑因为 `strftime('%f')` 报错退出（`run.log` 20:10:58），改完重跑；第 4 步头两轮因为布局变了点错坐标、对照不成立，按新坐标重跑并做了字节级复核。**失败记录都留在 `run.log` 里，没有删**。
- 第 2 步 F 段按旧布局量的「去登录」坐标其实没命中按钮，那条结论以第 4 步重做的为准。
- 02 里 `0.1263` 那次画面变化是悬停底色，不是滚动，第 3 步专门复核过。
- **WSLg 环境是共用的**：`sodam-arch` 里还有另一个会话在跑 issue #136 的 Linux 残留验证（`/root/drive_linux.sh`、`/root/linux_click.sh`，证据写到 `C:/sodam/prototype/136-hover-residue/evidence/`）。本轮的 X11 实验在 21:56–21:59 跑，那段时间没有它的脚本在跑；它启动的 SodaM 进程 pid `2811` 一直没动过，实验前后窗口都是 `IsViewable`、位置没变（`evidence/linux/final_state.log`）。只在 Arch 里多装了 5 个只读的 X11 观察工具，没删改它的任何东西。
- Linux 侧第一版 `xev -event mouse` 没抓到按键事件，加了 `-event button`、再用 `stdbuf` 强制行缓冲才拿到完整时间线；第一版日志被重跑覆盖了，没单独留档，`x11_steps.log` 是最后成功那一轮。原生 Wayland 两次尝试都失败了，日志都保留了。

## 产物清单

```
prototype/142-middle-drag/
  REPORT.md                    这份记录
  tools/winprobe.py            ctypes 封装：找窗口、注入输入、抓屏、写证据
  tools/01_baseline.py         起发行版、记环境
  tools/02_middle_probe.py     中键事件与捕获、失焦、最小化
  tools/03_drag_verify.py      复核中键拖动有没有滚页面
  tools/04_click_control.py    中键点击 vs 左键点击对照
  tools/linux/                 WSLg 探查、X11 事件、包核对、Wayland 尝试、收尾检查
  evidence/install.log         安装命令、退出码、版本
  evidence/SHA256SUMS          官方校验文件
  evidence/run.log             Windows 四步完整输出（含失败重跑）
  evidence/middle_events.csv   Windows 每步的捕获 / 按键 / 前台窗口
  evidence/*.png               Windows 各步截图
  evidence/linux/*.log         Linux 侧全部日志：环境、后端、事件时间线、包核对、Wayland 尝试
```

安装包本体（Windows 9.9 MB、Arch 20 MB、deb 15 MB）没放进分支，按日志里的 Release 地址和 SHA256 随时能再下。Linux 的包下载在 `C:/Windows/Temp/sodam142-pkgs/`，是临时目录。

## 等确认的事

1. 上面五条测量口径认不认，特别是第 5 条（X11 那条是间接证据）。
2. 问题 1 和问题 3 要往下走，得放开本地编译、或让远端 CI 出一个带插桩的临时包 —— 走哪条？
3. 未登录没数据这个卡点，用测试号还是造假数据？
4. WSLg 这次只补了 X11 路径，而且不是裸机真机。原生 Wayland 要不要继续查（怎么起实例、换输入注入方式）？裸机 Linux 谁来拖一遍？macOS 按 Q7 等另一位作者的结论。
5. 这个分支只留证据，**不合并主干、不开 PR**。要动正式代码，等你说开始。
