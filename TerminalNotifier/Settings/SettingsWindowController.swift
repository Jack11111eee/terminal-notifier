import AppKit
import SwiftUI

class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let visualMode: SettingsVisualMode
    var onPreview: () -> Void = {}
    var onSelfCheck: () -> Void = {}

    init(visualMode: SettingsVisualMode = .current) {
        self.visualMode = visualMode
        super.init()
    }

    func showSettings(preferences: PreferencesManager) {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(preferences: preferences,
                                        visualMode: visualMode,
                                        onPreview: onPreview,
                                        onSelfCheck: onSelfCheck)
        let hostingController = NSHostingController(rootView: settingsView)
        // The SwiftUI hierarchy defines the minimum usable size; AppKit remains
        // responsible for allowing this resizable window to grow freely.
        hostingController.sizingOptions = [.minSize]

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
        // Let AppKit place and manage the native window controls while the sidebar
        // supplies the full-height navigation material beneath the titlebar.
        win.titlebarAppearsTransparent = true
        win.titlebarSeparatorStyle = .none
        NSApp.activate(ignoringOtherApps: true)

        self.window = win
        alignWindowControlsWithSidebar(in: win)
    }

    private func alignWindowControlsWithSidebar(in window: NSWindow) {
        guard visualMode.repositionsWindowControls,
              !window.styleMask.contains(.fullScreen) else { return }
        let firstCenterX: CGFloat = 26
        let centerSpacing: CGFloat = 23
        let centerY = window.frame.height - 26
        for (index, kind) in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].enumerated() {
            guard let button = window.standardWindowButton(kind), let container = button.superview else { continue }
            let center = container.convert(NSPoint(x: firstCenterX + CGFloat(index) * centerSpacing,
                                                   y: centerY), from: nil)
            button.setFrameOrigin(NSPoint(x: center.x - button.frame.width / 2,
                                          y: center.y - button.frame.height / 2))
        }
    }

    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        alignWindowControlsWithSidebar(in: window)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
