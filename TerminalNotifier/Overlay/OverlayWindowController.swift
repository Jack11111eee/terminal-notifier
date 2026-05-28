import AppKit

class OverlayWindow: NSWindow {
    var onEscPressed: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscPressed?()
        } else {
            super.keyDown(with: event)
        }
    }
}

class OverlayWindowController {
    private var window: OverlayWindow?
    private var contentView: OverlayContentView?
    private let dropAnimator = DropBounceAnimator()
    private let jumpBackAnimator = JumpBackAnimator()
    private var isDismissing = false

    var onDropAnimationComplete: (() -> Void)?
    var onJumpBackComplete: (() -> Void)?
    var onDismissRequested: (() -> Void)?

    func show(on screen: NSScreen,
              message: String,
              menuBarIconFrame: NSRect) {

        if window != nil { forceClose() }
        isDismissing = false

        let window = OverlayWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.isReleasedWhenClosed = false

        window.onEscPressed = { [weak self] in
            self?.onDismissRequested?()
        }

        let contentView = OverlayContentView(
            frame: NSRect(origin: .zero, size: screen.frame.size),
            petSize: Constants.defaultPetSize,
            message: message
        )
        contentView.onTap = { [weak self] in
            self?.onDismissRequested?()
        }

        window.contentView = contentView
        window.makeKeyAndOrderFront(nil)
        window.alphaValue = 1.0

        self.window = window
        self.contentView = contentView

        animateDrop(from: menuBarIconFrame, screen: screen)
    }

    private func animateDrop(from menuBarFrame: NSRect, screen: NSScreen) {
        guard let petView = contentView?.petView else { return }
        petView.wantsLayer = true

        let finalCenterX = screen.frame.midX
        let finalPetY = screen.frame.maxY * 0.35 + Constants.defaultPetSize / 2
        let startY = screen.frame.maxY - menuBarFrame.origin.y

        petView.layer?.position = CGPoint(x: finalCenterX, y: startY)

        dropAnimator.animate(
            layer: petView.layer!,
            from: startY,
            to: finalPetY,
            completion: { [weak self] in
                self?.onDropAnimationComplete?()
            }
        )
    }

    func updateMessage(_ message: String) {
        contentView?.updateMessage(message)
    }

    func beginDismiss() {
        guard !isDismissing, let screenFrame = window?.screen?.frame ?? NSScreen.main?.frame else {
            forceClose()
            return
        }
        isDismissing = true

        let menuBarY = screenFrame.maxY
        let currentPos = contentView?.petView.layer?.position
            ?? CGPoint(x: screenFrame.midX, y: screenFrame.maxY * 0.35)

        if let petView = contentView?.petView {
            petView.wantsLayer = true

            jumpBackAnimator.animate(
                layer: petView.layer!,
                from: currentPos,
                to: CGPoint(x: screenFrame.midX, y: menuBarY),
                completion: { [weak self] in
                    self?.onJumpBackComplete?()
                }
            )
        }

        if let bubble = contentView?.bubbleView {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                bubble.animator().alphaValue = 0
            }
        }
    }

    func forceClose() {
        window?.orderOut(nil)
        window = nil
        contentView = nil
        isDismissing = false
    }

    func close() {
        forceClose()
    }
}
