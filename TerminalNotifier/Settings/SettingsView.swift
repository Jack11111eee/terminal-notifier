import SwiftUI

enum SettingsLayout {
    static let sidebarCornerRadius: CGFloat = 13
    static let sidebarInset: CGFloat = 8
}

struct SettingsView: View {
    @ObservedObject var preferences: PreferencesManager
    @ObservedObject var navigation: SettingsNavigation
    let visualMode: SettingsVisualMode
    var onPreview: () -> Void = {}
    var onSelfCheck: () -> Void = {}
    @AppStorage("language") private var language = "system"
    private var locale: String { PreferencesManager.resolveLocale(language) }
    private func text(_ en: String, _ zh: String) -> String { locale == "zh" ? zh : en }

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            VStack(spacing: 0) {
                Text(navigation.selection.title(locale))
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                    .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .frame(height: 48)
                Form {
                    switch navigation.selection {
                    case .general: general
                    case .integrations: integrations
                    case .notifications: notifications
                    case .appearance: appearance
                    case .about: about
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .clipped()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minWidth: 398, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 620, minHeight: 440)
        .background(Color(nsColor: .windowBackgroundColor))
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var sidebar: some View {
        if visualMode.usesInsetGlassSidebar {
            sidebarContent
                .frame(width: 206)
                .frame(maxHeight: .infinity)
                .tnGlassSurface(cornerRadius: SettingsLayout.sidebarCornerRadius)
                .padding(SettingsLayout.sidebarInset)
        } else {
            HStack(spacing: 0) {
                sidebarContent
                    .frame(width: 221)
                    .frame(maxHeight: .infinity)
                    .background(.regularMaterial)
                Divider()
            }
        }
    }

    private var sidebarContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Terminal Notifier")
                .font(.system(size: 20, weight: .semibold))
                .padding(.horizontal, 16)
                .padding(.top, 44)
            List(selection: $navigation.selection) {
                ForEach(SettingsSection.primaryCases) { section in
                    Label(section.title(locale), systemImage: section.symbol).tag(section)
                }
                Label(SettingsSection.about.title(locale), systemImage: SettingsSection.about.symbol)
                    .tag(SettingsSection.about)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            Label(text(preferences.enabled ? "Notifications enabled" : "Notifications disabled",
                       preferences.enabled ? "提醒已启用" : "提醒已关闭"),
                  systemImage: preferences.enabled ? "bell" : "bell.slash")
                .font(.caption).foregroundStyle(.secondary)
                .padding(16)
        }
    }

    private var general: some View {
        Group {
            Section(text("Notifications", "提醒")) {
                VStack(alignment: .leading, spacing: 16) {
                    settingToggle(text("Enable notifications", "启用提醒"),
                                  text("Keep reminders available while the app runs in the menu bar.", "应用在菜单栏运行时接收提醒。"),
                                  $preferences.enabled)
                }
            }
            Section(text("Startup", "启动")) {
                VStack(alignment: .leading, spacing: 16) {
                    settingToggle(text("Launch at login", "登录时启动"),
                                  text("Start automatically after you sign in to your Mac.", "登录 Mac 后自动启动。"),
                                  $preferences.launchAtLogin)
                }
            }
            Section(text("Language", "语言")) {
                VStack(alignment: .leading, spacing: 16) {
                    Picker(text("Interface language", "界面语言"), selection: $preferences.language) {
                        Text(text("System", "跟随系统")).tag("system")
                        Text("中文").tag("zh")
                        Text("English").tag("en")
                    }
                }
            }
        }
    }

    private var integrations: some View {
        Group {
            Section("Claude Code") {
                VStack(alignment: .leading, spacing: 16) {
                    settingToggle(text("Detect Claude Code state", "检测 Claude Code 状态"),
                                  text("Remind me when confirmation is needed or a turn is complete.", "需要确认或完成对话时提醒。"),
                                  $preferences.claudeCodeEnabled)
                    settingToggle(text("Locate the source window", "定位来源窗口"),
                                  text("Match reminders to a Terminal window. Requires Accessibility permission and may request Terminal automation.", "将提醒关联到 Terminal 窗口。需要辅助功能权限，也可能请求 Terminal 自动化权限。"),
                                  $preferences.claudeWindowAttributionEnabled)
                        .disabled(!preferences.claudeCodeEnabled)
                    DisclosureGroup(text("Integration details", "集成详情")) {
                        Text(text("Managed hooks are written to ~/.claude/settings.json. Background reminders do not require Accessibility permission.", "受管理的 hooks 写入 ~/.claude/settings.json。后台提醒不需要辅助功能权限。"))
                            .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
            }
            Section("Codex") {
                VStack(alignment: .leading, spacing: 16) {
                    settingToggle(text("Detect Codex state", "检测 Codex 状态"),
                                  text("Remind me about approvals and completed turns.", "需要审批或完成对话时提醒。"),
                                  $preferences.codexAppEnabled)
                    settingToggle(text("Approval request reminders", "审批请求提醒"),
                                  text("Turn off to receive only completion reminders, including during auto-review.", "关闭后仅接收完成提醒，也适用于 auto-review 期间。"),
                                  $preferences.codexPermissionRequestEnabled)
                        .disabled(!preferences.codexAppEnabled)
                    DisclosureGroup(text("Hook setup and trust", "Hook 设置与信任")) {
                        Text(text("Managed hooks are written to ~/.codex/hooks.json. Reopen Codex, then trust “Terminal Notifier: Codex approval reminder” (if enabled) and “Terminal Notifier: Codex completion reminder” in Settings > Hooks. Auto-review can still emit approval events.", "受管理的 hooks 写入 ~/.codex/hooks.json。重新打开 Codex，然后在设置 > 钩子中信任 “Terminal Notifier: Codex approval reminder”（如已开启）和 “Terminal Notifier: Codex completion reminder”。auto-review 仍可能产生审批事件。"))
                            .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
            }
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    Button(action: onSelfCheck) {
                        Label(text("Check integration health…", "检查集成状态…"), systemImage: "stethoscope")
                    }
                    .tnGlassButtonIfAvailable()
                }
            }
        }
    }

    private var notifications: some View {
        Group {
            Section(text("Sound and frequency", "声音与频率")) {
                VStack(alignment: .leading, spacing: 16) {
                    Toggle(text("Play sound", "播放声音"), isOn: $preferences.soundEnabled)
                    Picker(text("Minimum reminder interval", "最短提醒间隔"), selection: $preferences.cooldownSeconds) {
                        ForEach([5, 10, 15, 30, 60, 120], id: \.self) { value in
                            Text(text("\(value) seconds", "\(value) 秒")).tag(value)
                        }
                    }
                }
            }
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    Toggle(text("Scheduled quiet hours", "定时免打扰"), isOn: $preferences.dndEnabled)
                    if preferences.dndEnabled {
                        hourPicker(text("From", "开始时间"), $preferences.dndStartHour)
                        hourPicker(text("Until", "结束时间"), $preferences.dndEndHour)
                    }
                }
            } header: {
                Text(text("Quiet hours", "免打扰"))
            } footer: {
                Text(text("Applies to all reminders. Overnight schedules are supported.", "适用于所有提醒，支持跨午夜时段。"))
            }
            Section(text("Reminder behavior", "提醒行为")) {
                VStack(alignment: .leading, spacing: 16) {
                    settingToggle(text("Automatically collapse reminders", "自动收起提醒"),
                                  text("Keep an unanswered reminder in the menu bar after the selected duration.", "超过指定时长后，将未处理提醒收起到菜单栏。"),
                                  $preferences.autoDismissEnabled)
                    if preferences.autoDismissEnabled {
                        Picker(text("Show for", "驻留时长"), selection: $preferences.autoDismissSeconds) {
                            ForEach([30, 60, 120, 300], id: \.self) { value in
                                Text(value < 60 ? text("\(value) seconds", "\(value) 秒") : text("\(value / 60) minutes", "\(value / 60) 分钟")).tag(value)
                            }
                        }
                    }
                    Picker(text("Remind me later after", "稍后提醒间隔"), selection: $preferences.snoozeMinutes) {
                        ForEach([5, 10, 30], id: \.self) { value in
                            Text(text("\(value) minutes", "\(value) 分钟")).tag(value)
                        }
                    }
                    settingToggle(text("Click the cat to open the source", "点击猫咪打开来源"),
                                  text("When off, clicking the cat closes the reminder. Close and Later never switch apps.", "关闭此项时，点击猫咪仅关闭提醒。“关闭”和“稍后”始终不会切换应用。"),
                                  $preferences.switchToTerminal)
                }
            }
        }
    }

    private var appearance: some View {
        Group {
            Section(text("Your companion", "你的伙伴")) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(spacing: 16) {
                        if let url = Bundle.main.url(forResource: "PetCat", withExtension: "png"),
                           let cat = NSImage(contentsOf: url) {
                            Image(nsImage: cat).interpolation(.none).resizable()
                                .scaledToFit().frame(width: 96, height: 96)
                                .accessibilityHidden(true)
                        }
                        Text(text("Orange Cat", "橘猫")).font(.headline)
                        Text(text("A pixel companion, at home on your Mac.", "像素伙伴，融入你的 Mac。"))
                            .foregroundStyle(.secondary)
                        Button(action: onPreview) {
                            Label(text("Preview reminder", "预览提醒"), systemImage: "play.fill")
                        }
                        .tnGlassProminentButtonIfAvailable()
                    }
                    .padding(.vertical, 20).frame(maxWidth: .infinity)
                }
            }
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    Label(text("Follows system appearance", "跟随系统外观"), systemImage: "circle.lefthalf.filled")
                    Text(text("Materials and contrast follow your Mac’s settings. Reduced motion replaces the cat’s bounce with a gentle fade.", "材质与对比度跟随 Mac 设置。开启“减少动态效果”后，猫咪使用轻柔淡入淡出。"))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var about: some View {
        Group {
            Section {
                VStack(spacing: 10) {
                    if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
                       let icon = NSImage(contentsOf: url) {
                        Image(nsImage: icon)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 88, height: 88)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .accessibilityHidden(true)
                    }
                    Text("Terminal Notifier")
                        .font(.system(size: 24, weight: .semibold))
                    Text(versionText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(text("A pixel cat that lives in your menu bar and calls you back when your terminal needs you.",
                              "一只住在菜单栏、在终端需要你时叫你的像素猫。"))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 430)
                }
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
            }

            Section(text("Privacy", "隐私")) {
                VStack(alignment: .leading, spacing: 8) {
                    compactLabel(text("Local by design", "本地运行，尊重隐私"), symbol: "lock.shield")
                        .font(.headline)
                    Text(text("No account, analytics, or telemetry. Reminder history and integration events stay on your Mac.",
                              "不需要账户，不包含分析或遥测。通知历史和集成事件仅保存在你的 Mac 上。"))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(text("Optional Claude Code and Codex integrations install managed local hooks that can be removed by turning the integration off.",
                              "可选的 Claude Code 与 Codex 集成会安装受管理的本地 hooks；关闭对应集成即可移除。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }

            Section(text("Contributors", "贡献者")) {
                HStack(spacing: 10) {
                    contributorLink("Jack11111eee", url: "https://github.com/Jack11111eee")
                    contributorLink("GeniusLv2006", url: "https://github.com/GeniusLv2006")
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 2)
            }

            Section(text("Project", "项目")) {
                HStack(spacing: 10) {
                    projectLink(text("Project Home", "项目主页"), symbol: "chevron.left.forwardslash.chevron.right",
                                url: "https://github.com/Jack11111eee/terminal-notifier")
                    projectLink(text("Releases", "查看新版本"), symbol: "arrow.down.circle",
                                url: "https://github.com/Jack11111eee/terminal-notifier/releases")
                    projectLink(text("Report an Issue", "反馈问题"), symbol: "exclamationmark.bubble",
                                url: "https://github.com/Jack11111eee/terminal-notifier/issues")
                }
                .padding(.vertical, 4)
            }

            Section {
                VStack(alignment: .leading, spacing: 5) {
                    Link(destination: URL(string: "https://github.com/Jack11111eee/terminal-notifier/blob/main/LICENSE")!) {
                        compactLabel("MIT License", symbol: "doc.text")
                    }
                    Text("Copyright © 2026 Terminal Notifier Contributors")
                        .foregroundStyle(.secondary)
                    Text(text("The cat isn’t rushing you. It just thinks that terminal window looks lonely.",
                              "猫不会催你，它只是觉得那个终端窗口可能有点孤单。"))
                        .foregroundStyle(.tertiary)
                        .italic()
                }
                .font(.caption)
                .padding(.vertical, 4)
            }
        }
    }

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return text("Version \(version) (Build \(build))", "版本 \(version)（Build \(build)）")
    }

    private func contributorLink(_ name: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            compactLabel(name, symbol: "person.crop.circle")
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(.quaternary, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func projectLink(_ title: String, symbol: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            compactLabel(title, symbol: symbol)
        }
        .tnGlassButtonIfAvailable()
    }

    private func compactLabel(_ title: String, symbol: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
            Text(title)
        }
    }

    private func settingToggle(_ title: String, _ subtitle: String, _ binding: Binding<Bool>) -> some View {
        Toggle(isOn: binding) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }

    private func hourPicker(_ title: String, _ selection: Binding<Int>) -> some View {
        Picker(title, selection: selection) {
            ForEach(0..<24, id: \.self) { hour in
                Text(String(format: "%02d:00", hour)).tag(hour)
            }
        }
    }
}

final class SettingsNavigation: ObservableObject {
    @Published var selection: SettingsSection = .general {
        didSet { onSelectionChanged?() }
    }
    var onSelectionChanged: (() -> Void)?
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, integrations, notifications, appearance, about
    static let primaryCases: [SettingsSection] = [.general, .integrations, .notifications, .appearance]
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .integrations: return "puzzlepiece.extension"
        case .notifications: return "bell.badge"
        case .appearance: return "paintpalette"
        case .about: return "info.circle"
        }
    }
    func title(_ locale: String) -> String {
        switch self {
        case .general: return locale == "zh" ? "通用" : "General"
        case .integrations: return locale == "zh" ? "集成" : "Integrations"
        case .notifications: return locale == "zh" ? "通知" : "Notifications"
        case .appearance: return locale == "zh" ? "外观" : "Appearance"
        case .about: return locale == "zh" ? "关于" : "About"
        }
    }
}
