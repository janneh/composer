import Foundation

public enum WorkState: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case backlog
    case ready
    case running
    case humanReview
    case merging
    case done
    case failed
    case blocked
    case canceled

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .backlog: "Backlog"
        case .ready: "Ready"
        case .running: "Running"
        case .humanReview: "Human Review"
        case .merging: "Merging"
        case .done: "Done"
        case .failed: "Failed"
        case .blocked: "Blocked"
        case .canceled: "Canceled"
        }
    }

    public var canDispatch: Bool {
        self == .ready
    }

    public var isTerminal: Bool {
        switch self {
        case .done, .canceled:
            true
        case .backlog, .ready, .running, .humanReview, .merging, .failed, .blocked:
            false
        }
    }

    public static let boardStates: [WorkState] = [
        .backlog,
        .ready,
        .running,
        .humanReview,
        .merging,
        .done
    ]
}

public enum WorkPriority: Int, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case low = 0
    case normal = 1
    case high = 2
    case urgent = 3

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .low: "Low"
        case .normal: "Normal"
        case .high: "High"
        case .urgent: "Urgent"
        }
    }
}

public enum AgentKind: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case codex
    case claude
    case gemini
    case custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude"
        case .gemini: "Gemini"
        case .custom: "Custom"
        }
    }
}

public struct AgentConfiguration: Codable, Hashable, Sendable {
    public var kind: AgentKind
    public var model: String?
    public var profile: String?
    public var parameters: [String: String]

    public init(
        kind: AgentKind,
        model: String? = nil,
        profile: String? = nil,
        parameters: [String: String] = [:]
    ) {
        self.kind = kind
        self.model = model
        self.profile = profile
        self.parameters = parameters
    }
}

public struct Project: Identifiable, Codable, Hashable, Sendable {
    public var id: ProjectID
    public var name: String
    public var repositoryPath: String?
    public var workflowPath: String?
    public var defaultAgent: AgentConfiguration
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: ProjectID = ProjectID(),
        name: String,
        repositoryPath: String? = nil,
        workflowPath: String? = nil,
        defaultAgent: AgentConfiguration = AgentConfiguration(kind: .codex),
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.repositoryPath = repositoryPath
        self.workflowPath = workflowPath
        self.defaultAgent = defaultAgent
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct ExternalLink: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var url: URL
    public var kind: String

    public init(id: String = UUID().uuidString, title: String, url: URL, kind: String) {
        self.id = id
        self.title = title
        self.url = url
        self.kind = kind
    }
}

public struct WorkItem: Identifiable, Codable, Hashable, Sendable {
    public var id: TaskID
    public var projectID: ProjectID
    public var identifier: String
    public var title: String
    public var description: String
    public var state: WorkState
    public var priority: WorkPriority
    public var labels: [String]
    public var blockedBy: [TaskID]
    public var preferredAgent: AgentConfiguration?
    public var links: [ExternalLink]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: TaskID = TaskID(),
        projectID: ProjectID,
        identifier: String,
        title: String,
        description: String = "",
        state: WorkState = .backlog,
        priority: WorkPriority = .normal,
        labels: [String] = [],
        blockedBy: [TaskID] = [],
        preferredAgent: AgentConfiguration? = nil,
        links: [ExternalLink] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.projectID = projectID
        self.identifier = identifier
        self.title = title
        self.description = description
        self.state = state
        self.priority = priority
        self.labels = labels
        self.blockedBy = blockedBy
        self.preferredAgent = preferredAgent
        self.links = links
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func moving(to state: WorkState, at date: Date = Date()) -> WorkItem {
        var copy = self
        copy.state = state
        copy.updatedAt = date
        return copy
    }
}

public enum RunStatus: String, Codable, Hashable, Identifiable, Sendable {
    case queued
    case running
    case waitingForInput
    case succeeded
    case failed
    case canceled
    case stalled

    public var id: String { rawValue }
}

public enum WorkspaceCleanupPolicy: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case keep
    case removeOnSuccess
    case removeOnCompletion

    public var id: String { rawValue }
}

public struct WorkspaceReference: Codable, Hashable, Sendable {
    public var path: String
    public var cleanupPolicy: WorkspaceCleanupPolicy
    public var preparedAt: Date

    public init(
        path: String,
        cleanupPolicy: WorkspaceCleanupPolicy = .keep,
        preparedAt: Date = Date()
    ) {
        self.path = path
        self.cleanupPolicy = cleanupPolicy
        self.preparedAt = preparedAt
    }
}

public struct RunAttempt: Identifiable, Codable, Hashable, Sendable {
    public var id: RunID
    public var taskID: TaskID
    public var agent: AgentConfiguration
    public var status: RunStatus
    public var sessionID: AgentSessionID?
    public var resumeToken: String?
    public var workspace: WorkspaceReference?
    public var startedAt: Date?
    public var finishedAt: Date?
    public var summary: String?

    public init(
        id: RunID = RunID(),
        taskID: TaskID,
        agent: AgentConfiguration,
        status: RunStatus = .queued,
        sessionID: AgentSessionID? = nil,
        resumeToken: String? = nil,
        workspace: WorkspaceReference? = nil,
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        summary: String? = nil
    ) {
        self.id = id
        self.taskID = taskID
        self.agent = agent
        self.status = status
        self.sessionID = sessionID
        self.resumeToken = resumeToken
        self.workspace = workspace
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.summary = summary
    }
}

public enum RuntimeEventKind: String, Codable, Hashable, Sendable {
    case taskCreated
    case taskUpdated
    case taskMoved
    case taskDeleted
    case runQueued
    case runStarted
    case runEvent
    case runFinished
    case runFailed
    case userInputRequired
}

public struct RuntimeEvent: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var taskID: TaskID?
    public var runID: RunID?
    public var kind: RuntimeEventKind
    public var message: String
    public var payload: [String: String]
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        taskID: TaskID? = nil,
        runID: RunID? = nil,
        kind: RuntimeEventKind,
        message: String,
        payload: [String: String] = [:],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.taskID = taskID
        self.runID = runID
        self.kind = kind
        self.message = message
        self.payload = payload
        self.createdAt = createdAt
    }
}

public enum SyncOutboxAggregate: String, Codable, Hashable, Sendable {
    case project
    case task
    case run
    case event
    case custom
}

public enum SyncOutboxOperation: String, Codable, Hashable, Sendable {
    case create
    case update
    case delete
    case append
}

public enum SyncOutboxStatus: String, Codable, Hashable, Sendable {
    case pending
    case inFlight
    case sent
    case failed
}

public struct SyncOutboxReceipt: Codable, Hashable, Sendable {
    public var externalReference: String?
    public var metadata: [String: String]

    public init(externalReference: String? = nil, metadata: [String: String] = [:]) {
        self.externalReference = externalReference
        self.metadata = metadata
    }
}

public struct SyncRecordVersion: Codable, Hashable, Sendable {
    public var revision: String?
    public var updatedAt: Date?

    public init(revision: String? = nil, updatedAt: Date? = nil) {
        self.revision = revision
        self.updatedAt = updatedAt
    }
}

public struct SyncCursor: RawRepresentable, Codable, Hashable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.rawValue = value
    }
}

public struct SyncRemoteChange: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var aggregate: SyncOutboxAggregate
    public var aggregateID: String
    public var operation: SyncOutboxOperation
    public var payload: [String: String]
    public var version: SyncRecordVersion
    public var externalReference: String?
    public var isDeleted: Bool
    public var receivedAt: Date

    public init(
        id: String = UUID().uuidString,
        aggregate: SyncOutboxAggregate,
        aggregateID: String,
        operation: SyncOutboxOperation,
        payload: [String: String] = [:],
        version: SyncRecordVersion = SyncRecordVersion(),
        externalReference: String? = nil,
        isDeleted: Bool = false,
        receivedAt: Date = Date()
    ) {
        self.id = id
        self.aggregate = aggregate
        self.aggregateID = aggregateID
        self.operation = operation
        self.payload = payload
        self.version = version
        self.externalReference = externalReference
        self.isDeleted = isDeleted
        self.receivedAt = receivedAt
    }
}

public struct SyncPullBatch: Codable, Hashable, Sendable {
    public var changes: [SyncRemoteChange]
    public var nextCursor: SyncCursor?
    public var hasMore: Bool

    public init(
        changes: [SyncRemoteChange],
        nextCursor: SyncCursor? = nil,
        hasMore: Bool = false
    ) {
        self.changes = changes
        self.nextCursor = nextCursor
        self.hasMore = hasMore
    }
}

public struct SyncMetadataRecord: Identifiable, Codable, Hashable, Sendable {
    public var aggregate: SyncOutboxAggregate
    public var aggregateID: String
    public var externalReference: String?
    public var version: SyncRecordVersion
    public var lastPulledAt: Date?
    public var lastPushedAt: Date?
    public var hasLocalChanges: Bool
    public var updatedAt: Date

    public var id: String {
        "\(aggregate.rawValue):\(aggregateID)"
    }

    public init(
        aggregate: SyncOutboxAggregate,
        aggregateID: String,
        externalReference: String? = nil,
        version: SyncRecordVersion = SyncRecordVersion(),
        lastPulledAt: Date? = nil,
        lastPushedAt: Date? = nil,
        hasLocalChanges: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.aggregate = aggregate
        self.aggregateID = aggregateID
        self.externalReference = externalReference
        self.version = version
        self.lastPulledAt = lastPulledAt
        self.lastPushedAt = lastPushedAt
        self.hasLocalChanges = hasLocalChanges
        self.updatedAt = updatedAt
    }
}

public struct SyncCursorRecord: Identifiable, Codable, Hashable, Sendable {
    public var scope: String
    public var cursor: SyncCursor?
    public var updatedAt: Date

    public var id: String {
        scope
    }

    public init(
        scope: String,
        cursor: SyncCursor? = nil,
        updatedAt: Date = Date()
    ) {
        self.scope = scope
        self.cursor = cursor
        self.updatedAt = updatedAt
    }
}

public struct SyncOutboxEntry: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var aggregate: SyncOutboxAggregate
    public var aggregateID: String
    public var operation: SyncOutboxOperation
    public var payload: [String: String]
    public var status: SyncOutboxStatus
    public var attemptCount: Int
    public var availableAt: Date
    public var lastError: String?
    public var externalReference: String?
    public var receiptMetadata: [String: String]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        aggregate: SyncOutboxAggregate,
        aggregateID: String,
        operation: SyncOutboxOperation,
        payload: [String: String] = [:],
        status: SyncOutboxStatus = .pending,
        attemptCount: Int = 0,
        availableAt: Date = Date(),
        lastError: String? = nil,
        externalReference: String? = nil,
        receiptMetadata: [String: String] = [:],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.aggregate = aggregate
        self.aggregateID = aggregateID
        self.operation = operation
        self.payload = payload
        self.status = status
        self.attemptCount = attemptCount
        self.availableAt = availableAt
        self.lastError = lastError
        self.externalReference = externalReference
        self.receiptMetadata = receiptMetadata
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct AgentCapabilities: Codable, Hashable, Sendable {
    public var supportsStreaming: Bool
    public var supportsResume: Bool
    public var supportsCancellation: Bool
    public var supportsInteractiveInput: Bool

    public init(
        supportsStreaming: Bool = true,
        supportsResume: Bool = false,
        supportsCancellation: Bool = true,
        supportsInteractiveInput: Bool = false
    ) {
        self.supportsStreaming = supportsStreaming
        self.supportsResume = supportsResume
        self.supportsCancellation = supportsCancellation
        self.supportsInteractiveInput = supportsInteractiveInput
    }
}

public struct AgentRunRequest: Codable, Hashable, Sendable {
    public var task: WorkItem
    public var project: Project
    public var workflowPrompt: String
    public var workspacePath: String
    public var agent: AgentConfiguration
    public var environment: [String: String]

    public init(
        task: WorkItem,
        project: Project,
        workflowPrompt: String,
        workspacePath: String,
        agent: AgentConfiguration,
        environment: [String: String] = [:]
    ) {
        self.task = task
        self.project = project
        self.workflowPrompt = workflowPrompt
        self.workspacePath = workspacePath
        self.agent = agent
        self.environment = environment
    }
}

public struct AgentSession: Identifiable, Codable, Hashable, Sendable {
    public var id: AgentSessionID
    public var runID: RunID
    public var resumeToken: String?

    public init(id: AgentSessionID = AgentSessionID(), runID: RunID, resumeToken: String? = nil) {
        self.id = id
        self.runID = runID
        self.resumeToken = resumeToken
    }
}

public enum AgentInput: Codable, Hashable, Sendable {
    case userMessage(String)
    case approval(granted: Bool, reason: String?)
}

public enum AgentRunEvent: Codable, Hashable, Sendable {
    case started(message: String)
    case progress(message: String)
    case toolUse(name: String, inputSummary: String?)
    case partialOutput(String)
    case waitingForInput(prompt: String)
    case completed(summary: String)
    case failed(message: String)
}
