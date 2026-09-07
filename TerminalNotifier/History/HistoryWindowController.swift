import AppKit
import SwiftUI

class HistoryWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    /// 共享刷新模型：AppDelegate 新增记录后 bump，已打开的 HistoryView 自动响应。
    let refreshModel = HistoryRefreshModel()

    func showHistory(
        historyManager: NotificationHistoryManager,
        onRecordTapped: ((NotificationRecord) -> Void)? = nil
    ) {
        if let existing = window {
            // 窗口已开：同步刷新信号并前置即可，无需重建视图。
            refreshModel.reloadToken += 1
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let historyView = HistoryView(
            historyManager: historyManager,
            onRecordTapped: onRecordTapped,
            refreshModel: refreshModel)
        let hostingController = NSHostingController(rootView: historyView)
        // Keep SwiftUI's minimum-size protection without deriving a maximum
        // window size from the current history content.
        hostingController.sizingOptions = [.minSize]

        let win = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        win.title = PreferencesManager.shared.resolvedLocale == "zh" ? "提醒历史" : "Notification History"
        win.titleVisibility = .visible
        win.titlebarSeparatorStyle = .none
        win.backgroundColor = .windowBackgroundColor
        win.toolbarStyle = .unifiedCompact
        win.tabbingMode = .disallowed
        win.contentViewController = hostingController
        win.setContentSize(NSSize(width: 620, height: 460))
        win.contentMinSize = NSSize(width: 500, height: 360)
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.center()
        win.setFrameAutosaveName("TerminalNotifier.History")
        win.makeKeyAndOrderFront(nil)
        // Apply after SwiftUI installs its toolbar, which can reset titlebar appearance.
        win.titlebarAppearsTransparent = true
        win.titlebarSeparatorStyle = .none
        NSApp.activate(ignoringOtherApps: true)

        self.window = win
    }

    /// 历史记录新增后调用：bump 共享 token，已打开的列表立即刷新，而不是等重开。
    func reloadIfVisible() {
        guard window != nil else { return }
        refreshModel.reloadToken += 1
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
