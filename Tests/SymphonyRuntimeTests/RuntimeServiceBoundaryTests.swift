import Foundation
import XCTest
import SymphonyCore
import SymphonyInterfaces
@testable import SymphonyRuntime

final class RuntimeServiceBoundaryTests: XCTestCase {
    func testLocalRuntimeServiceHandlesTypedRequests() async throws {
        let project = Project(
            id: ProjectID(rawValue: "project-1"),
            name: "Composer",
            defaultAgent: AgentConfiguration(kind: .codex)
        )
        let task = WorkItem(
            id: TaskID(rawValue: "task-1"),
            projectID: project.id,
            identifier: "LOCAL-1",
            title: "Ready task",
            state: .ready
        )
        let store = InMemoryStore(projects: [project], tasks: [task])
        let orchestrator = Orchestrator(
            taskStore: store,
            projectStore: store,
            runners: [NoopAgentRunner(kind: .codex)]
        )
        let service = LocalRuntimeService(orchestrator: orchestrator)

        let response = try await service.handle(.previewDispatch(projectID: project.id))
        let plan = try response.dispatchPlan()

        XCTAssertEqual(plan.ready.map(\.id), [task.id])
        XCTAssertEqual(plan.blocked, [])
        XCTAssertEqual(plan.missingRunner, [])
    }

    func testRuntimeXPCCodecRoundTripsRequestAndResponse() throws {
        let projectID = ProjectID(rawValue: "project-1")
        let request = RuntimeServiceRequest.previewDispatch(projectID: projectID)
        let requestData = try RuntimeXPCCodec.encodeRequest(request)

        XCTAssertEqual(try RuntimeXPCCodec.decodeRequest(requestData), request)

        let response = RuntimeServiceResponse.dispatchPlan(
            DispatchPlan(ready: [], blocked: [], missingRunner: [])
        )
        let responseData = try RuntimeXPCCodec.encodeResponse(response)

        XCTAssertEqual(try RuntimeXPCCodec.decodeResponse(responseData), response)
    }

    func testRuntimeXPCAdapterReturnsEncodedResponse() async throws {
        let project = Project(
            id: ProjectID(rawValue: "project-1"),
            name: "Composer",
            defaultAgent: AgentConfiguration(kind: .codex)
        )
        let task = WorkItem(
            id: TaskID(rawValue: "task-1"),
            projectID: project.id,
            identifier: "LOCAL-1",
            title: "Ready task",
            state: .ready
        )
        let store = InMemoryStore(projects: [project], tasks: [task])
        let orchestrator = Orchestrator(
            taskStore: store,
            projectStore: store,
            runners: [NoopAgentRunner(kind: .codex)]
        )
        let service = LocalRuntimeService(orchestrator: orchestrator)
        let adapter = RuntimeServiceXPCAdapter(service: service)
        let requestData = try RuntimeXPCCodec.encodeRequest(.previewDispatch(projectID: project.id))

        let (responseData, errorMessage) = await withCheckedContinuation { continuation in
            adapter.handleRuntimeRequest(requestData) { responseData, errorMessage in
                continuation.resume(returning: (responseData, errorMessage))
            }
        }

        XCTAssertNil(errorMessage)
        let data = try XCTUnwrap(responseData)
        let plan = try RuntimeXPCCodec.decodeResponse(data).dispatchPlan()
        XCTAssertEqual(plan.ready.map(\.id), [task.id])
    }

    func testFallbackRuntimeServiceUsesFallbackWhenPrimaryMatchesPolicy() async throws {
        let fallbackPlan = DispatchPlan(ready: [], blocked: [], missingRunner: [])
        let service = FallbackRuntimeService(
            primary: ThrowingRuntimeService(error: RuntimeXPCClientError.invalidProxy),
            fallback: StaticRuntimeService(plan: fallbackPlan),
            shouldFallback: { error in
                error.localizedDescription == RuntimeXPCClientError.invalidProxy.localizedDescription
            }
        )

        let plan = try await service.previewDispatch(projectID: nil)

        XCTAssertEqual(plan, fallbackPlan)
    }
}

private struct StaticRuntimeService: RuntimeService {
    var plan: DispatchPlan

    func previewDispatch(projectID: ProjectID?) async throws -> DispatchPlan {
        plan
    }

    func dispatchReady(projectID: ProjectID?) async throws -> DispatchExecution {
        DispatchExecution(plan: plan, startedRuns: [], failedRuns: [])
    }

    func cancelRun(taskID: TaskID, runID: RunID) async throws -> RunAttempt {
        RunAttempt(taskID: taskID, agent: AgentConfiguration(kind: .codex))
    }

    func retryTask(id taskID: TaskID) async throws -> WorkItem {
        WorkItem(projectID: ProjectID(rawValue: "project-1"), identifier: "LOCAL-1", title: "Task")
    }

    func markStalledRuns(olderThan interval: TimeInterval) async throws -> [RunAttempt] {
        []
    }

    func resumeRun(taskID: TaskID, runID: RunID) async throws -> RunAttempt {
        RunAttempt(taskID: taskID, agent: AgentConfiguration(kind: .codex))
    }
}

private struct ThrowingRuntimeService: RuntimeService {
    var error: Error

    func previewDispatch(projectID: ProjectID?) async throws -> DispatchPlan {
        throw error
    }

    func dispatchReady(projectID: ProjectID?) async throws -> DispatchExecution {
        throw error
    }

    func cancelRun(taskID: TaskID, runID: RunID) async throws -> RunAttempt {
        throw error
    }

    func retryTask(id taskID: TaskID) async throws -> WorkItem {
        throw error
    }

    func markStalledRuns(olderThan interval: TimeInterval) async throws -> [RunAttempt] {
        throw error
    }

    func resumeRun(taskID: TaskID, runID: RunID) async throws -> RunAttempt {
        throw error
    }
}
