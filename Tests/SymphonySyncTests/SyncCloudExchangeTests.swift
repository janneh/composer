import XCTest
import SymphonyCore
import SymphonyInterfaces
@testable import SymphonySync

final class SyncCloudExchangeTests: XCTestCase {
    func testPullRemoteChangesUsesCloudTransportBoundary() async throws {
        let change = SyncRemoteChange(
            id: "change-1",
            aggregate: .task,
            aggregateID: "task-1",
            operation: .update,
            payload: ["title": "Remote"],
            version: SyncRecordVersion(revision: "rev-2", updatedAt: Date(timeIntervalSince1970: 200)),
            externalReference: "cloud-task-1",
            receivedAt: Date(timeIntervalSince1970: 300)
        )
        let expectedBatch = SyncPullBatch(changes: [change], nextCursor: "cursor-2", hasMore: true)
        let transport = RecordingCloudTransport(pullBatch: expectedBatch)
        let store = InMemorySyncOutboxStore(entries: [])
        let exchange = SyncCloudExchange(outboxStore: store, transport: transport)

        let batch = try await exchange.pullRemoteChanges(since: "cursor-1", limit: 0)

        XCTAssertEqual(batch, expectedBatch)
        let requests = await transport.recordedPullRequests()
        XCTAssertEqual(requests, [PullRequest(cursor: "cursor-1", limit: 1)])
    }

    func testPushPendingOutboxUsesCloudTransportReceipts() async throws {
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
        let transport = RecordingCloudTransport(
            pushReceipts: [SyncOutboxReceipt(externalReference: "cloud-1", metadata: ["revision": "rev-2"])]
        )
        let exchange = SyncCloudExchange(outboxStore: store, transport: transport, now: { date })

        let summary = try await exchange.pushPendingOutbox(limit: 25)

        XCTAssertEqual(summary, SyncOutboxProcessingSummary(processed: 1, sent: 1, failed: 0))
        let pushedEntries = await transport.recordedPushedEntries()
        XCTAssertEqual(pushedEntries.map(\.id), ["entry-1"])
        let storedEntry = await store.entry(id: "entry-1")
        let stored = try XCTUnwrap(storedEntry)
        XCTAssertEqual(stored.status, .sent)
        XCTAssertEqual(stored.externalReference, "cloud-1")
        XCTAssertEqual(stored.receiptMetadata, ["revision": "rev-2"])
    }
}

private struct PullRequest: Equatable, Sendable {
    var cursor: SyncCursor?
    var limit: Int
}

private actor RecordingCloudTransport: SyncCloudTransport {
    private var pullBatch: SyncPullBatch
    private var pushReceipts: [SyncOutboxReceipt]
    private var pullRequests: [PullRequest] = []
    private var pushedEntries: [SyncOutboxEntry] = []

    init(
        pullBatch: SyncPullBatch = SyncPullBatch(changes: []),
        pushReceipts: [SyncOutboxReceipt] = []
    ) {
        self.pullBatch = pullBatch
        self.pushReceipts = pushReceipts
    }

    func pullChanges(since cursor: SyncCursor?, limit: Int) async throws -> SyncPullBatch {
        pullRequests.append(PullRequest(cursor: cursor, limit: limit))
        return pullBatch
    }

    func push(_ entry: SyncOutboxEntry) async throws -> SyncOutboxReceipt {
        pushedEntries.append(entry)
        guard !pushReceipts.isEmpty else {
            return SyncOutboxReceipt()
        }

        return pushReceipts.removeFirst()
    }

    func recordedPullRequests() -> [PullRequest] {
        pullRequests
    }

    func recordedPushedEntries() -> [SyncOutboxEntry] {
        pushedEntries
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
