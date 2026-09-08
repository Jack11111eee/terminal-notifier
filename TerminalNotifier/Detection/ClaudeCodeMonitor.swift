import AppKit

/// 同一 tty 的密集 `done` 防抖：Monitor/自动化会话每轮结束都触发一次 Stop hook，
/// 猫会被连环弹。首条 done 立即发出（不延迟正常提醒）；窗口期内的后续 done 只
/// 计数，静默 `doneDebounceSeconds` 后发一条「连续完成 N 轮」汇总事件收束。
/// needs_confirm 与不同 tty 不经过本层。
final class DoneDebouncer {
    struct Summary {
        let tty: String?
        let targetWindow: TerminalWindowInfo?
        let count: Int
    }

    private let windowSeconds: TimeInterval
    private var timers: [String: Timer] = [:]
    private var counts: [String: Int] = [:]
    private var contexts: [String: AgentNotificationEvent] = [:]
    private let onEmit: (Summary) -> Void

    /// tty 为 nil 时用此 key，与其他任何真实 tty 不冲突。
    private static let nilTTYKey = "\u{0}<nil>"

    init(windowSeconds: TimeInterval = Constants.doneDebounceSeconds,
         onEmit: @escaping (Summary) -> Void) {
        self.windowSeconds = windowSeconds
        self.onEmit = onEmit
    }

    /// 投递一条 done 事件。返回 true 表示这是窗口内首条（调用方应该照常放行
    /// 原事件）；返回 false 表示已并入正在集结的窗口（调用方应吞掉）。
    @discardableResult
    func offer(_ event: AgentNotificationEvent) -> Bool {
        guard event.category == .done, event.source == .claudeCode else {
            return true
        }
        let key = event.tty ?? Self.nilTTYKey
        if timers[key] == nil {
            counts[key] = 1
            contexts[key] = event
            scheduleFlush(for: key)
            return true
        }
        counts[key, default: 0] += 1
        contexts[key] = event
        return false
    }

    private func scheduleFlush(for key: String) {
        timers[key] = Timer(timeInterval: windowSeconds, repeats: false) { [weak self] _ in
            self?.flush(key)
        }
        RunLoop.main.add(timers[key]!, forMode: .common)
    }

    private func flush(_ key: String) {
        timers[key] = nil
        guard let count = counts.removeValue(forKey: key),
              count > 1,
              let context = contexts.removeValue(forKey: key) else {
            contexts.removeValue(forKey: key)
            return
        }
        onEmit(Summary(tty: context.tty, targetWindow: context.targetWindow, count: count))
    }

    /// 停止所有计时并在必要时立即收束（App 退出/监控暂停时调用）。
    func cancel() {
        for timer in timers.values { timer.invalidate() }
        timers.removeAll()
        counts.removeAll()
        contexts.removeAll()
    }
}

/// 监听 Claude Code hook 投放的事件标记文件。
///
/// hook（注册在 ~/.claude/settings.json）在「需要确认 / 对话完成」时，
/// 用 mktemp 在 `Constants.claudeEventsDir` 投放一个 JSON 标记文件。本监控每秒
/// 轮询该目录，消费（删除）标记文件并回调 delegate。
///
/// Terminal 在后台时沿用提醒；开启前台多窗口归因后，Terminal 在前台时仅当
/// 标记能映射到非最上层 Terminal 窗口时才提醒。
protocol ClaudeCodeMonitorDelegate: AnyObject {
    func claudeCodeMonitor(_ monitor: ClaudeCodeMonitor, didEmit event: AgentNotificationEvent)
}

struct AgentNotificationEvent {
    let category: MessageProvider.Category
    let source: NotificationSource
    let tty: String?
    let targetWindow: TerminalWindowInfo?
    /// 仅 doneBatched 用：窗口期内合并的 done 数；其余事件恒 1。
    let batchCount: Int

    init(
        category: MessageProvider.Category,
        source: NotificationSource,
        tty: String?,
        targetWindow: TerminalWindowInfo?,
        batchCount: Int = 1
    ) {
        self.category = category
        self.source = source
        self.tty = tty
        self.targetWindow = targetWindow
        self.batchCount = batchCount
    }
}

class ClaudeCodeMonitor {
    weak var delegate: ClaudeCodeMonitorDelegate?
    private var timer: Timer?
    /// 会话屏蔽查询/记录，测试通过 init 注入替换。
    private let blockedSessions: BlockedSessionsManager
    /// 同 tty 密集 done 合并；触发条件详见 DoneDebouncer 文档注释。
    private lazy var doneDebouncer = DoneDebouncer { [weak self] summary in
        guard let self else { return }
        self.flushWindowAttribution(for: summary.tty) { target in
            self.delegate?.claudeCodeMonitor(
                self,
                didEmit: summary.count > 1
                    ? AgentNotificationEvent(
                        category: .doneBatched,
                        source: .claudeCode,
                        tty: summary.tty,
                        targetWindow: target ?? summary.targetWindow,
                        batchCount: summary.count)
                    : AgentNotificationEvent(
                        category: .done,
                        source: .claudeCode,
                        tty: summary.tty,
                        targetWindow: target ?? summary.targetWindow))
        }
    }

    func startMonitoring() {
        ensureEventsDirExists()
        // 先清掉启动前堆积的旧标记，避免一上线就连弹。
        drainExistingMarkers()
        timer = Timer.scheduledTimer(withTimeInterval: Constants.badgePollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    init(blockedSessions: BlockedSessionsManager = .shared) {
        self.blockedSessions = blockedSessions
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        doneDebouncer.cancel()
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
        let windowAttributionEnabled = PreferencesManager.shared.claudeWindowAttributionEnabled
        for url in markerFiles() {
            let marker = Self.marker(for: url)
            try? FileManager.default.removeItem(at: url)
            guard let category = marker.category else { continue }

            // 会话屏蔽：marker 消费后早期丢弃，不进防抖器也不提醒（彻底安静）。
            // tty 为 nil 时（hook 探测失败）不命中——宁可多提醒，不可误吞。
            if blockedSessions.blocks(tty: marker.tty, category: category) {
                blockedSessions.recordIntercept(tty: marker.tty)
                continue
            }

            // 窗口归因可能执行 Terminal AppleScript，只能在用户明确开启后运行。
            // 开关关闭时仍保留 marker 的 tty，用户之后主动点击历史记录时再定位。
            let target = Self.attributedWindow(
                for: marker.tty,
                enabled: windowAttributionEnabled)

            guard Self.shouldEmit(
                category: category, frontmost: frontmost,
                target: target, windowAttributionEnabled: windowAttributionEnabled
            ) else { continue }

            guard doneDebouncer.offer(AgentNotificationEvent(
                category: category,
                source: .claudeCode,
                tty: marker.tty,
                targetWindow: target)) else { continue }

            delegate?.claudeCodeMonitor(self, didEmit: AgentNotificationEvent(
                category: category,
                source: .claudeCode,
                tty: marker.tty,
                targetWindow: target))
        }
    }

    /// 只在用户 opt-in 后解析 Terminal 窗口。`resolver` 参数使禁用路径可回归验证。
    static func attributedWindow(
        for tty: String?,
        enabled: Bool,
        resolver: (String) -> TerminalWindowInfo? = { TerminalWindowRegistry.window(forTTY: $0) }
    ) -> TerminalWindowInfo? {
        guard enabled, let tty else { return nil }
        return resolver(tty)
    }

    /// Terminal 前台 + 窗口归因开启时，丢弃属于最上层（用户正看的）窗口的事件。
    private static func shouldEmit(
        category: MessageProvider.Category,
        frontmost: Bool,
        target: TerminalWindowInfo?,
        windowAttributionEnabled: Bool
    ) -> Bool {
        guard windowAttributionEnabled else {
            return !frontmost
        }
        if frontmost {
            guard let target, !TerminalWindowRegistry.isTopTerminalWindow(target) else {
                return false
            }
        }
        return true
    }

    /// 防抖收束事件发送前重查归因（timer 回调时刻的前台状态可能已变化）。
    private func flushWindowAttribution(for tty: String?, emit: @escaping (TerminalWindowInfo?) -> Void) {
        // 收束也过会话屏蔽：防抖窗口开启后才屏蔽的会话，汇总不再弹出。
        if blockedSessions.blocks(tty: tty, category: .doneBatched) {
            blockedSessions.recordIntercept(tty: tty)
            return
        }
        let windowAttributionEnabled = PreferencesManager.shared.claudeWindowAttributionEnabled
        let target = Self.attributedWindow(for: tty, enabled: windowAttributionEnabled)
        guard Self.shouldEmit(
            category: .doneBatched,
            frontmost: isTerminalFrontmost(),
            target: target,
            windowAttributionEnabled: windowAttributionEnabled
        ) else { return }
        emit(target)
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
