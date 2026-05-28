import AppKit

class StatusBarController {
    private let statusItem: NSStatusItem
    private let menu: NSMenu
    private var isPaused: Bool = false

    var menuBarIconFrame: NSRect? {
        return statusItem.button?.window?.convertToScreen(statusItem.button?.bounds ?? .zero)
    }

    var onSettingsClicked: (() -> Void)?
    var onPauseToggled: ((Bool) -> Void)?
    var onHistoryClicked: (() -> Void)?
    var onQuitClicked: (() -> Void)?

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu = NSMenu()

        setupStatusItem()
        setupMenu()
    }

    private func setupStatusItem() {
        if let button = statusItem.button {
            button.image = Self.createPixelCatIcon(size: Constants.menuBarIconSize)
            button.image?.isTemplate = true
        }
    }

    private func setupMenu() {
        let settingsItem = NSMenuItem(
            title: NSLocalizedString("Settings...", comment: ""),
            action: #selector(settingsAction),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        let pauseItem = NSMenuItem(
            title: NSLocalizedString("Pause Notifications", comment: ""),
            action: #selector(pauseAction),
            keyEquivalent: ""
        )
        pauseItem.target = self
        menu.addItem(pauseItem)

        let historyItem = NSMenuItem(
            title: NSLocalizedString("Notification History", comment: ""),
            action: #selector(historyAction),
            keyEquivalent: ""
        )
        historyItem.target = self
        menu.addItem(historyItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: NSLocalizedString("Quit Terminal Notifier", comment: ""),
            action: #selector(quitAction),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    func updateIcon(state: MenuBarIconState) {
        DispatchQueue.main.async {
            switch state {
            case .normal:
                if let button = self.statusItem.button {
                    button.image = Self.createPixelCatIcon(size: Constants.menuBarIconSize)
                    button.image?.isTemplate = true
                }
            case .notifying:
                break
            case .paused:
                if let button = self.statusItem.button {
                    button.image = Self.createPausedIcon(size: Constants.menuBarIconSize)
                    button.image?.isTemplate = true
                }
            }
        }
    }

    func updatePauseMenuItem(isPaused: Bool) {
        self.isPaused = isPaused
        if let pauseItem = menu.item(at: 1) {
            pauseItem.title = isPaused
                ? NSLocalizedString("Resume Notifications", comment: "")
                : NSLocalizedString("Pause Notifications", comment: "")
        }
    }

    @objc private func settingsAction() {
        onSettingsClicked?()
    }

    @objc private func pauseAction() {
        isPaused.toggle()
        updatePauseMenuItem(isPaused: isPaused)
        updateIcon(state: isPaused ? .paused : .normal)
        onPauseToggled?(isPaused)
    }

    @objc private func historyAction() {
        onHistoryClicked?()
    }

    @objc private func quitAction() {
        onQuitClicked?()
    }

    // MARK: - Pixel Cat Icon (Placeholder)

    static func createPixelCatIcon(size: CGFloat) -> NSImage {
        return drawPixelCat(size: size, color: NSColor.black)
    }

    static func createPausedIcon(size: CGFloat) -> NSImage {
        return drawPixelCat(size: size, color: NSColor.gray)
    }

    private static func drawPixelCat(size: CGFloat, color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.isTemplate = true

        image.lockFocus()
        color.setFill()

        let pixel = size / 9.0

        // A simple 9x9 pixel art cat face
        // Row 0: .........
        // Row 1: ..*...*..
        // Row 2: .*...*.*.
        // Row 3: .*.**.*..
        // Row 4: .*.***...
        // Row 5: ..***....
        // Row 6: ..*.*....
        // Row 7: ..*.*....
        // Row 8: .........

        let pixels: [(Int, Int)] = [
            (2,1), (5,1),
            (1,2), (4,2), (6,2),
            (1,3), (3,3), (4,3), (6,3),
            (1,4), (3,4), (4,4), (5,4),
            (2,5), (3,5), (4,5),
            (2,6), (4,6),
            (2,7), (4,7),
        ]

        for (col, row) in pixels {
            let rect = NSRect(
                x: CGFloat(col) * pixel,
                y: CGFloat(8 - row) * pixel,
                width: pixel,
                height: pixel
            )
            rect.fill()
        }

        image.unlockFocus()
        return image
    }
}
