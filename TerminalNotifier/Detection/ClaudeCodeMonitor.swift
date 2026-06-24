import AppKit

/// 监听 Claude Code hook 投放的事件标记文件。
///
/// hook（注册在 ~/.claude/settings.json）在「需要确认 / 对话完成」时，
/// 用 mktemp 在 `Constants.claudeEventsDir` 投放一个 JSON 标记文件。本监控每秒
/// 轮询该目录，消费（删除）标记文件并回调 delegate。
///
/// Terminal 在后台时沿用提醒；Terminal 在前台时，仅当标记能映射到非最上层
/// Terminal 窗口时才提醒。
protocol ClaudeCodeMonitorDelegate: AnyObject {
    func claudeCodeMonitor(_ monitor: ClaudeCodeMonitor, didEmit event: AgentNotificationEvent)
}

struct AgentNotificationEvent {
    let category: MessageProvider.Category
    let source: NotificationSource
    let tty: String?
    let targetWindow: TerminalWindowInfo?
}

class ClaudeCodeMonitor {
    weak var delegate: ClaudeCodeMonitorDelegate?
    private var timer: Timer?

    func startMonitoring() {
        ensureEventsDirExists()
        // 先清掉启动前堆积的旧标记，避免一上线就连弹。
        drainExistingMarkers()
        timer = Timer.scheduledTimer(withTimeInterval: Constants.badgePollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    private func ensureEventsDirExists() {
        try? FileManager.default.createDirectory(
            at: Constants.claudeEventsDir, withIntermediateDirectories: true)
    }

    /// 删除现存标记但不回调（用于启动时清场）。
    private func drainExistingMarkers() {
        for url in markerFiles() {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func poll() {
        let frontmost = isTerminalFrontmost()
        for url in markerFiles() {
            let marker = Self.marker(for: url)
            try? FileManager.default.removeItem(at: url)
            guard let category = marker.category else { continue }

            let target = marker.tty.flatMap { TerminalWindowRegistry.window(forTTY: $0) }
            if frontmost {
                guard let target, !TerminalWindowRegistry.isTopTerminalWindow(target) else {
                    continue
                }
            }
            delegate?.claudeCodeMonitor(self, didEmit: AgentNotificationEvent(
                category: category,
                source: .claudeCode,
                tty: marker.tty,
                targetWindow: target))
        }
    }

    private func markerFiles() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: Constants.claudeEventsDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles)) ?? []
    }

    /// JSON marker 优先；旧版空 marker 按文件名前缀兼容。
    private static func marker(for url: URL) -> (category: MessageProvider.Category?, tty: String?) {
        if let data = try? Data(contentsOf: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let type = json["event"] as? String ?? url.lastPathComponent.components(separatedBy: ".").first
            return (category(forType: type), normalizedTTY(json["tty"] as? String))
        }

        let type = url.lastPathComponent.components(separatedBy: ".").first ?? url.lastPathComponent
        return (category(forType: type), nil)
    }

    private static func category(forType type: String?) -> MessageProvider.Category? {
        switch type {
        case Constants.claudeEventNeedsConfirm: return .needsConfirm
        case Constants.claudeEventDone: return .done
        default: return nil
        }
    }

    private static func normalizedTTY(_ raw: String?) -> String? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              value != "??",
              value != "not a tty" else { return nil }
        if value.hasPrefix("/dev/") {
            value.removeFirst("/dev/".count)
        }
        return value
    }

    private func isTerminalFrontmost() -> Bool {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return false }
        return frontApp.bundleIdentifier == "com.apple.Terminal"
    }

    deinit {
        stopMonitoring()
    }
}
