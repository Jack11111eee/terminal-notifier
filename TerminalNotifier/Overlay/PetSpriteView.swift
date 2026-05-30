import AppKit

class PetSpriteView: NSView {
    private let defaultSize = NSSize(width: Constants.defaultPetSize, height: Constants.defaultPetSize)

    // 像素猫素材(16×16 设计,@2x PNG)。加载一次,跨实例复用。
    private static let catImage: NSImage? = {
        guard let url = Bundle.main.url(forResource: "PetCat", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        self.frame.size = defaultSize
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current else { return }
        // 像素画:关抗锯齿 + 最近邻插值,放大保持硬边不糊
        ctx.imageInterpolation = .none
        ctx.cgContext.setShouldAntialias(false)
        PetSpriteView.catImage?.draw(in: bounds)
    }
}
