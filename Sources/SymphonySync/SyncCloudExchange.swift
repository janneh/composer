import Foundation
import SymphonyCore
import SymphonyInterfaces

public struct SyncCloudExchange: Sendable {
    private let transport: any SyncCloudTransport
    private let outboxProcessor: SyncOutboxProcessor

    public init(
        outboxStore: any SyncOutboxStore,
        transport: any SyncCloudTransport,
        retryPolicy: SyncOutboxRetryPolicy = SyncOutboxRetryPolicy(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.transport = transport
        self.outboxProcessor = SyncOutboxProcessor(
            store: outboxStore,
            transport: transport,
            retryPolicy: retryPolicy,
            now: now
        )
    }

    public func pullRemoteChanges(
        since cursor: SyncCursor? = nil,
        limit: Int = 100
    ) async throws -> SyncPullBatch {
        try await transport.pullChanges(since: cursor, limit: max(1, limit))
    }

    public func pushPendingOutbox(limit: Int = 25) async throws -> SyncOutboxProcessingSummary {
        try await outboxProcessor.processBatch(limit: limit)
    }
}
