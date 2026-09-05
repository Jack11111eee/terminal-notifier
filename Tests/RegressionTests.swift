import AppKit
import XCTest

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
        guard suite.testCaseCount > 0 else { fatalError("No regression tests discovered") }
        suite.run()
        exit(suite.testRun?.hasSucceeded == true ? 0 : 1)
    }
}
