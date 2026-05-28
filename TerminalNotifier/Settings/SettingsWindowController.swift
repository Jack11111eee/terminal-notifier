import AppKit
import SwiftUI

class SettingsWindowController {
    private var window: NSWindow?

    func showSettings(preferences: PreferencesManager) {
        if let existing = window {
            existing.center()
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(preferences: preferences)
        let hostingController = NSHostingController(rootView: settingsView)

        let win = NSWindow(contentViewController: hostingController)
        win.title = NSLocalizedString("Terminal Notifier Settings", comment: "")
        win.styleMask = [.titled, .closable, .miniaturizable]
        win.setContentSize(NSSize(width: 450, height: 360))
        win.isReleasedWhenClosed = false
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = win
    }
}
