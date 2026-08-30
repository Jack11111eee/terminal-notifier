import AppKit

func dbg(_ msg: String) {
#if DEBUG
    if let fh = FileHandle(forWritingAtPath: "/tmp/terminal-notifier-debug.log"),
       let data = "[CM] \(msg)\n".data(using: .utf8) {
        fh.seekToEndOfFile()
        fh.write(data)
    }
#endif
}

protocol TerminalContentMonitorDelegate: AnyObject {
    func terminalContentDidChange(_ monitor: TerminalContentMonitor)
    /// badge 从非空清空（用户回到 Terminal 看完了通知），状态机应回到 .idle。
    func terminalContentDidClear(_ monitor: TerminalContentMonitor)
}

class TerminalContentMonitor {
    weak var delegate: TerminalContentMonitorDelegate?
    private var timer: Timer?
    private var lastBadgeLabel: String?
    private var tickCount = 0

    func startMonitoring() {
#if DEBUG
        try? FileManager.default.removeItem(atPath: "/tmp/terminal-notifier-debug.log")
        FileManager.default.createFile(atPath: "/tmp/terminal-notifier-debug.log", contents: nil)
#endif
        dbg("startMonitoring (badge-based, no AX needed)")

        // Capture initial badge state without triggering
        lastBadgeLabel = readBadge()
        dbg("initial badge=\(lastBadgeLabel ?? "nil")")

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkBadge()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    private func checkBadge() {
        tickCount += 1
        let frontmost = isTerminalFrontmost()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let badge = self.readBadge()
            DispatchQueue.main.async { [weak self] in
                self?.processBadge(badge, frontmost: frontmost)
            }
        }
    }

    private func processBadge(_ badge: String?, frontmost: Bool) {
        if tickCount % 5 == 1 {
            dbg("tick #\(tickCount) frontmost=\(frontmost) badge=\(badge ?? "nil") lastBadge=\(lastBadgeLabel ?? "nil")")
        }

        if frontmost {
            // User is looking at Terminal — 已经在看消息了。
            // badge 若从非空清空，正是「用户回 Terminal 看完消息」的信号。
            if let prev = lastBadgeLabel, !prev.isEmpty, prev != "0",
               (badge == nil || badge?.isEmpty == true || badge == "0") {
                dbg("BADGE CLEARED (frontmost): \(prev) → \(badge ?? "nil")")
                lastBadgeLabel = badge
                delegate?.terminalContentDidClear(self)
                return
            }
            lastBadgeLabel = badge
            return
        }

        // Badge appeared (was nil, now has value) or changed (count increased)
        if let badge = badge, !badge.isEmpty, badge != "0", badge != lastBadgeLabel {
            dbg("BADGE APPEARED: \(lastBadgeLabel ?? "nil") → \(badge)")
            delegate?.terminalContentDidChange(self)
        }
        // Badge cleared (was non-nil, now nil/empty/"0")。
        // frontmost=true 的分支在上方会先更新 lastBadgeLabel，所以这里看到的是真正的
        // 「用户离开前台且 badge 被清空」——也就是用户已经回到了 Terminal 看过消息。
        if badge == nil || badge?.isEmpty == true || badge == "0" {
            if let prev = lastBadgeLabel, !prev.isEmpty, prev != "0" {
                dbg("BADGE CLEARED: \(prev) → \(badge ?? "nil")")
                delegate?.terminalContentDidClear(self)
            }
        }
        lastBadgeLabel = badge
    }

    private func isTerminalFrontmost() -> Bool {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return false }
        return frontApp.bundleIdentifier == "com.apple.Terminal"
    }

    private func readBadge() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/lsappinfo")
        process.arguments = ["info", "-only", "StatusLabel", "com.apple.Terminal"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.launch()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }

        // Parse ' "label"="N" ' from the output
        guard let range = output.range(of: #""label"\s*=\s*"([^"]*)""#, options: .regularExpression) else {
            // No badge: "StatusLabel"=(null) or missing
            return nil
        }
        // Extract just the numeric value
        let match = String(output[range])
        guard let valRange = match.range(of: #""[^"]*"$"#, options: .regularExpression) else { return nil }
        return String(match[valRange]).replacingOccurrences(of: "\"", with: "")
    }

    deinit {
        stopMonitoring()
    }
}
