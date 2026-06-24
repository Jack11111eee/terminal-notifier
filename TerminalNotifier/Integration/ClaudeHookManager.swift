import Foundation

/// 管理写入 ~/.claude/settings.json 的 Claude Code hook。
///
/// 开启「检测 Claude Code 状态」时 install()，关闭时 uninstall()。
/// 安全原则：
/// - 只增删带 `Constants.claudeHookMarker` 标记的 entry，绝不触碰用户其它 hook/键。
/// - 写入前做带时间戳备份。
/// - 幂等：重复 install 不会堆叠重复 entry。
///
/// 已知权衡：JSONSerialization 重写会规整 settings.json 的格式与键序
/// （用户手工排版会被规整）。这是为了用系统自带能力安全地做结构化合并；
/// 已通过备份缓解，且仅在用户显式开关时才改动。
enum ClaudeHookManager {

    private static var settingsURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".claude/settings.json")
    }

    private static func command(for event: String) -> String {
        let rel = Constants.claudeEventsRelativePath
        return """
        rel='\(rel)'; dir="$HOME/$rel"; mkdir -p "$dir"; \
        tty_name="$(ps -o tty= -p $$ 2>/dev/null | tr -d ' ')"; \
        [ -z "$tty_name" ] && tty_name="$(tty 2>/dev/null | sed 's#^/dev/##')"; \
        file="$(mktemp "$dir/\(event).XXXXXX")" || exit 0; \
        printf '{"event":"%s","source":"claude","tty":"%s","timestamp":%s}\\n' '\(event)' "$tty_name" "$(date +%s)" > "$file" \
        \(Constants.claudeHookMarker)
        """
    }

    // MARK: - 公开接口

    @discardableResult
    static func install() -> Bool {
        guard var settings = loadSettings() else { return false }
        guard var hooks = loadHooks(from: settings) else { return false }
        guard let notificationGroups = loadHookGroups(from: hooks, event: "Notification"),
              let stopGroups = loadHookGroups(from: hooks, event: "Stop") else {
            return false
        }

        hooks["Notification"] = ensureEntry(
            in: notificationGroups,
            matcher: "permission_prompt",
            command: command(for: Constants.claudeEventNeedsConfirm))
        hooks["Stop"] = ensureEntry(
            in: stopGroups,
            matcher: nil,
            command: command(for: Constants.claudeEventDone))

        settings["hooks"] = hooks
        return save(settings)
    }

    @discardableResult
    static func uninstall() -> Bool {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return true }
        guard var settings = loadSettings() else { return false }
        guard settings["hooks"] != nil else { return true }
        guard var hooks = loadHooks(from: settings) else { return false }

        for event in ["Notification", "Stop"] {
            guard let groups = loadHookGroups(from: hooks, event: event) else { return false }
            if groups.isEmpty, hooks[event] == nil { continue }
            let kept = groups.filter { !groupContainsMarker($0) }
            if kept.isEmpty { hooks.removeValue(forKey: event) }
            else { hooks[event] = kept }
        }

        if hooks.isEmpty { settings.removeValue(forKey: "hooks") }
        else { settings["hooks"] = hooks }
        return save(settings)
    }

    // MARK: - 结构操作

    /// 若 groups 中尚无带标记的 entry，追加一个；否则原样返回（幂等）。
    private static func ensureEntry(
        in groups: [[String: Any]], matcher: String?, command: String
    ) -> [[String: Any]] {
        if groups.contains(where: groupContainsMarker) {
            return groups.map { group in
                guard var hooks = group["hooks"] as? [[String: Any]],
                      hooks.contains(where: { ($0["command"] as? String)?.contains(Constants.claudeHookMarker) == true })
                else { return group }

                hooks = hooks.map { hook in
                    guard (hook["command"] as? String)?.contains(Constants.claudeHookMarker) == true else {
                        return hook
                    }
                    var updated = hook
                    updated["type"] = "command"
                    updated["command"] = command
                    return updated
                }

                var updatedGroup = group
                updatedGroup["hooks"] = hooks
                return updatedGroup
            }
        }
        var group: [String: Any] = ["hooks": [["type": "command", "command": command]]]
        if let matcher { group["matcher"] = matcher }
        return groups + [group]
    }

    private static func groupContainsMarker(_ group: [String: Any]) -> Bool {
        guard let hooks = group["hooks"] as? [[String: Any]] else { return false }
        return hooks.contains { ($0["command"] as? String)?.contains(Constants.claudeHookMarker) == true }
    }

    private static func loadHooks(from settings: [String: Any]) -> [String: Any]? {
        guard let hooks = settings["hooks"] else { return [:] }
        guard let hooks = hooks as? [String: Any] else {
            print("[TerminalNotifier] settings.json 中 hooks 不是 JSON object，已取消写入")
            return nil
        }
        return hooks
    }

    private static func loadHookGroups(from hooks: [String: Any], event: String) -> [[String: Any]]? {
        guard let groups = hooks[event] else { return [] }
        guard let groups = groups as? [[String: Any]] else {
            print("[TerminalNotifier] settings.json 中 hooks.\(event) 不是 hook group array，已取消写入")
            return nil
        }
        return groups
    }

    // MARK: - 读写

    private static func loadSettings() -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return [:] }

        do {
            let data = try Data(contentsOf: settingsURL)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("[TerminalNotifier] settings.json 顶层不是 JSON object，已取消写入: \(settingsURL.path)")
                return nil
            }
            return json
        } catch {
            print("[TerminalNotifier] 读取 settings.json 失败，已取消写入: \(error)")
            return nil
        }
    }

    private static func save(_ settings: [String: Any]) -> Bool {
        guard backupIfPresent() else { return false }
        do {
            try FileManager.default.createDirectory(
                at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONSerialization.data(
                withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: settingsURL, options: .atomic)
            return true
        } catch {
            print("[TerminalNotifier] 写入 settings.json 失败: \(error)")
            return false
        }
    }

    private static func backupIfPresent() -> Bool {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return true }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd-HHmmss"
        let backup = availableBackupURL(timestamp: fmt.string(from: Date()))
        do {
            try FileManager.default.copyItem(at: settingsURL, to: backup)
            return true
        } catch {
            print("[TerminalNotifier] 备份 settings.json 失败，已取消写入: \(error)")
            return false
        }
    }

    private static func availableBackupURL(timestamp: String) -> URL {
        let directory = settingsURL.deletingLastPathComponent()
        let baseName = "settings.json.tn-backup-\(timestamp)"
        var candidate = directory.appendingPathComponent(baseName)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName)-\(suffix)")
            suffix += 1
        }
        return candidate
    }
}
