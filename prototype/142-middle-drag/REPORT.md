# 中键拖动原型（issue #142）验证记录

**状态：一次性的原型，只留证据，不进主干。等确认。**

## 这个原型本来要回答三件事

1. 队列抽屉用 `base_handle.set_offset()` 能不能按像素滚，下一帧会不会被 `uniform_list` 拽回去。
2. 按住中键拖出窗口、在窗口外松手，应用能不能收到松开、把拖动停掉。Windows / Linux X11 / Wayland 都要真机；macOS 由另一位作者用三键鼠标验。
3. 手感：1:1 跟手、方向、2px 死区、嵌套只滚最里层、不改指针、不加滚动条、没有惯性。

**这一轮的做法按交接文件来：不本地编译，直接下发行版跑真机。** 下面每条都写「通过 / 不通过 / 没验成」，不用「应该可以」糊过去。

## 一句话结论

三条问题里，**没有一条能判「通过」**。发行版里根本没有中键拖动这个功能，能测的是 Windows 平台层怎么接中键，另外顺手量了几条基线；剩下需要原型代码的，一律标「没验成」，没有拿静态读源码或推测顶替。

## 环境与怎么跑的

| 项 | 值 |
| --- | --- |
| 机器 | Windows，屏幕 1920x1026，桌面会话可交互 |
| 发行版 | GitHub Release `v0.3.9`，`sodam-0.3.9-windows-x64-setup.exe` |
| 校验 | SHA256 `f544a83a…5e172ccbc8b31e21b2ab65f`，跟 Release 的 `SHA256SUMS` 对得上 |
| 安装 | Inno Setup 静默安装，退出码 0，文件版本 `0.3.8 → 0.3.9`（`evidence/install.log`） |
| 应用窗口 | `Zed::Window`，`462,189-1458,837`；跑起来是「设置」页，**未登录** |
| 探针 | Python 3.13 + 自带 `ctypes`，零第三方包，零编译；注入中键 / 滚轮、抓屏、读 `GetGUIThreadInfo` |
| 没做的事 | 没有 cargo / build / check，没改 sodam 任何一行，没动依赖版本，没提交主干，没开 PR |

复跑（Windows，装好 v0.3.9，Python 3，脚本会自己起窗口）：

```
python tools/01_baseline.py       # 起窗口、记环境、截底图
python tools/02_middle_probe.py   # 中键按下/拖出/窗口外松手/失焦/最小化
python tools/03_drag_verify.py    # 复核「中键拖到底滚不滚页面」
python tools/04_click_control.py  # 中键会不会被当成点击（带左键对照）
```

证据都在 `evidence/`：`run.log` 是四步的完整输出（含失败重跑），`middle_events.csv` 是每一步的捕获 / 按键 / 前台窗口，PNG 是各步截图。

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
| Linux X11 | **没验成**。这台是 Windows，没有 Linux 真机；源码里的指针 grab 没实测 |
| Linux Wayland | **没验成**。同上，交接文件里也说没核到对应实现 |
| macOS | **未验证**。按 Q7 由仓库另一位作者用带中键的鼠标验，这里不替他写结论 |

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

## 干扰和限制（不藏着）

- 测试期间屏幕上还有另一个会话的窗口（`ZCode` / `Chrome_RenderWidgetHostHWND`）。SodaM 实例在第 1 步和第 2 步之间换过一次（pid `7904 → 4676`），窗口内布局在第 3、4 步之间也变过（侧栏从 110 宽变 224 宽）。脚本每步都记前台窗口和捕获状态，SodaM 相关步骤前台都是它自己。
- 第 2 步第一次跑因为 `strftime('%f')` 报错退出（`run.log` 20:10:58），改完重跑；第 4 步头两轮因为布局变了点错坐标、对照不成立，按新坐标重跑并做了字节级复核。**失败记录都留在 `run.log` 里，没有删**。
- 第 2 步 F 段按旧布局量的「去登录」坐标其实没命中按钮，那条结论以第 4 步重做的为准。
- 02 里 `0.1263` 那次画面变化是悬停底色，不是滚动，第 3 步专门复核过。

## 产物清单

```
prototype/142-middle-drag/
  REPORT.md                    这份记录
  tools/winprobe.py            ctypes 封装：找窗口、注入输入、抓屏、写证据
  tools/01_baseline.py         起发行版、记环境
  tools/02_middle_probe.py     中键事件与捕获、失焦、最小化
  tools/03_drag_verify.py      复核中键拖动有没有滚页面
  tools/04_click_control.py    中键点击 vs 左键点击对照
  evidence/install.log         安装命令、退出码、版本
  evidence/SHA256SUMS          官方校验文件
  evidence/run.log             四步完整输出（含失败重跑）
  evidence/middle_events.csv   每步的捕获 / 按键 / 前台窗口
  evidence/*.png               各步截图
```

安装包本体（9.9 MB）没放进分支，按 `install.log` 里的 Release 地址和 SHA256 随时能再下。

## 等确认的事

1. 上面四条测量口径认不认。
2. 问题 1 和问题 3 要往下走，得放开本地编译、或让远端 CI 出一个带插桩的临时包 —— 走哪条？
3. 未登录没数据这个卡点，用测试号还是造假数据？
4. Linux X11 / Wayland 真机谁来做、什么时候做；macOS 按 Q7 等另一位作者的结论。
5. 这个分支只留证据，**不合并主干、不开 PR**。要动正式代码，等你说开始。
