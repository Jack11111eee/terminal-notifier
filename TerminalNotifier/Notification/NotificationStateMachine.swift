import Foundation

enum NotificationState: Equatable {
    case idle
    case detected(count: Int)
    case showing(count: Int)
    case animatingOut
    /// 已自动降级或用户点了「稍后」：猫已收起，但事件仍挂起，待手动复查或稍后重弹。
    case pending
}

enum NotificationEvent {
    case badgeDetected
    case badgeCleared
    case agentTrigger(AgentNotificationEvent)
    case dropAnimationCompleted
    case userDismissed
    case userSnoozed
    case jumpBackCompleted
    case cooldownExpired
    case longWaitElapsed
    case autoDismissElapsed
    case snoozeElapsed
    case clearPending
    case overlaySuppressed
}

protocol NotificationStateMachineDelegate: AnyObject {
    func stateMachine(_ sm: NotificationStateMachine, didTransitionTo state: NotificationState)
    func stateMachine(
        _ sm: NotificationStateMachine,
        shouldShowOverlayWithMessage message: String,
        category: MessageProvider.Category,
        source: NotificationSource,
        targetWindow: TerminalWindowInfo?)
    func stateMachine(
        _ sm: NotificationStateMachine,
        shouldUpdateMessage message: String,
        category: MessageProvider.Category,
        source: NotificationSource,
        targetWindow: TerminalWindowInfo?)
    func stateMachineShouldDismissOverlay(_ sm: NotificationStateMachine)
}

class NotificationStateMachine {
    weak var delegate: NotificationStateMachineDelegate?

    private(set) var currentState: NotificationState = .idle
    private var pendingCount: Int = 0
    private var badgeFirstDetectedAt: Date?
    private var isInCooldown: Bool = false
    private var cooldownTimer: Timer?
    private var longWaitTimer: Timer?
    /// 非 nil 表示当前提醒来自语义化 hook（携带具体分类）；nil 表示 badge 默认行为。
    private var activeCategory: MessageProvider.Category?
    private var activeSource: NotificationSource = .terminal
    private var activeTargetWindow: TerminalWindowInfo?
    /// 当前事件的 TTY（仅 Claude hook 来源有），供 delegate 写入历史记录。
    /// 生命周期与 activeTargetWindow 一致。
    private(set) var activeTTY: String?
    /// 当前展示/挂起中的提醒原文，供 pendingInfo 记录并在倒计时后原样重弹。
    private var activeMessage: String?
    /// Accepted hook events wait in arrival order until the current overlay is closed.
    private var pendingAgents: [AgentNotificationEvent] = []
    private var isOverlayDismissing = false
    private var autoDismissTimer: Timer?
    private var snoozeTimer: Timer?
    /// 挂起事件（自动降级或「稍后」）的完整上下文，供菜单栏重看与跳窗激活。
    private(set) var pendingInfo: PendingInfo?

    struct PendingInfo {
        let message: String
        let category: MessageProvider.Category
        let source: NotificationSource
        let targetWindow: TerminalWindowInfo?
    }
    private let messageProvider = MessageProvider()
    private var locale: String { PreferencesManager.shared.resolvedLocale }

    func handleEvent(_ event: NotificationEvent) {
        if case .cooldownExpired = event {
            cooldownTimer?.invalidate()
            cooldownTimer = nil
            isInCooldown = false
        }
        if case .agentTrigger(let agent) = event {
            pendingAgents.append(agent)
            if (currentState == .idle || currentState == .pending),
               !isInCooldown, !isOverlayDismissing {
                showNextAgent()
            }
            return
        }
        let oldState = currentState
        switch (currentState, event) {
        case (.idle, .badgeDetected):
            guard !isInCooldown else {
                pendingCount += 1
                return
            }
            activeCategory = nil
            activeSource = .terminal
            activeTargetWindow = nil
            activeTTY = nil
            pendingCount = 1
            let msg = messageProvider.randomMessage(category: .newNotification, locale: locale)
            activeMessage = msg
            currentState = .detected(count: 1)
            badgeFirstDetectedAt = Date()
            delegate?.stateMachine(self, didTransitionTo: currentState)
            delegate?.stateMachine(
                self,
                shouldShowOverlayWithMessage: msg,
                category: .newNotification,
                source: .terminal,
                targetWindow: nil)

        case (.idle, .cooldownExpired):
            guard !isOverlayDismissing else { return }
            if !pendingAgents.isEmpty {
                showNextAgent()
            } else if pendingCount > 0 {
                let count = pendingCount
                pendingCount = 0
                activeCategory = nil
                activeSource = .terminal
                activeTargetWindow = nil
                activeTTY = nil
                let message = messageForShowing(count: count, badgeAge: 0)
                activeMessage = message.text
                currentState = .detected(count: count)
                badgeFirstDetectedAt = Date()
                delegate?.stateMachine(self, didTransitionTo: currentState)
                delegate?.stateMachine(
                    self,
                    shouldShowOverlayWithMessage: message.text,
                    category: message.category,
                    source: .terminal,
                    targetWindow: nil)
            }

        case (.detected, .overlaySuppressed):
            // No window exists, so no animation completion will arrive.
            pendingInfo = currentPendingInfo()
            currentState = .pending
            delegate?.stateMachine(self, didTransitionTo: currentState)
            if !pendingAgents.isEmpty { startCooldown() }

        case (.detected, .badgeDetected):
            pendingCount += 1

        case (.detected, .dropAnimationCompleted):
            currentState = .showing(count: pendingCount)
            // Hook 提醒话语已具体（需确认/完成），不做 2 分钟「长时间未响应」升级覆盖。
            if activeCategory == nil { startLongWaitTimer() }
            startAutoDismissTimerIfNeeded()
            delegate?.stateMachine(self, didTransitionTo: currentState)

        case (.showing, .longWaitElapsed):
            if case .showing(let count) = currentState {
                let message = messageForShowing(count: count, badgeAge: badgeAge)
                activeMessage = message.text
                delegate?.stateMachine(
                    self,
                    shouldUpdateMessage: message.text,
                    category: message.category,
                    source: activeSource,
                    targetWindow: activeTargetWindow)
            }

        case (.showing, .badgeDetected):
            var newCount: Int
            if case .showing(let count) = currentState { newCount = count + 1 }
            else { newCount = 1 }
            activeCategory = nil
            activeSource = .terminal
            activeTargetWindow = nil
            activeTTY = nil
            currentState = .showing(count: newCount)
            let message = messageForShowing(count: newCount, badgeAge: badgeAge)
            activeMessage = message.text
            // M1 修复：Showing 中角标计数变化同样开启新一轮展示，重置自动降级倒计时。
            startAutoDismissTimerIfNeeded()
            delegate?.stateMachine(
                self,
                shouldUpdateMessage: message.text,
                category: message.category,
                source: .terminal,
                targetWindow: nil)

        case (.detected, .userDismissed), (.showing, .userDismissed):
            longWaitTimer?.invalidate()
            autoDismissTimer?.invalidate()
            currentState = .animatingOut
            isOverlayDismissing = true
            delegate?.stateMachine(self, didTransitionTo: currentState)
            delegate?.stateMachineShouldDismissOverlay(self)

        case (.detected, .userSnoozed), (.showing, .userSnoozed):
            longWaitTimer?.invalidate()
            autoDismissTimer?.invalidate()
            let info = currentPendingInfo()
            pendingInfo = info
            currentState = .pending
            isOverlayDismissing = true
            startSnoozeTimer()
            delegate?.stateMachine(self, didTransitionTo: currentState)
            delegate?.stateMachineShouldDismissOverlay(self)

        case (.showing, .autoDismissElapsed):
            guard PreferencesManager.shared.autoDismissEnabled else { return }
            longWaitTimer?.invalidate()
            let info = currentPendingInfo()
            pendingInfo = info
            currentState = .pending
            isOverlayDismissing = true
            delegate?.stateMachine(self, didTransitionTo: currentState)
            delegate?.stateMachineShouldDismissOverlay(self)

        case (.animatingOut, .jumpBackCompleted):
            isOverlayDismissing = false
            pendingCount = 0
            badgeFirstDetectedAt = nil
            activeCategory = nil
            activeSource = .terminal
            activeTargetWindow = nil
            activeTTY = nil
            activeMessage = nil
            // pendingInfo 属于「挂起事件」，不受 dismiss 影响；只在 clearPending / snooze 爆炸时处理。
            if pendingInfo != nil {
                currentState = .pending
                delegate?.stateMachine(self, didTransitionTo: currentState)
            } else {
                currentState = .idle
                delegate?.stateMachine(self, didTransitionTo: currentState)
            }
            startCooldown()

        case (.pending, .jumpBackCompleted), (.idle, .jumpBackCompleted):
            guard isOverlayDismissing else { return }
            isOverlayDismissing = false
            if !pendingAgents.isEmpty { startCooldown() }

        case (.pending, .snoozeElapsed):
            guard let info = pendingInfo else {
                currentState = .idle
                delegate?.stateMachine(self, didTransitionTo: currentState)
                return
            }
            pendingInfo = nil
            activeCategory = info.category
            activeSource = info.source
            activeTargetWindow = info.targetWindow
            activeTTY = nil
            activeMessage = info.message
            pendingCount = 1
            badgeFirstDetectedAt = Date()
            currentState = .detected(count: 1)
            delegate?.stateMachine(self, didTransitionTo: currentState)
            delegate?.stateMachine(
                self,
                shouldShowOverlayWithMessage: info.message,
                category: info.category,
                source: info.source,
                targetWindow: info.targetWindow)
            startCooldown()

        case (.pending, .clearPending):
            pendingInfo = nil
            pendingCount = 0
            badgeFirstDetectedAt = nil
            activeCategory = nil
            activeSource = .terminal
            activeTargetWindow = nil
            activeTTY = nil
            activeMessage = nil
            currentState = .idle
            delegate?.stateMachine(self, didTransitionTo: currentState)
            if !pendingAgents.isEmpty, !isOverlayDismissing { startCooldown() }

        case (.pending, .badgeDetected):
            pendingInfo = nil
            snoozeTimer?.invalidate()
            snoozeTimer = nil
            activeCategory = nil
            activeSource = .terminal
            activeTargetWindow = nil
            activeTTY = nil
            pendingCount = 1
            let msg = messageProvider.randomMessage(category: .newNotification, locale: locale)
            activeMessage = msg
            currentState = .detected(count: 1)
            badgeFirstDetectedAt = Date()
            delegate?.stateMachine(self, didTransitionTo: currentState)
            delegate?.stateMachine(
                self,
                shouldShowOverlayWithMessage: msg,
                category: .newNotification,
                source: .terminal,
                targetWindow: nil)

        case (.pending, .cooldownExpired):
            guard !isOverlayDismissing else { return }
            showNextAgent()

        case (.idle, .badgeCleared):
            badgeFirstDetectedAt = nil
            pendingCount = 0

        // 用户已经回到 Terminal（badge 清空），任何活跃状态都应回到 .idle。
        // 否则菜单栏红点会永远卡在 .detected / .pending 不消。
        case (.detected, .badgeCleared), (.pending, .badgeCleared):
            guard activeCategory == nil else { return }
            longWaitTimer?.invalidate()
            autoDismissTimer?.invalidate()
            snoozeTimer?.invalidate()
            snoozeTimer = nil
            pendingInfo = nil
            pendingCount = 0
            badgeFirstDetectedAt = nil
            activeCategory = nil
            activeSource = .terminal
            activeTargetWindow = nil
            activeTTY = nil
            activeMessage = nil
            currentState = .idle
            delegate?.stateMachine(self, didTransitionTo: .idle)
            if !pendingAgents.isEmpty { startCooldown() }

        default:
            break
        }
#if DEBUG
        if String(describing: oldState) != String(describing: currentState) {
            print("[SM] \(oldState) + \(event) → \(currentState)")
        } else {
            print("[SM] \(oldState) + \(event) → (no transition)")
        }
#endif
    }

    private func showNextAgent() {
        guard !pendingAgents.isEmpty else { return }
        let event = pendingAgents.removeFirst()
        pendingInfo = nil
        snoozeTimer?.invalidate()
        snoozeTimer = nil
        activeCategory = event.category
        activeSource = event.source
        activeTargetWindow = event.targetWindow
        activeTTY = event.tty
        pendingCount = 1
        let message = messageProvider.randomMessage(category: event.category, locale: locale)
        activeMessage = message
        badgeFirstDetectedAt = Date()
        currentState = .detected(count: 1)
        delegate?.stateMachine(self, didTransitionTo: currentState)
        delegate?.stateMachine(
            self,
            shouldShowOverlayWithMessage: message,
            category: event.category,
            source: event.source,
            targetWindow: event.targetWindow)
    }

    private func messageForShowing(count: Int, badgeAge: TimeInterval)
        -> (text: String, category: MessageProvider.Category) {
        if count > 1 {
            return (messageProvider.mergedMessage(count: count, locale: locale), .merged)
        }
        let category: MessageProvider.Category = badgeAge >= Constants.longWaitThreshold
            ? .longWait : .newNotification
        return (messageProvider.randomMessage(category: category, locale: locale), category)
    }

    private var badgeAge: TimeInterval {
        guard let start = badgeFirstDetectedAt else { return 0 }
        return Date().timeIntervalSince(start)
    }

    private func startLongWaitTimer() {
        longWaitTimer?.invalidate()
        let remaining = max(0, Constants.longWaitThreshold - badgeAge)
        longWaitTimer = Timer.scheduledTimer(
            withTimeInterval: remaining,
            repeats: false
        ) { [weak self] _ in
            self?.handleEvent(.longWaitElapsed)
        }
    }

    private func startAutoDismissTimerIfNeeded() {
        autoDismissTimer?.invalidate()
        autoDismissTimer = nil
        guard PreferencesManager.shared.autoDismissEnabled else { return }
        autoDismissTimer = Timer.scheduledTimer(
            withTimeInterval: PreferencesManager.shared.resolvedAutoDismiss,
            repeats: false
        ) { [weak self] _ in
            self?.handleEvent(.autoDismissElapsed)
        }
    }

    private func startSnoozeTimer() {
        snoozeTimer?.invalidate()
        snoozeTimer = nil
        snoozeTimer = Timer.scheduledTimer(
            withTimeInterval: PreferencesManager.shared.resolvedSnooze,
            repeats: false
        ) { [weak self] _ in
            self?.handleEvent(.snoozeElapsed)
        }
    }

    private func currentPendingInfo() -> PendingInfo {
        PendingInfo(
            message: activeMessage ?? "",
            category: activeCategory ?? .newNotification,
            source: activeSource,
            targetWindow: activeTargetWindow)
    }

    private func startCooldown() {
        isInCooldown = true
        cooldownTimer?.invalidate()
        let cooldown = PreferencesManager.shared.resolvedCooldown
        cooldownTimer = Timer.scheduledTimer(
            withTimeInterval: cooldown,
            repeats: false
        ) { [weak self] _ in
            self?.handleEvent(.cooldownExpired)
        }
    }

    func reset() {
        cooldownTimer?.invalidate()
        cooldownTimer = nil
        longWaitTimer?.invalidate()
        longWaitTimer = nil
        autoDismissTimer?.invalidate()
        autoDismissTimer = nil
        snoozeTimer?.invalidate()
        snoozeTimer = nil
        isInCooldown = false
        pendingCount = 0
        badgeFirstDetectedAt = nil
        activeCategory = nil
        activeSource = .terminal
        activeTargetWindow = nil
        activeTTY = nil
        activeMessage = nil
        pendingInfo = nil
        pendingAgents.removeAll()
        isOverlayDismissing = false
        currentState = .idle
    }
}
