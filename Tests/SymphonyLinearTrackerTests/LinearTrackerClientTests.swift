import XCTest
import SymphonyCore
@testable import SymphonyLinearTracker

final class LinearTrackerClientTests: XCTestCase {
    func testListReadyTasksMapsLinearIssuesToWorkItems() async throws {
        let projectID = ProjectID(rawValue: "project-1")
        let transport = RecordingLinearTransport(responses: [Self.readyIssuesResponse])
        let client = LinearTrackerClient(
            configuration: LinearTrackerConfiguration(
                apiKey: "linear-key",
                teamID: "team-1",
                localProjectID: projectID,
                projectSlugID: "composer",
                readyStateNames: ["Ready"],
                pageSize: 500
            ),
            transport: transport
        )

        let tasks = try await client.listReadyTasks(projectID: projectID)

        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks[0].id, TaskID(rawValue: "issue-1"))
        XCTAssertEqual(tasks[0].projectID, projectID)
        XCTAssertEqual(tasks[0].identifier, "ENG-1")
        XCTAssertEqual(tasks[0].title, "Ship sync")
        XCTAssertEqual(tasks[0].description, "Wire Linear")
        XCTAssertEqual(tasks[0].state, .ready)
        XCTAssertEqual(tasks[0].priority, .high)
        XCTAssertEqual(tasks[0].labels, ["sync", "agent"])
        XCTAssertEqual(tasks[0].links.first?.kind, "linear")

        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertTrue(requests[0].query.contains("team(id: $teamID)"))
        XCTAssertTrue(requests[0].query.contains("projectSlugID"))
        XCTAssertTrue(requests[0].query.contains("project: { slugId"))
        XCTAssertEqual(requests[0].variables["teamID"], .string("team-1"))
        XCTAssertEqual(requests[0].variables["projectSlugID"], .string("composer"))
        XCTAssertEqual(requests[0].variables["first"], .int(100))
    }

    func testListReadyTasksRequiresProjectSlugID() async {
        let transport = RecordingLinearTransport(responses: [])
        let client = LinearTrackerClient(
            configuration: LinearTrackerConfiguration(
                apiKey: "linear-key",
                teamID: "team-1",
                localProjectID: ProjectID(rawValue: "project-1")
            ),
            transport: transport
        )

        do {
            _ = try await client.listReadyTasks(projectID: nil)
            XCTFail("Expected missing Linear project slug ID error.")
        } catch let error as LinearTrackerError {
            XCTAssertEqual(error, .missingProjectSlugID)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests, [])
    }

    func testListReadyTasksIgnoresOtherLocalProjectIDs() async throws {
        let projectID = ProjectID(rawValue: "project-1")
        let transport = RecordingLinearTransport(responses: [])
        let client = LinearTrackerClient(
            configuration: LinearTrackerConfiguration(
                apiKey: "linear-key",
                teamID: "team-1",
                localProjectID: projectID
            ),
            transport: transport
        )

        let tasks = try await client.listReadyTasks(projectID: ProjectID(rawValue: "other-project"))

        XCTAssertEqual(tasks, [])
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests, [])
    }

    func testUpdateTaskStateUsesConfiguredLinearStateID() async throws {
        let transport = RecordingLinearTransport(responses: [Self.mutationSuccessResponse])
        let client = LinearTrackerClient(
            configuration: LinearTrackerConfiguration(
                apiKey: "linear-key",
                teamID: "team-1",
                localProjectID: ProjectID(rawValue: "project-1"),
                stateIDsByWorkState: [.done: "state-done"]
            ),
            transport: transport
        )

        try await client.updateTaskState(id: TaskID(rawValue: "ENG-1"), state: .done)

        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertTrue(requests[0].query.contains("issueUpdate"))
        XCTAssertEqual(requests[0].variables["id"], .string("ENG-1"))
        XCTAssertEqual(requests[0].variables["stateId"], .string("state-done"))
    }

    func testUpdateTaskStateRequiresStateMapping() async {
        let client = LinearTrackerClient(
            configuration: LinearTrackerConfiguration(
                apiKey: "linear-key",
                teamID: "team-1",
                localProjectID: ProjectID(rawValue: "project-1")
            ),
            transport: RecordingLinearTransport(responses: [])
        )

        do {
            try await client.updateTaskState(id: TaskID(rawValue: "ENG-1"), state: .done)
            XCTFail("Expected missing state mapping error.")
        } catch let error as LinearTrackerError {
            XCTAssertEqual(error, .missingStateMapping(.done))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAnnotateTaskCreatesLinearComment() async throws {
        let transport = RecordingLinearTransport(responses: [Self.commentSuccessResponse])
        let client = LinearTrackerClient(
            configuration: LinearTrackerConfiguration(
                apiKey: "linear-key",
                teamID: "team-1",
                localProjectID: ProjectID(rawValue: "project-1")
            ),
            transport: transport
        )

        try await client.annotateTask(id: TaskID(rawValue: "ENG-1"), message: "Composer note")

        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertTrue(requests[0].query.contains("commentCreate"))
        XCTAssertEqual(requests[0].variables["issueId"], .string("ENG-1"))
        XCTAssertEqual(requests[0].variables["body"], .string("Composer note"))
    }

    func testGraphQLErrorsSurfaceMessages() async {
        let client = LinearTrackerClient(
            configuration: LinearTrackerConfiguration(
                apiKey: "linear-key",
                teamID: "team-1",
                localProjectID: ProjectID(rawValue: "project-1"),
                projectSlugID: "composer"
            ),
            transport: RecordingLinearTransport(responses: [Self.graphQLErrorResponse])
        )

        do {
            _ = try await client.listReadyTasks(projectID: nil)
            XCTFail("Expected GraphQL error.")
        } catch let error as LinearTrackerError {
            XCTAssertEqual(error, .graphQLErrors(["No access"]))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private static let readyIssuesResponse = Data("""
    {
      "data": {
        "team": {
          "issues": {
            "nodes": [
              {
                "id": "issue-1",
                "identifier": "ENG-1",
                "title": "Ship sync",
                "description": "Wire Linear",
                "priority": 2,
                "url": "https://linear.app/acme/issue/ENG-1/ship-sync",
                "createdAt": "2026-01-01T00:00:00Z",
                "updatedAt": "2026-01-02T00:00:00Z",
                "state": { "id": "state-ready", "name": "Ready" },
                "labels": { "nodes": [{ "name": "sync" }, { "name": "agent" }] }
              },
              {
                "id": "issue-2",
                "identifier": "ENG-2",
                "title": "Done task",
                "description": null,
                "priority": 4,
                "url": null,
                "createdAt": "2026-01-01T00:00:00Z",
                "updatedAt": "2026-01-02T00:00:00Z",
                "state": { "id": "state-done", "name": "Done" },
                "labels": { "nodes": [] }
              }
            ]
          }
        }
      }
    }
    """.utf8)

    private static let mutationSuccessResponse = Data("""
    {
      "data": {
        "issueUpdate": {
          "success": true
        }
      }
    }
    """.utf8)

    private static let commentSuccessResponse = Data("""
    {
      "data": {
        "commentCreate": {
          "success": true
        }
      }
    }
    """.utf8)

    private static let graphQLErrorResponse = Data("""
    {
      "errors": [
        { "message": "No access" }
      ]
    }
    """.utf8)
}

private actor RecordingLinearTransport: LinearGraphQLTransport {
    private var responses: [Data]
    private var requests: [LinearGraphQLRequest] = []

    init(responses: [Data]) {
        self.responses = responses
    }

    func send(_ request: LinearGraphQLRequest) async throws -> Data {
        requests.append(request)
        guard !responses.isEmpty else {
            throw LinearTrackerError.invalidResponse
        }

        return responses.removeFirst()
    }

    func recordedRequests() -> [LinearGraphQLRequest] {
        requests
    }
}
