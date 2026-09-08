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

    /// 新 tty 探测（进程树上行）的确定性回归。
    ///
    /// 编排出「真实 hook 子进程」的形态——无 controlling tty、stdio 全被重定向：
    /// script 分配 pty（祖先有 ctty）→ perl fork 出的子进程 setsid 脱离 ctty
    /// （必须先 fork：会话 leader 调 setsid 会 EPERM）并重定向 stdio，再 exec 探测 sh。
    /// 此形态下探测的前三级（直接 ctty / tty 命令 / lsof fd）必然失败，唯一命中
    /// 途径是第四级沿 ppid 链上溯——正是本特性要验证的行为。不依赖运行环境：
    /// headless CI（xctest 全链无 ctty，旧断言「链上必有 tty」正是 CI 挂掉的原因）同样成立。
    func testClaudeHookCommandProducesTTYFromProcessAncestry() throws {
        let markerDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("terminal-notifier-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: markerDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: markerDir) }

        // 探测段与 ClaudeHookManager.command(for:) 保持一致，唯 dir 改指临时目录
        // （直接执行 install 产出的命令不可行：它写 ~/.claude 下的 marker）。
        let script = """
        dir='\(markerDir.path)'; mkdir -p "$dir"; \
        tty_name="$(ps -o tty= -p $$ 2>/dev/null | tr -d ' ')"; \
        if [ -z "$tty_name" ] || [ "$tty_name" = "??" ]; then tty_name="$(tty 2>/dev/null | sed 's#^/dev/##')"; fi; \
        if [ -z "$tty_name" ] || [ "$tty_name" = "not a tty" ]; then tty_name="$(lsof -p $$ -a -Fn -d 0,1,2 2>/dev/null | grep -m1 '^n/dev/tty' | sed 's#^n/dev/##')"; fi; \
        if [ -z "$tty_name" ] || [ "$tty_name" = "??" ] || [ "$tty_name" = "not a tty" ]; then \
            _p=$$; _i=0; _tty=""; \
            while [ "$_i" -lt 20 ]; do \
                _p="$(ps -o ppid= -p "$_p" 2>/dev/null | tr -d ' ')"; \
                if [ -z "$_p" ] || [ "$_p" -le 1 ]; then break; fi; \
                _tty="$(ps -o tty= -p "$_p" 2>/dev/null | tr -d ' ')"; \
                if [ -n "$_tty" ] && [ "$_tty" != "??" ]; then tty_name="$_tty"; break; fi; \
                _i=$((_i+1)); \
            done; \
        fi; \
        printf '{"event":"%s","source":"claude","tty":"%s","timestamp":%s}\\n' 'done' "$tty_name" "$(date +%s)" > "$dir/marker.json"
        """

        // 探测脚本经环境变量传给 perl（避免多层引号转义）；子进程 exec 后其 ppid
        // 即留在 pty 会话里的 perl 父进程——第四级一跳即可命中。perl 父进程再把
        // 自身 ctty 落盘为期望值。
        let orchestrator = """
        my $kid = fork();
        die "fork: $!" unless defined $kid;
        if ($kid == 0) {
            setsid() or die "setsid: $!";
            open STDIN, "<", "/dev/null" or die $!;
            open STDOUT, ">", "/dev/null" or die $!;
            open STDERR, ">&STDOUT" or die $!;
            exec "/bin/sh", "-c", $ENV{TN_PROBE_SCRIPT};
            die "exec: $!";
        }
        waitpid($kid, 0);
        chomp(my $tty = `ps -o tty= -p $$`);
        open my $fh, ">", $ENV{TN_MARKER_DIR} . "/expected.txt" or die $!;
        print $fh $tty;
        close $fh;
        """

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        proc.arguments = ["-q", "/dev/null", "/usr/bin/perl", "-MPOSIX", "-e", orchestrator]
        var environment = ProcessInfo.processInfo.environment
        environment["TN_PROBE_SCRIPT"] = script
        environment["TN_MARKER_DIR"] = markerDir.path
        proc.environment = environment
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        try proc.run()
        proc.waitUntilExit()

        XCTAssertEqual(proc.terminationStatus, 0, "编排进程应正常退出（script/perl/sh 任一失败即测试失效）")
        let data = try Data(contentsOf: markerDir.appendingPathComponent("marker.json"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let tty = try XCTUnwrap(json["tty"] as? String)
        // 前三级失败的占位值不应出现
        XCTAssertFalse(tty.isEmpty)
        XCTAssertNotEqual(tty, "??")
        XCTAssertNotEqual(tty, "not a tty")
        // 关键断言：tty 应恰为 ppid 链上第一个有 ctty 的祖先（perl 父进程，即
        // script 分配的 pty），证明它来自第四级进程树上行，而非其它路径的巧合。
        let expected = try String(contentsOf: markerDir.appendingPathComponent("expected.txt"),
                                  encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(expected.isEmpty, "perl 父进程应能拿到自身 ctty")
        XCTAssertEqual(tty, expected)
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

final class SettingsVisualModeTests: XCTestCase {
    func testExplicitSettingsVisualModeOverridesAutomaticSelection() {
        XCTAssertEqual(SettingsVisualMode.resolved(
            arguments: ["TerminalNotifier", "--settings-visual-mode", "modern"],
            environment: [:]), .modern)
        XCTAssertEqual(SettingsVisualMode.resolved(
            arguments: ["TerminalNotifier"],
            environment: ["TERMINAL_NOTIFIER_SETTINGS_VISUAL_MODE": "compatible"]), .compatible)
    }

    func testInvalidSettingsVisualModeFallsBackToSupportedAutomaticMode() {
        let mode = SettingsVisualMode.resolved(
            arguments: ["TerminalNotifier", "--settings-visual-mode", "invalid"],
            environment: ["TERMINAL_NOTIFIER_SETTINGS_VISUAL_MODE": "invalid"])
        XCTAssertTrue(SettingsVisualMode.allCases.contains(mode))
    }

    func testModernAndCompatibleModesUseDistinctChromePolicies() {
        XCTAssertTrue(SettingsVisualMode.modern.usesInsetGlassSidebar)
        XCTAssertTrue(SettingsVisualMode.modern.repositionsWindowControls)
        XCTAssertFalse(SettingsVisualMode.compatible.usesInsetGlassSidebar)
        XCTAssertFalse(SettingsVisualMode.compatible.repositionsWindowControls)
    }
}

/// Opt-in window tests require a GUI session; ordinary regressions remain headless.
final class WindowLayoutTests: XCTestCase {
    private func settle() { RunLoop.current.run(until: Date().addingTimeInterval(0.15)) }

    private func requireScreen() throws -> NSScreen {
        guard let screen = NSScreen.main else {
            throw XCTSkip("Window layout tests require a logged-in macOS graphical session")
        }
        return screen
    }

    func testSettingsAndHistoryResizeWithWindow() throws {
        _ = try requireScreen()
        let settings = SettingsWindowController(visualMode: .modern)
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
                XCTAssertTrue(window.styleMask.contains(.fullSizeContentView),
                              "The settings sidebar should extend through the titlebar")
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
        let screen = try requireScreen()
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
        suite.addTest(SettingsVisualModeTests.defaultTestSuite)
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
