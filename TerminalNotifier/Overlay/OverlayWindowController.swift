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
    /// 当前是否处于角落迷你形态（输入保护收缩/直接迷你弹出）。
    private(set) var isMini = false
    var onDropAnimationComplete: (() -> Void)?
    var onJumpBackComplete: (() -> Void)?
    var onDismissRequested: (() -> Void)?
    var onOpenSourceRequested: (() -> Void)?
    var onSnoozeRequested: (() -> Void)?
    /// 「屏蔽此会话」请求（AppDelegate 决定是否提供：仅 Claude 来源且带 tty）。
    var onBlockRequested: (() -> Void)?

    func show(on screen: NSScreen, message: String,
              source: NotificationSource = .terminal,
              category: MessageProvider.Category = .newNotification,
              mini: Bool = false) {
        forceClose()
        let token = generation
        isMini = mini
        currentSource = source
        currentCategory = category
        let size = mini
            ? Self.miniSize
            : OverlayContentView.preferredSize(message: message, petSize: Constants.defaultPetSize)
        let visible = screen.visibleFrame
        // 迷你形态驻留屏幕右下角落（避开中央视线），全尺寸居中。
        let rect = mini
            ? NSRect(x: visible.maxX - size.width - 28,
                     y: visible.minY + 28,
                     width: size.width, height: size.height)
            : NSRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2,
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
        let content = OverlayContentView(
            frame: NSRect(origin: .zero, size: size),
            petSize: mini ? Self.miniPetSize : Constants.defaultPetSize,
            message: mini ? "" : message,
            mini: mini)
        if !mini {
            content.bubbleView.heading = heading(source: source, category: category)
        }
        content.onTap = { [weak self] in
            guard let self else { return }
            if self.isMini {
                // 迷你猫点击 = 展开为完整提醒（气泡消息等上下文补全后重排）。
                self.expandFromMini()
            } else if PreferencesManager.shared.switchToTerminal {
                self.onOpenSourceRequested?()
            } else {
                self.onDismissRequested?()
            }
        }
        content.onClose = { [weak self] in self?.onDismissRequested?() }
        content.onOpen = { [weak self] in self?.onOpenSourceRequested?() }
        content.onSnooze = { [weak self] in self?.onSnoozeRequested?() }
        content.onBlock = onBlockRequested
        panel.contentView = content
        window = panel
        contentView = content
        content.layoutSubtreeIfNeeded()
        let layer = content.petView.layer!
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if mini {
            // 迷你形态：无掉落动画，轻淡入即可，不需要通知 dropAnimationCompleted。
            // AppDelegate 对 mini 弹出直接补发该事件（isMini 时不会发出）。
            layer.opacity = 0
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.opacity = 1
            CATransaction.commit()
        } else {
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
            return
        }
        panel.orderFrontRegardless()
        content.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
    }

    func updateMessage(_ message: String, source: NotificationSource = .terminal,
                       category: MessageProvider.Category = .newNotification) {
        guard let window, let contentView else { return }
        guard !isMini else {
            // 迷你形态不展示消息文本；活事件更新（计数升级/longWait）仅记录，
            // 展开时通过 pendingUpdate 上下文补发。当前实现直接忽略即可，
            // 因为 mini 展开后 stateMachine 的 shouldUpdate 会重新到达。
            return
        }
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
        isMini = false
    }
    func close() { forceClose() }

    // MARK: - 迷你形态（输入保护）

    private static let miniPetSize: CGFloat = 72
    private static let miniSize = NSSize(width: miniPetSize, height: miniPetSize)

    /// 全尺寸猫 → 迷你角落猫。输入开始时调用，不关窗口（生命周期、autoDismiss
    /// 计时都交由状态机照常运转）。已在迷你态时幂等。
    ///
    /// - Parameter force: true 时不做「是否有窗口」检查外的任何守卫（预留给 AppDelegate
    ///   显式路径）；常规输入边沿用 false。
    func shrinkToMiniIfNeeded(force: Bool) {
        guard window != nil, contentView != nil, !isDismissing, !isMini else { return }
        guard let screen = window?.screen else { return }
        let message = contentView?.bubbleView.text ?? ""
        let source = currentSource
        let category = currentCategory
        isMini = true
        // 直接重建成迷你呈现：窗口位置/内容层级变化大，动画收益低、复杂度高。
        show(on: screen, message: message, source: source, category: category, mini: true)
    }

    /// 迷你猫点击 → 原地展开为完整提醒（当前活跃事件的最新消息由 stateMachine
    /// 后续 shouldUpdate/shouldShow 补发；此处仅展示收缩时的快照消息）。
    private func expandFromMini() {
        guard let window, let contentView, isMini, !isDismissing else { return }
        guard let screen = window.screen else { return }
        let message = contentView.bubbleView.text
        let source = currentSource
        let category = currentCategory
        isMini = false
        show(on: screen, message: message, source: source, category: category, mini: false)
        // 展开相当于重新展示：正常路径会等 dropAnimationCompleted，等它回调即可。
    }

    /// 记录最近一次 show 的 source/category，迷你态收缩/展开时还原 heading 上下文。
    private var currentSource: NotificationSource = .terminal
    private var currentCategory: MessageProvider.Category = .newNotification

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
        case .done, .codexDone, .doneBatched: status = zh ? "已完成" : "Completed"
        case .longWait: status = zh ? "等待处理" : "Waiting for you"
        default: status = zh ? "提醒" : "Reminder"
        }
        return "\(name) · \(status)"
    }
}
