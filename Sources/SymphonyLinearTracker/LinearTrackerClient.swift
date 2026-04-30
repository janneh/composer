import Foundation
import SymphonyCore
import SymphonyInterfaces

public struct LinearTrackerConfiguration: Equatable, Sendable {
    public var apiKey: String
    public var teamID: String
    public var localProjectID: ProjectID
    public var projectSlugID: String?
    public var endpoint: URL
    public var readyStateNames: Set<String>
    public var stateIDsByWorkState: [WorkState: String]
    public var pageSize: Int

    public init(
        apiKey: String,
        teamID: String,
        localProjectID: ProjectID,
        projectSlugID: String? = nil,
        endpoint: URL = URL(string: "https://api.linear.app/graphql")!,
        readyStateNames: Set<String> = ["Ready"],
        stateIDsByWorkState: [WorkState: String] = [:],
        pageSize: Int = 50
    ) {
        self.apiKey = apiKey
        self.teamID = teamID
        self.localProjectID = localProjectID
        self.projectSlugID = Self.trimmedNonEmpty(projectSlugID)
        self.endpoint = endpoint
        self.readyStateNames = Set(readyStateNames.map(Self.normalizedStateName))
        self.stateIDsByWorkState = stateIDsByWorkState
        self.pageSize = min(max(1, pageSize), 100)
    }

    func isReadyState(_ name: String) -> Bool {
        readyStateNames.contains(Self.normalizedStateName(name))
    }

    private static func normalizedStateName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

public enum LinearJSONValue: Equatable, Sendable, Encodable {
    case string(String)
    case int(Int)
    case bool(Bool)
    case array([LinearJSONValue])
    case object([String: LinearJSONValue])
    case null

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value):
            try container.encode(value)
        case let .int(value):
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

public struct LinearGraphQLRequest: Equatable, Sendable, Encodable {
    public var query: String
    public var variables: [String: LinearJSONValue]

    public init(query: String, variables: [String: LinearJSONValue] = [:]) {
        self.query = query
        self.variables = variables
    }
}

public protocol LinearGraphQLTransport: Sendable {
    func send(_ request: LinearGraphQLRequest) async throws -> Data
}

public struct URLSessionLinearGraphQLTransport: LinearGraphQLTransport {
    private let endpoint: URL
    private let apiKey: String

    public init(endpoint: URL, apiKey: String) {
        self.endpoint = endpoint
        self.apiKey = apiKey
    }

    public func send(_ request: LinearGraphQLRequest) async throws -> Data {
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "Authorization")

        let body = try JSONEncoder().encode(request)
        let (data, response) = try await URLSession.shared.upload(for: urlRequest, from: body)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LinearTrackerError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LinearTrackerError.httpStatus(httpResponse.statusCode, body)
        }

        return data
    }
}

public enum LinearTrackerError: Error, Equatable, LocalizedError {
    case graphQLErrors([String])
    case invalidResponse
    case missingProjectSlugID
    case missingStateMapping(WorkState)
    case operationFailed(String)
    case httpStatus(Int, String)

    public var errorDescription: String? {
        switch self {
        case let .graphQLErrors(messages):
            return "Linear GraphQL error: \(messages.joined(separator: "; "))"
        case .invalidResponse:
            return "Linear returned an invalid response."
        case .missingProjectSlugID:
            return "No Linear project slug ID is configured."
        case let .missingStateMapping(state):
            return "No Linear workflow state ID is configured for \(state.title)."
        case let .operationFailed(operation):
            return "Linear operation failed: \(operation)."
        case let .httpStatus(status, body):
            return "Linear HTTP \(status): \(body)"
        }
    }
}

public struct LinearTrackerClient: TrackerClient {
    private let configuration: LinearTrackerConfiguration
    private let transport: any LinearGraphQLTransport

    public init(configuration: LinearTrackerConfiguration) {
        self.init(
            configuration: configuration,
            transport: URLSessionLinearGraphQLTransport(
                endpoint: configuration.endpoint,
                apiKey: configuration.apiKey
            )
        )
    }

    public init(configuration: LinearTrackerConfiguration, transport: any LinearGraphQLTransport) {
        self.configuration = configuration
        self.transport = transport
    }

    public func listReadyTasks(projectID: ProjectID?) async throws -> [WorkItem] {
        guard projectID == nil || projectID == configuration.localProjectID else {
            return []
        }
        guard let projectSlugID = configuration.projectSlugID else {
            throw LinearTrackerError.missingProjectSlugID
        }

        let data = try await perform(
            LinearGraphQLRequest(
                query: Self.readyIssuesQuery,
                variables: [
                    "teamID": .string(configuration.teamID),
                    "projectSlugID": .string(projectSlugID),
                    "first": .int(configuration.pageSize)
                ]
            ),
            as: ReadyIssuesData.self
        )

        return data.team?.issues.nodes
            .filter { configuration.isReadyState($0.state.name) }
            .map { $0.workItem(projectID: configuration.localProjectID) } ?? []
    }

    public func updateTaskState(id: TaskID, state: WorkState) async throws {
        guard let stateID = configuration.stateIDsByWorkState[state] else {
            throw LinearTrackerError.missingStateMapping(state)
        }

        let data = try await perform(
            LinearGraphQLRequest(
                query: Self.updateIssueStateMutation,
                variables: [
                    "id": .string(id.rawValue),
                    "stateId": .string(stateID)
                ]
            ),
            as: UpdateIssueStateData.self
        )

        guard data.issueUpdate.success else {
            throw LinearTrackerError.operationFailed("issueUpdate")
        }
    }

    public func annotateTask(id: TaskID, message: String) async throws {
        let data = try await perform(
            LinearGraphQLRequest(
                query: Self.commentCreateMutation,
                variables: [
                    "issueId": .string(id.rawValue),
                    "body": .string(message)
                ]
            ),
            as: CommentCreateData.self
        )

        guard data.commentCreate.success else {
            throw LinearTrackerError.operationFailed("commentCreate")
        }
    }

    private func perform<Response: Decodable>(
        _ request: LinearGraphQLRequest,
        as type: Response.Type
    ) async throws -> Response {
        let data = try await transport.send(request)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let response = try decoder.decode(GraphQLResponse<Response>.self, from: data)

        if let errors = response.errors, !errors.isEmpty {
            throw LinearTrackerError.graphQLErrors(errors.map(\.message))
        }

        guard let data = response.data else {
            throw LinearTrackerError.invalidResponse
        }

        return data
    }

    private static let readyIssuesQuery = """
    query ComposerLinearReadyIssues($teamID: String!, $projectSlugID: String!, $first: Int!) {
      team(id: $teamID) {
        issues(
          first: $first
          filter: { project: { slugId: { eq: $projectSlugID } } }
        ) {
          nodes {
            id
            identifier
            title
            description
            priority
            url
            createdAt
            updatedAt
            state {
              id
              name
            }
            labels {
              nodes {
                name
              }
            }
          }
        }
      }
    }
    """

    private static let updateIssueStateMutation = """
    mutation ComposerLinearUpdateIssueState($id: String!, $stateId: String!) {
      issueUpdate(id: $id, input: { stateId: $stateId }) {
        success
      }
    }
    """

    private static let commentCreateMutation = """
    mutation ComposerLinearCommentCreate($issueId: String!, $body: String!) {
      commentCreate(input: { issueId: $issueId, body: $body }) {
        success
      }
    }
    """
}

private struct GraphQLResponse<Payload: Decodable>: Decodable {
    var data: Payload?
    var errors: [GraphQLError]?
}

private struct GraphQLError: Decodable {
    var message: String
}

private struct ReadyIssuesData: Decodable {
    var team: LinearTeam?
}

private struct LinearTeam: Decodable {
    var issues: LinearIssueConnection
}

private struct LinearIssueConnection: Decodable {
    var nodes: [LinearIssue]
}

private struct LinearIssue: Decodable {
    var id: String
    var identifier: String
    var title: String
    var description: String?
    var priority: Int?
    var url: URL?
    var createdAt: Date
    var updatedAt: Date
    var state: LinearWorkflowState
    var labels: LinearLabelConnection?

    func workItem(projectID: ProjectID) -> WorkItem {
        WorkItem(
            id: TaskID(rawValue: id),
            projectID: projectID,
            identifier: identifier,
            title: title,
            description: description ?? "",
            state: .ready,
            priority: priority.map(WorkPriority.init(linearPriority:)) ?? .normal,
            labels: labels?.nodes.map(\.name) ?? [],
            links: url.map { [ExternalLink(title: "Linear", url: $0, kind: "linear")] } ?? [],
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

private struct LinearWorkflowState: Decodable {
    var id: String
    var name: String
}

private struct LinearLabelConnection: Decodable {
    var nodes: [LinearLabel]
}

private struct LinearLabel: Decodable {
    var name: String
}

private struct UpdateIssueStateData: Decodable {
    var issueUpdate: LinearMutationPayload
}

private struct CommentCreateData: Decodable {
    var commentCreate: LinearMutationPayload
}

private struct LinearMutationPayload: Decodable {
    var success: Bool
}

private extension WorkPriority {
    init(linearPriority: Int) {
        switch linearPriority {
        case 1:
            self = .urgent
        case 2:
            self = .high
        case 4:
            self = .low
        default:
            self = .normal
        }
    }
}
