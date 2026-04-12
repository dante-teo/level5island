import XCTest
@testable import Level5IslandCore

private func makeEvent(_ name: String, sessionId: String, toolName: String? = nil) -> HookEvent {
    var json: [String: Any] = [
        "hook_event_name": name,
        "session_id": sessionId,
    ]
    if let toolName { json["tool_name"] = toolName }
    let data = try! JSONSerialization.data(withJSONObject: json)
    return HookEvent(from: data)!
}

/// Tests that `finishTool` in the reducer guards against overwriting `needsAttention` states.
final class FinishToolGuardTests: XCTestCase {

    private var sessions: [String: SessionSnapshot]!

    override func setUp() {
        sessions = [:]
    }

    // MARK: - Guard preserves needsAttention

    func testPostToolUsePreservesWaitingApproval() {
        sessions["s1"] = makeSession(status: .waitingApproval)
        _ = reduceEvent(sessions: &sessions, event: makeEvent("PostToolUse", sessionId: "s1", toolName: "Read"), maxHistory: 10)
        XCTAssertEqual(sessions["s1"]?.status, .waitingApproval)
    }

    func testPostToolUsePreservesWaitingQuestion() {
        sessions["s1"] = makeSession(status: .waitingQuestion)
        _ = reduceEvent(sessions: &sessions, event: makeEvent("PostToolUse", sessionId: "s1", toolName: "Read"), maxHistory: 10)
        XCTAssertEqual(sessions["s1"]?.status, .waitingQuestion)
    }

    func testPostToolUseFailurePreservesWaitingApproval() {
        sessions["s1"] = makeSession(status: .waitingApproval)
        _ = reduceEvent(sessions: &sessions, event: makeEvent("PostToolUseFailure", sessionId: "s1", toolName: "Read"), maxHistory: 10)
        XCTAssertEqual(sessions["s1"]?.status, .waitingApproval)
    }

    func testPermissionDeniedPreservesWaitingApproval() {
        sessions["s1"] = makeSession(status: .waitingApproval)
        _ = reduceEvent(sessions: &sessions, event: makeEvent("PermissionDenied", sessionId: "s1", toolName: "Read"), maxHistory: 10)
        XCTAssertEqual(sessions["s1"]?.status, .waitingApproval)
    }

    func testSubagentStopPreservesWaitingApproval() {
        sessions["s1"] = makeSession(status: .waitingApproval)
        _ = reduceEvent(sessions: &sessions, event: makeEvent("SubagentStop", sessionId: "s1"), maxHistory: 10)
        XCTAssertEqual(sessions["s1"]?.status, .waitingApproval)
    }

    // MARK: - Normal transition still works

    func testPostToolUseTransitionsRunningToProcessing() {
        var session = makeSession(status: .running)
        session.currentTool = "Read"
        sessions["s1"] = session
        _ = reduceEvent(sessions: &sessions, event: makeEvent("PostToolUse", sessionId: "s1", toolName: "Read"), maxHistory: 10)
        XCTAssertEqual(sessions["s1"]?.status, .processing)
        XCTAssertNil(sessions["s1"]?.currentTool)
    }

    // MARK: - Helpers

    private func makeSession(status: AgentStatus) -> SessionSnapshot {
        var s = SessionSnapshot()
        s.status = status
        s.currentTool = "Bash"
        return s
    }
}
