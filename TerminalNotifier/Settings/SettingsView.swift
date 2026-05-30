import SwiftUI

struct SettingsView: View {
    @ObservedObject var preferences: PreferencesManager
    // 观察 language 键,语言切换时让界面文字即时刷新(共用偏好,不再读系统语言)。
    @AppStorage("language") private var language: String = "system"
    private var locale: String { PreferencesManager.resolveLocale(language) }

    var body: some View {
        TabView {
            GeneralSettingsTab(preferences: preferences)
                .tabItem {
                    Label(settingsLang("General", zh: "通用", locale: locale), systemImage: "gear")
                }
            NotificationSettingsTab(preferences: preferences)
                .tabItem {
                    Label(settingsLang("Notifications", zh: "通知", locale: locale), systemImage: "bell")
                }
        }
        .frame(width: 450, height: 360)
    }
}

// MARK: - General Tab

struct GeneralSettingsTab: View {
    @ObservedObject var preferences: PreferencesManager
    @AppStorage("language") private var language: String = "system"
    private var locale: String { PreferencesManager.resolveLocale(language) }

    var body: some View {
        Form {
            Toggle(isOn: $preferences.enabled) {
                Text(settingsLang("Enable Notifications", zh: "启用提醒", locale: locale))
            }

            Toggle(isOn: $preferences.launchAtLogin) {
                Text(settingsLang("Launch at Login", zh: "开机自启动", locale: locale))
            }

            Toggle(isOn: $preferences.claudeCodeEnabled) {
                Text(settingsLang("Detect Claude Code state", zh: "检测 Claude Code 状态", locale: locale))
            }
            Text(settingsLang(
                "Pops on \"needs confirmation\" / \"done\". Writes a hook into ~/.claude/settings.json (backed up; turn off to remove).",
                zh: "在「需要确认 / 对话完成」时弹出。会在 ~/.claude/settings.json 写入 hook（已备份；关闭即移除）。",
                locale: locale))
                .font(.caption)
                .foregroundColor(.secondary)

            Picker(selection: $preferences.language) {
                Text(settingsLang("System Default", zh: "跟随系统", locale: locale)).tag("system")
                Text("中文").tag("zh")
                Text("English").tag("en")
            } label: {
                Text(settingsLang("Language", zh: "语言", locale: locale))
            }

            Picker(selection: $preferences.selectedPet) {
                Text(settingsLang("Orange Cat", zh: "橘猫", locale: locale)).tag("pixel_cat")
            } label: {
                Text(settingsLang("Pet", zh: "宠物", locale: locale))
            }
            .disabled(true) // Reserved for future

            HStack {
                Spacer()
                Text(settingsLang("More pets coming soon", zh: "更多宠物即将推出", locale: locale))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .padding()
    }
}

// MARK: - Notification Tab

struct NotificationSettingsTab: View {
    @ObservedObject var preferences: PreferencesManager
    @AppStorage("language") private var language: String = "system"
    private var locale: String { PreferencesManager.resolveLocale(language) }

    private let cooldownOptions = [5, 10, 15, 30, 60, 120]

    var body: some View {
        Form {
            Toggle(isOn: $preferences.soundEnabled) {
                Text(settingsLang("Play Sound", zh: "播放声音", locale: locale))
            }

            Picker(selection: $preferences.cooldownSeconds) {
                ForEach(cooldownOptions, id: \.self) { sec in
                    Text(settingsLang("\(sec)s", zh: "\(sec) 秒", locale: locale)).tag(sec)
                }
            } label: {
                Text(settingsLang("Cooldown", zh: "冷却时间", locale: locale))
            }

            Toggle(isOn: $preferences.dndEnabled) {
                Text(settingsLang("Do Not Disturb", zh: "免打扰时段", locale: locale))
            }

            if preferences.dndEnabled {
                HStack {
                    Text(settingsLang("From", zh: "从", locale: locale))
                    Picker("", selection: $preferences.dndStartHour) {
                        ForEach(0..<24) { hour in
                            Text(String(format: "%02d:00", hour)).tag(hour)
                        }
                    }
                    .frame(width: 80)
                    Text(settingsLang("to", zh: "至", locale: locale))
                    Picker("", selection: $preferences.dndEndHour) {
                        ForEach(0..<24) { hour in
                            Text(String(format: "%02d:00", hour)).tag(hour)
                        }
                    }
                    .frame(width: 80)
                }
            }

            Toggle(isOn: $preferences.switchToTerminal) {
                Text(settingsLang("Switch to Terminal on dismiss", zh: "关闭提醒后跳转终端", locale: locale))
            }
        }
        .padding()
    }
}

private func settingsLang(_ en: String, zh: String, locale: String) -> String {
    locale == "zh" ? zh : en
}
