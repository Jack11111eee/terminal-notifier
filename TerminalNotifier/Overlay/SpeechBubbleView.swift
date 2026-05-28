import AppKit

class SpeechBubbleView: NSView {
    var text: String = "" {
        didSet { needsDisplay = true }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        let bounds = self.bounds
        let bubbleRect = bounds.insetBy(dx: 4, dy: 12)

        // Bubble body
        let bubblePath = NSBezierPath(roundedRect: bubbleRect, xRadius: 16, yRadius: 16)

        // Tail pointing down (to the cat below)
        let tailPath = NSBezierPath()
        let tailCenterX = bounds.midX
        let tailWidth: CGFloat = 16
        let tailHeight: CGFloat = 12
        tailPath.move(to: NSPoint(x: tailCenterX - tailWidth / 2, y: bubbleRect.minY))
        tailPath.line(to: NSPoint(x: tailCenterX, y: bubbleRect.minY - tailHeight))
        tailPath.line(to: NSPoint(x: tailCenterX + tailWidth / 2, y: bubbleRect.minY))
        tailPath.close()

        // Fill
        NSColor.white.setFill()
        bubblePath.fill()
        tailPath.fill()

        // Stroke (pixel-style thick border)
        NSColor.black.setStroke()
        bubblePath.lineWidth = 3
        bubblePath.stroke()
        tailPath.lineWidth = 3
        tailPath.stroke()
        tailPath.lineWidth = 3
        let tailStroke = NSBezierPath()
        tailStroke.move(to: NSPoint(x: tailCenterX, y: bubbleRect.minY - tailHeight))
        tailStroke.line(to: NSPoint(x: tailCenterX, y: bubbleRect.minY + 3))
        tailStroke.stroke()

        // Text
        let textStyle = NSMutableParagraphStyle()
        textStyle.alignment = .center
        textStyle.lineBreakMode = .byWordWrapping

        let fontSize: CGFloat = 16
        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)

        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black,
            .paragraphStyle: textStyle
        ]

        let textRect = bubbleRect.insetBy(dx: 20, dy: 12)
        (text as NSString).draw(in: textRect, withAttributes: textAttrs)
    }
}
