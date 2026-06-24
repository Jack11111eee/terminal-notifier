import AppKit
import ApplicationServices

struct TerminalWindowInfo: Equatable {
    let windowID: CGWindowID
    let ownerPID: pid_t
    let title: String
    let bounds: CGRect
}

enum TerminalWindowRegistry {
    private struct ScriptWindow {
        let tty: String
        let title: String
        let bounds: CGRect
    }

    static func orderedWindows() -> [TerminalWindowInfo] {
        let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []

        return windowList.compactMap { window in
            guard (window[kCGWindowOwnerName as String] as? String) == "Terminal",
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  let id = uint32(in: window, key: kCGWindowNumber as String),
                  let pid = int(in: window, key: kCGWindowOwnerPID as String),
                  let boundsDict = window[kCGWindowBounds as String] as? [String: Any]
            else { return nil }

            let bounds = CGRect(
                x: number(in: boundsDict, key: "X"),
                y: number(in: boundsDict, key: "Y"),
                width: number(in: boundsDict, key: "Width"),
                height: number(in: boundsDict, key: "Height")
            )
            guard bounds.width > 0, bounds.height > 0 else { return nil }

            return TerminalWindowInfo(
                windowID: CGWindowID(id),
                ownerPID: pid_t(pid),
                title: window[kCGWindowName as String] as? String ?? "",
                bounds: bounds
            )
        }
    }

    static func topWindow() -> TerminalWindowInfo? {
        orderedWindows().first
    }

    static func isTopTerminalWindow(_ window: TerminalWindowInfo) -> Bool {
        topWindow()?.windowID == window.windowID
    }

    static func screen(for window: TerminalWindowInfo?) -> NSScreen {
        guard let window else {
            return NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
        }
        return screen(containing: window.bounds)
    }

    @discardableResult
    static func requestAccessibilityTrustIfNeeded() -> Bool {
        if AXIsProcessTrusted() { return true }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func window(forTTY tty: String) -> TerminalWindowInfo? {
        let normalized = normalizeTTY(tty)
        let windows = orderedWindows()

        if windows.count == 1 {
            return windows.first
        }

        if let fromScripting = windowFromTerminalScripting(forTTY: normalized, windows: windows) {
            return fromScripting
        }

        if let fromTitle = windows.first(where: { titleContainsTTY($0.title, tty: normalized) }) {
            return fromTitle
        }

        for window in windows {
            guard let axWindow = axWindow(matching: window),
                  axWindowContainsTTY(axWindow, tty: normalized) else { continue }
            return window
        }

        return nil
    }

    static func activate(_ window: TerminalWindowInfo?) {
        guard let window else {
            NSWorkspace.shared.runningApplications
                .first { $0.bundleIdentifier == "com.apple.Terminal" }?
                .activate(options: .activateIgnoringOtherApps)
            return
        }

        NSWorkspace.shared.runningApplications
            .first { $0.processIdentifier == window.ownerPID }?
            .activate(options: .activateIgnoringOtherApps)

        guard let axWindow = axWindow(matching: window) else { return }
        AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
    }

    private static func screen(containing bounds: CGRect) -> NSScreen {
        for screen in NSScreen.screens where screen.frame.intersects(bounds) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
    }

    private static func normalizeTTY(_ tty: String) -> String {
        var value = tty.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("/dev/") {
            value.removeFirst("/dev/".count)
        }
        return value
    }

    private static func number(in dictionary: [String: Any], key: String) -> CGFloat {
        if let number = dictionary[key] as? NSNumber {
            return CGFloat(truncating: number)
        }
        return dictionary[key] as? CGFloat ?? 0
    }

    private static func int(in dictionary: [String: Any], key: String) -> Int? {
        if let number = dictionary[key] as? NSNumber {
            return number.intValue
        }
        return dictionary[key] as? Int
    }

    private static func uint32(in dictionary: [String: Any], key: String) -> UInt32? {
        if let number = dictionary[key] as? NSNumber {
            return number.uint32Value
        }
        return dictionary[key] as? UInt32
    }

    private static func titleContainsTTY(_ title: String, tty: String) -> Bool {
        title.contains(tty) || title.contains("/dev/\(tty)")
    }

    private static func windowFromTerminalScripting(
        forTTY tty: String,
        windows: [TerminalWindowInfo]
    ) -> TerminalWindowInfo? {
        let scriptWindows = terminalScriptWindows()
        guard !scriptWindows.isEmpty else { return nil }

        let matchingRows = scriptWindows.filter { normalizeTTY($0.tty) == tty }
        for row in matchingRows {
            let matchingWindows = windows.filter {
                windowsMatch($0, scriptWindow: row)
            }
            if matchingWindows.count == 1 {
                return matchingWindows.first
            }
        }

        return nil
    }

    private static func terminalScriptWindows() -> [ScriptWindow] {
        let script = """
        set fieldSep to ASCII character 31
        set rowSep to ASCII character 30
        set output to ""
        tell application id "com.apple.Terminal"
            repeat with w in windows
                try
                    if visible of w is true and miniaturized of w is false then
                        set windowTitle to name of w
                        set windowBounds to bounds of w
                        repeat with t in tabs of w
                            set tabTTY to tty of t
                            set output to output & tabTTY & fieldSep & windowTitle & fieldSep & (item 1 of windowBounds as text) & fieldSep & (item 2 of windowBounds as text) & fieldSep & (item 3 of windowBounds as text) & fieldSep & (item 4 of windowBounds as text) & rowSep
                        end repeat
                    end if
                end try
            end repeat
        end tell
        return output
        """

        var error: NSDictionary?
        guard let output = NSAppleScript(source: script)?.executeAndReturnError(&error).stringValue,
              !output.isEmpty else { return [] }

        return output
            .split(separator: "\u{1e}")
            .compactMap { row in
                let parts = row.split(separator: "\u{1f}")
                guard parts.count == 6,
                      let left = Double(parts[2]),
                      let top = Double(parts[3]),
                      let right = Double(parts[4]),
                      let bottom = Double(parts[5]) else { return nil }
                return ScriptWindow(
                    tty: String(parts[0]),
                    title: String(parts[1]),
                    bounds: CGRect(
                        x: left,
                        y: top,
                        width: right - left,
                        height: bottom - top
                    )
                )
            }
    }

    private static func windowsMatch(
        _ window: TerminalWindowInfo,
        scriptWindow: ScriptWindow
    ) -> Bool {
        if window.title == scriptWindow.title { return true }
        return abs(window.bounds.origin.x - scriptWindow.bounds.origin.x) < 2
            && abs(window.bounds.width - scriptWindow.bounds.width) < 2
            && abs(window.bounds.height - scriptWindow.bounds.height) < 2
    }

    private static func axWindow(matching window: TerminalWindowInfo) -> AXUIElement? {
        let app = AXUIElementCreateApplication(window.ownerPID)
        guard let axWindows: [AXUIElement] = copyAttribute(app, kAXWindowsAttribute as String) else {
            return nil
        }

        return axWindows.first { axWindow in
            let title: String? = copyAttribute(axWindow, kAXTitleAttribute as String)
            if title == window.title { return true }

            guard let frame = frame(of: axWindow) else { return false }
            return abs(frame.origin.x - window.bounds.origin.x) < 2
                && abs(frame.origin.y - window.bounds.origin.y) < 2
                && abs(frame.width - window.bounds.width) < 2
                && abs(frame.height - window.bounds.height) < 2
        }
    }

    private static func axWindowContainsTTY(_ axWindow: AXUIElement, tty: String) -> Bool {
        containsTTY(axWindow, tty: tty, depth: 0, maxDepth: 5)
    }

    private static func containsTTY(
        _ element: AXUIElement,
        tty: String,
        depth: Int,
        maxDepth: Int
    ) -> Bool {
        for attr in [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute] {
            if let text: String = copyAttribute(element, attr as String),
               (text.contains(tty) || text.contains("/dev/\(tty)")) {
                return true
            }
        }

        guard depth < maxDepth,
              let children: [AXUIElement] = copyAttribute(element, kAXChildrenAttribute as String)
        else { return false }

        for child in children {
            if containsTTY(child, tty: tty, depth: depth + 1, maxDepth: maxDepth) {
                return true
            }
        }
        return false
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        guard let position: AXValue = copyAttribute(element, kAXPositionAttribute as String),
              let size: AXValue = copyAttribute(element, kAXSizeAttribute as String)
        else { return nil }

        var point = CGPoint.zero
        var cgSize = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &point),
              AXValueGetValue(size, .cgSize, &cgSize) else { return nil }
        return CGRect(origin: point, size: cgSize)
    }

    private static func copyAttribute<T>(_ element: AXUIElement, _ attr: String) -> T? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attr as CFString, &value)
        guard error == .success else { return nil }
        return value as? T
    }
}
