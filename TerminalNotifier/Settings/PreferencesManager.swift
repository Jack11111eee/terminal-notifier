import Foundation
import SwiftUI

class PreferencesManager: ObservableObject {
    static let shared = PreferencesManager()

    @AppStorage("enabled")              var enabled: Bool = true
    @AppStorage("soundEnabled")         var soundEnabled: Bool = true
    @AppStorage("cooldownSeconds")      var cooldownSeconds: Int = 10
    @AppStorage("dndEnabled")           var dndEnabled: Bool = false
    @AppStorage("dndStartHour")         var dndStartHour: Int = 22
    @AppStorage("dndEndHour")           var dndEndHour: Int = 8
    @AppStorage("launchAtLogin")        var launchAtLogin: Bool = false
    @AppStorage("language")             var language: String = "system"
    @AppStorage("switchToTerminal")     var switchToTerminal: Bool = false
    @AppStorage("selectedPet")          var selectedPet: String = "pixel_cat"
    @AppStorage("claudeCodeEnabled")    var claudeCodeEnabled: Bool = false
    @AppStorage("claudeWindowAttributionEnabled") var claudeWindowAttributionEnabled: Bool = false
    @AppStorage("codexAppEnabled")      var codexAppEnabled: Bool = false
    @AppStorage("codexPermissionRequestEnabled") var codexPermissionRequestEnabled: Bool = true
    @AppStorage("autoDismissEnabled")   var autoDismissEnabled: Bool = true
    @AppStorage("autoDismissSeconds")   var autoDismissSeconds: Int = Constants.autoDismissSecondsDefault
    @AppStorage("snoozeMinutes")        var snoozeMinutes: Int = Constants.snoozeMinutesDefault
    /// 输入保护：打字时新提醒弹迷你角落猫、挂着的全尺寸猫缩为迷你。
    @AppStorage("typingShrinkEnabled")  var typingShrinkEnabled: Bool = true

    var isInDNDPeriod: Bool {
        guard dndEnabled else { return false }
        let now = Calendar.current.component(.hour, from: Date())
        if dndStartHour < dndEndHour {
            return now >= dndStartHour && now < dndEndHour
        } else {
            // Cross-midnight: e.g. 22:00 - 08:00
            return now >= dndStartHour || now < dndEndHour
        }
    }

    var resolvedLocale: String { Self.resolveLocale(language) }

    /// 把语言偏好("system"/"zh"/"en")解析成实际语言("zh"/"en")。
    /// 设置界面与通知话语共用此处,确保两边显示语言一致。
    static func resolveLocale(_ language: String) -> String {
        switch language {
        case "zh": return "zh"
        case "en": return "en"
        default:
            let preferred = Locale.preferredLanguages.first ?? "en"
            return preferred.hasPrefix("zh") ? "zh" : "en"
        }
    }

    var resolvedCooldown: TimeInterval {
        TimeInterval(max(1, cooldownSeconds))
    }

    var resolvedAutoDismiss: TimeInterval {
        TimeInterval(max(10, autoDismissSeconds))
    }

    var resolvedSnooze: TimeInterval {
        TimeInterval(max(60, snoozeMinutes * 60))
    }
}
