# Windows 安装器运行中实例规范

- 状态：accepted
- 日期：2026-10-20
- 关联：fork 安装包实测；`docs/TRAY-CLICK-SPEC.md`（关闭到托盘）
- 决策来源：本轮 grill 账本 D-001 ~ D-007（归档于 `.scratch/archive/2026-10-20-installer-update/`，不入库）
- 实现交接：`.scratch/installer-update/handoffs/next-round.md`（不入库）

## 1. 范围

覆盖 Windows x64 Inno Setup 安装包在 SodaM 正在运行时执行安装/升级的交互与失败处理。覆盖主窗口打开与已关闭到托盘两种状态。

不覆盖：卸载器代码、macOS/Linux 打包、应用内自动更新、应用侧 Restart Manager 优雅退出、队列/播放位置持久化。

## 2. 触发与关闭对象（D-007）

- 安装器通过 Windows Restart Manager 按「谁占用了待替换文件」检测，只命中安装目录 `{app}\sodam.exe` 的实例。
- 覆盖主窗口打开与已关闭到托盘（无窗口）两种状态。
- 开发构建、便携副本、其他路径的同名进程不受影响。
- 不使用 `taskkill /IM sodam.exe` 之类的按映像名全局结束。

## 3. 确认交互（D-001、D-003）

非静默安装在 Preparing to Install 页暂停，显示：

```text
SodaM 正在运行，安装程序需要关闭它才能继续。
SodaM is running. Setup must close it to continue.

[关闭 SodaM 并继续 / Close SodaM and continue]  [取消安装 / Cancel installation]
```

- 选择「关闭 SodaM 并继续」：关闭实例后继续安装。
- 选择「取消安装」：中止安装，不复制文件，SodaM 保持运行。
- 不静默自动关闭；不只提示用户手动退出。

## 4. 关闭实现（D-003、D-007）

- `CloseApplications=force`，保留 Inno 的确认页与 Restart Manager 兜底；覆盖无窗口托盘状态。
- 用户确认后，在 `NextButtonClick(wpPreparing)` 里按 `{app}\sodam.exe` 路径找到并立即结束该实例（PowerShell `Stop-Process`），再让 Inno 的 RM 走空流程，避免 RM 对不响应 `WM_QUERYENDSESSION` 的进程等待约 30 秒。
- 若立即结束失败（提权/权限不足），显示双语提示并留在确认页，不进入 RM 的 30 秒等待。
- `RestartApplications=no`，避免 Inno 在安装完成后自动重启（见第 6 节）。
- 只关闭第 2 节定义的实例；不扩大到其他路径的同名进程。
- 强制关闭会中断播放；队列与播放位置本就不持久化，本轮不新增持久化。

## 5. 关闭失败（D-004）

用户确认后仍无法关闭（提权进程、权限不足、安全软件保护、进程卡死等）时：

- 用户选择「取消安装」：在 `ssInstall` 之前中止，不复制任何文件，显示「安装已取消。SodaM 未被关闭。」
- 用户选择「关闭」但强制关闭失败：在 Restart Manager 关闭尝试之后、文件复制之前（`[Files]` 的 `BeforeInstall`）中止；不复制 `sodam.exe`。Inno 可能在失败路径中已更新卸载器文件 `unins000.exe`。
- 不使用 `restartreplace` 排队重启替换；不再重复强杀。
- 显示中英双语提示，指导用户从托盘菜单退出 SodaM（必要时用任务管理器结束 `sodam.exe`）后重试；用户可原地重试或取消安装。
- 即使用户在 Inno 内建错误框选择 Ignore，守卫也必须中止，不能带着占用继续复制文件。

## 6. 安装完成与启动（D-002）

- 安装器不自动重启 SodaM。
- 保留现有 `[Run] postinstall` 的「Launch SodaM」复选框，默认勾选；由用户决定是否启动。
- 不因安装前实例在运行就条件重启。

## 7. 静默安装（D-006）

- 不支持静默安装；对外只承诺交互式安装。
- 静默模式（`/SILENT`、`/VERYSILENT`）下若检测到运行中的 SodaM，直接中止并返回非零退出码，不做无确认强杀。
- 静默模式且没有运行中的 SodaM 时，按 Inno 正常流程安装。

## 8. 卸载（D-005）

- 本轮不修改卸载器。
- Windows 安装说明（README 与 website 安装页）增加：卸载前请先从托盘菜单退出 SodaM。
- 原因：Inno 的 `CloseApplications` 仅作用于安装器；`AppMutex` 会同时影响安装启动流程；`uninsrestartdelete` 需要管理员权限，本项目按用户安装无法使用。

## 9. 决策—计划映射

| 决策 | 规范条目 | 计划条目 |
| --- | --- | --- |
| D-001 | 第 3、4 节 | P1、P6 |
| D-002 | 第 6 节 | P4、P6 |
| D-003 | 第 3、4 节 | P1、P6 |
| D-004 | 第 5 节 | P2、P6 |
| D-005 | 第 8 节 | P5 |
| D-006 | 第 7 节 | P3、P6 |
| D-007 | 第 2、4 节 | P1、P2、P6 |

## 10. 实施计划

| 编号 | 任务 | 覆盖决策 | 验收 |
| --- | --- | --- | --- |
| P1 | `sodam.iss`：`CloseApplications=force`、`RestartApplications=no`、双语 `[Messages]` 覆盖 | D-001、D-003、D-007 | 运行中安装弹出双语确认；确认后关闭并安装；取消不复制文件；关闭到托盘可被关闭 |
| P2 | 取消/关闭失败守卫：`ssInstall` 处理取消分支，`[Files]` 的 `BeforeInstall` 兜底强制关闭失败 | D-004、D-007 | 取消路径不复制任何文件；关闭失败路径不复制 `sodam.exe`；Ignore 也中止 |
| P3 | 静默模式守卫：检测到运行中实例则中止并返回非零退出码 | D-006 | `/SILENT` 运行中退出非零；无运行中实例正常安装 |
| P4 | 安装完成页保持 `[Run] postinstall` 复选框，不自动重启 | D-002 | 默认勾选「Launch SodaM」；取消勾选不启动；无额外自动重启 |
| P5 | README 与 website 安装页补充卸载前退出说明与安装器行为说明 | D-005 | 文档可检索到说明；不改卸载器代码 |
| P6 | 验证矩阵：CI 构建 + Windows 真机覆盖运行中/托盘/提权失败/静默/无实例/开发构建 | D-001 ~ D-007 | 每项有命令或截图证据；无文件占用重试循环 |

## 11. 显式范围外

- 应用侧 `WM_QUERYENDSESSION` / `WM_ENDSESSION` 优雅退出与 `RegisterApplicationRestart`。
- 应用内自动更新器（Chrome/Squirrel/electron-builder 式）。
- 卸载器代码改造；卸载时自动关闭。
- 安装器向导全量本地化（本轮只本地化关闭确认与失败提示）。
- 管理员安装模型 / UAC。
- 队列与播放位置持久化。
- macOS/Linux 打包行为。

## 12. 已知后果与验证风险

- 强制关闭会中断播放；队列和播放位置不会保留（既有行为）。
- Restart Manager 对无响应或无窗口的 GUI 进程，强制关闭最长可能需要约 30 秒；P1 的立即结束路径应把确认后的等待降到秒级，需在真机记录实际耗时。
- 立即结束使用 PowerShell `Get-CimInstance` + `Stop-Process -Force`，只匹配 `{app}\sodam.exe`；提权进程会失败并走第 5 节。
- Inno 的「Do not close」按钮默认是「继续安装」，P2 的守卫必须把它转换为「中止」。
- `CurStepChanged(ssInstall)` 早于 Inno 的 `ShutdownApplications`，不能作为「关闭后检查点」；取消分支在 `ssInstall` 处理，强制关闭失败由 `[Files]` 的 `BeforeInstall` 兜底（它在 RM 关闭尝试之后、`sodam.exe` 复制之前执行）。
- 强制关闭失败路径中，Inno 可能已更新卸载器文件 `unins000.exe`；这是唯一可能被写入的文件，`sodam.exe` 不会被覆盖。
- `[Messages]` 覆盖与 `.iss` 的 UTF-8 BOM 需在 CI 构建和真机安装中一起验证。
- 以管理员身份运行的 SodaM 无法被按用户安装器关闭，走 P2 失败路径。
- 开发构建/其他路径同名进程不受影响，需在验证矩阵中确认。

## 13. 为什么没有单独 ADR

本轮决策可通过对 `sodam.iss` 与一小段 Pascal 守卫的修改逆转，不满足「难逆转」判据；取舍与权限约束已完整记录在本规范第 4、5、8 节。因此不新增 ADR。
