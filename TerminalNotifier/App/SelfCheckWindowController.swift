import AppKit
import SwiftUI

/// 自检与修复窗口：把权限/hook 的隐性问题变成一眼可查、一键可修的清单。
class SelfCheckWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show() {
        let view = SelfCheckView()
        let hosting = NSHostingController(rootView: view)

        if let existing = window {
            existing.contentViewController = hosting
            existing.center()
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let win = NSWindow(contentViewController: hosting)
        win.title = NSLocalizedString("Self-Check", comment: "")
        win.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.tabbingMode = .disallowed
        win.setContentSize(NSSize(width: 520, height: 400))
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = win
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

// MARK: - 检查逻辑

private enum CheckStatus {
    case ok
    case failed
    case disabled   // 未启用，灰显不算失败
}

private struct CheckItem: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    var status: CheckStatus
    var detail: String
    var repairTitle: String?
    var repair: (() -> Void)?
}

private struct SelfCheckView: View {
    @State private var items: [CheckItem] = []
    private var locale: String { PreferencesManager.shared.resolvedLocale }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "stethoscope")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text(lang("Self-Check & Repair", zh: "自检与修复"))
                        .font(.system(size: 22, weight: .semibold))
                    Text(lang("Detect and fix permission & hook issues.", zh: "检测并修复权限与 hook 的隐性问题。"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    runChecks()
                } label: {
                    Label(lang("Re-run", zh: "重新检查"), systemImage: "arrow.clockwise")
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)

            Divider()

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(items) { item in
                        CheckRow(item: item)
                    }
                }
                .padding(18)
            }
        }
        .frame(width: 520, height: 400)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear(perform: runChecks)
    }

    private func runChecks() {
        items = [
            checkAccessibility(),
            checkClaudeHook(),
            checkCodexHook(),
            checkClaudeBackup(),
        ]
    }

    /// 修复动作执行后延迟刷新：启用开关经 UserDefaults 通知异步生效，0.5s 后重跑确保状态准确。
    private func runRepair(_ repair: @escaping () -> Void) {
        repair()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            runChecks()
        }
    }

    // MARK: 各项检查

    private func checkAccessibility() -> CheckItem {
        let trusted = AXIsProcessTrusted()
        return CheckItem(
            icon: "hand.raised",
            title: lang("Accessibility permission", zh: "辅助功能权限"),
            status: trusted ? .ok : .failed,
            detail: trusted
                ? lang("Granted — window attribution works.", zh: "已授权，窗口归因可用。")
                : lang("Not granted — window jump will silently fail.", zh: "未授权，点击跳转窗口会静默失效。"),
            repairTitle: trusted ? nil : lang("Re-authorize", zh: "重新授权"),
            repair: trusted ? nil : { [self] in
                runRepair { _ = TerminalWindowRegistry.requestAccessibilityTrustIfNeeded() }
            }
        )
    }

    private func checkClaudeHook() -> CheckItem {
        // 未启用时给「立即启用」而非「重新安装」——白装了 monitor 也不会启动。
        guard PreferencesManager.shared.claudeCodeEnabled else {
            return CheckItem(
                icon: "terminal",
                title: "Claude Code hook",
                status: .disabled,
                detail: lang("Claude detection is off.", zh: "Claude Code 检测未启用。"),
                repairTitle: lang("Enable Now", zh: "立即启用"),
                repair: { [self] in
                    runRepair { PreferencesManager.shared.claudeCodeEnabled = true }
                }
            )
        }
        let path = NSHomeDirectory() + "/.claude/settings.json"
        let content = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        let installed = content.contains(Constants.claudeHookMarker)
        return CheckItem(
            icon: "terminal",
            title: "Claude Code hook",
            status: installed ? .ok : .failed,
            detail: installed
                ? lang("Installed in ~/.claude/settings.json.", zh: "已安装到 ~/.claude/settings.json。")
                : lang("Missing — Claude reminders won't fire.", zh: "缺失，Claude 提醒不会触发。"),
            repairTitle: installed ? nil : lang("Reinstall", zh: "重新安装"),
            repair: installed ? nil : { [self] in
                runRepair { _ = ClaudeHookManager.install() }
            }
        )
    }

    private func checkCodexHook() -> CheckItem {
        guard PreferencesManager.shared.codexAppEnabled else {
            return CheckItem(
                icon: "macwindow",
                title: "Codex hook",
                status: .disabled,
                detail: lang("Codex detection is off.", zh: "Codex 检测未启用。"),
                repairTitle: lang("Enable Now", zh: "立即启用"),
                repair: { [self] in
                    runRepair { PreferencesManager.shared.codexAppEnabled = true }
                }
            )
        }
        let path = NSHomeDirectory() + "/.codex/hooks.json"
        let content = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        // install() 写入的是按事件拆分的新 marker；旧版总 marker 仅用于卸载时识别。
        // 此处需与新 marker 对齐，否则已安装会被误判为缺失。
        let installed = content.contains(Constants.codexStopHookMarker)
            || content.contains(Constants.codexPermissionHookMarker)
        return CheckItem(
            icon: "macwindow",
            title: "Codex hook",
            status: installed ? .ok : .failed,
            detail: installed
                ? lang("Installed in ~/.codex/hooks.json.", zh: "已安装到 ~/.codex/hooks.json。")
                : lang("Missing — Codex reminders won't fire.", zh: "缺失，Codex 提醒不会触发。"),
            repairTitle: installed ? nil : lang("Reinstall", zh: "重新安装"),
            repair: installed ? nil : { [self] in
                runRepair { _ = CodexHookManager.install() }
            }
        )
    }

    private func checkClaudeBackup() -> CheckItem {
        let dir = NSHomeDirectory() + "/.claude"
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        let hasBackup = files.contains { $0.hasPrefix("settings.json.tn-backup-") }
        return CheckItem(
            icon: "doc.on.doc",
            title: lang("Claude config backup", zh: "Claude 配置备份"),
            status: hasBackup ? .ok : .failed,
            detail: hasBackup
                ? lang("A timestamped backup exists.", zh: "已存在带时间戳的备份。")
                : lang("No backup yet — created on next hook change.", zh: "暂无备份，将在下次修改 hook 时自动生成。"),
            repairTitle: nil,
            repair: nil
        )
    }

    private func lang(_ en: String, zh: String, locale: String? = nil) -> String {
        (locale ?? self.locale) == "zh" ? zh : en
    }
}

private struct CheckRow: View {
    let item: CheckItem

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: statusIcon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(statusColor)
                .frame(width: 24, height: 24)

            Image(systemName: item.icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                Text(item.detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            if let repairTitle = item.repairTitle, let repair = item.repair {
                Button(repairTitle) { repair() }
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
        )
    }

    private var statusIcon: String {
        switch item.status {
        case .ok: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .disabled: return "minus.circle"
        }
    }

    private var statusColor: Color {
        switch item.status {
        case .ok: return .green
        case .failed: return .red
        case .disabled: return .secondary
        }
    }
}
