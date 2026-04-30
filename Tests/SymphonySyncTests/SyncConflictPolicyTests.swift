import XCTest
@testable import SymphonySync

final class SyncConflictPolicyTests: XCTestCase {
    func testResolveKeepsLocalWhenOnlyLocalChanged() {
        let base = snapshot("base", at: 100)
        let local = snapshot("local", at: 200)
        let remote = snapshot("base", at: 300)
        let policy = SyncConflictPolicy<String>()

        let resolution = policy.resolve(base: base, local: local, remote: remote)

        XCTAssertEqual(resolution.action, .useLocal)
        XCTAssertEqual(resolution.value, "local")
        XCTAssertFalse(resolution.isDeleted)
        XCTAssertEqual(resolution.reason, .localChanged)
        XCTAssertFalse(resolution.requiresManualResolution)
    }

    func testResolveUsesRemoteWhenOnlyRemoteChanged() {
        let base = snapshot("base", at: 100)
        let local = snapshot("base", at: 300)
        let remote = snapshot("remote", at: 200)
        let policy = SyncConflictPolicy<String>()

        let resolution = policy.resolve(base: base, local: local, remote: remote)

        XCTAssertEqual(resolution.action, .useRemote)
        XCTAssertEqual(resolution.value, "remote")
        XCTAssertEqual(resolution.reason, .remoteChanged)
    }

    func testResolveLastWriterWinsForConcurrentUpdates() {
        let base = snapshot("base", at: 100)
        let local = snapshot("local", at: 200)
        let remote = snapshot("remote", at: 300)
        let policy = SyncConflictPolicy<String>(strategy: .lastWriterWins)

        let resolution = policy.resolve(base: base, local: local, remote: remote)

        XCTAssertEqual(resolution.action, .useRemote)
        XCTAssertEqual(resolution.value, "remote")
        XCTAssertEqual(resolution.reason, .concurrentUpdate)
        XCTAssertEqual(resolution.chosenVersion?.updatedAt, Date(timeIntervalSince1970: 300))
    }

    func testResolveManualStrategyLeavesDivergentChangesUnresolved() throws {
        let base = snapshot("base", at: 100)
        let local = snapshot("local", at: 200)
        let remote = snapshot("remote", at: 300)
        let policy = SyncConflictPolicy<String>(strategy: .requireManualResolution)

        let resolution = policy.resolve(base: base, local: local, remote: remote)

        XCTAssertEqual(resolution.action, .unresolved)
        XCTAssertNil(resolution.value)
        XCTAssertTrue(resolution.requiresManualResolution)
        XCTAssertEqual(resolution.reason, .concurrentUpdate)
        let conflict = try XCTUnwrap(resolution.conflict)
        XCTAssertEqual(conflict.local.value, "local")
        XCTAssertEqual(conflict.remote.value, "remote")
        XCTAssertEqual(conflict.reason, .concurrentUpdate)
    }

    func testResolveAcceptsRemoteDeleteWhenLocalIsUnchanged() {
        let base = snapshot("base", at: 100)
        let local = snapshot("base", at: 200)
        let remote = deleted(at: 300)
        let policy = SyncConflictPolicy<String>()

        let resolution = policy.resolve(base: base, local: local, remote: remote)

        XCTAssertEqual(resolution.action, .useRemote)
        XCTAssertNil(resolution.value)
        XCTAssertTrue(resolution.isDeleted)
        XCTAssertEqual(resolution.reason, .remoteChanged)
    }

    func testResolveLastWriterWinsLeavesEqualClocksUnresolved() throws {
        let base = snapshot("base", at: 100)
        let local = snapshot("local", at: 200)
        let remote = snapshot("remote", at: 200)
        let policy = SyncConflictPolicy<String>(strategy: .lastWriterWins)

        let resolution = policy.resolve(base: base, local: local, remote: remote)

        XCTAssertEqual(resolution.action, .unresolved)
        XCTAssertTrue(resolution.requiresManualResolution)
        XCTAssertEqual(resolution.reason, .ambiguousWinner)
        let conflict = try XCTUnwrap(resolution.conflict)
        XCTAssertEqual(conflict.reason, .ambiguousWinner)
    }
}

private func snapshot(_ value: String, at timestamp: TimeInterval) -> SyncRecordSnapshot<String> {
    SyncRecordSnapshot(
        value: value,
        version: SyncRecordVersion(updatedAt: Date(timeIntervalSince1970: timestamp))
    )
}

private func deleted(at timestamp: TimeInterval) -> SyncRecordSnapshot<String> {
    SyncRecordSnapshot<String>.deleted(
        version: SyncRecordVersion(updatedAt: Date(timeIntervalSince1970: timestamp))
    )
}
