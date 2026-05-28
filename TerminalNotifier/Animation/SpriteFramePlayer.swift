import Foundation

class SpriteFramePlayer {
    private var timer: Timer?
    private let fps: Double = 8.0
    private var currentFrame: Int = 0
    private var frameCount: Int = 0
    private var loop: Bool = false

    var onFrameUpdate: ((Int) -> Void)?

    func play(frameCount: Int, loop: Bool) {
        stop()
        self.frameCount = frameCount
        self.loop = loop
        self.currentFrame = 0
        onFrameUpdate?(0)

        let interval = 1.0 / fps
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.currentFrame += 1
            if self.currentFrame >= self.frameCount {
                if self.loop {
                    self.currentFrame = 0
                    self.onFrameUpdate?(self.currentFrame)
                } else {
                    self.stop()
                }
            } else {
                self.onFrameUpdate?(self.currentFrame)
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    var isPlaying: Bool { timer != nil }

    deinit {
        stop()
    }
}
