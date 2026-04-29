import XCTest
@testable import SymphonyCore

final class SymphonyCoreTests: XCTestCase {
    func testOnlyReadyStateDispatchesByDefault() {
        XCTAssertTrue(WorkState.ready.canDispatch)
        XCTAssertFalse(WorkState.backlog.canDispatch)
        XCTAssertFalse(WorkState.running.canDispatch)
        XCTAssertFalse(WorkState.done.canDispatch)
    }

    func testMovingTaskUpdatesState() {
        let projectID = ProjectID(rawValue: "project")
        let task = WorkItem(projectID: projectID, identifier: "LOCAL-1", title: "Test")
        let moved = task.moving(to: .ready)

        XCTAssertEqual(moved.id, task.id)
        XCTAssertEqual(moved.state, .ready)
        XCTAssertGreaterThanOrEqual(moved.updatedAt, task.updatedAt)
    }

    func testRunAttemptTracksWorkspaceReference() throws {
        let workspace = WorkspaceReference(
            path: "/tmp/composer-workspaces/local-1",
            cleanupPolicy: .removeOnSuccess,
            preparedAt: Date(timeIntervalSince1970: 100)
        )
        let run = RunAttempt(
            id: RunID(rawValue: "run-1"),
            taskID: TaskID(rawValue: "task-1"),
            agent: AgentConfiguration(kind: .codex),
            workspace: workspace
        )

        let encoded = try JSONEncoder().encode(run)
        let decoded = try JSONDecoder().decode(RunAttempt.self, from: encoded)

        XCTAssertEqual(decoded.workspace, workspace)
    }

    func testRunAttemptDecodesWithoutWorkspaceForExistingStores() throws {
        let data = """
        {
          "id": "run-1",
          "taskID": "task-1",
          "agent": { "kind": "codex", "parameters": {} },
          "status": "queued"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(RunAttempt.self, from: data)

        XCTAssertNil(decoded.workspace)
    }
}
