import Foundation
import SymphonyCore
import SymphonyInterfaces

public struct GitHubIssuesTrackerConfiguration: Equatable, Sendable {
    public var token: String?
    public var owner: String
    public var repository: String
    public var localProjectID: ProjectID
    public var baseURL: URL
    public var readyLabels: [String]
    public var pageSize: Int

    public init(
        token: String? = nil,
        owner: String,
        repository: String,
        localProjectID: ProjectID,
        baseURL: URL = URL(string: "https://api.github.com")!,
        readyLabels: [String] = ["ready"],
        pageSize: Int = 50
    ) {
        self.token = token
        self.owner = owner
        self.repository = repository
        self.localProjectID = localProjectID
        self.baseURL = baseURL
        self.readyLabels = readyLabels
        self.pageSize = min(max(1, pageSize), 100)
    }
}

public struct GitHubQueryItem: Equatable, Sendable {
    public var name: String
    public var value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

public struct GitHubRESTRequest: Equatable, Sendable {
    public var method: String
    public var path: String
    public var queryItems: [GitHubQueryItem]
    public var body: Data?

    public init(
        method: String,
        path: String,
        queryItems: [GitHubQueryItem] = [],
        body: Data? = nil
    ) {
        self.method = method
        self.path = path
        self.queryItems = queryItems
        self.body = body
    }
}

public protocol GitHubRESTTransport: Sendable {
    func send(_ request: GitHubRESTRequest) async throws -> Data
}

public struct URLSessionGitHubRESTTransport: GitHubRESTTransport {
    private let baseURL: URL
    private let token: String?

    public init(baseURL: URL, token: String?) {
        self.baseURL = baseURL
        self.token = token
    }

    public func send(_ request: GitHubRESTRequest) async throws -> Data {
        guard let relativeURL = URL(string: request.path, relativeTo: baseURL),
              var components = URLComponents(url: relativeURL, resolvingAgainstBaseURL: true) else {
            throw GitHubIssuesTrackerError.invalidRequestPath(request.path)
        }

        if !request.queryItems.isEmpty {
            components.queryItems = request.queryItems.map {
                URLQueryItem(name: $0.name, value: $0.value)
            }
        }

        guard let url = components.url else {
            throw GitHubIssuesTrackerError.invalidRequestPath(request.path)
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        urlRequest.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let token, !token.isEmpty {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubIssuesTrackerError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GitHubIssuesTrackerError.httpStatus(httpResponse.statusCode, body)
        }

        return data
    }
}

public enum GitHubIssuesTrackerError: Error, Equatable, LocalizedError {
    case invalidIssueNumber(String)
    case invalidRequestPath(String)
    case invalidResponse
    case httpStatus(Int, String)

    public var errorDescription: String? {
        switch self {
        case let .invalidIssueNumber(value):
            return "Invalid GitHub issue number: \(value)."
        case let .invalidRequestPath(path):
            return "Invalid GitHub request path: \(path)."
        case .invalidResponse:
            return "GitHub returned an invalid response."
        case let .httpStatus(status, body):
            return "GitHub HTTP \(status): \(body)"
        }
    }
}

public struct GitHubIssuesTrackerClient: TrackerClient {
    private let configuration: GitHubIssuesTrackerConfiguration
    private let transport: any GitHubRESTTransport

    public init(configuration: GitHubIssuesTrackerConfiguration) {
        self.init(
            configuration: configuration,
            transport: URLSessionGitHubRESTTransport(
                baseURL: configuration.baseURL,
                token: configuration.token
            )
        )
    }

    public init(configuration: GitHubIssuesTrackerConfiguration, transport: any GitHubRESTTransport) {
        self.configuration = configuration
        self.transport = transport
    }

    public func listReadyTasks(projectID: ProjectID?) async throws -> [WorkItem] {
        guard projectID == nil || projectID == configuration.localProjectID else {
            return []
        }

        let data = try await transport.send(
            GitHubRESTRequest(
                method: "GET",
                path: issuesPath,
                queryItems: listIssuesQueryItems()
            )
        )
        let decoder = JSONDecoder.github
        let issues = try decoder.decode([GitHubIssue].self, from: data)

        return issues
            .filter { $0.pullRequest == nil }
            .map { $0.workItem(projectID: configuration.localProjectID) }
    }

    public func updateTaskState(id: TaskID, state: WorkState) async throws {
        let issueNumber = try issueNumber(from: id)
        let body = try JSONEncoder().encode(GitHubIssueUpdateRequest(workState: state))
        _ = try await transport.send(
            GitHubRESTRequest(
                method: "PATCH",
                path: "\(issuesPath)/\(issueNumber)",
                body: body
            )
        )
    }

    public func annotateTask(id: TaskID, message: String) async throws {
        let issueNumber = try issueNumber(from: id)
        let body = try JSONEncoder().encode(GitHubIssueCommentRequest(body: message))
        _ = try await transport.send(
            GitHubRESTRequest(
                method: "POST",
                path: "\(issuesPath)/\(issueNumber)/comments",
                body: body
            )
        )
    }

    private var issuesPath: String {
        "/repos/\(configuration.owner.urlPathComponentEscaped)/\(configuration.repository.urlPathComponentEscaped)/issues"
    }

    private func listIssuesQueryItems() -> [GitHubQueryItem] {
        var items = [
            GitHubQueryItem(name: "state", value: "open"),
            GitHubQueryItem(name: "per_page", value: "\(configuration.pageSize)")
        ]

        if !configuration.readyLabels.isEmpty {
            items.append(GitHubQueryItem(name: "labels", value: configuration.readyLabels.joined(separator: ",")))
        }

        return items
    }

    private func issueNumber(from id: TaskID) throws -> Int {
        let rawValue = id.rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard let number = Int(rawValue), number > 0 else {
            throw GitHubIssuesTrackerError.invalidIssueNumber(id.rawValue)
        }
        return number
    }
}

private struct GitHubIssue: Decodable {
    var number: Int
    var title: String
    var body: String?
    var state: String
    var htmlURL: URL
    var createdAt: Date
    var updatedAt: Date
    var labels: [GitHubLabel]
    var pullRequest: GitHubPullRequestMarker?

    enum CodingKeys: String, CodingKey {
        case number
        case title
        case body
        case state
        case htmlURL = "html_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case labels
        case pullRequest = "pull_request"
    }

    func workItem(projectID: ProjectID) -> WorkItem {
        WorkItem(
            id: TaskID(rawValue: "\(number)"),
            projectID: projectID,
            identifier: "#\(number)",
            title: title,
            description: body ?? "",
            state: .ready,
            priority: labels.priority,
            labels: labels.map(\.name),
            links: [ExternalLink(title: "GitHub Issue", url: htmlURL, kind: "github-issue")],
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

private struct GitHubPullRequestMarker: Decodable {}

private struct GitHubLabel: Decodable {
    var name: String
}

private struct GitHubIssueUpdateRequest: Encodable {
    var state: String
    var stateReason: String?

    enum CodingKeys: String, CodingKey {
        case state
        case stateReason = "state_reason"
    }

    init(workState: WorkState) {
        switch workState {
        case .done:
            self.state = "closed"
            self.stateReason = "completed"
        case .canceled:
            self.state = "closed"
            self.stateReason = "not_planned"
        default:
            self.state = "open"
            self.stateReason = "reopened"
        }
    }
}

private struct GitHubIssueCommentRequest: Encodable {
    var body: String
}

private extension Array where Element == GitHubLabel {
    var priority: WorkPriority {
        let normalized = Set(map { $0.name.lowercased() })
        if normalized.contains("priority: urgent") || normalized.contains("urgent") {
            return .urgent
        }
        if normalized.contains("priority: high") || normalized.contains("high priority") {
            return .high
        }
        if normalized.contains("priority: low") || normalized.contains("low priority") {
            return .low
        }
        return .normal
    }
}

private extension JSONDecoder {
    static var github: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension String {
    var urlPathComponentEscaped: String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}
