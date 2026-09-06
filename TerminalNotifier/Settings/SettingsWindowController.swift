import AppKit
import SwiftUI

class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    var onPreview: () -> Void = {}
    var onSelfCheck: () -> Void = {}

    func showSettings(preferences: PreferencesManager) {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(preferences: preferences, onPreview: onPreview, onSelfCheck: onSelfCheck)
        let hostingController = NSHostingController(rootView: settingsView)

        let win = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        win.title = preferences.resolvedLocale == "zh" ? "设置" : "Settings"
        win.titleVisibility = .hidden
        win.titlebarSeparatorStyle = .none
        win.backgroundColor = .windowBackgroundColor
        win.tabbingMode = .disallowed
        win.contentViewController = hostingController
        win.setContentSize(NSSize(width: 740, height: 500))
        win.contentMinSize = NSSize(width: 620, height: 440)
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.center()
        win.setFrameAutosaveName("TerminalNotifier.Settings")
        win.makeKeyAndOrderFront(nil)
        // Keep the full-height sidebar visible behind the native window controls.
        win.titlebarAppearsTransparent = true
        win.titlebarSeparatorStyle = .none
        NSApp.activate(ignoringOtherApps: true)

        self.window = win
        positionWindowButtons(win)
    }

    private func positionWindowButtons(_ window: NSWindow) {
        // Position the native controls within the inset sidebar, preserving their behavior.
        for (index, kind) in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].enumerated() {
            guard let button = window.standardWindowButton(kind), let container = button.superview else { continue }
            let center = container.convert(NSPoint(x: 26 + CGFloat(index) * 23,
                                                   y: window.frame.height - 26), from: nil)
            button.setFrameOrigin(NSPoint(x: center.x - button.frame.width / 2,
                                          y: center.y - button.frame.height / 2))
        }
    }

    func windowDidResize(_ notification: Notification) {
        if let window = notification.object as? NSWindow { positionWindowButtons(window) }
    }

    func windowDidUpdate(_ notification: Notification) {
        if let window = notification.object as? NSWindow { positionWindowButtons(window) }
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
