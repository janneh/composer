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
    case taskNotFound(TaskID)
    case runNotFound(RunID)
    case runnerNotFound(AgentKind)
    case sessionNotFound(RunID)
    case workspaceNotFound(RunID)

    public var description: String {
        switch self {
        case let .missingDispatchDependencies(names):
            return "Dispatch requires missing dependencies: \(names.joined(separator: ", "))"
        case let .projectNotFound(projectID):
            return "Project not found for dispatch: \(projectID.rawValue)"
        case let .taskNotFound(taskID):
            return "Task not found: \(taskID.rawValue)"
        case let .runNotFound(runID):
            return "Run not found: \(runID.rawValue)"
        case let .runnerNotFound(kind):
            return "Runner not found: \(kind.title)"
        case let .sessionNotFound(runID):
            return "Run has no active session: \(runID.rawValue)"
        case let .workspaceNotFound(runID):
            return "Run has no workspace to resume: \(runID.rawValue)"
        }
    }

    public var errorDescription: String? {
        description
    }
}

public struct AgentRunEventProjection: Hashable, Sendable {
    public var run: RunAttempt
    public var event: RuntimeEvent

    public init(run: RunAttempt, event: RuntimeEvent) {
        self.run = run
        self.event = event
    }

    public static func project(_ agentEvent: AgentRunEvent, run: RunAttempt, taskID: TaskID, at date: Date) -> AgentRunEventProjection {
        var updatedRun = run
        let runtimeEvent: RuntimeEvent

        switch agentEvent {
        case let .started(message):
            updatedRun.status = .running
            updatedRun.startedAt = updatedRun.startedAt ?? date
            runtimeEvent = RuntimeEvent(
                taskID: taskID,
                runID: run.id,
                kind: .runStarted,
                message: message,
                payload: ["agentEvent": "started"],
                createdAt: date
            )
        case let .progress(message):
            runtimeEvent = RuntimeEvent(
                taskID: taskID,
                runID: run.id,
                kind: .runEvent,
                message: message,
                payload: ["agentEvent": "progress"],
                createdAt: date
            )
        case let .toolUse(name, inputSummary):
            var payload = [
                "agentEvent": "toolUse",
                "toolName": name
            ]
            if let inputSummary {
                payload["inputSummary"] = inputSummary
            }
            runtimeEvent = RuntimeEvent(
                taskID: taskID,
                runID: run.id,
                kind: .runEvent,
                message: "Tool used: \(name)",
                payload: payload,
                createdAt: date
            )
        case let .partialOutput(output):
            runtimeEvent = RuntimeEvent(
                taskID: taskID,
                runID: run.id,
                kind: .runEvent,
                message: "Partial output",
                payload: [
                    "agentEvent": "partialOutput",
                    "output": output
                ],
                createdAt: date
            )
        case let .waitingForInput(prompt):
            updatedRun.status = .waitingForInput
            runtimeEvent = RuntimeEvent(
                taskID: taskID,
                runID: run.id,
                kind: .userInputRequired,
                message: prompt,
                payload: [
                    "agentEvent": "waitingForInput",
                    "prompt": prompt
                ],
                createdAt: date
            )
        case let .completed(summary):
            updatedRun.status = .succeeded
            updatedRun.finishedAt = date
            updatedRun.summary = summary
            runtimeEvent = RuntimeEvent(
                taskID: taskID,
                runID: run.id,
                kind: .runFinished,
                message: summary,
                payload: ["agentEvent": "completed"],
                createdAt: date
            )
        case let .failed(message):
            updatedRun.status = .failed
            updatedRun.finishedAt = date
            updatedRun.summary = message
            runtimeEvent = RuntimeEvent(
                taskID: taskID,
                runID: run.id,
                kind: .runFailed,
                message: message,
                payload: ["agentEvent": "failed"],
                createdAt: date
            )
        }

        return AgentRunEventProjection(run: updatedRun, event: runtimeEvent)
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
                run.resumeToken = session.resumeToken
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

    public func recordAgentEvent(_ agentEvent: AgentRunEvent, taskID: TaskID, runID: RunID) async throws -> RunAttempt {
        let dependencies = try eventRecordingDependencies()
        let runs = try await dependencies.runStore.listRuns(taskID: taskID)
        guard let run = runs.first(where: { $0.id == runID }) else {
            throw OrchestratorError.runNotFound(runID)
        }

        let projection = AgentRunEventProjection.project(agentEvent, run: run, taskID: taskID, at: now())
        try await dependencies.runStore.upsertRun(projection.run)
        try await dependencies.eventStore.appendEvent(projection.event)
        return projection.run
    }

    public func cancelRun(taskID: TaskID, runID: RunID) async throws -> RunAttempt {
        let dependencies = try eventRecordingDependencies()
        var run = try await run(taskID: taskID, runID: runID, runStore: dependencies.runStore)
        guard let sessionID = run.sessionID else {
            throw OrchestratorError.sessionNotFound(runID)
        }
        guard let runner = runners[run.agent.kind] else {
            throw OrchestratorError.runnerNotFound(run.agent.kind)
        }

        try await runner.cancel(sessionID: sessionID)
        let finishedAt = now()
        run.status = .canceled
        run.finishedAt = finishedAt
        run.summary = "Canceled"
        try await dependencies.runStore.upsertRun(run)
        if let task = try await taskStore.task(id: taskID) {
            try await taskStore.upsertTask(task.moving(to: .canceled, at: finishedAt))
        }
        try await dependencies.eventStore.appendEvent(RuntimeEvent(
            taskID: taskID,
            runID: runID,
            kind: .runFinished,
            message: "Run canceled",
            payload: ["agent": run.agent.kind.rawValue],
            createdAt: finishedAt
        ))
        return run
    }

    public func retryTask(id taskID: TaskID) async throws -> WorkItem {
        let dependencies = try eventRecordingDependencies()
        guard let task = try await taskStore.task(id: taskID) else {
            throw OrchestratorError.taskNotFound(taskID)
        }
        let retriedAt = now()
        let retried = task.moving(to: .ready, at: retriedAt)
        try await taskStore.upsertTask(retried)
        try await dependencies.eventStore.appendEvent(RuntimeEvent(
            taskID: taskID,
            kind: .taskMoved,
            message: "Task queued for retry",
            createdAt: retriedAt
        ))
        return retried
    }

    public func markStalledRuns(olderThan interval: TimeInterval) async throws -> [RunAttempt] {
        let dependencies = try eventRecordingDependencies()
        let date = now()
        let runs = try await dependencies.runStore.listRuns(taskID: nil)
        var stalledRuns: [RunAttempt] = []

        for var run in runs where run.status.canStall {
            guard let startedAt = run.startedAt, date.timeIntervalSince(startedAt) >= interval else {
                continue
            }

            run.status = .stalled
            run.finishedAt = date
            run.summary = "Run stalled after \(Int(interval)) seconds without completion."
            try await dependencies.runStore.upsertRun(run)
            try await dependencies.eventStore.appendEvent(RuntimeEvent(
                taskID: run.taskID,
                runID: run.id,
                kind: .runFailed,
                message: "Run stalled",
                payload: ["agent": run.agent.kind.rawValue],
                createdAt: date
            ))
            stalledRuns.append(run)
        }

        return stalledRuns
    }

    public func resumeRun(taskID: TaskID, runID: RunID) async throws -> RunAttempt {
        let dependencies = try dispatchDependencies()
        guard let task = try await taskStore.task(id: taskID) else {
            throw OrchestratorError.taskNotFound(taskID)
        }
        guard let project = try await projectStore.project(id: task.projectID) else {
            throw OrchestratorError.projectNotFound(task.projectID)
        }
        var run = try await run(taskID: taskID, runID: runID, runStore: dependencies.runStore)
        guard let runner = runners[run.agent.kind] else {
            throw OrchestratorError.runnerNotFound(run.agent.kind)
        }
        guard runner.capabilities.supportsResume else {
            throw AgentRunnerCapabilityError.resumeUnsupported(run.agent.kind)
        }
        guard let sessionID = run.sessionID else {
            throw OrchestratorError.sessionNotFound(runID)
        }
        guard let workspace = run.workspace else {
            throw OrchestratorError.workspaceNotFound(runID)
        }

        let prompt = try await dependencies.workflowProvider.prompt(for: task, project: project, run: run)
        let request = AgentRunRequest(
            task: task,
            project: project,
            workflowPrompt: prompt,
            workspacePath: workspace.path,
            agent: run.agent
        )
        let session = try await runner.resume(
            request: request,
            runID: runID,
            session: AgentSession(id: sessionID, runID: runID, resumeToken: run.resumeToken)
        )
        let resumedAt = now()
        run.status = .running
        run.sessionID = session.id
        run.resumeToken = session.resumeToken
        run.finishedAt = nil
        run.startedAt = run.startedAt ?? resumedAt
        try await dependencies.runStore.upsertRun(run)
        try await dependencies.eventStore.appendEvent(RuntimeEvent(
            taskID: taskID,
            runID: runID,
            kind: .runStarted,
            message: "Run resumed",
            payload: ["agent": run.agent.kind.rawValue],
            createdAt: resumedAt
        ))
        return run
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

    private func eventRecordingDependencies() throws -> (runStore: RunStore, eventStore: EventStore) {
        var missing: [String] = []
        if runStore == nil { missing.append("runStore") }
        if eventStore == nil { missing.append("eventStore") }
        guard missing.isEmpty,
              let runStore,
              let eventStore else {
            throw OrchestratorError.missingDispatchDependencies(missing)
        }

        return (runStore, eventStore)
    }

    private func run(taskID: TaskID, runID: RunID, runStore: RunStore) async throws -> RunAttempt {
        let runs = try await runStore.listRuns(taskID: taskID)
        guard let run = runs.first(where: { $0.id == runID }) else {
            throw OrchestratorError.runNotFound(runID)
        }
        return run
    }
}

private extension RunStatus {
    var canStall: Bool {
        switch self {
        case .running, .waitingForInput:
            true
        case .queued, .succeeded, .failed, .canceled, .stalled:
            false
        }
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
