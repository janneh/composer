import Foundation
import SymphonyCore
import SymphonyInterfaces

public struct OrchestratorConfiguration: Sendable {
    public var maxConcurrentRuns: Int
    public var dispatchableStates: Set<WorkState>

    public init(
        maxConcurrentRuns: Int = 4,
        dispatchableStates: Set<WorkState> = [.ready]
    ) {
        self.maxConcurrentRuns = maxConcurrentRuns
        self.dispatchableStates = dispatchableStates
    }
}

public struct DispatchPlan: Codable, Hashable, Sendable {
    public var ready: [WorkItem]
    public var blocked: [WorkItem]
    public var missingRunner: [WorkItem]

    public init(ready: [WorkItem], blocked: [WorkItem], missingRunner: [WorkItem]) {
        self.ready = ready
        self.blocked = blocked
        self.missingRunner = missingRunner
    }
}

public struct DispatchExecution: Codable, Hashable, Sendable {
    public var plan: DispatchPlan
    public var startedRuns: [RunAttempt]
    public var failedRuns: [RunAttempt]

    public init(plan: DispatchPlan, startedRuns: [RunAttempt], failedRuns: [RunAttempt]) {
        self.plan = plan
        self.startedRuns = startedRuns
        self.failedRuns = failedRuns
    }
}

public enum OrchestratorError: Error, Equatable, CustomStringConvertible, LocalizedError {
    case missingDispatchDependencies([String])
    case projectNotFound(ProjectID)

    public var description: String {
        switch self {
        case let .missingDispatchDependencies(names):
            return "Dispatch requires missing dependencies: \(names.joined(separator: ", "))"
        case let .projectNotFound(projectID):
            return "Project not found for dispatch: \(projectID.rawValue)"
        }
    }

    public var errorDescription: String? {
        description
    }
}

public actor Orchestrator {
    private let taskStore: TaskStore
    private let projectStore: ProjectStore
    private let runStore: RunStore?
    private let eventStore: EventStore?
    private let workflowProvider: WorkflowProvider?
    private let workspaceProvider: WorkspaceProvider?
    private let configuration: OrchestratorConfiguration
    private let now: @Sendable () -> Date
    private var runners: [AgentKind: any AgentRunner]

    public init(
        taskStore: TaskStore,
        projectStore: ProjectStore,
        runStore: RunStore? = nil,
        eventStore: EventStore? = nil,
        workflowProvider: WorkflowProvider? = nil,
        workspaceProvider: WorkspaceProvider? = nil,
        runners: [any AgentRunner] = [],
        configuration: OrchestratorConfiguration = OrchestratorConfiguration(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.taskStore = taskStore
        self.projectStore = projectStore
        self.runStore = runStore
        self.eventStore = eventStore
        self.workflowProvider = workflowProvider
        self.workspaceProvider = workspaceProvider
        self.configuration = configuration
        self.now = now
        self.runners = Dictionary(uniqueKeysWithValues: runners.map { ($0.kind, $0) })
    }

    public func registerRunner(_ runner: any AgentRunner) {
        runners[runner.kind] = runner
    }

    public func previewDispatch(projectID: ProjectID?) async throws -> DispatchPlan {
        let tasks = try await taskStore.listTasks(projectID: projectID)
        let projects = try await projectStore.listProjects()
        let projectsByID = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
        let tasksByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })

        var ready: [WorkItem] = []
        var blocked: [WorkItem] = []
        var missingRunner: [WorkItem] = []

        for task in tasks where configuration.dispatchableStates.contains(task.state) {
            let unresolvedBlockers = task.blockedBy.compactMap { tasksByID[$0] }.filter { !$0.state.isTerminal }
            guard unresolvedBlockers.isEmpty else {
                blocked.append(task)
                continue
            }

            let agent = task.preferredAgent ?? projectsByID[task.projectID]?.defaultAgent
            guard let agent, runners[agent.kind] != nil else {
                missingRunner.append(task)
                continue
            }

            ready.append(task)
        }

        return DispatchPlan(
            ready: Array(ready.prefix(configuration.maxConcurrentRuns)),
            blocked: blocked,
            missingRunner: missingRunner
        )
    }

    public func dispatchReady(projectID: ProjectID?) async throws -> DispatchExecution {
        let dependencies = try dispatchDependencies()
        let plan = try await previewDispatch(projectID: projectID)
        let projects = try await projectStore.listProjects()
        let projectsByID = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
        var startedRuns: [RunAttempt] = []
        var failedRuns: [RunAttempt] = []

        for task in plan.ready {
            guard let project = projectsByID[task.projectID] else {
                throw OrchestratorError.projectNotFound(task.projectID)
            }

            let agent = task.preferredAgent ?? project.defaultAgent
            guard let runner = runners[agent.kind] else {
                continue
            }

            var run = RunAttempt(taskID: task.id, agent: agent, status: .queued)
            let queuedAt = now()
            try await dependencies.runStore.upsertRun(run)
            try await dependencies.eventStore.appendEvent(RuntimeEvent(
                taskID: task.id,
                runID: run.id,
                kind: .runQueued,
                message: "Run queued",
                payload: ["agent": agent.kind.rawValue],
                createdAt: queuedAt
            ))

            do {
                let workspace = try await dependencies.workspaceProvider.prepareWorkspace(for: task, project: project)
                run.workspace = workspace
                let prompt = try await dependencies.workflowProvider.prompt(for: task, project: project, run: run)
                let request = AgentRunRequest(
                    task: task,
                    project: project,
                    workflowPrompt: prompt,
                    workspacePath: workspace.path,
                    agent: agent
                )
                let session = try await runner.start(request: request, runID: run.id)
                let startedAt = now()
                run.status = .running
                run.sessionID = session.id
                run.startedAt = startedAt
                try await dependencies.runStore.upsertRun(run)
                try await taskStore.upsertTask(task.moving(to: .running, at: startedAt))
                try await dependencies.eventStore.appendEvent(RuntimeEvent(
                    taskID: task.id,
                    runID: run.id,
                    kind: .runStarted,
                    message: "Run started",
                    payload: [
                        "agent": agent.kind.rawValue,
                        "workspacePath": workspace.path
                    ],
                    createdAt: startedAt
                ))
                startedRuns.append(run)
            } catch {
                let failedAt = now()
                run.status = .failed
                run.finishedAt = failedAt
                run.summary = error.localizedDescription
                try await dependencies.runStore.upsertRun(run)
                try await dependencies.eventStore.appendEvent(RuntimeEvent(
                    taskID: task.id,
                    runID: run.id,
                    kind: .runFailed,
                    message: "Run failed: \(error.localizedDescription)",
                    payload: ["agent": agent.kind.rawValue],
                    createdAt: failedAt
                ))
                failedRuns.append(run)
            }
        }

        return DispatchExecution(plan: plan, startedRuns: startedRuns, failedRuns: failedRuns)
    }

    private func dispatchDependencies() throws -> (
        runStore: RunStore,
        eventStore: EventStore,
        workflowProvider: WorkflowProvider,
        workspaceProvider: WorkspaceProvider
    ) {
        var missing: [String] = []
        if runStore == nil { missing.append("runStore") }
        if eventStore == nil { missing.append("eventStore") }
        if workflowProvider == nil { missing.append("workflowProvider") }
        if workspaceProvider == nil { missing.append("workspaceProvider") }
        guard missing.isEmpty,
              let runStore,
              let eventStore,
              let workflowProvider,
              let workspaceProvider else {
            throw OrchestratorError.missingDispatchDependencies(missing)
        }

        return (runStore, eventStore, workflowProvider, workspaceProvider)
    }
}

public struct NoopAgentRunner: AgentRunner {
    public var kind: AgentKind
    public var capabilities: AgentCapabilities

    public init(kind: AgentKind) {
        self.kind = kind
        capabilities = AgentCapabilities(
            supportsStreaming: false,
            supportsResume: false,
            supportsCancellation: true,
            supportsInteractiveInput: false
        )
    }

    public func start(request: AgentRunRequest, runID: RunID) async throws -> AgentSession {
        AgentSession(runID: runID)
    }

    public func send(_ input: AgentInput, to sessionID: AgentSessionID) async throws {}

    public func cancel(sessionID: AgentSessionID) async throws {}

    public func events(for sessionID: AgentSessionID) -> AsyncThrowingStream<AgentRunEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}
