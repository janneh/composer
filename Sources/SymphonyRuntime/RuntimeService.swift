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

public actor FallbackRuntimeService: RuntimeService {
    private let primary: any RuntimeService
    private let fallback: any RuntimeService
    private let shouldFallback: @Sendable (Error) -> Bool

    public init(
        primary: any RuntimeService,
        fallback: any RuntimeService,
        shouldFallback: @escaping @Sendable (Error) -> Bool
    ) {
        self.primary = primary
        self.fallback = fallback
        self.shouldFallback = shouldFallback
    }

    public func previewDispatch(projectID: ProjectID?) async throws -> DispatchPlan {
        try await call(primary: { try await primary.previewDispatch(projectID: projectID) },
                       fallback: { try await fallback.previewDispatch(projectID: projectID) })
    }

    public func dispatchReady(projectID: ProjectID?) async throws -> DispatchExecution {
        try await call(primary: { try await primary.dispatchReady(projectID: projectID) },
                       fallback: { try await fallback.dispatchReady(projectID: projectID) })
    }

    public func cancelRun(taskID: TaskID, runID: RunID) async throws -> RunAttempt {
        try await call(primary: { try await primary.cancelRun(taskID: taskID, runID: runID) },
                       fallback: { try await fallback.cancelRun(taskID: taskID, runID: runID) })
    }

    public func retryTask(id taskID: TaskID) async throws -> WorkItem {
        try await call(primary: { try await primary.retryTask(id: taskID) },
                       fallback: { try await fallback.retryTask(id: taskID) })
    }

    public func markStalledRuns(olderThan interval: TimeInterval) async throws -> [RunAttempt] {
        try await call(primary: { try await primary.markStalledRuns(olderThan: interval) },
                       fallback: { try await fallback.markStalledRuns(olderThan: interval) })
    }

    public func resumeRun(taskID: TaskID, runID: RunID) async throws -> RunAttempt {
        try await call(primary: { try await primary.resumeRun(taskID: taskID, runID: runID) },
                       fallback: { try await fallback.resumeRun(taskID: taskID, runID: runID) })
    }

    private func call<T>(
        primary: () async throws -> T,
        fallback: () async throws -> T
    ) async throws -> T {
        do {
            return try await primary()
        } catch {
            guard shouldFallback(error) else {
                throw error
            }
            return try await fallback()
        }
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

public struct RuntimeServiceStoreContext: Codable, Hashable, Sendable {
    public var backend: String
    public var path: String?

    public init(backend: String, path: String?) {
        self.backend = backend
        self.path = path
    }
}

public struct RuntimeServiceEnvelope: Codable, Hashable, Sendable {
    public var request: RuntimeServiceRequest
    public var storeContext: RuntimeServiceStoreContext?

    public init(request: RuntimeServiceRequest, storeContext: RuntimeServiceStoreContext? = nil) {
        self.request = request
        self.storeContext = storeContext
    }
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

public enum RuntimeXPCClientError: Error, Equatable, CustomStringConvertible, LocalizedError {
    case invalidProxy
    case missingResponse
    case remoteError(String)

    public var description: String {
        switch self {
        case .invalidProxy:
            return "Could not create runtime XPC service proxy."
        case .missingResponse:
            return "Runtime XPC service returned no response."
        case let .remoteError(message):
            return message
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
    public static func encodeRequest(
        _ request: RuntimeServiceRequest,
        storeContext: RuntimeServiceStoreContext? = nil
    ) throws -> Data {
        try JSONEncoder().encode(RuntimeServiceEnvelope(request: request, storeContext: storeContext))
    }

    public static func decodeEnvelope(_ data: Data) throws -> RuntimeServiceEnvelope {
        let decoder = JSONDecoder()
        if let envelope = try? decoder.decode(RuntimeServiceEnvelope.self, from: data) {
            return envelope
        }

        return RuntimeServiceEnvelope(request: try decoder.decode(RuntimeServiceRequest.self, from: data))
    }

    public static func decodeRequest(_ data: Data) throws -> RuntimeServiceRequest {
        try decodeEnvelope(data).request
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
    private let serviceFactory: @Sendable (RuntimeServiceStoreContext?) async throws -> any RuntimeService

    public init(service: any RuntimeService) {
        self.serviceFactory = { _ in service }
    }

    public init(
        serviceFactory: @escaping @Sendable (RuntimeServiceStoreContext?) async throws -> any RuntimeService
    ) {
        self.serviceFactory = serviceFactory
    }

    public func handleRuntimeRequest(_ requestData: Data, withReply reply: @escaping (Data?, String?) -> Void) {
        Task {
            do {
                let envelope = try RuntimeXPCCodec.decodeEnvelope(requestData)
                let service = try await serviceFactory(envelope.storeContext)
                let response = try await service.handle(envelope.request)
                reply(try RuntimeXPCCodec.encodeResponse(response), nil)
            } catch {
                reply(nil, error.localizedDescription)
            }
        }
    }
}

public final class RuntimeXPCClient: RuntimeService, @unchecked Sendable {
    public static let defaultMachServiceName = "dev.janneh.composer.runtime"

    private let machServiceName: String
    public let storeContext: RuntimeServiceStoreContext?
    private let lock = NSLock()
    private var connection: NSXPCConnection?

    public init(
        machServiceName: String = RuntimeXPCClient.defaultMachServiceName,
        storeContext: RuntimeServiceStoreContext? = nil
    ) {
        self.machServiceName = machServiceName
        self.storeContext = storeContext
    }

    deinit {
        connection?.invalidate()
    }

    public func previewDispatch(projectID: ProjectID?) async throws -> DispatchPlan {
        try await send(.previewDispatch(projectID: projectID)).dispatchPlan()
    }

    public func dispatchReady(projectID: ProjectID?) async throws -> DispatchExecution {
        try await send(.dispatchReady(projectID: projectID)).dispatchExecution()
    }

    public func cancelRun(taskID: TaskID, runID: RunID) async throws -> RunAttempt {
        try await send(.cancelRun(taskID: taskID, runID: runID)).runAttempt()
    }

    public func retryTask(id taskID: TaskID) async throws -> WorkItem {
        try await send(.retryTask(taskID: taskID)).workItem()
    }

    public func markStalledRuns(olderThan interval: TimeInterval) async throws -> [RunAttempt] {
        try await send(.markStalledRuns(olderThan: interval)).runAttempts()
    }

    public func resumeRun(taskID: TaskID, runID: RunID) async throws -> RunAttempt {
        try await send(.resumeRun(taskID: taskID, runID: runID)).runAttempt()
    }

    private func send(_ request: RuntimeServiceRequest) async throws -> RuntimeServiceResponse {
        let requestData = try RuntimeXPCCodec.encodeRequest(request, storeContext: storeContext)
        return try await withCheckedThrowingContinuation { continuation in
            guard let proxy = remoteProxy(errorHandler: { error in
                continuation.resume(throwing: error)
            }) else {
                continuation.resume(throwing: RuntimeXPCClientError.invalidProxy)
                return
            }

            proxy.handleRuntimeRequest(requestData) { responseData, errorMessage in
                if let errorMessage {
                    continuation.resume(throwing: RuntimeXPCClientError.remoteError(errorMessage))
                    return
                }

                guard let responseData else {
                    continuation.resume(throwing: RuntimeXPCClientError.missingResponse)
                    return
                }

                do {
                    continuation.resume(returning: try RuntimeXPCCodec.decodeResponse(responseData))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func remoteProxy(errorHandler: @escaping (Error) -> Void) -> ComposerRuntimeXPCServicing? {
        let connection = currentConnection()
        return connection.remoteObjectProxyWithErrorHandler(errorHandler) as? ComposerRuntimeXPCServicing
    }

    private func currentConnection() -> NSXPCConnection {
        lock.lock()
        defer { lock.unlock() }

        if let connection {
            return connection
        }

        let newConnection = NSXPCConnection(machServiceName: machServiceName)
        newConnection.remoteObjectInterface = RuntimeXPCInterfaceFactory.makeInterface()
        newConnection.resume()
        connection = newConnection
        return newConnection
    }
}

public enum RuntimeXPCInterfaceFactory {
    public static func makeInterface() -> NSXPCInterface {
        NSXPCInterface(with: ComposerRuntimeXPCServicing.self)
    }
}
#endif
