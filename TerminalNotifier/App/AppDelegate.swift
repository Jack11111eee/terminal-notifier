import AppKit
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusBarController: StatusBarController!
    private var badgeMonitor: BadgeMonitor!
    private var overlayController: OverlayWindowController!
    private var stateMachine: NotificationStateMachine!
    private var settingsController: SettingsWindowController!
    private var historyManager = NotificationHistoryManager()
    private var soundManager = SoundManager()
    private let preferences = PreferencesManager.shared
    private var lastLaunchAtLoginValue: Bool = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlayController = OverlayWindowController()
        statusBarController = StatusBarController()
        badgeMonitor = BadgeMonitor()
        settingsController = SettingsWindowController()
        stateMachine = NotificationStateMachine(locale: preferences.resolvedLocale)

        badgeMonitor.delegate = self
        stateMachine.delegate = self

        overlayController.onDismissRequested = { [weak self] in
            self?.stateMachine.handleEvent(.userDismissed)
        }
        overlayController.onDropAnimationComplete = { [weak self] in
            self?.stateMachine.handleEvent(.dropAnimationCompleted)
        }
        overlayController.onJumpBackComplete = { [weak self] in
            self?.stateMachine.handleEvent(.jumpBackCompleted)
        }

        statusBarController.onSettingsClicked = { [weak self] in
            guard let self else { return }
            self.settingsController.showSettings(preferences: self.preferences)
        }
        statusBarController.onPauseToggled = { [weak self] paused in
            if paused { self?.badgeMonitor.stopMonitoring() }
            else { self?.badgeMonitor.startMonitoring() }
        }
        statusBarController.onHistoryClicked = { [weak self] in self?.showHistory() }
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
        }
        lastLaunchAtLoginValue = preferences.launchAtLogin

        badgeMonitor.startMonitoring()
    }

    func applicationWillTerminate(_ notification: Notification) {
        badgeMonitor.stopMonitoring()
        overlayController.close()
    }

    private func showOverlay(message: String) {
        guard preferences.enabled, !preferences.isInDNDPeriod else { return }
        let screen = TerminalScreenLocator.locateScreen()
        let menuBarFrame = statusBarController.menuBarIconFrame ?? .zero
        overlayController.show(on: screen, message: message, menuBarIconFrame: menuBarFrame)
        soundManager.playNotificationSound()
    }

    private func showHistory() {
        let records = historyManager.getRecords()
        let alert = NSAlert()
        alert.messageText = "Notification History"
        if records.isEmpty {
            alert.informativeText = "No notifications yet."
        } else {
            alert.informativeText = records.prefix(20).map { r in
                let df = DateFormatter(); df.dateFormat = "HH:mm:ss"
                return "[\(df.string(from: r.timestamp))] \(r.message)"
            }.joined(separator: "\n")
        }
        alert.addButton(withTitle: "OK")
        if !records.isEmpty { alert.addButton(withTitle: "Clear History") }
        if alert.runModal() == .alertSecondButtonReturn { historyManager.clearHistory() }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do { if enabled { try service.register() } else { try service.unregister() } }
        catch { print("[TerminalNotifier] Launch at login error: \(error)") }
    }
}

extension AppDelegate: BadgeMonitorDelegate {
    func badgeMonitor(_ monitor: BadgeMonitor, didDetectBadge label: String) {
        guard preferences.enabled, !preferences.isInDNDPeriod else { return }
        stateMachine.handleEvent(.badgeDetected)
    }
    func badgeMonitorDidClearBadge(_ monitor: BadgeMonitor) {
        stateMachine.handleEvent(.badgeCleared)
    }
}

extension AppDelegate: NotificationStateMachineDelegate {
    func stateMachine(_ sm: NotificationStateMachine, didTransitionTo state: NotificationState) {
        switch state {
        case .idle: statusBarController.updateIcon(state: .normal)
        case .detected, .animatingIn: statusBarController.updateIcon(state: .notifying)
        case .showing: break
        case .animatingOut: break
        }
    }
    func stateMachine(_ sm: NotificationStateMachine, shouldShowOverlayWithMessage message: String) {
        historyManager.addRecord(NotificationRecord(
            id: UUID(), timestamp: Date(), badgeLabel: "detected", message: message, category: "new_notification"))
        showOverlay(message: message)
    }
    func stateMachine(_ sm: NotificationStateMachine, shouldUpdateMessage message: String) {
        overlayController.updateMessage(message)
    }
    func stateMachineShouldDismissOverlay(_ sm: NotificationStateMachine) {
        if preferences.switchToTerminal {
            NSWorkspace.shared.runningApplications
                .first { $0.bundleIdentifier == "com.apple.Terminal" }?
                .activate(options: .activateIgnoringOtherApps)
        }
        overlayController.beginDismiss()
    }
}
