import XCTest
import SymphonyCore
import SymphonyInterfaces
@testable import SymphonyRuntime

final class OrchestratorDispatchTests: XCTestCase {
    func testDispatchReadyCreatesRunWorkspacePromptAndAgentRequest() async throws {
        let date = Date(timeIntervalSince1970: 1_000)
        let project = Project(
            id: ProjectID(rawValue: "project-1"),
            name: "Composer",
            repositoryPath: "/repo",
            defaultAgent: AgentConfiguration(kind: .codex, model: "gpt-5")
        )
        let task = WorkItem(
            id: TaskID(rawValue: "task-1"),
            projectID: project.id,
            identifier: "LOCAL-1",
            title: "Dispatch task",
            state: .ready
        )
        let workspace = WorkspaceReference(
            path: "/tmp/composer-workspaces/local-1",
            cleanupPolicy: .removeOnSuccess,
            preparedAt: date
        )
        let store = InMemoryStore(projects: [project], tasks: [task])
        let workflowProvider = RecordingWorkflowProvider()
        let workspaceProvider = RecordingWorkspaceProvider(workspace: workspace)
        let runner = RecordingAgentRunner(kind: .codex)
        let orchestrator = Orchestrator(
            taskStore: store,
            projectStore: store,
            runStore: store,
            eventStore: store,
            workflowProvider: workflowProvider,
            workspaceProvider: workspaceProvider,
            runners: [runner],
            now: { date }
        )

        let execution = try await orchestrator.dispatchReady(projectID: project.id)

        XCTAssertEqual(execution.plan.ready.map(\.id), [task.id])
        XCTAssertEqual(execution.failedRuns, [])
        let run = try XCTUnwrap(execution.startedRuns.first)
        XCTAssertEqual(run.taskID, task.id)
        XCTAssertEqual(run.agent, project.defaultAgent)
        XCTAssertEqual(run.status, .running)
        XCTAssertEqual(run.workspace, workspace)
        XCTAssertEqual(run.startedAt, date)
        XCTAssertEqual(run.sessionID, AgentSessionID(rawValue: "session-1"))

        let persistedRuns = try await store.listRuns(taskID: task.id)
        XCTAssertEqual(persistedRuns, [run])
        let persistedTask = try await store.task(id: task.id)
        let updatedTask = try XCTUnwrap(persistedTask)
        XCTAssertEqual(updatedTask.state, .running)

        XCTAssertEqual(workspaceProvider.preparedTaskIDs, [task.id])
        XCTAssertEqual(workflowProvider.promptedRun?.workspace, workspace)
        XCTAssertEqual(runner.startedRunIDs, [run.id])
        let request = try XCTUnwrap(runner.requests.first)
        XCTAssertEqual(request.task, task)
        XCTAssertEqual(request.project, project)
        XCTAssertEqual(request.workspacePath, workspace.path)
        XCTAssertEqual(request.agent, project.defaultAgent)
        XCTAssertTrue(request.workflowPrompt.contains(run.id.rawValue))
        XCTAssertTrue(request.workflowPrompt.contains(workspace.path))

        let events = try await store.listEvents(taskID: task.id, limit: 10)
        XCTAssertEqual(events.map(\.kind), [.runQueued, .runStarted])
        XCTAssertEqual(events[1].payload["workspacePath"], workspace.path)
    }

    func testDispatchReadyRecordsRunFailureAndContinues() async throws {
        let date = Date(timeIntervalSince1970: 1_000)
        let project = Project(
            id: ProjectID(rawValue: "project-1"),
            name: "Composer",
            repositoryPath: "/repo",
            defaultAgent: AgentConfiguration(kind: .codex)
        )
        let task = WorkItem(
            id: TaskID(rawValue: "task-1"),
            projectID: project.id,
            identifier: "LOCAL-1",
            title: "Dispatch task",
            state: .ready
        )
        let store = InMemoryStore(projects: [project], tasks: [task])
        let runner = RecordingAgentRunner(kind: .codex)
        let orchestrator = Orchestrator(
            taskStore: store,
            projectStore: store,
            runStore: store,
            eventStore: store,
            workflowProvider: FailingWorkflowProvider(),
            workspaceProvider: RecordingWorkspaceProvider(
                workspace: WorkspaceReference(path: "/tmp/workspace", preparedAt: date)
            ),
            runners: [runner],
            now: { date }
        )

        let execution = try await orchestrator.dispatchReady(projectID: project.id)

        XCTAssertEqual(execution.startedRuns, [])
        let failedRun = try XCTUnwrap(execution.failedRuns.first)
        XCTAssertEqual(failedRun.status, .failed)
        XCTAssertEqual(failedRun.finishedAt, date)
        XCTAssertEqual(runner.requests, [])
        let storedTask = try await store.task(id: task.id)
        let persistedTask = try XCTUnwrap(storedTask)
        XCTAssertEqual(persistedTask.state, .ready)
        let events = try await store.listEvents(taskID: task.id, limit: 10)
        XCTAssertEqual(events.map(\.kind), [.runQueued, .runFailed])
    }

    func testDispatchReadyRequiresExecutionDependencies() async throws {
        let project = Project(id: ProjectID(rawValue: "project-1"), name: "Composer")
        let store = InMemoryStore(projects: [project], tasks: [])
        let orchestrator = Orchestrator(taskStore: store, projectStore: store)

        do {
            _ = try await orchestrator.dispatchReady(projectID: project.id)
            XCTFail("Expected missing dependency error")
        } catch let error as OrchestratorError {
            XCTAssertEqual(
                error,
                .missingDispatchDependencies(["runStore", "eventStore", "workflowProvider", "workspaceProvider"])
            )
        }
    }
}

actor InMemoryStore: ProjectStore, TaskStore, RunStore, EventStore {
    private var projects: [ProjectID: Project]
    private var tasks: [TaskID: WorkItem]
    private var runs: [RunID: RunAttempt] = [:]
    private var events: [RuntimeEvent] = []

    init(projects: [Project], tasks: [WorkItem]) {
        self.projects = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
        self.tasks = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
    }

    func listProjects() async throws -> [Project] {
        Array(projects.values)
    }

    func project(id: ProjectID) async throws -> Project? {
        projects[id]
    }

    func upsertProject(_ project: Project) async throws {
        projects[project.id] = project
    }

    func deleteProject(id: ProjectID) async throws {
        projects[id] = nil
        tasks = tasks.filter { $0.value.projectID != id }
    }

    func listTasks(projectID: ProjectID?) async throws -> [WorkItem] {
        tasks.values
            .filter { projectID == nil || $0.projectID == projectID }
            .sorted { $0.identifier < $1.identifier }
    }

    func task(id: TaskID) async throws -> WorkItem? {
        tasks[id]
    }

    func upsertTask(_ task: WorkItem) async throws {
        tasks[task.id] = task
    }

    func deleteTask(id: TaskID) async throws {
        tasks[id] = nil
    }

    func listRuns(taskID: TaskID?) async throws -> [RunAttempt] {
        runs.values
            .filter { taskID == nil || $0.taskID == taskID }
            .sorted { $0.id.rawValue < $1.id.rawValue }
    }

    func upsertRun(_ run: RunAttempt) async throws {
        runs[run.id] = run
    }

    func appendEvent(_ event: RuntimeEvent) async throws {
        events.append(event)
    }

    func listEvents(taskID: TaskID?, limit: Int) async throws -> [RuntimeEvent] {
        Array(events.filter { taskID == nil || $0.taskID == taskID }.prefix(limit))
    }
}

private final class RecordingWorkflowProvider: WorkflowProvider, @unchecked Sendable {
    private(set) var promptedRun: RunAttempt?

    func prompt(for task: WorkItem, project: Project, run: RunAttempt?) async throws -> String {
        promptedRun = run
        return "Prompt for \(task.identifier) run \(run?.id.rawValue ?? "none") workspace \(run?.workspace?.path ?? "none")"
    }

    func validate(project: Project) async throws -> [WorkflowDiagnostic] {
        []
    }
}

private struct FailingWorkflowProvider: WorkflowProvider {
    func prompt(for task: WorkItem, project: Project, run: RunAttempt?) async throws -> String {
        throw TestError(message: "No workflow")
    }

    func validate(project: Project) async throws -> [WorkflowDiagnostic] {
        []
    }
}

private final class RecordingWorkspaceProvider: WorkspaceProvider, @unchecked Sendable {
    private let workspace: WorkspaceReference
    private(set) var preparedTaskIDs: [TaskID] = []

    init(workspace: WorkspaceReference) {
        self.workspace = workspace
    }

    func prepareWorkspace(for task: WorkItem, project: Project) async throws -> WorkspaceReference {
        preparedTaskIDs.append(task.id)
        return workspace
    }

    func cleanupWorkspace(_ workspace: WorkspaceReference, for task: WorkItem, project: Project) async throws {}
}

private final class RecordingAgentRunner: AgentRunner, @unchecked Sendable {
    var kind: AgentKind
    var capabilities = AgentCapabilities()
    private(set) var requests: [AgentRunRequest] = []
    private(set) var startedRunIDs: [RunID] = []

    init(kind: AgentKind) {
        self.kind = kind
    }

    func start(request: AgentRunRequest, runID: RunID) async throws -> AgentSession {
        requests.append(request)
        startedRunIDs.append(runID)
        return AgentSession(id: AgentSessionID(rawValue: "session-1"), runID: runID)
    }

    func send(_ input: AgentInput, to sessionID: AgentSessionID) async throws {}

    func cancel(sessionID: AgentSessionID) async throws {}

    func events(for sessionID: AgentSessionID) -> AsyncThrowingStream<AgentRunEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

private struct TestError: Error, LocalizedError {
    var message: String
    var errorDescription: String? { message }
}
