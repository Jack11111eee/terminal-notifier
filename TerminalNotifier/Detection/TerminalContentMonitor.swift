import AppKit
import ApplicationServices

func dbg(_ msg: String) {
    if let fh = FileHandle(forWritingAtPath: "/tmp/terminal-notifier-debug.log"),
       let data = "[CM] \(msg)\n".data(using: .utf8) {
        fh.seekToEndOfFile()
        fh.write(data)
    }
}

protocol TerminalContentMonitorDelegate: AnyObject {
    func terminalContentDidChange(_ monitor: TerminalContentMonitor)
}

class TerminalContentMonitor {
    weak var delegate: TerminalContentMonitorDelegate?
    private var timer: Timer?
    private var lastContent: String?
    private var tickCount = 0

    private let maxRetries = 5

    func startMonitoring() {
        try? FileManager.default.removeItem(atPath: "/tmp/terminal-notifier-debug.log")
        FileManager.default.createFile(atPath: "/tmp/terminal-notifier-debug.log", contents: nil)
        dbg("startMonitoring called")

        if AXIsProcessTrusted() {
            dbg("AX trusted, starting polling")
            startPolling()
            return
        }

        dbg("AX not trusted, prompting")
        promptAndRetry(attempt: 1)
    }

    private func promptAndRetry(attempt: Int) {
        guard attempt <= maxRetries else {
            dbg("AX still not trusted after \(maxRetries) attempts, giving up")
            return
        }

        // Always check silently first — permission may have been granted since last retry
        if AXIsProcessTrusted() {
            dbg("AX already trusted (detected in retry), starting")
            startPolling()
            return
        }

        dbg("AX prompting attempt \(attempt)/\(maxRetries)")
        let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)

        let delay: TimeInterval = attempt <= 2 ? TimeInterval(attempt + 1) : 5
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.promptAndRetry(attempt: attempt + 1)
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    private func startPolling() {
        stopMonitoring()
        checkContent()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkContent()
        }
    }

    private func checkContent() {
        tickCount += 1
        let frontmost = isTerminalFrontmost()
        let currentContent = terminalContent()

        // Log every 5 ticks
        if tickCount % 5 == 1 {
            let len = currentContent?.count ?? -1
            dbg("tick #\(tickCount) frontmost=\(frontmost) contentLen=\(len) lastLen=\(lastContent?.count ?? -1)")
        }

        if frontmost {
            lastContent = currentContent
            return
        }

        guard let current = currentContent else {
            if tickCount % 5 == 1 { dbg("no content (Terminal windows not found?)") }
            return
        }

        // Only trigger when new text was appended to the end (real output),
        // not when AX representation randomly changes (rendering noise).
        if let last = lastContent, current != last, current.hasPrefix(last) {
            let added = current.count - last.count
            // Real terminal output always adds full lines (newline + content).
            // AX noise occasionally appends 1-2 control characters — ignore those.
            if added >= 3 {
                dbg("CONTENT APPENDED! +\(added) chars")
                delegate?.terminalContentDidChange(self)
            }
        }
        lastContent = current
    }

    private func isTerminalFrontmost() -> Bool {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return false }
        return frontApp.bundleIdentifier == "com.apple.Terminal"
    }

    private func terminalContent() -> String? {
        guard let termApp = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.Terminal").first else {
            return nil
        }

        let termEl = AXUIElementCreateApplication(termApp.processIdentifier)

        // Prefer the focused window, fall back to first window
        var win: AXUIElement?
        var focused: CFTypeRef?
        if AXUIElementCopyAttributeValue(termEl, "AXFocusedWindow" as CFString, &focused) == .success {
            win = (focused as! AXUIElement?)
        }
        if win == nil {
            var windows: CFTypeRef?
            AXUIElementCopyAttributeValue(termEl, "AXWindows" as CFString, &windows)
            win = (windows as? [AXUIElement])?.first
        }
        guard let targetWin = win else { return nil }

        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(targetWin, "AXChildren" as CFString, &children) == .success,
              let childList = children as? [AXUIElement],
              let splitGroup = childList.first(where: { el in
                  var role: CFTypeRef?
                  AXUIElementCopyAttributeValue(el, "AXRole" as CFString, &role)
                  return (role as? String) == "AXSplitGroup"
              }),
              let scrollArea = firstChild(of: splitGroup, role: "AXScrollArea"),
              let textArea = firstChild(of: scrollArea, role: "AXTextArea") else {
            return nil
        }

        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(textArea, "AXValue" as CFString, &value) == .success,
              let text = value as? String else { return nil }

        return text
    }

    private func firstChild(of element: AXUIElement, role: String) -> AXUIElement? {
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXChildren" as CFString, &children) == .success,
              let childList = children as? [AXUIElement] else { return nil }
        return childList.first { el in
            var r: CFTypeRef?
            AXUIElementCopyAttributeValue(el, "AXRole" as CFString, &r)
            return (r as? String) == role
        }
    }

    deinit {
        stopMonitoring()
    }
}
