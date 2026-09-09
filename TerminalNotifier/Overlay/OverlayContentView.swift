import AppKit

final class OverlayContentView: NSView {
    var onTap: (() -> Void)?
    var onSnooze: (() -> Void)? { didSet { bubbleView.onSnoozeTapped = onSnooze } }
    var onClose: (() -> Void)? { didSet { bubbleView.onCloseTapped = onClose } }
    var onOpen: (() -> Void)? { didSet { bubbleView.onOpenTapped = onOpen } }
    /// 「屏蔽此会话」回调；nil 时隐藏屏蔽按钮（非 Claude 来源 / 无 tty）。
    var onBlock: (() -> Void)? {
        didSet {
            bubbleView.onBlockTapped = onBlock
            bubbleView.blockButton.isHidden = onBlock == nil
        }
    }
    let petView: PetSpriteView
    let bubbleView: SpeechBubbleView
    private let petSize: CGFloat

    static func preferredSize(message: String, petSize: CGFloat, width: CGFloat = 328) -> NSSize {
        let bubble = SpeechBubbleView.preferredSize(for: message, width: width - 24)
        return NSSize(width: width, height: petSize + bubble.height + 80)
    }

    init(frame: NSRect, petSize: CGFloat, message: String, mini: Bool = false) {
        self.petSize = petSize
        self.mini = mini
        petView = PetSpriteView(frame: .zero)
        bubbleView = SpeechBubbleView(frame: .zero)
        super.init(frame: frame)
        addSubview(petView)
        if !mini { addSubview(bubbleView) }
        bubbleView.text = message
        let zh = PreferencesManager.shared.resolvedLocale == "zh"
        petView.setAccessibilityElement(true)
        petView.setAccessibilityRole(.button)
        petView.setAccessibilityLabel(zh ? "橘猫" : "Orange Cat")
        petView.setAccessibilityHelp(PreferencesManager.shared.switchToTerminal
            ? (zh ? "打开来源应用" : "Open the source app")
            : (zh ? "关闭提醒" : "Close reminder"))
        if mini {
            petView.setAccessibilityHelp(zh ? "展开提醒" : "Expand reminder")
        }
        petView.onPress = { [weak self] in self?.onTap?() }
        layoutViews()
    }

    private let mini: Bool

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() { super.layout(); layoutViews() }

    private func layoutViews() {
        if mini {
            // 迷你形态：只有猫本体，占满整个视图（窗口即迷你尺寸）。
            bubbleView.removeFromSuperview()
            petView.frame = NSRect(x: (bounds.width - petSize) / 2,
                                   y: (bounds.height - petSize) / 2,
                                   width: petSize, height: petSize)
            return
        }
        let bubbleSize = SpeechBubbleView.preferredSize(for: bubbleView.text, width: bounds.width - 24)
        bubbleView.frame = NSRect(x: 12, y: 12, width: bubbleSize.width, height: bubbleSize.height)
        petView.frame = NSRect(x: (bounds.width - petSize) / 2,
                               y: bubbleView.frame.maxY + 8, width: petSize, height: petSize)
    }

    func updateMessage(_ message: String) {
        guard !mini else { return }
        bubbleView.text = message
        layoutViews()
    }
}
