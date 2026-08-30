import Foundation

struct NotificationRecord: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let badgeLabel: String
    let message: String
    let category: String
    /// 可选：Claude hook 事件自带的 TTY，用于点击记录时反查目标窗口。
    /// badge 来源的记录该字段为 nil；旧版本存的记录没有此键，解码后为 nil。
    let tty: String?
    /// 可选：触发时目标 Terminal 窗口的标题，仅供历史 UI 展示「来自哪个窗口」，不参与匹配。
    /// badge 来源与旧记录为 nil。
    let windowTitle: String?

    init(
        id: UUID,
        timestamp: Date,
        badgeLabel: String,
        message: String,
        category: String,
        tty: String? = nil,
        windowTitle: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.badgeLabel = badgeLabel
        self.message = message
        self.category = category
        self.tty = tty
        self.windowTitle = windowTitle
    }
}

class NotificationHistoryManager {
    private let maxRecords = 100
    private let storageKey: String
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(storageKey: String = "notificationHistory") {
        self.storageKey = storageKey
    }

    func addRecord(_ record: NotificationRecord) {
        var records = getRecords()
        records.insert(record, at: 0)
        if records.count > maxRecords {
            records = Array(records.prefix(maxRecords))
        }
        saveRecords(records)
    }

    func getRecords() -> [NotificationRecord] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return [] }
        return (try? decoder.decode([NotificationRecord].self, from: data)) ?? []
    }

    func clearHistory() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    private func saveRecords(_ records: [NotificationRecord]) {
        guard let data = try? encoder.encode(records) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
