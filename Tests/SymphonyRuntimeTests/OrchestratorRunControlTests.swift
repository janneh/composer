import XCTest
import SymphonyCore
import SymphonyInterfaces
@testable import SymphonyRuntime

final class OrchestratorRunControlTests: XCTestCase {
    func testCancelRunCancelsRunnerAndMarksTaskCanceled() async throws {
        let date = Date(timeIntervalSince1970: 2_000)
        let project = Project(id: ProjectID(rawValue: "project-1"), name: "Composer")
        let task = WorkItem(
            id: TaskID(rawValue: "task-1"),
            projectID: project.id,
            identifier: "LOCAL-1",
            title: "Cancel",
            state: .running
        )
        let run = RunAttempt(
            id: RunID(rawValue: "run-1"),
            taskID: task.id,
            agent: AgentConfiguration(kind: .codex),
            status: .running,
            sessionID: AgentSessionID(rawValue: "session-1")
        )
        let store = InMemoryStore(projects: [project], tasks: [task])
        try await store.upsertRun(run)
        let runner = RecordingAgentRunner(kind: .codex)
        let orchestrator = Orchestrator(
            taskStore: store,
            projectStore: store,
            runStore: store,
            eventStore: store,
            runners: [runner],
            now: { date }
        )

        let canceled = try await orchestrator.cancelRun(taskID: task.id, runID: run.id)

        XCTAssertEqual(canceled.status, .canceled)
        XCTAssertEqual(canceled.finishedAt, date)
        XCTAssertEqual(runner.canceledSessionIDs, [AgentSessionID(rawValue: "session-1")])
        let storedTask = try await store.task(id: task.id)
        let updatedTask = try XCTUnwrap(storedTask)
        XCTAssertEqual(updatedTask.state, .canceled)
        let events = try await store.listEvents(taskID: task.id, limit: 10)
        XCTAssertEqual(events.map(\.kind), [.runFinished])
        XCTAssertEqual(events.first?.message, "Run canceled")
    }

    func testRetryTaskMovesTaskBackToReady() async throws {
        let date = Date(timeIntervalSince1970: 2_000)
        let project = Project(id: ProjectID(rawValue: "project-1"), name: "Composer")
        let task = WorkItem(
            id: TaskID(rawValue: "task-1"),
            projectID: project.id,
            identifier: "LOCAL-1",
            title: "Retry",
            state: .failed
        )
        let store = InMemoryStore(projects: [project], tasks: [task])
        let orchestrator = Orchestrator(
            taskStore: store,
            projectStore: store,
            runStore: store,
            eventStore: store,
            now: { date }
        )

        let retried = try await orchestrator.retryTask(id: task.id)

        XCTAssertEqual(retried.state, .ready)
        XCTAssertEqual(retried.updatedAt, date)
        let events = try await store.listEvents(taskID: task.id, limit: 10)
        XCTAssertEqual(events.map(\.kind), [.taskMoved])
    }

    func testMarkStalledRunsMarksOldRunningRuns() async throws {
        let now = Date(timeIntervalSince1970: 2_000)
        let project = Project(id: ProjectID(rawValue: "project-1"), name: "Composer")
        let task = WorkItem(id: TaskID(rawValue: "task-1"), projectID: project.id, identifier: "LOCAL-1", title: "Stall")
        let oldRun = RunAttempt(
            id: RunID(rawValue: "run-old"),
            taskID: task.id,
            agent: AgentConfiguration(kind: .codex),
            status: .running,
            startedAt: Date(timeIntervalSince1970: 1_000)
        )
        let freshRun = RunAttempt(
            id: RunID(rawValue: "run-fresh"),
            taskID: task.id,
            agent: AgentConfiguration(kind: .codex),
            status: .running,
            startedAt: Date(timeIntervalSince1970: 1_950)
        )
        let store = InMemoryStore(projects: [project], tasks: [task])
        try await store.upsertRun(oldRun)
        try await store.upsertRun(freshRun)
        let orchestrator = Orchestrator(
            taskStore: store,
            projectStore: store,
            runStore: store,
            eventStore: store,
            now: { now }
        )

        let stalled = try await orchestrator.markStalledRuns(olderThan: 300)

        XCTAssertEqual(stalled.map(\.id), [oldRun.id])
        XCTAssertEqual(stalled.first?.status, .stalled)
        let runs = try await store.listRuns(taskID: task.id)
        XCTAssertEqual(runs.first(where: { $0.id == oldRun.id })?.status, .stalled)
        XCTAssertEqual(runs.first(where: { $0.id == freshRun.id })?.status, .running)
    }

    func testMarkStalledRunsCancelsLiveSessionAndMarksTaskFailed() async throws {
        let now = Date(timeIntervalSince1970: 2_000)
        let project = Project(id: ProjectID(rawValue: "project-1"), name: "Composer")
        let task = WorkItem(
            id: TaskID(rawValue: "task-1"),
            projectID: project.id,
            identifier: "LOCAL-1",
            title: "Stall",
            state: .running
        )
        let run = RunAttempt(
            id: RunID(rawValue: "run-1"),
            taskID: task.id,
            agent: AgentConfiguration(kind: .codex),
            status: .running,
            sessionID: AgentSessionID(rawValue: "session-1"),
            startedAt: Date(timeIntervalSince1970: 1_000)
        )
        let store = InMemoryStore(projects: [project], tasks: [task])
        try await store.upsertRun(run)
        let runner = RecordingAgentRunner(kind: .codex)
        let orchestrator = Orchestrator(
            taskStore: store,
            projectStore: store,
            runStore: store,
            eventStore: store,
            runners: [runner],
            now: { now }
        )

        let stalled = try await orchestrator.markStalledRuns(olderThan: 300)

        XCTAssertEqual(stalled.map(\.id), [run.id])
        XCTAssertEqual(runner.canceledSessionIDs, [AgentSessionID(rawValue: "session-1")])
        let storedTask = try await store.task(id: task.id)
        XCTAssertEqual(storedTask?.state, .failed)
        let events = try await store.listEvents(taskID: task.id, limit: 10)
        XCTAssertEqual(events.map(\.kind), [.runFailed])
        XCTAssertEqual(events.first?.payload["sessionID"], "session-1")
    }

    func testResumeRunUsesExistingWorkspaceAndResumeToken() async throws {
        let date = Date(timeIntervalSince1970: 2_000)
        let project = Project(
            id: ProjectID(rawValue: "project-1"),
            name: "Composer",
            repositoryPath: "/repo",
            defaultAgent: AgentConfiguration(kind: .codex)
        )
        let task = WorkItem(id: TaskID(rawValue: "task-1"), projectID: project.id, identifier: "LOCAL-1", title: "Resume")
        let workspace = WorkspaceReference(path: "/tmp/workspace", preparedAt: date)
        let run = RunAttempt(
            id: RunID(rawValue: "run-1"),
            taskID: task.id,
            agent: AgentConfiguration(kind: .codex),
            status: .stalled,
            sessionID: AgentSessionID(rawValue: "session-1"),
            resumeToken: "resume-token-1",
            workspace: workspace
        )
        let store = InMemoryStore(projects: [project], tasks: [task])
        try await store.upsertRun(run)
        let runner = RecordingAgentRunner(
            kind: .codex,
            capabilities: AgentCapabilities(supportsResume: true)
        )
        let orchestrator = Orchestrator(
            taskStore: store,
            projectStore: store,
            runStore: store,
            eventStore: store,
            workflowProvider: RunControlWorkflowProvider(),
            workspaceProvider: RunControlWorkspaceProvider(),
            runners: [runner],
            now: { date }
        )

        let resumed = try await orchestrator.resumeRun(taskID: task.id, runID: run.id)

        XCTAssertEqual(resumed.status, .running)
        XCTAssertEqual(resumed.sessionID, AgentSessionID(rawValue: "session-resumed"))
        XCTAssertEqual(resumed.resumeToken, "resume-token-2")
        XCTAssertEqual(runner.resumedSessions, [
            AgentSession(id: AgentSessionID(rawValue: "session-1"), runID: run.id, resumeToken: "resume-token-1")
        ])
        XCTAssertEqual(runner.requests.first?.workspacePath, workspace.path)
    }
}

private struct RunControlWorkflowProvider: WorkflowProvider {
    func prompt(for task: WorkItem, project: Project, run: RunAttempt?) async throws -> String {
        "Prompt for \(task.identifier)"
    }

    func validate(project: Project) async throws -> [WorkflowDiagnostic] {
        []
    }
}

private struct RunControlWorkspaceProvider: WorkspaceProvider {
    func prepareWorkspace(for task: WorkItem, project: Project) async throws -> WorkspaceReference {
        WorkspaceReference(path: "/unused")
    }

    func cleanupWorkspace(_ workspace: WorkspaceReference, for task: WorkItem, project: Project) async throws {}
}
