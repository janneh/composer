import Foundation
import SymphonyCore

public protocol RuntimeService: Sendable {
    func previewDispatch(projectID: ProjectID?) async throws -> DispatchPlan
    func dispatchReady(projectID: ProjectID?) async throws -> DispatchExecution
    func cancelRun(taskID: TaskID, runID: RunID) async throws -> RunAttempt
    func retryTask(id taskID: TaskID) async throws -> WorkItem
    func markStalledRuns(olderThan interval: TimeInterval) async throws -> [RunAttempt]
    func resumeRun(taskID: TaskID, runID: RunID) async throws -> RunAttempt
}

public extension RuntimeService {
    func handle(_ request: RuntimeServiceRequest) async throws -> RuntimeServiceResponse {
        switch request {
        case let .previewDispatch(projectID):
            return .dispatchPlan(try await previewDispatch(projectID: projectID))
        case let .dispatchReady(projectID):
            return .dispatchExecution(try await dispatchReady(projectID: projectID))
        case let .cancelRun(taskID, runID):
            return .runAttempt(try await cancelRun(taskID: taskID, runID: runID))
        case let .retryTask(taskID):
            return .workItem(try await retryTask(id: taskID))
        case let .markStalledRuns(interval):
            return .runAttempts(try await markStalledRuns(olderThan: interval))
        case let .resumeRun(taskID, runID):
            return .runAttempt(try await resumeRun(taskID: taskID, runID: runID))
        }
    }
}

public actor LocalRuntimeService: RuntimeService {
    private let orchestrator: Orchestrator

    public init(orchestrator: Orchestrator) {
        self.orchestrator = orchestrator
    }

    public func previewDispatch(projectID: ProjectID?) async throws -> DispatchPlan {
        try await orchestrator.previewDispatch(projectID: projectID)
    }

    public func dispatchReady(projectID: ProjectID?) async throws -> DispatchExecution {
        try await orchestrator.dispatchReady(projectID: projectID)
    }

    public func cancelRun(taskID: TaskID, runID: RunID) async throws -> RunAttempt {
        try await orchestrator.cancelRun(taskID: taskID, runID: runID)
    }

    public func retryTask(id taskID: TaskID) async throws -> WorkItem {
        try await orchestrator.retryTask(id: taskID)
    }

    public func markStalledRuns(olderThan interval: TimeInterval) async throws -> [RunAttempt] {
        try await orchestrator.markStalledRuns(olderThan: interval)
    }

    public func resumeRun(taskID: TaskID, runID: RunID) async throws -> RunAttempt {
        try await orchestrator.resumeRun(taskID: taskID, runID: runID)
    }
}

public enum RuntimeServiceRequest: Codable, Hashable, Sendable {
    case previewDispatch(projectID: ProjectID?)
    case dispatchReady(projectID: ProjectID?)
    case cancelRun(taskID: TaskID, runID: RunID)
    case retryTask(taskID: TaskID)
    case markStalledRuns(olderThan: TimeInterval)
    case resumeRun(taskID: TaskID, runID: RunID)
}

public enum RuntimeServiceResponse: Codable, Hashable, Sendable {
    case dispatchPlan(DispatchPlan)
    case dispatchExecution(DispatchExecution)
    case runAttempt(RunAttempt)
    case runAttempts([RunAttempt])
    case workItem(WorkItem)
}

public enum RuntimeServiceBoundaryError: Error, Equatable, CustomStringConvertible, LocalizedError {
    case unexpectedResponse(expected: String, actual: RuntimeServiceResponse)

    public var description: String {
        switch self {
        case let .unexpectedResponse(expected, actual):
            return "Expected runtime service response \(expected), got \(actual)."
        }
    }

    public var errorDescription: String? {
        description
    }
}

public extension RuntimeServiceResponse {
    func dispatchPlan() throws -> DispatchPlan {
        guard case let .dispatchPlan(plan) = self else {
            throw RuntimeServiceBoundaryError.unexpectedResponse(expected: "dispatchPlan", actual: self)
        }
        return plan
    }

    func dispatchExecution() throws -> DispatchExecution {
        guard case let .dispatchExecution(execution) = self else {
            throw RuntimeServiceBoundaryError.unexpectedResponse(expected: "dispatchExecution", actual: self)
        }
        return execution
    }

    func runAttempt() throws -> RunAttempt {
        guard case let .runAttempt(run) = self else {
            throw RuntimeServiceBoundaryError.unexpectedResponse(expected: "runAttempt", actual: self)
        }
        return run
    }

    func runAttempts() throws -> [RunAttempt] {
        guard case let .runAttempts(runs) = self else {
            throw RuntimeServiceBoundaryError.unexpectedResponse(expected: "runAttempts", actual: self)
        }
        return runs
    }

    func workItem() throws -> WorkItem {
        guard case let .workItem(task) = self else {
            throw RuntimeServiceBoundaryError.unexpectedResponse(expected: "workItem", actual: self)
        }
        return task
    }
}

public enum RuntimeXPCCodec {
    public static func encodeRequest(_ request: RuntimeServiceRequest) throws -> Data {
        try JSONEncoder().encode(request)
    }

    public static func decodeRequest(_ data: Data) throws -> RuntimeServiceRequest {
        try JSONDecoder().decode(RuntimeServiceRequest.self, from: data)
    }

    public static func encodeResponse(_ response: RuntimeServiceResponse) throws -> Data {
        try JSONEncoder().encode(response)
    }

    public static func decodeResponse(_ data: Data) throws -> RuntimeServiceResponse {
        try JSONDecoder().decode(RuntimeServiceResponse.self, from: data)
    }
}

#if canImport(ObjectiveC)
@objc public protocol ComposerRuntimeXPCServicing {
    func handleRuntimeRequest(_ requestData: Data, withReply reply: @escaping (Data?, String?) -> Void)
}

public final class RuntimeServiceXPCAdapter: NSObject, ComposerRuntimeXPCServicing, @unchecked Sendable {
    private let service: any RuntimeService

    public init(service: any RuntimeService) {
        self.service = service
    }

    public func handleRuntimeRequest(_ requestData: Data, withReply reply: @escaping (Data?, String?) -> Void) {
        Task {
            do {
                let request = try RuntimeXPCCodec.decodeRequest(requestData)
                let response = try await service.handle(request)
                reply(try RuntimeXPCCodec.encodeResponse(response), nil)
            } catch {
                reply(nil, error.localizedDescription)
            }
        }
    }
}

public enum RuntimeXPCInterfaceFactory {
    public static func makeInterface() -> NSXPCInterface {
        NSXPCInterface(with: ComposerRuntimeXPCServicing.self)
    }
}
#endif
