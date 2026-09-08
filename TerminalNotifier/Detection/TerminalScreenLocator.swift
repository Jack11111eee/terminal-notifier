import AppKit

struct TerminalScreenLocator {
    /// Returns the screen where the target app's frontmost window is, or main screen.
    /// 匹配一律按 PID（owner 名随系统语言本地化，中文系统为「终端」）。
    static func locateScreen(bundleIdentifier: String = Constants.terminalBundleIdentifier) -> NSScreen {
        let ownerPID = NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == bundleIdentifier }?
            .processIdentifier

        let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []

        for window in windowList {
            if let ownerPID,
               let pid = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
               pid != ownerPID { continue }
            guard let boundsDict = window[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            let bounds = CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0,
                height: boundsDict["Height"] ?? 0
            )
            for screen in NSScreen.screens {
                if screen.frame.intersects(bounds) {
                    return screen
                }
            }
            break
        }

        return NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
    }
}
