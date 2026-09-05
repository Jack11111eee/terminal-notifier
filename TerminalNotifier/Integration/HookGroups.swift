import Foundation

enum HookGroups {
    static func removingCommands(
        from groups: [[String: Any]],
        matching isManaged: (String) -> Bool
    ) -> [[String: Any]] {
        groups.compactMap { group in
            guard let hooks = group["hooks"] as? [Any] else { return group }
            let kept = hooks.filter { hook in
                guard let entry = hook as? [String: Any],
                      let command = entry["command"] as? String else { return true }
                return !isManaged(command)
            }
            guard kept.count != hooks.count else { return group }
            guard !kept.isEmpty else { return nil }
            var updated = group
            updated["hooks"] = kept
            return updated
        }
    }
}
