import AppKit
import SwiftUI

/// Standard text and buttons remain accessible inside a single material surface.
final class SpeechBubbleView: NSView {
    var text: String = "" {
        didSet {
            messageLabel.stringValue = text
            messageLabel.toolTip = text
            messageLabel.setAccessibilityValue(text)
            messageLabel.invalidateIntrinsicContentSize()
            needsLayout = true
        }
    }
    var heading: String = "Terminal Notifier" { didSet { headingLabel.stringValue = heading } }
    var onSnoozeTapped: (() -> Void)?
    var onCloseTapped: (() -> Void)?
    var onOpenTapped: (() -> Void)?
    var snoozeTitle: String = "" { didSet { snoozeButton.title = snoozeTitle } }
    let snoozeButton = FirstClickButton(title: "", target: nil, action: nil)
    let closeButton = FirstClickButton(title: "", target: nil, action: nil)
    let openButton = FirstClickButton(title: "", target: nil, action: nil)
    private let headingLabel = NSTextField(labelWithString: "Terminal Notifier")
    let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let content = NSView()
    private var surface: NSView?
    private var displayObserver: NSObjectProtocol?
    private var messageHeight: NSLayoutConstraint?

    final class FirstClickButton: NSButton {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override var needsPanelToBecomeKey: Bool { true }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        let zh = PreferencesManager.shared.resolvedLocale == "zh"
        headingLabel.font = .systemFont(ofSize: 12, weight: .medium)
        headingLabel.textColor = .secondaryLabelColor
        headingLabel.lineBreakMode = .byTruncatingTail
        messageLabel.font = Self.messageFont
        messageLabel.preferredMaxLayoutWidth = 280
        messageLabel.textColor = .labelColor
        messageLabel.maximumNumberOfLines = 6
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.cell?.wraps = true
        messageLabel.cell?.isScrollable = false
        messageLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        messageLabel.setAccessibilityRole(.staticText)

        snoozeButton.title = zh ? "稍后" : "Later"
        openButton.title = zh ? "打开来源" : "Open source"
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: zh ? "关闭提醒" : "Close reminder")
        closeButton.setAccessibilityLabel(zh ? "关闭提醒" : "Close reminder")
        closeButton.toolTip = zh ? "关闭提醒，不切换应用" : "Close without switching apps"
        closeButton.isBordered = false
        closeButton.keyEquivalent = "\u{1b}"
        for button in [snoozeButton, openButton] {
            button.bezelStyle = .rounded
            button.controlSize = .regular
            button.font = .systemFont(ofSize: 13)
        }
        for view in [headingLabel, messageLabel, closeButton, snoozeButton, openButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        snoozeButton.target = self
        snoozeButton.action = #selector(snoozeClicked)
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        openButton.target = self
        openButton.action = #selector(openClicked)
        let height = messageLabel.heightAnchor.constraint(equalToConstant: 18)
        height.isActive = true
        messageHeight = height
        NSLayoutConstraint.activate([
            headingLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            headingLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            headingLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -8),
            closeButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            closeButton.centerYAnchor.constraint(equalTo: headingLabel.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 28),
            closeButton.heightAnchor.constraint(equalToConstant: 28),
            messageLabel.topAnchor.constraint(equalTo: headingLabel.bottomAnchor, constant: 8),
            messageLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            messageLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            messageLabel.bottomAnchor.constraint(lessThanOrEqualTo: openButton.topAnchor, constant: -8),
            openButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            openButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10),
            openButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 32),
            snoozeButton.trailingAnchor.constraint(equalTo: openButton.leadingAnchor, constant: -10),
            snoozeButton.centerYAnchor.constraint(equalTo: openButton.centerYAnchor),
            snoozeButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 32),
            snoozeButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 64),
            snoozeButton.leadingAnchor.constraint(greaterThanOrEqualTo: content.leadingAnchor, constant: 16)
        ])
        updateSurface()
        displayObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.updateSurface() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit {
        if let displayObserver { NSWorkspace.shared.notificationCenter.removeObserver(displayObserver) }
    }

    private func updateSurface() {
        content.removeFromSuperview()
        surface?.removeFromSuperview()
        let background: NSView
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            background = NSView()
            background.wantsLayer = true
            background.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            background.layer?.cornerRadius = 20
            background.addSubview(content)
        } else if #available(macOS 26.0, *) {
            // Appearance stays active without making the panel key or activating the app.
            let glass = NSHostingView(rootView: ReminderGlassSurface())
            glass.sizingOptions = []
            let backdrop = NSVisualEffectView()
            backdrop.material = .underWindowBackground
            backdrop.blendingMode = .behindWindow
            backdrop.state = .active
            backdrop.wantsLayer = true
            backdrop.layer?.cornerRadius = 20
            backdrop.layer?.masksToBounds = true
            backdrop.addSubview(glass)
            glass.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                glass.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor),
                glass.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor),
                glass.topAnchor.constraint(equalTo: backdrop.topAnchor),
                glass.bottomAnchor.constraint(equalTo: backdrop.bottomAnchor)
            ])
            backdrop.addSubview(content)
            background = backdrop
        } else {
            let material = NSVisualEffectView()
            material.material = .popover
            material.blendingMode = .behindWindow
            material.state = .active
            material.wantsLayer = true
            material.layer?.cornerRadius = 20
            material.layer?.masksToBounds = true
            material.addSubview(content)
            background = material
        }
        addSubview(background)
        background.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            background.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            background.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            background.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            content.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            content.topAnchor.constraint(equalTo: background.topAnchor),
            content.bottomAnchor.constraint(equalTo: background.bottomAnchor)
        ])
        surface = background
        background.wantsLayer = true
        background.layer?.borderWidth = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 1 : 0
        background.layer?.borderColor = NSColor.labelColor.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateSurface()
    }

    override func layout() {
        // Resolve the line height before AppKit lays out the first, non-key frame.
        // NSTextField's intrinsic height may otherwise remain at one line until focus changes.
        messageLabel.preferredMaxLayoutWidth = max(1, bounds.width - 48)
        messageHeight?.constant = Self.textHeight(for: text, width: bounds.width)
        super.layout()
    }

    static let messageFont = NSFont.systemFont(ofSize: 14, weight: .regular)
    static func textHeight(for text: String, width: CGFloat) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let measured = NSAttributedString(string: text, attributes: [
            .font: messageFont, .paragraphStyle: paragraph
        ]).boundingRect(with: NSSize(width: max(1, width - 48), height: 10000),
                        options: [.usesLineFragmentOrigin, .usesFontLeading])
        let lineHeight = ceil(messageFont.ascender - messageFont.descender + messageFont.leading)
        return max(lineHeight, min(ceil(measured.height) + 2, lineHeight * 6))
    }

    static func preferredSize(for text: String, width: CGFloat) -> NSSize {
        NSSize(width: width, height: max(122, textHeight(for: text, width: width) + 100))
    }

    @objc private func snoozeClicked() { onSnoozeTapped?() }
    @objc private func closeClicked() { onCloseTapped?() }
    @objc private func openClicked() { onOpenTapped?() }
}

@available(macOS 26.0, *)
private struct ReminderGlassSurface: View {
    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .glassEffect(.regular, in: .rect(cornerRadius: 20))
            .environment(\.appearsActive, true)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
