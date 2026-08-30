import AppKit

class OverlayContentView: NSView {
    var onTap: (() -> Void)?
    var onSnooze: (() -> Void)? {
        didSet { bubbleView.onSnoozeTapped = onSnooze }
    }
    let petView: PetSpriteView
    let bubbleView: SpeechBubbleView

    static func petCenter(in size: NSSize, petSize: CGFloat) -> CGPoint {
        // 与 layoutViews 的不变量一致：估算最坏情况气泡高度，决定猫的最终中心位置。
        // 模拟气泡最坏高度（长文案 + snooze 按钮区），确保气泡永远不被屏幕底部裁切。
        let bubbleGap: CGFloat = 12
        let bottomMargin: CGFloat = 24
        let topMargin: CGFloat = 24
        // 估算：单行短文案的气泡高度约 64，多行约 120。取偏高的 120 保证不溢出。
        let estimatedBubbleHeight: CGFloat = 120
        let desiredCenterY = size.height / 2
        let neededBottom = estimatedBubbleHeight + bubbleGap + bottomMargin
        let minPetCenterY = neededBottom + petSize / 2
        var centerY = max(desiredCenterY, minPetCenterY)
        let maxPetCenterY = size.height - topMargin - petSize / 2
        centerY = min(centerY, maxPetCenterY)
        // 屏幕过矮时（maxPetCenterY < minPetCenterY)，优先贴住顶部，气泡会跟着降。
        return CGPoint(x: size.width / 2, y: centerY)
    }

    init(frame: NSRect, petSize: CGFloat, message: String) {
        self.petView = PetSpriteView(frame: .zero)
        self.bubbleView = SpeechBubbleView(frame: .zero)

        super.init(frame: frame)

        petView.wantsLayer = true
        bubbleView.wantsLayer = true

        addSubview(petView)
        addSubview(bubbleView)
        bubbleView.text = message
        bubbleView.snoozeTitle = PreferencesManager.shared.resolvedLocale == "zh" ? "稍后" : "Later"

        layoutViews(petSize: petSize)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        layoutViews(petSize: petView.frame.width)
    }

    private func layoutViews(petSize: CGFloat) {
        let bubbleWidth = min(bounds.width - 64, 300)
        let bubbleSize = SpeechBubbleView.preferredSize(for: bubbleView.text, width: bubbleWidth)
        let bubbleGap: CGFloat = 12
        let bottomMargin: CGFloat = 24
        // 单一来源：静态 petCenter 已按最坏情况估算过 bubble 高度，猫落点已预留空隙。
        // 这里以真实 bubble 高度做最后校正：真实 bubble 比估算矮 → 猫不需要再让位；
        // 真实 bubble 比估算高 → 猫再上移差值，保证气泡底不低于 bottomMargin。
        let basePetCenter = Self.petCenter(in: bounds.size, petSize: petSize)
        let estimatedBubbleHeight: CGFloat = 120  // 与 petCenter 中的估算保持一致
        let extra = max(0, bubbleSize.height - estimatedBubbleHeight)
        let petCenterY = basePetCenter.y + extra
        let petY = petCenterY - petSize / 2
        let bubbleY = max(bottomMargin, petY - bubbleGap - bubbleSize.height)

        petView.frame = NSRect(
            x: basePetCenter.x - petSize / 2,
            y: petY,
            width: petSize,
            height: petSize
        )
        bubbleView.frame = NSRect(
            x: basePetCenter.x - bubbleWidth / 2,
            y: bubbleY,
            width: bubbleWidth,
            height: bubbleSize.height
        )
    }

    func updateMessage(_ message: String) {
        bubbleView.text = message
        layoutViews(petSize: petView.frame.width)
        bubbleView.needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        // 点击落在「稍后」按钮上时，由 NSButton 自己的 target-action 处理，不触发 dismiss。
        let bubblePoint = bubbleView.convert(localPoint, from: self)
        if bubbleView.snoozeButton.frame.contains(bubblePoint) {
            return
        }
        if petView.frame.contains(localPoint) || bubbleView.frame.contains(localPoint) {
            onTap?()
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // 让「稍后」按钮优先命中，否则 NSButton 收不到事件。
        let bubblePoint = bubbleView.convert(point, from: self)
        if bubbleView.snoozeButton.frame.contains(bubblePoint) {
            return bubbleView.snoozeButton
        }
        if petView.frame.contains(point) || bubbleView.frame.contains(point) {
            return self
        }
        return nil
    }
}
