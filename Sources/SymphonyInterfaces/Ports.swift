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
    func prompt(for task: WorkItem, project: Project, run: RunAttempt?) async throws -> String
    func validate(project: Project) async throws -> [WorkflowDiagnostic]
}

public extension WorkflowProvider {
    func prompt(for task: WorkItem, project: Project) async throws -> String {
        try await prompt(for: task, project: project, run: nil)
    }
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
    func resume(request: AgentRunRequest, runID: RunID, session: AgentSession) async throws -> AgentSession
    func send(_ input: AgentInput, to sessionID: AgentSessionID) async throws
    func cancel(sessionID: AgentSessionID) async throws
    func events(for sessionID: AgentSessionID) -> AsyncThrowingStream<AgentRunEvent, Error>
}

public enum AgentRunnerCapabilityError: Error, Equatable, CustomStringConvertible, LocalizedError {
    case resumeUnsupported(AgentKind)

    public var description: String {
        switch self {
        case let .resumeUnsupported(kind):
            return "\(kind.title) runner does not support resume."
        }
    }

    public var errorDescription: String? {
        description
    }
}

public extension AgentRunner {
    func resume(request: AgentRunRequest, runID: RunID, session: AgentSession) async throws -> AgentSession {
        throw AgentRunnerCapabilityError.resumeUnsupported(kind)
    }
}

public protocol SyncEngine: Sendable {
    func pull() async throws
    func push() async throws
}

public protocol SyncOutboxStore: Sendable {
    func enqueueSyncOutboxEntry(_ entry: SyncOutboxEntry) async throws
    func listPendingSyncOutboxEntries(limit: Int, now: Date) async throws -> [SyncOutboxEntry]
    func updateSyncOutboxEntry(_ entry: SyncOutboxEntry) async throws
}

public protocol SyncMetadataStore: Sendable {
    func upsertSyncMetadataRecord(_ record: SyncMetadataRecord) async throws
    func syncMetadataRecord(aggregate: SyncOutboxAggregate, aggregateID: String) async throws -> SyncMetadataRecord?
    func upsertSyncCursorRecord(_ record: SyncCursorRecord) async throws
    func syncCursorRecord(scope: String) async throws -> SyncCursorRecord?
}

public protocol SyncOutboxTransport: Sendable {
    func push(_ entry: SyncOutboxEntry) async throws -> SyncOutboxReceipt
}

public protocol SyncCloudTransport: SyncOutboxTransport {
    func pullChanges(since cursor: SyncCursor?, limit: Int) async throws -> SyncPullBatch
}

public protocol RuntimeEventSink: Sendable {
    func emit(_ event: RuntimeEvent) async
}
