import XCTest
import SymphonyCore
@testable import SymphonyGitHubIssuesTracker

final class GitHubIssuesTrackerClientTests: XCTestCase {
    func testListReadyTasksMapsGitHubIssuesAndSkipsPullRequests() async throws {
        let projectID = ProjectID(rawValue: "project-1")
        let transport = RecordingGitHubTransport(responses: [Self.issuesResponse])
        let client = GitHubIssuesTrackerClient(
            configuration: GitHubIssuesTrackerConfiguration(
                token: "github-token",
                owner: "acme",
                repository: "composer",
                localProjectID: projectID,
                readyLabels: ["ready"],
                pageSize: 500
            ),
            transport: transport
        )

        let tasks = try await client.listReadyTasks(projectID: projectID)

        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks[0].id, TaskID(rawValue: "12"))
        XCTAssertEqual(tasks[0].projectID, projectID)
        XCTAssertEqual(tasks[0].identifier, "#12")
        XCTAssertEqual(tasks[0].title, "Ship GitHub adapter")
        XCTAssertEqual(tasks[0].description, "Map issues")
        XCTAssertEqual(tasks[0].state, .ready)
        XCTAssertEqual(tasks[0].priority, .high)
        XCTAssertEqual(tasks[0].labels, ["ready", "priority: high"])
        XCTAssertEqual(tasks[0].links.first?.kind, "github-issue")

        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].method, "GET")
        XCTAssertEqual(requests[0].path, "/repos/acme/composer/issues")
        XCTAssertEqual(requests[0].queryItems, [
            GitHubQueryItem(name: "state", value: "open"),
            GitHubQueryItem(name: "per_page", value: "100"),
            GitHubQueryItem(name: "labels", value: "ready")
        ])
    }

    func testListReadyTasksIgnoresOtherLocalProjectIDs() async throws {
        let projectID = ProjectID(rawValue: "project-1")
        let transport = RecordingGitHubTransport(responses: [])
        let client = GitHubIssuesTrackerClient(
            configuration: GitHubIssuesTrackerConfiguration(
                owner: "acme",
                repository: "composer",
                localProjectID: projectID
            ),
            transport: transport
        )

        let tasks = try await client.listReadyTasks(projectID: ProjectID(rawValue: "other-project"))

        XCTAssertEqual(tasks, [])
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests, [])
    }

    func testUpdateTaskStateClosesDoneIssuesAsCompleted() async throws {
        let transport = RecordingGitHubTransport(responses: [Self.issueResponse])
        let client = GitHubIssuesTrackerClient(
            configuration: GitHubIssuesTrackerConfiguration(
                owner: "acme",
                repository: "composer",
                localProjectID: ProjectID(rawValue: "project-1")
            ),
            transport: transport
        )

        try await client.updateTaskState(id: TaskID(rawValue: "12"), state: .done)

        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].method, "PATCH")
        XCTAssertEqual(requests[0].path, "/repos/acme/composer/issues/12")
        let body = try XCTUnwrap(requests[0].jsonBody)
        XCTAssertEqual(body["state"] as? String, "closed")
        XCTAssertEqual(body["state_reason"] as? String, "completed")
    }

    func testUpdateTaskStateRejectsInvalidIssueNumber() async {
        let client = GitHubIssuesTrackerClient(
            configuration: GitHubIssuesTrackerConfiguration(
                owner: "acme",
                repository: "composer",
                localProjectID: ProjectID(rawValue: "project-1")
            ),
            transport: RecordingGitHubTransport(responses: [])
        )

        do {
            try await client.updateTaskState(id: TaskID(rawValue: "not-a-number"), state: .done)
            XCTFail("Expected invalid issue number.")
        } catch let error as GitHubIssuesTrackerError {
            XCTAssertEqual(error, .invalidIssueNumber("not-a-number"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAnnotateTaskCreatesIssueComment() async throws {
        let transport = RecordingGitHubTransport(responses: [Self.commentResponse])
        let client = GitHubIssuesTrackerClient(
            configuration: GitHubIssuesTrackerConfiguration(
                owner: "acme",
                repository: "composer",
                localProjectID: ProjectID(rawValue: "project-1")
            ),
            transport: transport
        )

        try await client.annotateTask(id: TaskID(rawValue: "#12"), message: "Composer note")

        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].method, "POST")
        XCTAssertEqual(requests[0].path, "/repos/acme/composer/issues/12/comments")
        let body = try XCTUnwrap(requests[0].jsonBody)
        XCTAssertEqual(body["body"] as? String, "Composer note")
    }

    private static let issuesResponse = Data("""
    [
      {
        "number": 12,
        "title": "Ship GitHub adapter",
        "body": "Map issues",
        "state": "open",
        "html_url": "https://github.com/acme/composer/issues/12",
        "created_at": "2026-01-01T00:00:00Z",
        "updated_at": "2026-01-02T00:00:00Z",
        "labels": [{ "name": "ready" }, { "name": "priority: high" }]
      },
      {
        "number": 13,
        "title": "Pull request",
        "body": null,
        "state": "open",
        "html_url": "https://github.com/acme/composer/pull/13",
        "created_at": "2026-01-01T00:00:00Z",
        "updated_at": "2026-01-02T00:00:00Z",
        "labels": [{ "name": "ready" }],
        "pull_request": { "url": "https://api.github.com/repos/acme/composer/pulls/13" }
      }
    ]
    """.utf8)

    private static let issueResponse = Data("""
    {
      "number": 12,
      "title": "Ship GitHub adapter"
    }
    """.utf8)

    private static let commentResponse = Data("""
    {
      "id": 100,
      "body": "Composer note"
    }
    """.utf8)
}

private actor RecordingGitHubTransport: GitHubRESTTransport {
    private var responses: [Data]
    private var requests: [GitHubRESTRequest] = []

    init(responses: [Data]) {
        self.responses = responses
    }

    func send(_ request: GitHubRESTRequest) async throws -> Data {
        requests.append(request)
        guard !responses.isEmpty else {
            throw GitHubIssuesTrackerError.invalidResponse
        }

        return responses.removeFirst()
    }

    func recordedRequests() -> [GitHubRESTRequest] {
        requests
    }
}

private extension GitHubRESTRequest {
    var jsonBody: [String: Any]? {
        guard let body else {
            return nil
        }

        return try? JSONSerialization.jsonObject(with: body) as? [String: Any]
    }
}
