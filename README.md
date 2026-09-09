# Terminal Notifier

> 一只住在 macOS 菜单栏的像素猫，会提醒你该看终端了。

[English](README-EN.md) | 简体中文

## 这是什么？

你在使用 Claude Code 或 Codex 时，是不是经常切到其他应用，然后忘了它们正等着你确认操作？

Terminal Notifier 默认检测 Terminal.app 的 Dock 红点（badge），也可以通过 Claude Code 和 Codex hooks 区分「需要确认」与「对话完成」。需要你处理时，像素猫会带着紧凑提醒出现在屏幕中央，但不会抢走当前应用的键盘焦点。

## 效果演示

1. 像素猫安静地住在菜单栏里 🐱
2. Terminal.app 出现 Dock 红点，或 Claude Code / Codex hook 发出事件
3. 猫咪与提醒面板出现，但不打断你在当前应用中的输入
4. 你可以选择「关闭」「稍后」或「打开来源」；也可以设置点击猫咪时是否打开来源
5. 未处理的提醒可自动收起到菜单栏，并在冷却结束后继续待命

## 安装

### 直接下载

从 [GitHub Releases](https://github.com/Jack11111eee/terminal-notifier/releases) 下载最新的 `.zip` 文件，解压后将 `Terminal Notifier.app` 拖到 `Applications` 文件夹即可。

### 从源码编译

**要求：**
- macOS 13 Ventura 及以上
- Apple Silicon Mac
- Xcode 或 Xcode Command Line Tools（`xcode-select --install`）
- 登录钥匙串中有代码签名证书 `TerminalNotifierDev`，用于保持辅助功能权限跨重编译稳定

```bash
git clone https://github.com/Jack11111eee/terminal-notifier.git
cd terminal-notifier
./build.sh
open "build/Terminal Notifier.app"
```

如需构建后复制到 `/Applications`：

```bash
INSTALL=1 ./build.sh
```

### 构建本地预览 DMG

如需生成用于本地安装检查的 Apple Silicon DMG，而不安装或发布应用：

```bash
bash package-dmg.sh
```

DMG 和 SHA-256 校验文件会写入 `build/`。脚本默认使用 ad-hoc 签名，不会进行公证；如需使用已有签名身份，可显式设置 `SIGN_IDENTITY`。使用 macOS 26 SDK 构建并在 macOS 26 运行时会启用 Liquid Glass，其他构建或系统版本使用原生控件与材质回退。

### 回归测试

安装完整 Xcode 并选为当前开发工具后，运行 `bash test.sh`。测试使用临时配置文件和进程内偏好，不修改实际 Claude/Codex 配置，也不会启动应用或请求系统权限。

在 macOS 图形会话中，可运行 `TN_RUN_UI_TESTS=1 bash test.sh`，额外检查窗口缩放、长消息按钮布局、提醒面板焦点和减少动态效果下的动画完成行为。

设置窗口会在 macOS 26 与 Swift 6.2 及以上的构建中使用现代 Liquid Glass 布局，其他环境使用传统原生材质布局。开发时可分别运行 `bash dev-preview.sh settings modern` 和 `bash dev-preview.sh settings compatible` 在同一台 Mac 上预览两种模式。

GitHub Actions 会在面向 `main` 的 PR 和 `main` 更新时，构建应用、校验 ad-hoc 签名并运行这些回归测试。CI 不安装应用、不使用正式签名证书，也不自动发布安装包。

## 功能

- **Badge 基础检测零权限**：默认只读 Terminal Dock badge，无需辅助功能权限或屏幕录制权限
- **Claude Code / Codex 状态检测**（可选）：通过 hook 直接区分「需要确认」和「对话完成」，不依赖终端响铃
- **Claude 前台多窗口归因**（可选增强）：Terminal.app 在前台时，Claude hook 事件来自非最上层 Terminal 窗口也会提醒
- **紧凑提醒**：提醒面板不会主动抢占键盘焦点，并提供「关闭」「稍后」「打开来源」三个独立操作
- **全屏兼容**：即使你在全屏看视频或写代码，猫也能弹出来
- **免打扰**：设置时段（如 22:00–08:00），猫会自觉安静
- **冷却时间**：可调（5–120 秒），防止猫刷屏
- **通知历史**：按日期浏览和搜索过往提醒，打开记录时跳转到对应 Terminal 或 Codex 来源
- **分级音效**：需确认的提醒用更引人注目的提示音，普通完成提醒用温和音效，耳朵即可分辨轻重
- **自检与修复**：菜单栏一键检查权限与 hook 状态，失败项可直接修复
- **专注模式联动**：macOS 专注模式开启时自动静默，仅留菜单栏红点与历史记录
- **系统辅助功能适配**：跟随系统外观、增加对比度、减少透明度和减少动态效果设置
- **中英文**：根据系统语言自动选择，也可手动设置
- **像素风**：纯正的像素艺术风格猫咪

## Claude Code 状态检测（可选）

默认的 badge 检测只能知道「终端有动静」。打开设置里的 **检测 Claude Code 状态** 后，App 会通过 Claude Code 官方 hook 直接读对话状态，区分两种事件并弹出对应话语：

- **需要确认**：Claude 等你批准某个操作（`Notification` / `permission_prompt`）
- **对话完成**：Claude 说完一轮（`Stop`）

开启时 App 会把 hook **安全合并**进 `~/.claude/settings.json`（保留你已有的全部 hook，并在写入前生成 `settings.json.tn-backup-<时间戳>` 备份），关闭即移除。Terminal 在后台时直接提醒；Terminal 在前台时默认继续抑制，避免打扰你正在查看的窗口。

**前台多窗口归因：** 如需在 Terminal.app 前台时识别非最上层 Terminal 窗口里的 Claude 事件，可额外开启「前台多窗口归因」。该增强功能会请求辅助功能权限，并可能请求控制 Terminal 的自动化权限；选择「打开来源」或点击猫咪时定位对应窗口也依赖该能力。未开启或未授权时会降级为零辅助功能权限行为：Terminal 后台提醒、Terminal 前台抑制。

**限制：** 按 Esc「中断」时 Claude Code 不触发任何 hook，因此无法检测中断；本功能不处理输入空闲（idle）。自动合并会规整 settings.json 的格式与键序（已备份）。

## Codex 状态检测（可选）

打开设置里的 **检测 Codex 状态** 后，App 会通过 Codex lifecycle hooks 捕捉两类事件：

- **需要确认**：Codex 等你批准某个操作（`PermissionRequest`）
- **对话完成**：Codex 完成一轮（`Stop`）

开启时 App 会把受管理的 hooks **安全合并**进 `~/.codex/hooks.json`（保留你已有的全部 hooks，并在写入前生成 `hooks.json.tn-backup-<时间戳>` 备份），关闭即移除。与 badge 一致，**仅 Codex 不在前台时才弹**。你可以单独关闭 `PermissionRequest` 的审批请求提醒，只保留 `Stop` 的完成提醒。

**必须信任 hooks：** 开启或修改 Codex hooks 后请退出并重新打开 Codex，让 hooks 重新加载。然后进入 Codex **设置 → 钩子**，信任 `Terminal Notifier: Codex approval reminder`（`PermissionRequest`，如已开启）和 `Terminal Notifier: Codex completion reminder`（`Stop`）。未信任前 Codex 会跳过这些 hooks，Terminal Notifier 不会收到提醒。

**auto-review：** Codex 的 `auto-review` 流程仍可能发出 `PermissionRequest` hook，因此即使 Codex 自动完成审核，也可能出现「需要确认」提醒。如果只想收到完成提醒，可在设置中关闭审批请求提醒。

**限制：** Codex hooks 是用户级配置，可能同时被本机 Codex App / CLI / IDE Extension 采用；当前不区分具体 Codex 入口，也不读取 Codex App 内部实时运行状态。若需要排查 hook 是否执行，可查看 `~/Library/Application Support/TerminalNotifier/codex-hook.log`。

## 设置

点击菜单栏猫咪 → **设置**，可以调整：

| 设置项 | 说明 | 默认值 |
|--------|------|--------|
| 启用提醒 | 开关全部提醒 | 开 |
| 检测 Claude Code 状态 | 通过 hook 区分「需要确认 / 对话完成」 | 关 |
| Claude 前台多窗口归因 | 识别非最上层 Terminal 窗口里的 Claude 事件；需要辅助功能权限 | 关 |
| 检测 Codex 状态 | 通过 Codex hook 区分「需要确认 / 对话完成」 | 关 |
| Codex 审批请求提醒 | 控制是否响应 `PermissionRequest`；完成提醒不受影响 | 开 |
| 开机自启 | 登录时自动启动 | 关 |
| 语言 | 中文 / 英文 / 跟随系统 | 跟随系统 |
| 声音 | 提醒时播放音效 | 开 |
| 冷却时间 | 两次提醒最短间隔 | 10 秒 |
| 免打扰 | 在指定时段暂停提醒 | 关 |
| 点击猫咪打开来源 | 开启后点击猫咪会切换到 Terminal / Codex；「关闭」和「稍后」始终不切换应用 | 关 |

## 更新日志

### v1.4.0 (2026-09-09)
- **打字时保持迷你**：开启后（默认），正在输入时新提醒不再弹出遮挡视线的大猫和气泡，改为屏幕角落的小猫；挂着的全尺寸提醒也会自动缩为角落小猫。点击小猫可展开为完整提醒。检测通过系统只读接口判断「最近几秒是否有按键」，无需任何权限、不读取按键内容。可在设置「提醒」中关闭。

### v1.3.0 (2026-09-08)
- 设置、提醒历史和自检改用原生可缩放窗口；macOS 26 支持 Liquid Glass，旧版系统使用原生材质回退。
- 提醒改为不主动抢占键盘焦点的紧凑面板，新增独立的「关闭」「稍后」和「打开来源」操作，并适配系统辅助功能显示设置。
- 提醒历史新增搜索、日期分组、复制消息和按来源打开 Terminal / Codex。
- 修复混合 hook 分组的清理逻辑，安装、更新和卸载时保留同组的用户 hook 与分组设置。
- 修复免打扰、专注模式或关闭提醒拦截显示后状态机卡住的问题；被拦截的提醒保留为待处理记录。
- Claude/Codex hook 提醒按接收顺序排队，当前提醒展示及进出动画期间的新事件不再丢失或覆盖当前提醒；收起后按冷却时间依次处理。
- Claude Code 状态检测增加 Terminal 前台多窗口归因：事件来自非最上层 Terminal 窗口时也会提醒，关闭后可跳到来源窗口。
- Claude 前台多窗口归因改为独立高级开关，Claude 后台 hook 提醒不再自动请求辅助功能权限。
- Claude hook marker 改为 JSON，包含事件类型、来源、TTY 和时间戳；旧版空 marker 仍兼容。
- 新增提醒生命周期管理：超时未处理自动收起为菜单栏红点（默认 60 秒可关），气泡新增「稍后」按钮可延后重弹。
- 新增菜单栏「待处理提醒」：挂起事件一键重弹或清除。
- 新增提醒历史点击跳转：点击历史记录直达对应终端窗口，附今日提醒统计。
- 新增分级音效：需确认的提醒用更引人注目的提示音，普通提醒沿用温和音效。
- 新增菜单栏「自检与修复」：一键排查辅助功能权限、Claude/Codex hook 与配置备份，失败项可直接修复。
- 新增系统专注模式联动：Focus 开启时提醒静默，仅留菜单栏红点与历史记录。
- Codex 状态检测支持单独关闭 `PermissionRequest` 审批请求提醒，同时保留 `Stop` 完成提醒。

### v1.2.1
- **修复语言切换无效**：设置界面此前只读系统语言、无视用户选择，与通知话语逻辑割裂；现统一判定，选完即时切换，设置界面与话语语言保持一致。
- 设置里宠物选项改名为「橘猫」。
- 冷却时间由滑块改为下拉选择（5/10/15/30/60/120 秒）。

### v1.2.0
- **正式像素猫素材**：用手绘 PNG 像素猫替换此前代码绘制的占位猫，画面更精致；菜单栏猫的「常态 / 提醒 / 暂停」三态各有专属造型（橙 / 红 / 灰）。
- 像素渲染统一关闭抗锯齿并按整数像素对齐，放大保持硬边不糊。

### v1.1.0
- 新增 **Claude Code 状态检测**（可选）：通过 Claude Code hook 区分「需要确认」和「对话完成」，不依赖终端响铃；开启时自动安全合并 hook 进 `~/.claude/settings.json`（带备份），关闭即移除。

### v1.0.0
- 首个稳定版：菜单栏像素猫 + Terminal Dock badge 检测 + 掉落动画 + 设置/历史/声音。

## 技术栈

Swift + AppKit + SwiftUI，不依赖任何第三方框架。

## 文档

- [使用说明](docs/USER-GUIDE.md)
- [架构说明](docs/ARCHITECTURE.md)

## 许可

MIT License

## 致谢

灵感来自各种编程 IDE 里的宠物陪伴插件，以及总是被码头红点忽略掉的开发者们。
