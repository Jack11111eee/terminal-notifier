import AppKit
import CoreGraphics

/// 「正在输入」判定：最近几秒内有键盘按键。
///
/// 唯一实现用 CGEventSource 只读查询最近一次 keyDown 的时间戳——
/// 无需辅助功能/输入监控权限（不装 event tap），读不到按键内容，
/// 只知道「N 秒前有按键」。provider 可注入，供单元测试替换。
enum TypingActivity {
    /// provider 返回最近一次 keyDown 距今的秒数（无按键记录返回 nil）。
    static func isTyping(
        secondsSinceLastKeyDown: () -> Double?,
        threshold: TimeInterval = Constants.typingActiveSeconds
    ) -> Bool {
        guard let elapsed = secondsSinceLastKeyDown() else { return false }
        return elapsed >= 0 && elapsed < threshold
    }

    /// CGEventSource 实现：combinedSessionState 覆盖当前登录会话所有输入源。
    static func secondsSinceLastKeyDown() -> Double? {
        let seconds = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState, eventType: .keyDown)
        // 未开机以来无按键时系统返回 -1；视为无记录。
        guard seconds >= 0, seconds.isFinite else { return nil }
        return seconds
    }
}

/// 观察输入状态跳变，只在「开始/停止输入」沿上回调（不逐 tick 重复）。
///
/// 边沿型而非电平型轮询： AppDelegate 只在 typingBegan 时收缩挂着的猫，
/// 每 0.5s 都回调一次毫无意义。provider 注入使逻辑可测。
final class TypingStateWatcher {
    /// 输入开始（无输入 → 输入中）。
    var onTypingBegan: (() -> Void)?
    /// 输入停止（输入中 → 静止；停止输入判定需要 typingIdleSeconds + 周期）。
    var onTypingEnded: (() -> Void)?
    /// 查询函数注入点：返回「最近一次 keyDown 距今秒数」，nil 表示无按键记录。
    private let secondsSinceLastKeyDown: () -> Double?
    private var timer: Timer?
    private var wasTyping = false
    private var isActive = true

    init(secondsSinceLastKeyDown: @escaping () -> Double? = TypingActivity.secondsSinceLastKeyDown) {
        self.secondsSinceLastKeyDown = secondsSinceLastKeyDown
    }

    func start() {
        stop()
        isActive = true
        // 取一次初值,避免启动后第一次 tick 误报 typingBegan（如启动时用户正打字:
        // 应该马上被视为 typing,但不应触发 onTypingBegan 回调——猫还没弹,回调空跑）。
        wasTyping = currentTyping()
        timer = Timer.scheduledTimer(withTimeInterval: Constants.typingPollSeconds, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        wasTyping = false
        isActive = false
    }

    /// 电平查询：此刻是否判定为正在输入（AppDelegate 决定新提醒走迷你形态时用）。
    var isTypingNow: Bool {
        currentTyping()
    }

    private func tick() {
        let typing = currentTyping()
        if typing && !wasTyping { onTypingBegan?() }
        if !typing && wasTyping { onTypingEnded?() }
        wasTyping = typing
    }

    private func currentTyping() -> Bool {
        guard isActive else { return false }
        return TypingActivity.isTyping(secondsSinceLastKeyDown: secondsSinceLastKeyDown)
    }
}
