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

public actor Orchestrator {
    private let taskStore: TaskStore
    private let projectStore: ProjectStore
    private let configuration: OrchestratorConfiguration
    private var runners: [AgentKind: any AgentRunner]

    public init(
        taskStore: TaskStore,
        projectStore: ProjectStore,
        runners: [any AgentRunner] = [],
        configuration: OrchestratorConfiguration = OrchestratorConfiguration()
    ) {
        self.taskStore = taskStore
        self.projectStore = projectStore
        self.configuration = configuration
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
