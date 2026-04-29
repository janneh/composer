import XCTest
import SymphonyCore
@testable import SymphonyRuntime

final class AgentRunEventProjectionTests: XCTestCase {
    func testProjectsNormalizedAgentEventsToRuntimeEventsAndRunUpdates() {
        let date = Date(timeIntervalSince1970: 2_000)
        let taskID = TaskID(rawValue: "task-1")
        let run = RunAttempt(
            id: RunID(rawValue: "run-1"),
            taskID: taskID,
            agent: AgentConfiguration(kind: .codex),
            status: .running,
            startedAt: Date(timeIntervalSince1970: 1_000)
        )

        let cases: [(AgentRunEvent, RuntimeEventKind, RunStatus, [String: String])] = [
            (.started(message: "Started"), .runStarted, .running, ["agentEvent": "started"]),
            (.progress(message: "Working"), .runEvent, .running, ["agentEvent": "progress"]),
            (
                .toolUse(name: "apply_patch", inputSummary: "Edited file"),
                .runEvent,
                .running,
                ["agentEvent": "toolUse", "toolName": "apply_patch", "inputSummary": "Edited file"]
            ),
            (
                .partialOutput("Line 1"),
                .runEvent,
                .running,
                ["agentEvent": "partialOutput", "output": "Line 1"]
            ),
            (
                .waitingForInput(prompt: "Approve?"),
                .userInputRequired,
                .waitingForInput,
                ["agentEvent": "waitingForInput", "prompt": "Approve?"]
            ),
            (.completed(summary: "Done"), .runFinished, .succeeded, ["agentEvent": "completed"]),
            (.failed(message: "Failed"), .runFailed, .failed, ["agentEvent": "failed"])
        ]

        for (agentEvent, runtimeKind, runStatus, payload) in cases {
            let projection = AgentRunEventProjection.project(agentEvent, run: run, taskID: taskID, at: date)

            XCTAssertEqual(projection.event.kind, runtimeKind)
            XCTAssertEqual(projection.event.taskID, taskID)
            XCTAssertEqual(projection.event.runID, run.id)
            XCTAssertEqual(projection.event.createdAt, date)
            XCTAssertEqual(projection.run.status, runStatus)
            XCTAssertEqual(projection.event.payload, payload)
        }
    }

    func testRecordAgentEventPersistsRuntimeEventAndRunStatus() async throws {
        let date = Date(timeIntervalSince1970: 2_000)
        let taskID = TaskID(rawValue: "task-1")
        let run = RunAttempt(
            id: RunID(rawValue: "run-1"),
            taskID: taskID,
            agent: AgentConfiguration(kind: .codex),
            status: .running
        )
        let store = InMemoryStore(projects: [], tasks: [])
        try await store.upsertRun(run)
        let orchestrator = Orchestrator(
            taskStore: store,
            projectStore: store,
            runStore: store,
            eventStore: store,
            now: { date }
        )

        let updatedRun = try await orchestrator.recordAgentEvent(.completed(summary: "Done"), taskID: taskID, runID: run.id)

        XCTAssertEqual(updatedRun.status, .succeeded)
        XCTAssertEqual(updatedRun.finishedAt, date)
        XCTAssertEqual(updatedRun.summary, "Done")
        let persistedRuns = try await store.listRuns(taskID: taskID)
        XCTAssertEqual(persistedRuns, [updatedRun])
        let events = try await store.listEvents(taskID: taskID, limit: 10)
        XCTAssertEqual(events.map(\.kind), [.runFinished])
        XCTAssertEqual(events.first?.payload["agentEvent"], "completed")
    }
}
