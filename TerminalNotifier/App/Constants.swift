import Foundation

enum Constants {
    static let appName = "Terminal Notifier"
    /// CGWindowList 的 owner 名随系统语言本地化（中文系统为「终端」），
    /// 窗口匹配一律用 bundle id → PID，禁止按名字过滤。
    static let terminalBundleIdentifier = "com.apple.Terminal"
    static let badgePollInterval: TimeInterval = 1.0
    static let defaultPetSize: CGFloat = 240
    static let menuBarIconSize: CGFloat = 22
    static let defaultCooldown: Int = 10
    static let longWaitThreshold: TimeInterval = 120
    /// 提醒挂屏达到该时长且用户无操作，自动收起为菜单栏待处理项（不再挂屏）。
    /// 0 表示完全禁用。
    static let autoDismissSecondsDefault: Int = 60
    /// 点击「稍后」后再次提醒的默认延迟（秒）。
    static let snoozeMinutesDefault: Int = 10

    /// 同一 tty 的密集 done 合并窗口（秒）：窗口期内后续 done 不再逐条弹猫，
    /// 收束时发一条「连续完成 N 轮」汇总。首个 done 仍立即提醒，不受影响。
    static let doneDebounceSeconds: TimeInterval = 60

    // MARK: - Claude Code 集成

    /// Claude Code hook 与 App 之间的事件目录（相对 $HOME）。
    /// hook 用 mktemp 在此投放标记文件，ClaudeCodeMonitor 轮询消费。
    static let claudeEventsRelativePath = "Library/Application Support/TerminalNotifier/claude-events"

    /// 标记文件类型（文件名 `.` 之前的部分）。
    static let claudeEventNeedsConfirm = "needs_confirm"
    static let claudeEventDone = "done"

    /// 写入 ~/.claude/settings.json 的 hook 命令尾部标记，用于幂等识别与卸载。
    static let claudeHookMarker = "# terminal-notifier-hook"

    static var claudeEventsDir: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(claudeEventsRelativePath)
    }

    // MARK: - Codex 集成

    /// Codex hook 与 App 之间的事件目录（相对 $HOME）。
    static let codexEventsRelativePath = "Library/Application Support/TerminalNotifier/codex-events"

    /// Codex hook 执行诊断日志（相对 $HOME）。
    static let codexHookLogRelativePath = "Library/Application Support/TerminalNotifier/codex-hook.log"

    /// 旧版 Codex hook 命令尾部标记，用于迁移时识别与卸载。
    static let codexHookMarker = "# terminal-notifier-codex-hook"
    /// 新版 Codex hook 命令尾部标记，按事件拆分便于识别与单独控制。
    static let codexPermissionHookMarker = "# terminal-notifier-codex-permission-hook"
    static let codexStopHookMarker = "# terminal-notifier-codex-stop-hook"

    static var codexEventsDir: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(codexEventsRelativePath)
    }
}

enum NotificationSource: String {
    case terminal
    case claudeCode
    case codexApp

    var bundleIdentifier: String? {
        switch self {
        case .terminal, .claudeCode:
            return Constants.terminalBundleIdentifier
        case .codexApp:
            return "com.openai.codex"
        }
    }

    var historyBadgeLabel: String {
        switch self {
        case .terminal:
            return "terminal"
        case .claudeCode:
            return "claude-code"
        case .codexApp:
            return "codex-app"
        }
    }
}

enum MenuBarIconState {
    case normal
    case notifying
    case paused
    /// 「待处理提醒」（自动降级或暂延后）时的红点态图标。复用 notifying 素材。
    case pending
}
