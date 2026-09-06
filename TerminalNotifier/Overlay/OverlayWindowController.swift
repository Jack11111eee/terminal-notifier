import AppKit

/// Appears without taking keyboard focus. A deliberate click can focus its controls.
final class OverlayWindow: NSPanel {
    var onEscPressed: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onEscPressed?() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscPressed?() }
        else { super.keyDown(with: event) }
    }
}

final class OverlayWindowController {
    private var window: OverlayWindow?
    private var contentView: OverlayContentView?
    private let dropAnimator = DropBounceAnimator()
    private let jumpBackAnimator = JumpBackAnimator()
    private var isDismissing = false
    private var generation = UUID()
    var onDropAnimationComplete: (() -> Void)?
    var onJumpBackComplete: (() -> Void)?
    var onDismissRequested: (() -> Void)?
    var onOpenSourceRequested: (() -> Void)?
    var onSnoozeRequested: (() -> Void)?

    func show(on screen: NSScreen, message: String,
              source: NotificationSource = .terminal,
              category: MessageProvider.Category = .newNotification) {
        forceClose()
        let token = generation
        let size = OverlayContentView.preferredSize(message: message, petSize: Constants.defaultPetSize)
        let visible = screen.visibleFrame
        let rect = NSRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2,
                          width: size.width, height: size.height)
        let panel = OverlayWindow(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel],
                                  backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.onEscPressed = { [weak self] in self?.onDismissRequested?() }
        let content = OverlayContentView(frame: NSRect(origin: .zero, size: size),
                                         petSize: Constants.defaultPetSize, message: message)
        content.bubbleView.heading = heading(source: source, category: category)
        content.onTap = { [weak self] in
            if PreferencesManager.shared.switchToTerminal { self?.onOpenSourceRequested?() }
            else { self?.onDismissRequested?() }
        }
        content.onClose = { [weak self] in self?.onDismissRequested?() }
        content.onOpen = { [weak self] in self?.onOpenSourceRequested?() }
        content.onSnooze = { [weak self] in self?.onSnoozeRequested?() }
        panel.contentView = content
        window = panel
        contentView = content
        content.layoutSubtreeIfNeeded()
        let layer = content.petView.layer!
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let endY = layer.position.y
        dropAnimator.prepareInitialState(layer: layer, from: endY + (reduceMotion ? 0 : 48), to: endY)
        // Do not call makeKeyAndOrderFront: incoming reminders must not interrupt typing.
        panel.orderFrontRegardless()
        content.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == token, !self.isDismissing else { return }
            self.dropAnimator.animate(layer: layer, from: endY + 48, to: endY,
                                      reduceMotion: reduceMotion) { [weak self] in
                guard let self, self.generation == token, !self.isDismissing else { return }
                self.onDropAnimationComplete?()
            }
        }
    }

    func updateMessage(_ message: String, source: NotificationSource = .terminal,
                       category: MessageProvider.Category = .newNotification) {
        guard let window, let contentView else { return }
        let size = OverlayContentView.preferredSize(message: message, petSize: Constants.defaultPetSize)
        // Keep the panel's top edge stable as text changes.
        let old = window.frame
        window.setFrame(NSRect(x: old.minX, y: old.maxY - size.height, width: size.width, height: size.height), display: true)
        contentView.frame.size = size
        contentView.updateMessage(message)
        contentView.bubbleView.heading = heading(source: source, category: category)
    }

    func beginDismiss() {
        guard !isDismissing, let contentView else { return }
        isDismissing = true
        let token = generation
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let layer = contentView.petView.layer!
        let current = layer.presentation()
        let position = CGPoint(x: layer.position.x,
                               y: layer.position.y + (current?.transform.m42 ?? layer.transform.m42))
        layer.removeAllAnimations()
        jumpBackAnimator.animate(layer: layer, from: position,
                                 to: CGPoint(x: position.x, y: position.y + 40),
                                 reduceMotion: reduceMotion) { [weak self] in
            guard let self, self.generation == token else { return }
            self.onJumpBackComplete?()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0.15 : 0.2
            contentView.bubbleView.animator().alphaValue = 0
        }
    }

    func forceClose() {
        generation = UUID()
        window?.orderOut(nil)
        contentView?.petView.layer?.removeAllAnimations()
        window = nil
        contentView = nil
        isDismissing = false
    }
    func close() { forceClose() }

    /// Only for an explicit request to interact, never for an incoming notification.
    func focusForInteraction() {
        window?.makeKeyAndOrderFront(nil)
    }

    private func heading(source: NotificationSource, category: MessageProvider.Category) -> String {
        let zh = PreferencesManager.shared.resolvedLocale == "zh"
        let name: String
        switch source {
        case .terminal: name = "Terminal"
        case .claudeCode: name = "Claude Code"
        case .codexApp: name = "Codex"
        }
        let status: String
        switch category {
        case .needsConfirm, .codexNeedsConfirm: status = zh ? "需要确认" : "Needs confirmation"
        case .done, .codexDone: status = zh ? "已完成" : "Completed"
        case .longWait: status = zh ? "等待处理" : "Waiting for you"
        default: status = zh ? "提醒" : "Reminder"
        }
        return "\(name) · \(status)"
    }
}
