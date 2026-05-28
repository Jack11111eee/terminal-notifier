import Foundation

protocol BadgeMonitorDelegate: AnyObject {
    func badgeMonitor(_ monitor: BadgeMonitor, didDetectBadge label: String)
    func badgeMonitorDidClearBadge(_ monitor: BadgeMonitor)
}

class BadgeMonitor {
    weak var delegate: BadgeMonitorDelegate?
    private var timer: Timer?
    private var lastBadgeLabel: String?

    func startMonitoring() {
        stopMonitoring()
        checkBadge()
        timer = Timer.scheduledTimer(
            withTimeInterval: Constants.badgePollInterval,
            repeats: true
        ) { [weak self] _ in
            self?.checkBadge()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    private func checkBadge() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/lsappinfo")
        process.arguments = ["info", "-only", "StatusLabel", Constants.terminalAppName]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        if let label = extractBadgeLabel(from: output) {
            if lastBadgeLabel == nil {
                delegate?.badgeMonitor(self, didDetectBadge: label)
            }
            lastBadgeLabel = label
        } else {
            if lastBadgeLabel != nil {
                delegate?.badgeMonitorDidClearBadge(self)
            }
            lastBadgeLabel = nil
        }
    }

    private func extractBadgeLabel(from output: String) -> String? {
        guard let match = output.range(of: #""label"\s*=\s*"([^"]*)""#, options: .regularExpression) else {
            return nil
        }
        let label = output[match]
        if let valueRange = label.range(of: #""[^"]*"$"#, options: .regularExpression) {
            var value = String(label[valueRange])
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            return value.isEmpty ? nil : value
        }
        return nil
    }

    deinit {
        stopMonitoring()
    }
}
