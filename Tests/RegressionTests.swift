import AppKit
import XCTest
import SwiftUI

final class HookManagerTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    private func userGroup(_ name: String) -> [String: Any] {
        ["matcher": name, "custom": ["keep": true], "hooks": [
            ["type": "command", "command": "echo user-\(name)", "timeout": 17],
            ["type": "prompt", "prompt": "Keep this prompt"]
        ]]
    }

    private func mixedGroup(_ name: String, markers: [String]) -> [String: Any] {
        var group = userGroup(name)
        var entries = group["hooks"] as! [[String: Any]]
        entries += markers.map { ["type": "command", "command": "true \($0)"] }
        group["hooks"] = entries
        return group
    }

    private func encoded(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: .sortedKeys)
    }

    private func read(_ url: URL) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    func testCodexInstallUpdateAndUninstallPreserveUserHooks() throws {
        let url = directory.appendingPathComponent("hooks.json")
        let fixture: [String: Any] = ["customRoot": ["keep": true], "hooks": [
            "PermissionRequest": [mixedGroup("approval", markers: [Constants.codexPermissionHookMarker])],
            "Stop": [mixedGroup("stop", markers: [Constants.codexHookMarker, Constants.codexStopHookMarker]),
                     ["hooks": [["type": "command", "command": "true \(Constants.codexStopHookMarker)"]]]],
            "OtherEvent": [userGroup("other")]
        ]]
        let original = try encoded(fixture)
        try original.write(to: url)
        XCTAssertTrue(CodexHookManager.install(at: url))
        let firstInstall = try encoded(read(url))
        XCTAssertTrue(CodexHookManager.install(at: url))
        XCTAssertEqual(try encoded(read(url)), firstInstall, "Repeated installation must not duplicate hooks")
        XCTAssertTrue(CodexHookManager.install(includePermissionRequest: false, at: url))
        let hooks = try XCTUnwrap(read(url)["hooks"] as? [String: Any])
        XCTAssertEqual(try encoded(hooks["PermissionRequest"]!), try encoded([userGroup("approval")]))
        XCTAssertTrue(CodexHookManager.uninstall(at: url))
        let expected: [String: Any] = ["customRoot": ["keep": true], "hooks": [
            "PermissionRequest": [userGroup("approval")],
            "Stop": [userGroup("stop")],
            "OtherEvent": [userGroup("other")]
        ]]
        XCTAssertEqual(try encoded(read(url)), try encoded(expected))
        let backups = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.contains("tn-backup") }
        XCTAssertTrue(try backups.contains { try Data(contentsOf: $0) == original })
    }

    func testClaudeInstallAndUninstallPreserveUserHooks() throws {
        let url = directory.appendingPathComponent("settings.json")
        let fixture: [String: Any] = ["env": ["KEEP": "value"], "hooks": [
            "Notification": [mixedGroup("permission_prompt", markers: [Constants.claudeHookMarker])],
            "Stop": [mixedGroup("stop", markers: [Constants.claudeHookMarker]),
                     ["hooks": [["type": "command", "command": "true \(Constants.claudeHookMarker)"]]]],
            "OtherEvent": [userGroup("other")]
        ]]
        try encoded(fixture).write(to: url)
        XCTAssertTrue(ClaudeHookManager.install(at: url))
        let firstInstall = try encoded(read(url))
        XCTAssertTrue(ClaudeHookManager.install(at: url))
        XCTAssertEqual(try encoded(read(url)), firstInstall)
        XCTAssertTrue(ClaudeHookManager.uninstall(at: url))
        let expected: [String: Any] = ["env": ["KEEP": "value"], "hooks": [
            "Notification": [userGroup("permission_prompt")],
            "Stop": [userGroup("stop")],
            "OtherEvent": [userGroup("other")]
        ]]
        XCTAssertEqual(try encoded(read(url)), try encoded(expected))
    }

}

private final class RecordingDelegate: NotificationStateMachineDelegate {
    var requests: [AgentNotificationEvent] = []
    var suppress = false
    var updates = 0

    func stateMachine(_ sm: NotificationStateMachine, didTransitionTo state: NotificationState) {}
    func stateMachine(_ sm: NotificationStateMachine, shouldShowOverlayWithMessage message: String,
                      category: MessageProvider.Category, source: NotificationSource,
                      targetWindow: TerminalWindowInfo?) {
        requests.append(AgentNotificationEvent(category: category, source: source,
                                               tty: sm.activeTTY, targetWindow: targetWindow))
        if suppress { sm.handleEvent(.overlaySuppressed) }
    }
    func stateMachine(_ sm: NotificationStateMachine, shouldUpdateMessage message: String,
                      category: MessageProvider.Category, source: NotificationSource,
                      targetWindow: TerminalWindowInfo?) { updates += 1 }
    func stateMachineShouldDismissOverlay(_ sm: NotificationStateMachine) {}
}

final class NotificationStateMachineTests: XCTestCase {
    private var machine: NotificationStateMachine!
    private var recorder: RecordingDelegate!

    override func setUp() {
        machine = NotificationStateMachine()
        recorder = RecordingDelegate()
        machine.delegate = recorder
    }

    override func tearDown() { machine.reset() }

    private func event(_ index: Int) -> AgentNotificationEvent {
        AgentNotificationEvent(
            category: index % 2 == 0 ? .needsConfirm : .codexDone,
            source: index % 2 == 0 ? .claudeCode : .codexApp,
            tty: "ttys\(index)",
            targetWindow: TerminalWindowInfo(windowID: UInt32(index + 1), ownerPID: 1,
                                             title: "Window \(index)", bounds: .zero))
    }

    private func send(_ index: Int) { machine.handleEvent(.agentTrigger(event(index))) }
    private func finishAndCoolDown() {
        machine.handleEvent(.dropAnimationCompleted)
        machine.handleEvent(.userDismissed)
        machine.handleEvent(.jumpBackCompleted)
        machine.handleEvent(.cooldownExpired)
    }

    private func assertRequests(_ indices: [Int], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(recorder.requests.count, indices.count, file: file, line: line)
        for (actual, index) in zip(recorder.requests, indices) {
            let expected = event(index)
            XCTAssertEqual(actual.category, expected.category, file: file, line: line)
            XCTAssertEqual(actual.source, expected.source, file: file, line: line)
            XCTAssertEqual(actual.tty, expected.tty, file: file, line: line)
            XCTAssertEqual(actual.targetWindow, expected.targetWindow, file: file, line: line)
        }
    }

    func testDismissDuringEntranceIgnoresLateAnimationCompletion() {
        send(0)
        send(1)
        machine.handleEvent(.userDismissed)
        XCTAssertEqual(machine.currentState, .animatingOut)
        machine.handleEvent(.dropAnimationCompleted)
        XCTAssertEqual(machine.currentState, .animatingOut)
        machine.handleEvent(.jumpBackCompleted)
        machine.handleEvent(.cooldownExpired)
        assertRequests([0, 1])
    }

    func testSnoozeDuringEntrancePreservesSourceAndDoesNotResumeEntrance() {
        send(1)
        machine.handleEvent(.userSnoozed)
        XCTAssertEqual(machine.currentState, .pending)
        XCTAssertEqual(machine.pendingInfo?.source, .codexApp)
        XCTAssertEqual(machine.pendingInfo?.targetWindow, event(1).targetWindow)
        machine.handleEvent(.dropAnimationCompleted)
        XCTAssertEqual(machine.currentState, .pending)
        machine.handleEvent(.jumpBackCompleted)
        machine.handleEvent(.snoozeElapsed)
        XCTAssertEqual(machine.currentState, .detected(count: 1))
        XCTAssertEqual(recorder.requests.count, 2)
        XCTAssertEqual(recorder.requests.last?.source, .codexApp)
        XCTAssertEqual(recorder.requests.last?.targetWindow, event(1).targetWindow)
    }

    func testBatchDuringDropIsDeliveredInOrderWithContext() {
        for index in 0..<4 { send(index) }
        machine.handleEvent(.badgeCleared)
        XCTAssertEqual(machine.currentState, .detected(count: 1))
        assertRequests([0])
        for _ in 0..<3 { finishAndCoolDown() }
        assertRequests([0, 1, 2, 3])
        finishAndCoolDown()
        XCTAssertEqual(machine.currentState, .idle)
    }

    func testShowingExitAnimationAndCooldownRetainEvents() {
        send(0)
        machine.handleEvent(.dropAnimationCompleted)
        send(1)
        machine.handleEvent(.cooldownExpired)
        XCTAssertEqual(recorder.updates, 0)
        machine.handleEvent(.userDismissed)
        send(2)
        send(3)
        machine.handleEvent(.jumpBackCompleted)
        send(4)
        send(5)
        assertRequests([0])
        machine.handleEvent(.cooldownExpired)
        for _ in 0..<4 { finishAndCoolDown() }
        assertRequests([0, 1, 2, 3, 4, 5])
    }

    func testSuppressedInitialCooldownAndSnoozeDisplaysRecover() {
        recorder.suppress = true
        machine.handleEvent(.badgeDetected)
        XCTAssertEqual(machine.currentState, .pending)
        XCTAssertEqual(machine.pendingInfo?.source, .terminal)
        recorder.suppress = false
        machine.handleEvent(.clearPending)
        recorder.requests.removeAll()
        send(0)
        send(1)
        send(2)
        recorder.suppress = true
        finishAndCoolDown()
        XCTAssertEqual(machine.currentState, .pending)
        XCTAssertEqual(machine.pendingInfo?.category, event(1).category)
        machine.handleEvent(.cooldownExpired)
        XCTAssertEqual(machine.currentState, .pending)
        assertRequests([0, 1, 2])
        recorder.suppress = false
        send(3)
        XCTAssertEqual(machine.currentState, .detected(count: 1))
        assertRequests([0, 1, 2, 3])
        machine.handleEvent(.dropAnimationCompleted)
        machine.handleEvent(.userSnoozed)
        machine.handleEvent(.jumpBackCompleted)
        recorder.suppress = true
        machine.handleEvent(.snoozeElapsed)
        XCTAssertEqual(machine.currentState, .pending)
        recorder.suppress = false
        machine.handleEvent(.snoozeElapsed)
        XCTAssertEqual(machine.currentState, .detected(count: 1))
    }

    func testPendingExitAnimationWaitsBeforeShowingQueuedEvents() {
        for action in [NotificationEvent.userSnoozed, .autoDismissElapsed] {
            machine.reset()
            recorder.requests.removeAll()
            send(0)
            machine.handleEvent(.dropAnimationCompleted)
            machine.handleEvent(action)
            XCTAssertEqual(machine.currentState, .pending)
            send(1)
            send(2)
            machine.handleEvent(.cooldownExpired)
            assertRequests([0])
            machine.handleEvent(.jumpBackCompleted)
            assertRequests([0])
            machine.handleEvent(.cooldownExpired)
            finishAndCoolDown()
            assertRequests([0, 1, 2])
        }
    }

}

/// Opt-in window tests require a GUI session; ordinary regressions remain headless.
final class WindowLayoutTests: XCTestCase {
    private func settle() { RunLoop.current.run(until: Date().addingTimeInterval(0.15)) }

    func testSettingsAndHistoryResizeWithWindow() {
        let settings = SettingsWindowController()
        settings.showSettings(preferences: .shared)
        let history = HistoryWindowController()
        history.showHistory(historyManager: NotificationHistoryManager(storageKey: "tn-layout-test-unused"))
        let windows = NSApp.windows.filter { $0.isVisible }
        XCTAssertEqual(windows.count, 2)
        for window in windows {
            if window.titleVisibility == .visible {
                XCTAssertFalse(window.styleMask.contains(.fullSizeContentView),
                               "Native titled content must not extend into the titlebar")
            }
            window.setContentSize(NSSize(width: 960, height: 680))
            settle()
            XCTAssertEqual(window.contentView?.bounds.width ?? 0, 960, accuracy: 1)
            XCTAssertGreaterThan(window.contentView?.bounds.height ?? 0, 600)
            window.setContentSize(window.contentMinSize)
            settle()
            XCTAssertEqual(window.contentView?.bounds.width ?? 0, window.contentMinSize.width, accuracy: 1)
            if window.titleVisibility == .hidden {
                for (index, kind) in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].enumerated() {
                    let button = window.standardWindowButton(kind)!
                    let rect = button.convert(button.bounds, to: nil)
                    XCTAssertEqual(rect.midX, 26 + CGFloat(index) * 23, accuracy: 1)
                    XCTAssertEqual(window.frame.height - rect.midY, 26, accuracy: 1)
                }
            }
            window.close()
        }
    }

    func testBubbleControlsStayInsideMaterialForLongMessages() {
        for message in ["Ready", String(repeating: "这是需要处理的长通知。 Long reminder message. ", count: 30)] {
            let size = SpeechBubbleView.preferredSize(for: message, width: 304)
            let bubble = SpeechBubbleView(frame: NSRect(origin: .zero, size: size))
            bubble.text = message
            let window = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                                 styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = bubble
            window.orderFrontRegardless()
            settle()
            bubble.layoutSubtreeIfNeeded()
            defer { window.close() }
            for button in [bubble.closeButton, bubble.snoozeButton, bubble.openButton] {
                let rect = button.convert(button.bounds, to: bubble)
                XCTAssertTrue(bubble.bounds.contains(rect), "Button must stay inside the bubble: \(rect)")
                XCTAssertGreaterThanOrEqual(rect.height, 28)
            }
            let textRect = bubble.messageLabel.convert(bubble.messageLabel.bounds, to: bubble)
            XCTAssertTrue(bubble.bounds.contains(textRect))
            if message.count > 100 {
                XCTAssertGreaterThan(textRect.height, 30, "Long messages must wrap to multiple lines")
            }
            let later = bubble.snoozeButton.convert(bubble.snoozeButton.bounds, to: bubble)
            let open = bubble.openButton.convert(bubble.openButton.bounds, to: bubble)
            XCTAssertFalse(later.intersects(open))
            XCTAssertLessThan(size.height, 400, "Long messages must not create a screen-sized overlay")
            if message == "Ready" {
                XCTAssertLessThanOrEqual(size.height, 125, "Short reminders should remain compact")
            }
        }
    }

    func testIncomingOverlayDoesNotBecomeKeyAndExplicitFocusWorks() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let overlay = OverlayWindowController()
        defer { overlay.forceClose() }
        overlay.show(on: screen, message: "这是一条示例提醒。准备好后，回到你的工作。")
        let panel = try XCTUnwrap(NSApp.windows.first { $0 is OverlayWindow && $0.isVisible })
        XCTAssertFalse(panel.isKeyWindow)
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertLessThan(panel.frame.width, screen.visibleFrame.width)
        let content = try XCTUnwrap(panel.contentView as? OverlayContentView)
        let beforeFocus = content.bubbleView.messageLabel.frame
        XCTAssertGreaterThan(beforeFocus.height, 28, "The second line must exist before any click")
        XCTAssertFalse(panel.isKeyWindow)
        overlay.focusForInteraction()
        settle()
        XCTAssertTrue(panel.isKeyWindow)
        XCTAssertEqual(content.bubbleView.messageLabel.frame.height, beforeFocus.height, accuracy: 0.5,
                       "Focusing must not change message layout")
        overlay.updateMessage(String(repeating: "Long reminder text. ", count: 12))
        content.layoutSubtreeIfNeeded()
        let label = content.bubbleView.messageLabel
        let textRect = label.convert(label.bounds, to: content.bubbleView)
        XCTAssertTrue(content.bubbleView.bounds.contains(textRect))
    }

    func testReducedMotionAnimationsCompleteWithoutTravel() {
        let layer = CALayer()
        layer.position = CGPoint(x: 100, y: 100)
        let enter = expectation(description: "Reduced-motion entrance completes")
        DropBounceAnimator().animate(layer: layer, from: 500, to: 100, reduceMotion: true) { enter.fulfill() }
        wait(for: [enter], timeout: 2)
        XCTAssertEqual(layer.transform.m42, 0)
        let exit = expectation(description: "Reduced-motion exit completes")
        JumpBackAnimator().animate(layer: layer, from: layer.position,
                                   to: CGPoint(x: 100, y: 500), reduceMotion: true) { exit.fulfill() }
        wait(for: [exit], timeout: 2)
        XCTAssertEqual(layer.transform.m42, 0)
    }
}

@main
enum RegressionTests {
    static func main() {
        // Volatile defaults affect only this process, never the installed app's preferences.
        UserDefaults.standard.setVolatileDomain([
            "language": "en", "autoDismissEnabled": true,
            "autoDismissSeconds": 3600, "cooldownSeconds": 3600
        ], forName: UserDefaults.argumentDomain)
        let suite = XCTestSuite(name: "Terminal Notifier regressions")
        suite.addTest(HookManagerTests.defaultTestSuite)
        suite.addTest(NotificationStateMachineTests.defaultTestSuite)
        if ProcessInfo.processInfo.environment["TN_RUN_UI_TESTS"] == "1" {
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.accessory)
            suite.addTest(WindowLayoutTests.defaultTestSuite)
        }
        guard suite.testCaseCount > 0 else { fatalError("No regression tests discovered") }
        suite.run()
        exit(suite.testRun?.hasSucceeded == true ? 0 : 1)
    }
}
