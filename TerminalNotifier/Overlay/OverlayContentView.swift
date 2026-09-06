import AppKit

final class OverlayContentView: NSView {
    var onTap: (() -> Void)?
    var onSnooze: (() -> Void)? { didSet { bubbleView.onSnoozeTapped = onSnooze } }
    var onClose: (() -> Void)? { didSet { bubbleView.onCloseTapped = onClose } }
    var onOpen: (() -> Void)? { didSet { bubbleView.onOpenTapped = onOpen } }
    let petView: PetSpriteView
    let bubbleView: SpeechBubbleView
    private let petSize: CGFloat

    static func preferredSize(message: String, petSize: CGFloat, width: CGFloat = 328) -> NSSize {
        let bubble = SpeechBubbleView.preferredSize(for: message, width: width - 24)
        return NSSize(width: width, height: petSize + bubble.height + 80)
    }

    init(frame: NSRect, petSize: CGFloat, message: String) {
        self.petSize = petSize
        petView = PetSpriteView(frame: .zero)
        bubbleView = SpeechBubbleView(frame: .zero)
        super.init(frame: frame)
        addSubview(petView)
        addSubview(bubbleView)
        bubbleView.text = message
        let zh = PreferencesManager.shared.resolvedLocale == "zh"
        petView.setAccessibilityElement(true)
        petView.setAccessibilityRole(.button)
        petView.setAccessibilityLabel(zh ? "橘猫" : "Orange Cat")
        petView.setAccessibilityHelp(PreferencesManager.shared.switchToTerminal
            ? (zh ? "打开来源应用" : "Open the source app")
            : (zh ? "关闭提醒" : "Close reminder"))
        petView.onPress = { [weak self] in self?.onTap?() }
        layoutViews()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() { super.layout(); layoutViews() }

    private func layoutViews() {
        let bubbleSize = SpeechBubbleView.preferredSize(for: bubbleView.text, width: bounds.width - 24)
        bubbleView.frame = NSRect(x: 12, y: 12, width: bubbleSize.width, height: bubbleSize.height)
        petView.frame = NSRect(x: (bounds.width - petSize) / 2,
                               y: bubbleView.frame.maxY + 8, width: petSize, height: petSize)
    }

    func updateMessage(_ message: String) {
        bubbleView.text = message
        layoutViews()
    }
}
