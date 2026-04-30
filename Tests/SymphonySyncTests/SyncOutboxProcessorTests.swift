import XCTest
import SymphonyCore
import SymphonyInterfaces
@testable import SymphonySync

final class SyncOutboxProcessorTests: XCTestCase {
    func testProcessBatchMarksEntriesSentWithReceipt() async throws {
        let date = Date(timeIntervalSince1970: 1_000)
        let entry = SyncOutboxEntry(
            id: "entry-1",
            aggregate: .task,
            aggregateID: "task-1",
            operation: .update,
            payload: ["state": "ready"],
            availableAt: date,
            createdAt: date,
            updatedAt: date
        )
        let store = InMemorySyncOutboxStore(entries: [entry])
        let transport = RecordingSyncTransport(
            results: [.success(SyncOutboxReceipt(externalReference: "remote-1", metadata: ["revision": "2"]))]
        )
        let processor = SyncOutboxProcessor(store: store, transport: transport, now: { date })

        let summary = try await processor.processBatch(limit: 10)

        XCTAssertEqual(summary, SyncOutboxProcessingSummary(processed: 1, sent: 1, failed: 0))
        let pushedEntries = await transport.recordedPushedEntries()
        XCTAssertEqual(pushedEntries.map(\.id), ["entry-1"])
        let storedEntry = await store.entry(id: "entry-1")
        let stored = try XCTUnwrap(storedEntry)
        XCTAssertEqual(stored.status, .sent)
        XCTAssertEqual(stored.externalReference, "remote-1")
        XCTAssertEqual(stored.receiptMetadata, ["revision": "2"])
        XCTAssertNil(stored.lastError)
    }

    func testProcessBatchRetriesFailedEntriesUntilMaxAttempts() async throws {
        let date = Date(timeIntervalSince1970: 1_000)
        let entry = SyncOutboxEntry(
            id: "entry-1",
            aggregate: .task,
            aggregateID: "task-1",
            operation: .update,
            attemptCount: 1,
            availableAt: date,
            createdAt: date,
            updatedAt: date
        )
        let store = InMemorySyncOutboxStore(entries: [entry])
        let transport = RecordingSyncTransport(results: [.failure(TestError(message: "network down"))])
        let processor = SyncOutboxProcessor(
            store: store,
            transport: transport,
            retryPolicy: SyncOutboxRetryPolicy(maxAttempts: 3, baseDelay: 10),
            now: { date }
        )

        let summary = try await processor.processBatch(limit: 10)

        XCTAssertEqual(summary, SyncOutboxProcessingSummary(processed: 1, sent: 0, failed: 1))
        let storedEntry = await store.entry(id: "entry-1")
        let stored = try XCTUnwrap(storedEntry)
        XCTAssertEqual(stored.status, .pending)
        XCTAssertEqual(stored.attemptCount, 2)
        XCTAssertEqual(stored.availableAt, date.addingTimeInterval(20))
        XCTAssertEqual(stored.lastError, "network down")
    }

    func testProcessBatchMarksEntryFailedAtMaxAttempts() async throws {
        let date = Date(timeIntervalSince1970: 1_000)
        let entry = SyncOutboxEntry(
            id: "entry-1",
            aggregate: .task,
            aggregateID: "task-1",
            operation: .update,
            attemptCount: 2,
            availableAt: date,
            createdAt: date,
            updatedAt: date
        )
        let store = InMemorySyncOutboxStore(entries: [entry])
        let transport = RecordingSyncTransport(results: [.failure(TestError(message: "permanent"))])
        let processor = SyncOutboxProcessor(
            store: store,
            transport: transport,
            retryPolicy: SyncOutboxRetryPolicy(maxAttempts: 3, baseDelay: 10),
            now: { date }
        )

        _ = try await processor.processBatch(limit: 10)

        let storedEntry = await store.entry(id: "entry-1")
        let stored = try XCTUnwrap(storedEntry)
        XCTAssertEqual(stored.status, .failed)
        XCTAssertEqual(stored.attemptCount, 3)
        XCTAssertEqual(stored.lastError, "permanent")
    }

    func testProcessBatchSkipsEntriesNotYetAvailable() async throws {
        let date = Date(timeIntervalSince1970: 1_000)
        let entry = SyncOutboxEntry(
            id: "entry-1",
            aggregate: .task,
            aggregateID: "task-1",
            operation: .update,
            availableAt: date.addingTimeInterval(60),
            createdAt: date,
            updatedAt: date
        )
        let store = InMemorySyncOutboxStore(entries: [entry])
        let transport = RecordingSyncTransport(results: [])
        let processor = SyncOutboxProcessor(store: store, transport: transport, now: { date })

        let summary = try await processor.processBatch(limit: 10)

        XCTAssertEqual(summary, SyncOutboxProcessingSummary())
        let pushedEntries = await transport.recordedPushedEntries()
        XCTAssertEqual(pushedEntries, [])
    }
}

private actor InMemorySyncOutboxStore: SyncOutboxStore {
    private var entries: [String: SyncOutboxEntry]

    init(entries: [SyncOutboxEntry]) {
        self.entries = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
    }

    func enqueueSyncOutboxEntry(_ entry: SyncOutboxEntry) async throws {
        entries[entry.id] = entry
    }

    func listPendingSyncOutboxEntries(limit: Int, now: Date) async throws -> [SyncOutboxEntry] {
        Array(entries.values)
            .filter { $0.status == .pending && $0.availableAt <= now }
            .sorted { $0.createdAt < $1.createdAt }
            .prefix(limit)
            .map { $0 }
    }

    func updateSyncOutboxEntry(_ entry: SyncOutboxEntry) async throws {
        entries[entry.id] = entry
    }

    func entry(id: String) -> SyncOutboxEntry? {
        entries[id]
    }
}

private actor RecordingSyncTransport: SyncOutboxTransport {
    private var results: [Result<SyncOutboxReceipt, Error>]
    private(set) var pushedEntries: [SyncOutboxEntry] = []

    init(results: [Result<SyncOutboxReceipt, Error>]) {
        self.results = results
    }

    func push(_ entry: SyncOutboxEntry) async throws -> SyncOutboxReceipt {
        pushedEntries.append(entry)
        guard !results.isEmpty else {
            return SyncOutboxReceipt()
        }

        return try results.removeFirst().get()
    }

    func recordedPushedEntries() -> [SyncOutboxEntry] {
        pushedEntries
    }
}

private struct TestError: Error, LocalizedError {
    var message: String
    var errorDescription: String? { message }
}
