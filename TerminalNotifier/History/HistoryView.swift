import SwiftUI

/// 历史列表的共享刷新信号：AppDelegate 新增记录后 bump，已打开的 HistoryView 通过
/// @ObservedObject 响应并重新加载。注入方式避免「rootView 值副本」不生效的问题。
final class HistoryRefreshModel: ObservableObject {
    @Published var reloadToken: Int = 0
}

struct HistoryView: View {
    let historyManager: NotificationHistoryManager
    /// 点击记录时回调（跳转对应窗口），由 HistoryWindowController 注入。
    var onRecordTapped: ((NotificationRecord) -> Void)?
    /// 共享刷新信号；token 变化即触发 reload。
    @ObservedObject var refreshModel: HistoryRefreshModel

    @AppStorage("language") private var language: String = "system"
    @State private var records: [NotificationRecord] = []
    @State private var selection: UUID?
    @State private var searchText = ""
    @State private var confirmClear = false
    @FocusState private var searchFocused: Bool

    private var filteredRecords: [NotificationRecord] {
        records.filter { searchText.isEmpty || $0.message.localizedCaseInsensitiveContains(searchText)
            || ($0.windowTitle ?? "").localizedCaseInsensitiveContains(searchText)
            || $0.badgeLabel.localizedCaseInsensitiveContains(searchText) }.sorted { $0.timestamp > $1.timestamp }
    }
    private var days: [Date] {
        Array(Set(filteredRecords.map { Calendar.current.startOfDay(for: $0.timestamp) })).sorted(by: >)
    }
    private var selectedRecord: NotificationRecord? {
        filteredRecords.first { $0.id == selection }
    }

    private var locale: String { PreferencesManager.resolveLocale(language) }

    init(historyManager: NotificationHistoryManager,
         onRecordTapped: ((NotificationRecord) -> Void)? = nil,
         refreshModel: HistoryRefreshModel) {
        self.historyManager = historyManager
        self.onRecordTapped = onRecordTapped
        self.refreshModel = refreshModel
    }

    var body: some View {
        Group {
            if records.isEmpty {
                emptyState
            } else if filteredRecords.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass").font(.largeTitle).foregroundStyle(.secondary)
                    Text(historyLang("No matching reminders", zh: "没有匹配的提醒", locale: locale)).font(.headline)
                    Text(historyLang("Try a different search.", zh: "试试其他关键词。", locale: locale)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selection) {
                    ForEach(days, id: \.self) { day in
                        Section(dayTitle(day)) {
                            ForEach(filteredRecords.filter { Calendar.current.isDate($0.timestamp, inSameDayAs: day) }) { record in
                                HistoryRecordRow(record: record, locale: locale)
                                    .tag(record.id)
                                    .listRowSeparator(.hidden)
                                    .contextMenu {
                                        Button(historyLang("Open source", zh: "打开来源", locale: locale)) {
                                            onRecordTapped?(record)
                                        }.disabled(onRecordTapped == nil)
                                        Button(historyLang("Copy message", zh: "复制消息", locale: locale)) {
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(record.message, forType: .string)
                                        }
                                    }
                            }
                        }
                        .listSectionSeparator(.hidden)
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(minWidth: 500, minHeight: 360)
        .background(Color.clear)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(historyLang("Notification History", zh: "提醒历史", locale: locale))
        .clipped()
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    Button { searchFocused = true } label: {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("f", modifiers: .command)
                    .accessibilityLabel(historyLang("Search reminders", zh: "搜索提醒", locale: locale))
                    TextField(historyLang("Search reminders", zh: "搜索提醒", locale: locale), text: $searchText)
                        .textFieldStyle(.plain)
                        .focused($searchFocused)
                    if !searchText.isEmpty {
                        Button { searchText = ""; searchFocused = true } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(historyLang("Clear search", zh: "清除搜索", locale: locale))
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 36)
                .tnGlassSurface(cornerRadius: 18)
                .frame(maxWidth: 320)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            .background(Color.clear)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    if let record = selectedRecord { onRecordTapped?(record) }
                } label: {
                    Label(historyLang("Open source", zh: "打开来源", locale: locale), systemImage: "arrow.up.forward.app")
                        .font(.system(size: 15)).frame(minWidth: 32, minHeight: 32)
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(selectedRecord == nil || onRecordTapped == nil)
                Button(role: .destructive) { confirmClear = true } label: {
                    Label(historyLang("Clear history", zh: "清空历史", locale: locale), systemImage: "trash")
                        .font(.system(size: 15)).frame(minWidth: 32, minHeight: 32)
                }
                .disabled(records.isEmpty)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Text(historyLang("\(records.count) recent records", zh: "最近 \(records.count) 条记录", locale: locale))
                Spacer()
                if let summary = todaySummary { Text(summary) }
            }
            .font(.caption).foregroundStyle(.secondary)
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(Color.clear)
        }
        .confirmationDialog(historyLang("Clear all notification history?", zh: "清空所有提醒历史？", locale: locale),
                            isPresented: $confirmClear, titleVisibility: .visible) {
            Button(historyLang("Clear history", zh: "清空历史", locale: locale), role: .destructive) {
                historyManager.clearHistory()
                reload()
            }
            Button(historyLang("Cancel", zh: "取消", locale: locale), role: .cancel) {}
        } message: {
            Text(historyLang("This cannot be undone.", zh: "此操作无法撤销。", locale: locale))
        }
        .onAppear(perform: reload)
        .onChange(of: refreshModel.reloadToken) { _ in reload() }
    }

    private func dayTitle(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return historyLang("Today", zh: "今天", locale: locale) }
        if Calendar.current.isDateInYesterday(date) { return historyLang("Yesterday", zh: "昨天", locale: locale) }
        return date.formatted(.dateTime.year().month().day().locale(Locale(identifier: locale)))
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
        .background(Color.clear)
    }

    private func reload() {
        records = historyManager.getRecords()
        if !records.contains(where: { $0.id == selection }) { selection = nil }
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
                if let title = record.windowTitle, !title.isEmpty {
                    Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
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
