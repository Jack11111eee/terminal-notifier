import AppKit

class OverlayContentView: NSView {
    var onTap: (() -> Void)?
    let petView: PetSpriteView
    let bubbleView: SpeechBubbleView

    init(frame: NSRect, petSize: CGFloat, message: String) {
        self.petView = PetSpriteView(frame: .zero)
        self.bubbleView = SpeechBubbleView(frame: .zero)

        super.init(frame: frame)

        petView.wantsLayer = true
        bubbleView.wantsLayer = true

        addSubview(petView)
        addSubview(bubbleView)
        bubbleView.text = message

        layoutViews(petSize: petSize)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        layoutViews(petSize: petView.frame.width)
    }

    private func layoutViews(petSize: CGFloat) {
        let centerX = bounds.midX
        let petY = bounds.maxY * 0.35

        petView.frame = NSRect(
            x: centerX - petSize / 2,
            y: petY,
            width: petSize,
            height: petSize
        )

        let bubbleWidth: CGFloat = 320
        let bubbleHeight: CGFloat = 80
        bubbleView.frame = NSRect(
            x: centerX - bubbleWidth / 2,
            y: petView.frame.maxY + 12,
            width: bubbleWidth,
            height: bubbleHeight
        )
    }

    func updateMessage(_ message: String) {
        bubbleView.text = message
        bubbleView.needsDisplay = true
    }

    @objc private func viewClicked() {
        onTap?()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if petView.frame.contains(point) || bubbleView.frame.contains(point) {
            return self
        }
        return nil
    }
}
