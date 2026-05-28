import AppKit

class PetSpriteView: NSView {
    private let defaultSize = NSSize(width: Constants.defaultPetSize, height: Constants.defaultPetSize)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        self.frame.size = defaultSize
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        if let context = NSGraphicsContext.current?.cgContext {
            context.setShouldAntialias(false)
        }
        drawPixelCatPlaceholder(in: bounds)
    }

    private func drawPixelCatPlaceholder(in rect: NSRect) {
        let size = rect.width
        let pixel = size / 16.0

        let bodyColor   = NSColor(red: 0.95, green: 0.65, blue: 0.25, alpha: 1.0)
        let darkColor   = NSColor(red: 0.75, green: 0.40, blue: 0.10, alpha: 1.0)
        let whiteColor  = NSColor.white
        let blackColor  = NSColor.black

        let colorMap: [String: NSColor] = [
            "B": bodyColor, "D": darkColor, "W": whiteColor, "K": blackColor
        ]

        // 16x16 pixel grid, uppercase letters = colors, any other = transparent
        let rows: [String] = [
            "................",
            "......BB..BB.....",
            ".....BDDBBDDB....",
            ".....BDWBBWDB....",
            "......BBBBBB.....",
            "......BKBBKB.....",
            ".....BBWBBWBB....",
            ".....BBBBBBBB....",
            ".....BB..BBBB....",
            "......BBBBBB.....",
            ".....BBBBBBBB....",
            "....BBBBBBBBBB...",
            "....BBBBBBBBBB...",
            ".....BBBBBBBBB...",
            ".....BDB..BDB....",
            "......B....B.....",
        ]

        for (rowIndex, row) in rows.enumerated() {
            for (colIndex, char) in row.enumerated() {
                let key = String(char)
                guard let color = colorMap[key] else { continue }
                color.setFill()
                let rect = NSRect(
                    x: CGFloat(colIndex) * pixel,
                    y: CGFloat(15 - rowIndex) * pixel,
                    width: pixel,
                    height: pixel
                )
                rect.fill()
            }
        }
    }
}
