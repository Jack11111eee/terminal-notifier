import Foundation
import SwiftUI

/// 会话级屏蔽：按 tty 键屏蔽特定终端会话的 Claude 提醒。
///
/// 场景：某个窗口里跑着高频任务（如 Monitor/自动化循环），猫被连环弹。
/// 用户在气泡上一键屏蔽该会话，彻底安静（不弹、不进历史）；解除需到设置页。
///
/// 键用 tty——事件里永远携带，不依赖归因开关/辅助功能权限。
/// ⚠️ tty 复用防护：macOS 重启后 tty 编号可能被新会话复用，屏蔽项
/// 创建满 7 天自动失效，防止长期误吞新会话的提醒。
final class BlockedSessionsManager: ObservableObject {
    struct BlockedSession: Codable, Equatable, Identifiable {
        /// 屏蔽范围：全部提醒 / 仅完成类（done 与 done 汇总）。
        enum Scope: String, Codable {
            case all
            case doneOnly
        }

        var tty: String
        /// 屏蔽时窗口标题快照，列表展示用；归因关闭时为空，回退显示 tty。
        var titleSnapshot: String
        var scope: Scope
        var createdAt: Date
        var interceptedCount: Int
        var lastInterceptedAt: Date?

        var id: String { tty }
    }

    static let shared = BlockedSessionsManager()
    /// 屏蔽项保留天数（tty 复用防护，见类注释）。
    static let expiryDays = 7

    @Published private(set) var sessions: [BlockedSession]
    private let defaults: UserDefaults
    private let storageKey: String

    init(storageKey: String = "blockedSessions", defaults: UserDefaults = .standard) {
        self.storageKey = storageKey
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([BlockedSession].self, from: data) {
            sessions = Self.prune(decoded, now: Date())
        } else {
            sessions = []
        }
        persist()
    }

    /// 事件是否命中屏蔽。tty 为 nil（hook 探测失败）不屏蔽——宁可多提醒，不可误吞。
    func blocks(tty: String?, category: MessageProvider.Category, at date: Date = Date()) -> Bool {
        guard let tty, !tty.isEmpty else { return false }
        guard let session = session(for: tty), !isExpired(session, now: date) else { return false }
        switch session.scope {
        case .all: return true
        case .doneOnly: return Self.isDoneCategory(category)
        }
    }

    /// done 类别（含防抖收束的 done 汇总）；needsConfirm 不属于。
    static func isDoneCategory(_ category: MessageProvider.Category) -> Bool {
        category == .done || category == .doneBatched
    }

    /// 屏蔽/改范围。同 tty 重复屏蔽幂等（更新范围与标题快照）。
    func block(tty: String, title: String, scope: BlockedSession.Scope) {
        let normalized = Self.normalize(tty)
        guard !normalized.isEmpty else { return }
        if let index = sessions.firstIndex(where: { $0.tty == normalized }) {
            sessions[index].scope = scope
            sessions[index].titleSnapshot = title
        } else {
            sessions.append(BlockedSession(
                tty: normalized,
                titleSnapshot: title,
                scope: scope,
                createdAt: Date(),
                interceptedCount: 0,
                lastInterceptedAt: nil))
        }
        persist()
    }

    func unblock(tty: String) {
        sessions.removeAll { $0.tty == Self.normalize(tty) }
        persist()
    }

    /// 命中屏蔽时由拦截方调用：累计活动性，供设置页展示。
    func recordIntercept(tty: String?) {
        guard let tty, let index = sessions.firstIndex(where: { $0.tty == Self.normalize(tty) }) else { return }
        sessions[index].interceptedCount += 1
        sessions[index].lastInterceptedAt = Date()
        persist()
    }

    /// 剔除过期屏蔽项（创建超过 expiryDays 天）。静态纯函数供测试。
    static func prune(_ sessions: [BlockedSession], now: Date) -> [BlockedSession] {
        let maxAge = Double(expiryDays) * 86400
        return sessions.filter { now.timeIntervalSince($0.createdAt) <= maxAge }
    }

    static func normalize(_ tty: String) -> String {
        var value = tty.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("/dev/") { value.removeFirst("/dev/".count) }
        return value
    }

    private func session(for tty: String) -> BlockedSession? {
        let normalized = Self.normalize(tty)
        return sessions.first { $0.tty == normalized }
    }

    private func isExpired(_ session: BlockedSession, now: Date) -> Bool {
        now.timeIntervalSince(session.createdAt) > Double(Self.expiryDays) * 86400
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
