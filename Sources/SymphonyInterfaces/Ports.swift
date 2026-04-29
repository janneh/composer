import Foundation
import SymphonyCore

public typealias ComposerStore = ProjectStore & TaskStore & RunStore & EventStore

public protocol ProjectStore: Sendable {
    func listProjects() async throws -> [Project]
    func project(id: ProjectID) async throws -> Project?
    func upsertProject(_ project: Project) async throws
    func deleteProject(id: ProjectID) async throws
}

public protocol TaskStore: Sendable {
    func listTasks(projectID: ProjectID?) async throws -> [WorkItem]
    func task(id: TaskID) async throws -> WorkItem?
    func upsertTask(_ task: WorkItem) async throws
    func deleteTask(id: TaskID) async throws
}

public protocol RunStore: Sendable {
    func listRuns(taskID: TaskID?) async throws -> [RunAttempt]
    func upsertRun(_ run: RunAttempt) async throws
}

public protocol EventStore: Sendable {
    func appendEvent(_ event: RuntimeEvent) async throws
    func listEvents(taskID: TaskID?, limit: Int) async throws -> [RuntimeEvent]
}

public protocol TrackerClient: Sendable {
    func listReadyTasks(projectID: ProjectID?) async throws -> [WorkItem]
    func updateTaskState(id: TaskID, state: WorkState) async throws
    func annotateTask(id: TaskID, message: String) async throws
}

public protocol WorkflowProvider: Sendable {
    func prompt(for task: WorkItem, project: Project) async throws -> String
    func validate(project: Project) async throws -> [WorkflowDiagnostic]
}

public struct WorkflowDiagnostic: Codable, Hashable, Sendable {
    public enum Severity: String, Codable, Hashable, Sendable {
        case info
        case warning
        case error
    }

    public var severity: Severity
    public var message: String

    public init(severity: Severity, message: String) {
        self.severity = severity
        self.message = message
    }
}

public protocol WorkspaceProvider: Sendable {
    func prepareWorkspace(for task: WorkItem, project: Project) async throws -> WorkspaceReference
    func cleanupWorkspace(_ workspace: WorkspaceReference, for task: WorkItem, project: Project) async throws
}

public protocol AgentRunner: Sendable {
    var kind: AgentKind { get }
    var capabilities: AgentCapabilities { get }

    func start(request: AgentRunRequest, runID: RunID) async throws -> AgentSession
    func send(_ input: AgentInput, to sessionID: AgentSessionID) async throws
    func cancel(sessionID: AgentSessionID) async throws
    func events(for sessionID: AgentSessionID) -> AsyncThrowingStream<AgentRunEvent, Error>
}

public protocol SyncEngine: Sendable {
    func pull() async throws
    func push() async throws
}

public protocol RuntimeEventSink: Sendable {
    func emit(_ event: RuntimeEvent) async
}
