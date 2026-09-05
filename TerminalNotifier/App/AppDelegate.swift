import AppKit
import ServiceManagement

func tnLog(_ msg: String) {
#if DEBUG
    if let fh = FileHandle(forWritingAtPath: "/tmp/terminal-notifier-debug.log"),
       let data = "[APP] \(msg)\n".data(using: .utf8) {
        fh.seekToEndOfFile()
        fh.write(data)
    }
#endif
}

class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusBarController: StatusBarController!
    private var contentMonitor: TerminalContentMonitor!
    private var claudeMonitor: ClaudeCodeMonitor!
    private var codexMonitor: CodexAppMonitor!
    private var overlayController: OverlayWindowController!
    private var stateMachine: NotificationStateMachine!
    private var settingsController: SettingsWindowController!
    private var historyController: HistoryWindowController!
    private var selfCheckController: SelfCheckWindowController?
    private var historyManager = NotificationHistoryManager()
    private var soundManager = SoundManager()
    private let preferences = PreferencesManager.shared
    private var lastLaunchAtLoginValue: Bool = false
    private var lastClaudeCodeEnabledValue: Bool = false
    private var lastClaudeWindowAttributionEnabledValue: Bool = false
    private var lastCodexAppEnabledValue: Bool = false
    private var lastCodexPermissionRequestEnabledValue: Bool = true
    private var currentOverlaySource: NotificationSource = .terminal
    private var currentOverlayTargetWindow: TerminalWindowInfo?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let previewMode = PreviewMode.current {
            startPreview(mode: previewMode)
            return
        }

        overlayController = OverlayWindowController()
        statusBarController = StatusBarController()
        contentMonitor = TerminalContentMonitor()
        claudeMonitor = ClaudeCodeMonitor()
        codexMonitor = CodexAppMonitor()
        settingsController = SettingsWindowController()
        historyController = HistoryWindowController()
        stateMachine = NotificationStateMachine()
        stateMachine.delegate = self
        statusBarController.pendingInfoProvider = { [weak self] in
            self?.stateMachine.pendingInfo
        }
        statusBarController.onPendingReactivated = { [weak self] in
            self?.reactivatePending()
        }
        statusBarController.onPendingCleared = { [weak self] in
            self?.stateMachine.handleEvent(.clearPending)
        }
        overlayController.onSnoozeRequested = { [weak self] in
            self?.stateMachine.handleEvent(.userSnoozed)
        }

        contentMonitor.delegate = self
        claudeMonitor.delegate = self
        codexMonitor.delegate = self

        overlayController.onDismissRequested = { [weak self] in
            self?.stateMachine.handleEvent(.userDismissed)
        }
        overlayController.onDropAnimationComplete = { [weak self] in
            self?.stateMachine.handleEvent(.dropAnimationCompleted)
        }
        overlayController.onJumpBackComplete = { [weak self] in
            guard let self else { return }
            self.overlayController.forceClose()
            self.stateMachine.handleEvent(.jumpBackCompleted)
        }

        statusBarController.onSettingsClicked = { [weak self] in
            guard let self else { return }
            self.settingsController.showSettings(preferences: self.preferences)
        }
        statusBarController.onPauseToggled = { [weak self] paused in
            if paused {
                self?.contentMonitor.stopMonitoring()
                self?.claudeMonitor.stopMonitoring()
                self?.codexMonitor.stopMonitoring()
                // 暂停时复位状态机并收起弹窗；否则仓鼠式转态机的 cooldown/snooze/
                // autoDismiss 定时器会在暂停期间继续走，恢复后立刻补弹过期提醒。
                self?.stateMachine.reset()
                self?.overlayController.forceClose()
            } else {
                self?.contentMonitor.startMonitoring()
                if self?.preferences.claudeCodeEnabled == true { self?.claudeMonitor.startMonitoring() }
                if self?.preferences.codexAppEnabled == true { self?.codexMonitor.startMonitoring() }
            }
        }
        statusBarController.onHistoryClicked = { [weak self] in self?.showHistory() }
        statusBarController.onSelfCheckClicked = { [weak self] in self?.showSelfCheck() }
        statusBarController.onQuitClicked = { NSApplication.shared.terminate(nil) }

        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let current = self.preferences.launchAtLogin
            if current != self.lastLaunchAtLoginValue {
                self.lastLaunchAtLoginValue = current
                self.setLaunchAtLogin(current)
            }
            let claudeCurrent = self.preferences.claudeCodeEnabled
            if claudeCurrent != self.lastClaudeCodeEnabledValue {
                self.lastClaudeCodeEnabledValue = claudeCurrent
                self.setClaudeCodeEnabled(claudeCurrent)
            }
            let claudeAttributionCurrent = self.preferences.claudeWindowAttributionEnabled
            if claudeAttributionCurrent != self.lastClaudeWindowAttributionEnabledValue {
                self.lastClaudeWindowAttributionEnabledValue = claudeAttributionCurrent
                self.setClaudeWindowAttributionEnabled(claudeAttributionCurrent)
            }
            let codexCurrent = self.preferences.codexAppEnabled
            if codexCurrent != self.lastCodexAppEnabledValue {
                self.lastCodexAppEnabledValue = codexCurrent
                self.setCodexAppEnabled(codexCurrent)
            }
            let codexPermissionCurrent = self.preferences.codexPermissionRequestEnabled
            if codexPermissionCurrent != self.lastCodexPermissionRequestEnabledValue {
                self.lastCodexPermissionRequestEnabledValue = codexPermissionCurrent
                self.setCodexPermissionRequestEnabled(codexPermissionCurrent)
            }
            self.statusBarController.refreshMenu()
        }
        lastLaunchAtLoginValue = preferences.launchAtLogin
        lastClaudeCodeEnabledValue = preferences.claudeCodeEnabled
        lastClaudeWindowAttributionEnabledValue = preferences.claudeWindowAttributionEnabled
        lastCodexAppEnabledValue = preferences.codexAppEnabled
        lastCodexPermissionRequestEnabledValue = preferences.codexPermissionRequestEnabled

        contentMonitor.startMonitoring()
        // 持久化开启时，自愈式确保 hook 已安装并启动监控。
        if preferences.claudeCodeEnabled {
            if !ClaudeHookManager.install() {
                print("[TerminalNotifier] Claude Code hook install failed")
            }
            claudeMonitor.startMonitoring()
        }
        if preferences.codexAppEnabled {
            if !CodexHookManager.install(includePermissionRequest: preferences.codexPermissionRequestEnabled) {
                print("[TerminalNotifier] Codex hook install failed")
            }
            codexMonitor.startMonitoring()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        contentMonitor?.stopMonitoring()
        claudeMonitor?.stopMonitoring()
        codexMonitor?.stopMonitoring()
        overlayController?.close()
    }

    /// 切换 Claude Code 状态检测：安装/卸载 hook + 启停监控。
    private func setClaudeCodeEnabled(_ enabled: Bool) {
        if enabled {
            if !ClaudeHookManager.install() {
                print("[TerminalNotifier] Claude Code hook install failed")
            }
            claudeMonitor.startMonitoring()
        } else {
            if !ClaudeHookManager.uninstall() {
                print("[TerminalNotifier] Claude Code hook uninstall failed")
            }
            claudeMonitor.stopMonitoring()
        }
    }

    private func setClaudeWindowAttributionEnabled(_ enabled: Bool) {
        if enabled {
            TerminalWindowRegistry.requestAccessibilityTrustIfNeeded()
        }
    }

    /// 切换 Codex 状态检测：安装/卸载 hook + 启停监控。
    private func setCodexAppEnabled(_ enabled: Bool) {
        if enabled {
            if !CodexHookManager.install(includePermissionRequest: preferences.codexPermissionRequestEnabled) {
                print("[TerminalNotifier] Codex hook install failed")
            }
            codexMonitor.startMonitoring()
        } else {
            if !CodexHookManager.uninstall() {
                print("[TerminalNotifier] Codex hook uninstall failed")
            }
            codexMonitor.stopMonitoring()
        }
    }

    private func setCodexPermissionRequestEnabled(_ enabled: Bool) {
        guard preferences.codexAppEnabled else { return }
        if !CodexHookManager.install(includePermissionRequest: enabled) {
            print("[TerminalNotifier] Codex hook update failed")
        }
    }

    private func showOverlay(
        message: String,
        category: MessageProvider.Category,
        source: NotificationSource,
        targetWindow: TerminalWindowInfo?
    ) {
        let focusActive = cachedSystemFocusActive()
        tnLog("showOverlay: enabled=\(preferences.enabled) dnd=\(preferences.isInDNDPeriod) focus=\(focusActive)")
        guard preferences.enabled, !preferences.isInDNDPeriod, !focusActive else {
            tnLog("showOverlay BLOCKED: enabled=\(preferences.enabled) dnd=\(preferences.isInDNDPeriod) focus=\(focusActive)")
            stateMachine.handleEvent(.overlaySuppressed)
            return
        }
        currentOverlayTargetWindow = targetWindow
        let screen = targetWindow.map { TerminalWindowRegistry.screen(for: $0) }
            ?? TerminalScreenLocator.locateScreen(ownerName: source.windowOwnerName)
        tnLog("showOverlay: calling overlayController.show screen=\(screen)")
        overlayController.show(on: screen, message: message)
        soundManager.playNotificationSound(for: category)
        tnLog("showOverlay: done")
    }

    private func showHistory() {
        historyController.showHistory(historyManager: historyManager) { record in
            if let tty = record.tty,
               let window = TerminalWindowRegistry.window(forTTY: tty) {
                TerminalWindowRegistry.activate(window)
            } else {
                // 找不到原窗口（已关闭/tty 复用）时降级激活 Terminal 本体，不打扰用户。
                TerminalWindowRegistry.activate(nil)
            }
        }
    }

    private func showSelfCheck() {
        if selfCheckController == nil {
            selfCheckController = SelfCheckWindowController()
        }
        selfCheckController?.show()
    }

    /// Focus 状态缓存：5 秒 TTL + 后台刷新，避免主线程跑 plutil 子进程阻塞提醒（修 Bug 1）。
    /// 首次调用返回 false（宁可不静默），后台队列异步填充，后续调用读缓存。
    private var focusCachedValue: Bool = false
    private var focusCachedAt: Date = .distantPast
    private let focusCacheTTL: TimeInterval = 5
    private var focusRefreshInFlight = false

    private func cachedSystemFocusActive() -> Bool {
        let now = Date()
        if now.timeIntervalSince(focusCachedAt) > focusCacheTTL {
            focusCachedAt = now
            refreshFocusCacheIfNeeded()
        }
        return focusCachedValue
    }

    private func refreshFocusCacheIfNeeded() {
        guard !focusRefreshInFlight else { return }
        focusRefreshInFlight = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = self?.computeSystemFocusActive() ?? false
            DispatchQueue.main.async { [weak self] in
                self?.focusCachedValue = result
                self?.focusRefreshInFlight = false
            }
        }
    }

    /// 系统专注模式（Focus / DND）是否激活。
    /// 优先读 ~/Library/DoNotDisturb/DB/Assertions.json，失败回退 com.apple.ncprefs 的 dnd_prefs。
    /// 所有读法都失败时返回 false：宁可让提醒正常弹，也不能因检测失败静默吞掉提醒。
    /// 此方法可能跑 plutil 子进程，仅在后台队列调用。
    private func computeSystemFocusActive() -> Bool {
        let assertionsPath = NSHomeDirectory() + "/Library/DoNotDisturb/DB/Assertions.json"
        if let data = FileManager.default.contents(atPath: assertionsPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let records = json["data"] as? [[String: Any]],
           !records.isEmpty {
            return true
        }

        // 回退路径：com.apple.ncprefs 的 dnd_prefs 是 base64 包装的嵌套 plist。
        // 仅当能解码出 userPref.enabled == true 才判定为 Focus 开启；
        // 任何一步失败都返回 false（宁可不静默，不可误静默）。
        let ncprefsPath = NSHomeDirectory() + "/Library/Preferences/com.apple.ncprefs.plist"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/plutil")
        process.arguments = ["-extract", "dnd_prefs", "xml1", "-o", "-", "--", ncprefsPath]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return false }
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return Self.dndPrefsIndicatesEnabled(output)
        } catch {
            return false
        }
    }

    /// 解析 plutil 输出的 dnd_prefs（base64 嵌套 plist），只在能确认 userPref.enabled == true 时返回 true。
    /// 判定失败（结构漂移、键缺失、解码失败）一律返回 false，由调用方视为「非 Focus」。
    private static func dndPrefsIndicatesEnabled(_ plutilOutput: String) -> Bool {
        // plutil -extract dnd_prefs 输出顶层即该键的值：一个 <data> 节点承载嵌套 plist。
        guard let nestedData = try? PropertyListSerialization.propertyList(
            from: Data(plutilOutput.utf8), options: [], format: nil
        ) as? Data,
              let nested = try? PropertyListSerialization.propertyList(
                  from: nestedData, options: [], format: nil
              ) as? [String: Any],
              let userPref = nested["userPref"] as? [String: Any],
              let enabled = userPref["enabled"] as? Bool
        else { return false }
        return enabled
    }

    /// 菜单栏「待处理提醒」触发：立刻把挂起消息重弹到屏幕上，并清掉挂起状态。
    /// 用户随后按 dismiss/snooze 的常规路径处理。
    private func reactivatePending() {
        guard let info = stateMachine.pendingInfo else { return }
        stateMachine.handleEvent(.clearPending)
        stateMachine.handleEvent(.agentTrigger(AgentNotificationEvent(
            category: info.category,
            source: info.source,
            tty: nil,
            targetWindow: info.targetWindow)))
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do { if enabled { try service.register() } else { try service.unregister() } }
        catch { print("[TerminalNotifier] Launch at login error: \(error)") }
    }

    private func startPreview(mode: PreviewMode) {
        settingsController = SettingsWindowController()
        historyController = HistoryWindowController()
        overlayController = OverlayWindowController()
        historyManager = Self.previewHistoryManager()

        overlayController.onDismissRequested = { [weak self] in
            self?.overlayController.beginDismiss()
        }
        overlayController.onJumpBackComplete = { [weak self] in
            guard let self else { return }
            self.overlayController.forceClose()
        }

        NSApp.activate(ignoringOtherApps: true)

        switch mode {
        case .settings:
            settingsController.showSettings(preferences: preferences)
        case .history:
            historyController.showHistory(historyManager: historyManager)
        case .overlay:
            showPreviewOverlay()
        case .all:
            settingsController.showSettings(preferences: preferences)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.historyController.showHistory(historyManager: self.historyManager)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self.showPreviewOverlay()
            }
        }
    }

    private func showPreviewOverlay() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        overlayController.show(
            on: screen,
            message: preferences.resolvedLocale == "zh"
                ? "点击猫或气泡关闭"
                : "Click the pet or bubble to dismiss"
        )
    }

    private static func previewHistoryManager() -> NotificationHistoryManager {
        let manager = NotificationHistoryManager(storageKey: "notificationHistoryPreview")
        manager.clearHistory()
        manager.addRecord(NotificationRecord(
            id: UUID(),
            timestamp: Date().addingTimeInterval(-80),
            badgeLabel: "preview",
            message: "Claude needs your confirmation.",
            category: MessageProvider.Category.needsConfirm.rawValue
        ))
        manager.addRecord(NotificationRecord(
            id: UUID(),
            timestamp: Date().addingTimeInterval(-260),
            badgeLabel: "preview",
            message: "Terminal notification detected in the active session.",
            category: MessageProvider.Category.newNotification.rawValue
        ))
        manager.addRecord(NotificationRecord(
            id: UUID(),
            timestamp: Date().addingTimeInterval(-540),
            badgeLabel: "preview",
            message: "Claude is done.",
            category: MessageProvider.Category.done.rawValue
        ))
        return manager
    }
}

extension AppDelegate: TerminalContentMonitorDelegate {
    func terminalContentDidClear(_ monitor: TerminalContentMonitor) {
        tnLog("terminalContentDidClear — forwarding badgeCleared to stateMachine")
        stateMachine.handleEvent(.badgeCleared)
    }
    func terminalContentDidChange(_ monitor: TerminalContentMonitor) {
        tnLog("terminalContentDidChange — forwarding to stateMachine")
        // DND 不再拦在这里：事件进 stateMachine、历史写入照常，只在 showOverlay 拦视觉/听觉。
        // 这样免打扰时菜单栏红点可见、历史可回补，但猫不掉、声音不响。
        guard preferences.enabled else {
            tnLog("terminalContentDidChange BLOCKED: disabled")
            return
        }
        stateMachine.handleEvent(.badgeDetected)
    }
}

extension AppDelegate: ClaudeCodeMonitorDelegate {
    func claudeCodeMonitor(_ monitor: ClaudeCodeMonitor, didEmit event: AgentNotificationEvent) {
        tnLog("claudeCodeMonitor didEmit \(event.category.rawValue) tty=\(event.tty ?? "nil") window=\(event.targetWindow?.windowID ?? 0)")
        guard preferences.enabled else {
            tnLog("claudeCodeMonitor BLOCKED: disabled")
            return
        }
        stateMachine.handleEvent(.agentTrigger(event))
    }
}

extension AppDelegate: CodexAppMonitorDelegate {
    func codexAppMonitor(_ monitor: CodexAppMonitor, didEmit category: MessageProvider.Category) {
        tnLog("codexAppMonitor didEmit \(category.rawValue)")
        guard preferences.enabled else {
            tnLog("codexAppMonitor BLOCKED: disabled")
            return
        }
        stateMachine.handleEvent(.agentTrigger(AgentNotificationEvent(
            category: category,
            source: .codexApp,
            tty: nil,
            targetWindow: nil)))
    }
}

extension AppDelegate: NotificationStateMachineDelegate {
    func stateMachine(_ sm: NotificationStateMachine, didTransitionTo state: NotificationState) {
        tnLog("stateMachine → \(state)")
        switch state {
        case .idle:
            statusBarController.updateIcon(state: .normal)
            statusBarController.refreshMenu()
        case .detected: statusBarController.updateIcon(state: .notifying)
        case .showing: break
        case .animatingOut: break
        case .pending:
            statusBarController.updateIcon(state: .pending)
            statusBarController.refreshMenu()
        }
    }
    func stateMachine(
        _ sm: NotificationStateMachine,
        shouldShowOverlayWithMessage message: String,
        category: MessageProvider.Category,
        source: NotificationSource,
        targetWindow: TerminalWindowInfo?
    ) {
        tnLog("stateMachine: shouldShowOverlay msg=\(message)")
        currentOverlaySource = source
        currentOverlayTargetWindow = targetWindow
        historyManager.addRecord(NotificationRecord(
            id: UUID(),
            timestamp: Date(),
            badgeLabel: source.historyBadgeLabel,
            message: message,
            category: category.rawValue,
            tty: sm.activeTTY,
            windowTitle: targetWindow?.title))
        // 历史窗口若正开着，立即刷新列表，而不是等重开。
        historyController.reloadIfVisible()
        showOverlay(message: message, category: category, source: source, targetWindow: targetWindow)
    }
    func stateMachine(
        _ sm: NotificationStateMachine,
        shouldUpdateMessage message: String,
        category: MessageProvider.Category,
        source: NotificationSource,
        targetWindow: TerminalWindowInfo?
    ) {
        tnLog("stateMachine: shouldUpdate msg=\(message)")
        currentOverlaySource = source
        currentOverlayTargetWindow = targetWindow
        overlayController.updateMessage(message)
    }
    func stateMachineShouldDismissOverlay(_ sm: NotificationStateMachine) {
        tnLog("stateMachine: shouldDismiss")
        if preferences.switchToTerminal {
            if currentOverlaySource == .claudeCode {
                TerminalWindowRegistry.activate(currentOverlayTargetWindow)
            } else {
                NSWorkspace.shared.runningApplications
                    .first { $0.bundleIdentifier == currentOverlaySource.bundleIdentifier }?
                    .activate(options: .activateIgnoringOtherApps)
            }
        }
        overlayController.beginDismiss()
    }
}
