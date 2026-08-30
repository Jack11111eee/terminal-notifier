import AppKit

class SpeechBubbleView: NSView {
    var text: String = "" {
        didSet { needsDisplay = true }
    }
    var onSnoozeTapped: (() -> Void)?
    var snoozeTitle: String = "" {
        didSet { snoozeButton.title = snoozeTitle }
    }

    /// 「稍后」按钮暴露给 OverlayContentView 做 hit-test 优先命中判断。
    /// 使用 CursorButton 子类，hover 时切换为手型光标（修复"点了稍后没反馈"）。
    let snoozeButton: CursorButton = {
        let button = CursorButton(title: "", target: nil, action: nil)
        button.isBordered = false
        button.bezelStyle = .inline
        button.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        button.contentTintColor = NSColor.secondaryLabelColor
        return button
    }()

    /// 简单 NSButton 子类：hover 时切换成手型光标。
    final class CursorButton: NSButton {
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            for area in trackingAreas { removeTrackingArea(area) }
            addTrackingArea(NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways],
                owner: self,
                userInfo: nil))
        }
        override func mouseEntered(with event: NSEvent) {
            super.mouseEntered(with: event)
            NSCursor.pointingHand.push()
        }
        override func mouseExited(with event: NSEvent) {
            NSCursor.pop()
            super.mouseExited(with: event)
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        snoozeButton.target = self
        snoozeButton.action = #selector(snoozeClicked)
        addSubview(snoozeButton)
    }

    @objc private func snoozeClicked() {
        onSnoozeTapped?()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    static func preferredSize(for text: String, width: CGFloat) -> NSSize {
        let contentInsets = NSEdgeInsets(top: 16, left: 24, bottom: 16, right: 24)
        let availableWidth = width - contentInsets.left - contentInsets.right
        let attributed = NSAttributedString(string: text, attributes: textAttributes)
        let measured = attributed.boundingRect(
            with: NSSize(width: availableWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        // 高度 = 文字 + 上下 padding + 底部按钮区，三者独立不累加进文字区
        let height = max(64, ceil(measured.height) + contentInsets.top + contentInsets.bottom + Self.snoozeAreaHeight)
        return NSSize(width: width, height: height)
    }

    /// 气泡底部为「稍后」按钮预留的固定高度（文字区与按钮区的分界）。
    private static let snoozeAreaHeight: CGFloat = 28

    override func layout() {
        super.layout()
        let drawingBounds = bounds.insetBy(dx: 8, dy: 6)
        let btnSize = NSSize(width: 44, height: 18)
        // 按钮放在底部预留区（snoozeAreaHeight=28）的垂直中心
        snoozeButton.frame = NSRect(
            x: drawingBounds.maxX - btnSize.width - 12,
            y: drawingBounds.minY + (Self.snoozeAreaHeight - btnSize.height) / 2,
            width: btnSize.width,
            height: btnSize.height
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        let drawingBounds = bounds.insetBy(dx: 8, dy: 6)
        let bubbleRect = drawingBounds
        let bubblePath = NSBezierPath(roundedRect: bubbleRect, xRadius: 18, yRadius: 18)
        let fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.96)
        let strokeColor = NSColor.separatorColor.withAlphaComponent(0.72)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(isDarkMode ? 0.36 : 0.16)
        shadow.shadowBlurRadius = 18
        shadow.shadowOffset = NSSize(width: 0, height: -4)
        shadow.set()

        fillColor.setFill()
        bubblePath.fill()
        NSGraphicsContext.restoreGraphicsState()

        strokeColor.setStroke()
        bubblePath.lineWidth = 1
        bubblePath.stroke()

        drawText(in: bubbleRect)
    }

    private func drawText(in bubbleRect: NSRect) {
        let hInset: CGFloat = 24
        let vInset: CGFloat = 15
        let availableWidth = bubbleRect.width - hInset * 2
        let attributed = NSAttributedString(string: text, attributes: Self.textAttributes)
        let drawOptions: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
        let measured = attributed.boundingRect(
            with: NSSize(width: availableWidth, height: .greatestFiniteMagnitude),
            options: drawOptions
        )
        // 文字占用气泡上部区域（总高 - 底部按钮区），在该子区域内垂直居中。
        // 这样短文字不会被推进按钮区，长文字也不溢出。
        let textRegion = NSRect(
            x: bubbleRect.minX,
            y: bubbleRect.minY + Self.snoozeAreaHeight,
            width: bubbleRect.width,
            height: bubbleRect.height - Self.snoozeAreaHeight
        )
        let textHeight = min(ceil(measured.height), textRegion.height - vInset * 2)
        let textRect = NSRect(
            x: bubbleRect.minX + hInset,
            y: textRegion.midY - textHeight / 2,
            width: availableWidth,
            height: textHeight
        )
        attributed.draw(with: textRect, options: drawOptions)
    }

    private var isDarkMode: Bool {
        effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private static var textAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 1.5

        return [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
    }
}
