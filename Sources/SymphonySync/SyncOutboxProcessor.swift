import Foundation
import SymphonyCore
import SymphonyInterfaces

public struct SyncOutboxRetryPolicy: Equatable, Sendable {
    public var maxAttempts: Int
    public var baseDelay: TimeInterval

    public init(maxAttempts: Int = 3, baseDelay: TimeInterval = 30) {
        self.maxAttempts = max(1, maxAttempts)
        self.baseDelay = max(0, baseDelay)
    }

    public func retryDelay(forAttempt attempt: Int) -> TimeInterval {
        guard attempt > 0 else {
            return 0
        }
        return baseDelay * pow(2, Double(attempt - 1))
    }
}

public struct SyncOutboxProcessingSummary: Equatable, Sendable {
    public var processed: Int
    public var sent: Int
    public var failed: Int

    public init(processed: Int = 0, sent: Int = 0, failed: Int = 0) {
        self.processed = processed
        self.sent = sent
        self.failed = failed
    }
}

public struct SyncOutboxProcessor: Sendable {
    private let store: any SyncOutboxStore
    private let transport: any SyncOutboxTransport
    private let retryPolicy: SyncOutboxRetryPolicy
    private let now: @Sendable () -> Date

    public init(
        store: any SyncOutboxStore,
        transport: any SyncOutboxTransport,
        retryPolicy: SyncOutboxRetryPolicy = SyncOutboxRetryPolicy(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.transport = transport
        self.retryPolicy = retryPolicy
        self.now = now
    }

    public func processBatch(limit: Int = 25) async throws -> SyncOutboxProcessingSummary {
        let batchLimit = max(1, limit)
        let entries = try await store.listPendingSyncOutboxEntries(limit: batchLimit, now: now())
        var summary = SyncOutboxProcessingSummary(processed: entries.count)

        for entry in entries {
            var inFlight = entry
            inFlight.status = .inFlight
            inFlight.updatedAt = now()
            try await store.updateSyncOutboxEntry(inFlight)

            do {
                let receipt = try await transport.push(entry)
                var sent = inFlight
                sent.status = .sent
                sent.lastError = nil
                sent.externalReference = receipt.externalReference
                sent.receiptMetadata = receipt.metadata
                sent.updatedAt = now()
                try await store.updateSyncOutboxEntry(sent)
                summary.sent += 1
            } catch {
                var failed = inFlight
                failed.attemptCount += 1
                failed.lastError = error.localizedDescription
                failed.updatedAt = now()

                if failed.attemptCount >= retryPolicy.maxAttempts {
                    failed.status = .failed
                } else {
                    failed.status = .pending
                    failed.availableAt = now().addingTimeInterval(
                        retryPolicy.retryDelay(forAttempt: failed.attemptCount)
                    )
                }

                try await store.updateSyncOutboxEntry(failed)
                summary.failed += 1
            }
        }

        return summary
    }
}
