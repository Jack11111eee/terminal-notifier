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
            existing.center()
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let historyView = HistoryView(
            historyManager: historyManager,
            onRecordTapped: onRecordTapped,
            refreshModel: refreshModel)
        let hostingController = NSHostingController(rootView: historyView)

        let win = NSWindow(contentViewController: hostingController)
        win.title = NSLocalizedString("Notification History", comment: "")
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.toolbarStyle = .unifiedCompact
        win.tabbingMode = .disallowed
        win.setContentSize(NSSize(width: 620, height: 460))
        win.minSize = NSSize(width: 560, height: 380)
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.center()
        win.makeKeyAndOrderFront(nil)
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
