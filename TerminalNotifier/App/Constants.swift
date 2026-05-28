import Foundation

enum Constants {
    static let appName = "Terminal Notifier"
    static let terminalAppName = "Terminal"
    static let badgePollInterval: TimeInterval = 1.0
    static let defaultPetSize: CGFloat = 300
    static let menuBarIconSize: CGFloat = 18
    static let defaultCooldown: Int = 10
    static let longWaitThreshold: TimeInterval = 120
}

enum MenuBarIconState {
    case normal
    case notifying
    case paused
}
