import Foundation

enum SettingsVisualMode: String, CaseIterable {
    case modern
    case compatible

    static var current: SettingsVisualMode {
        resolved(arguments: CommandLine.arguments,
                 environment: ProcessInfo.processInfo.environment)
    }

    static func resolved(arguments: [String], environment: [String: String]) -> SettingsVisualMode {
        if let index = arguments.firstIndex(of: "--settings-visual-mode"),
           arguments.indices.contains(index + 1),
           let forced = SettingsVisualMode(rawValue: arguments[index + 1]) {
            return forced
        }

        if let value = environment["TERMINAL_NOTIFIER_SETTINGS_VISUAL_MODE"],
           let forced = SettingsVisualMode(rawValue: value) {
            return forced
        }

#if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            return .modern
        }
#endif
        return .compatible
    }

    var usesInsetGlassSidebar: Bool { self == .modern }
    var repositionsWindowControls: Bool { self == .modern }
}
