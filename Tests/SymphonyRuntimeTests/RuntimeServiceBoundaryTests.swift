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
}
