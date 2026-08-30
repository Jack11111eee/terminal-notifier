import SwiftUI

struct HistoryView: View {
    let historyManager: NotificationHistoryManager
    /// 点击记录时回调（跳转对应窗口），由 HistoryWindowController 注入。
    var onRecordTapped: ((NotificationRecord) -> Void)?

    @AppStorage("language") private var language: String = "system"
    @State private var records: [NotificationRecord] = []

    private var locale: String { PreferencesManager.resolveLocale(language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            if records.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(records) { record in
                            HistoryRecordRow(record: record, locale: locale)
                                .contentShape(Rectangle())
                                .onTapGesture { onRecordTapped?(record) }
                        }
                    }
                    .padding(18)
                }
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .frame(width: 620, height: 460)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear(perform: reload)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.accentColor)
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(historyLang("Notification History", zh: "提醒历史", locale: locale))
                    .font(.system(size: 22, weight: .semibold))
                Text(historyLang("\(records.count) recent records", zh: "最近 \(records.count) 条记录", locale: locale))
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let summary = todaySummary {
                    Text(summary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Button(role: .destructive) {
                historyManager.clearHistory()
                reload()
            } label: {
                Label(historyLang("Clear", zh: "清空", locale: locale), systemImage: "trash")
            }
            .disabled(records.isEmpty)
            .tnGlassButtonIfAvailable()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "bell.slash")
                .font(.system(size: 38, weight: .regular))
                .foregroundColor(.secondary)
            Text(historyLang("No notifications yet", zh: "暂无提醒记录", locale: locale))
                .font(.system(size: 16, weight: .semibold))
            Text(historyLang("Terminal, Claude Code, and Codex reminders will appear here.", zh: "终端、Claude Code 和 Codex 提醒会显示在这里。", locale: locale))
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func reload() {
        records = historyManager.getRecords()
    }

    /// 「今日 N 次 · 需确认 X · 完成 Y · 终端 Z」统计行；今日 0 条时返回 nil 不显示。
    private var todaySummary: String? {
        var confirm = 0, done = 0, terminal = 0
        for record in records where Calendar.current.isDateInToday(record.timestamp) {
            switch record.category {
            case MessageProvider.Category.needsConfirm.rawValue,
                 MessageProvider.Category.codexNeedsConfirm.rawValue:
                confirm += 1
            case MessageProvider.Category.done.rawValue,
                 MessageProvider.Category.codexDone.rawValue:
                done += 1
            default:
                terminal += 1
            }
        }
        let total = confirm + done + terminal
        guard total > 0 else { return nil }
        return historyLang(
            "Today: \(total) · \(confirm) confirm · \(done) done · \(terminal) terminal",
            zh: "今日 \(total) 次 · 需确认 \(confirm) · 完成 \(done) · 终端 \(terminal)",
            locale: locale)
    }
}

private struct HistoryRecordRow: View {
    let record: NotificationRecord
    let locale: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(categoryColor.opacity(0.16))
                Image(systemName: categoryIcon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(categoryColor)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(categoryTitle)
                        .font(.system(size: 12, weight: .semibold))
                    Text(timeText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }

                Text(record.message)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
        )
    }

    private var timeText: String {
        Self.timeFormatter.string(from: record.timestamp)
    }

    private var categoryTitle: String {
        switch record.category {
        case MessageProvider.Category.needsConfirm.rawValue:
            return historyLang("Needs confirmation", zh: "需要确认", locale: locale)
        case MessageProvider.Category.done.rawValue:
            return historyLang("Claude done", zh: "Claude 完成", locale: locale)
        case MessageProvider.Category.codexNeedsConfirm.rawValue:
            return historyLang("Codex needs confirmation", zh: "Codex 需要确认", locale: locale)
        case MessageProvider.Category.codexDone.rawValue:
            return historyLang("Codex done", zh: "Codex 完成", locale: locale)
        case MessageProvider.Category.longWait.rawValue:
            return historyLang("Long wait", zh: "等待过久", locale: locale)
        case MessageProvider.Category.merged.rawValue:
            return historyLang("Multiple reminders", zh: "多条提醒", locale: locale)
        default:
            return historyLang("Terminal notification", zh: "终端提醒", locale: locale)
        }
    }

    private var categoryIcon: String {
        switch record.category {
        case MessageProvider.Category.needsConfirm.rawValue:
            return "questionmark.circle"
        case MessageProvider.Category.done.rawValue:
            return "checkmark.circle"
        case MessageProvider.Category.codexNeedsConfirm.rawValue:
            return "questionmark.circle"
        case MessageProvider.Category.codexDone.rawValue:
            return "checkmark.circle"
        case MessageProvider.Category.longWait.rawValue:
            return "timer"
        case MessageProvider.Category.merged.rawValue:
            return "bell.badge"
        default:
            return "terminal"
        }
    }

    private var categoryColor: Color {
        switch record.category {
        case MessageProvider.Category.needsConfirm.rawValue:
            return .orange
        case MessageProvider.Category.done.rawValue:
            return .green
        case MessageProvider.Category.codexNeedsConfirm.rawValue:
            return .orange
        case MessageProvider.Category.codexDone.rawValue:
            return .green
        case MessageProvider.Category.longWait.rawValue:
            return .purple
        case MessageProvider.Category.merged.rawValue:
            return .blue
        default:
            return .accentColor
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()
}

private func historyLang(_ en: String, zh: String, locale: String) -> String {
    locale == "zh" ? zh : en
}
