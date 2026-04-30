import Foundation

public struct SyncRecordVersion: Codable, Hashable, Sendable {
    public var revision: String?
    public var updatedAt: Date?

    public init(revision: String? = nil, updatedAt: Date? = nil) {
        self.revision = revision
        self.updatedAt = updatedAt
    }
}

public struct SyncRecordSnapshot<Value: Equatable & Sendable>: Equatable, Sendable {
    public var value: Value?
    public var version: SyncRecordVersion
    public var isDeleted: Bool

    public init(
        value: Value?,
        version: SyncRecordVersion = SyncRecordVersion(),
        isDeleted: Bool = false
    ) {
        self.value = isDeleted ? nil : value
        self.version = version
        self.isDeleted = isDeleted
    }

    public static func deleted(version: SyncRecordVersion = SyncRecordVersion()) -> SyncRecordSnapshot<Value> {
        SyncRecordSnapshot(value: nil, version: version, isDeleted: true)
    }
}

public enum SyncConflictStrategy: Equatable, Sendable {
    case preferLocal
    case preferRemote
    case lastWriterWins
    case requireManualResolution
}

public enum SyncConflictReason: String, Codable, Hashable, Sendable {
    case alreadyConverged
    case unchanged
    case localChanged
    case remoteChanged
    case bothChangedSame
    case concurrentUpdate
    case deleteUpdate
    case missingClock
    case ambiguousWinner
}

public enum SyncConflictResolutionAction: String, Codable, Hashable, Sendable {
    case noChange
    case useLocal
    case useRemote
    case unresolved
}

public struct SyncConflict<Value: Equatable & Sendable>: Equatable, Sendable {
    public var base: SyncRecordSnapshot<Value>?
    public var local: SyncRecordSnapshot<Value>
    public var remote: SyncRecordSnapshot<Value>
    public var reason: SyncConflictReason

    public init(
        base: SyncRecordSnapshot<Value>?,
        local: SyncRecordSnapshot<Value>,
        remote: SyncRecordSnapshot<Value>,
        reason: SyncConflictReason
    ) {
        self.base = base
        self.local = local
        self.remote = remote
        self.reason = reason
    }
}

public struct SyncConflictResolution<Value: Equatable & Sendable>: Equatable, Sendable {
    public var action: SyncConflictResolutionAction
    public var value: Value?
    public var isDeleted: Bool
    public var reason: SyncConflictReason
    public var chosenVersion: SyncRecordVersion?
    public var conflict: SyncConflict<Value>?

    public var requiresManualResolution: Bool {
        action == .unresolved
    }

    public init(
        action: SyncConflictResolutionAction,
        value: Value?,
        isDeleted: Bool,
        reason: SyncConflictReason,
        chosenVersion: SyncRecordVersion? = nil,
        conflict: SyncConflict<Value>? = nil
    ) {
        self.action = action
        self.value = value
        self.isDeleted = isDeleted
        self.reason = reason
        self.chosenVersion = chosenVersion
        self.conflict = conflict
    }
}

public struct SyncConflictPolicy<Value: Equatable & Sendable>: Sendable {
    public var strategy: SyncConflictStrategy

    public init(strategy: SyncConflictStrategy = .lastWriterWins) {
        self.strategy = strategy
    }

    public func resolve(
        base: SyncRecordSnapshot<Value>?,
        local: SyncRecordSnapshot<Value>,
        remote: SyncRecordSnapshot<Value>
    ) -> SyncConflictResolution<Value> {
        let localState = SyncRecordState(snapshot: local)
        let remoteState = SyncRecordState(snapshot: remote)

        if localState == remoteState {
            let reason: SyncConflictReason = base.map { SyncRecordState(snapshot: $0) == localState } == true
                ? .unchanged
                : .bothChangedSame
            return resolution(action: .noChange, snapshot: local, reason: reason)
        }

        guard let base else {
            return resolveDivergent(
                base: nil,
                local: local,
                remote: remote,
                reason: divergentReason(local: local, remote: remote)
            )
        }

        let baseState = SyncRecordState(snapshot: base)
        let localChanged = localState != baseState
        let remoteChanged = remoteState != baseState

        switch (localChanged, remoteChanged) {
        case (false, false):
            return resolution(action: .noChange, snapshot: local, reason: .unchanged)
        case (true, false):
            return resolution(action: .useLocal, snapshot: local, reason: .localChanged)
        case (false, true):
            return resolution(action: .useRemote, snapshot: remote, reason: .remoteChanged)
        case (true, true):
            return resolveDivergent(
                base: base,
                local: local,
                remote: remote,
                reason: divergentReason(local: local, remote: remote)
            )
        }
    }

    private func resolveDivergent(
        base: SyncRecordSnapshot<Value>?,
        local: SyncRecordSnapshot<Value>,
        remote: SyncRecordSnapshot<Value>,
        reason: SyncConflictReason
    ) -> SyncConflictResolution<Value> {
        switch strategy {
        case .preferLocal:
            return resolution(action: .useLocal, snapshot: local, reason: reason)
        case .preferRemote:
            return resolution(action: .useRemote, snapshot: remote, reason: reason)
        case .requireManualResolution:
            return unresolved(base: base, local: local, remote: remote, reason: reason)
        case .lastWriterWins:
            guard let localUpdatedAt = local.version.updatedAt,
                  let remoteUpdatedAt = remote.version.updatedAt else {
                return unresolved(base: base, local: local, remote: remote, reason: .missingClock)
            }

            if localUpdatedAt > remoteUpdatedAt {
                return resolution(action: .useLocal, snapshot: local, reason: reason)
            }

            if remoteUpdatedAt > localUpdatedAt {
                return resolution(action: .useRemote, snapshot: remote, reason: reason)
            }

            return unresolved(base: base, local: local, remote: remote, reason: .ambiguousWinner)
        }
    }

    private func resolution(
        action: SyncConflictResolutionAction,
        snapshot: SyncRecordSnapshot<Value>,
        reason: SyncConflictReason
    ) -> SyncConflictResolution<Value> {
        SyncConflictResolution(
            action: action,
            value: snapshot.value,
            isDeleted: snapshot.isDeleted,
            reason: reason,
            chosenVersion: snapshot.version
        )
    }

    private func unresolved(
        base: SyncRecordSnapshot<Value>?,
        local: SyncRecordSnapshot<Value>,
        remote: SyncRecordSnapshot<Value>,
        reason: SyncConflictReason
    ) -> SyncConflictResolution<Value> {
        let conflict = SyncConflict(base: base, local: local, remote: remote, reason: reason)
        return SyncConflictResolution(
            action: .unresolved,
            value: nil,
            isDeleted: false,
            reason: reason,
            conflict: conflict
        )
    }

    private func divergentReason(
        local: SyncRecordSnapshot<Value>,
        remote: SyncRecordSnapshot<Value>
    ) -> SyncConflictReason {
        local.isDeleted != remote.isDeleted ? .deleteUpdate : .concurrentUpdate
    }
}

private struct SyncRecordState<Value: Equatable & Sendable>: Equatable {
    var value: Value?
    var isDeleted: Bool

    init(snapshot: SyncRecordSnapshot<Value>) {
        self.value = snapshot.value
        self.isDeleted = snapshot.isDeleted
    }
}
