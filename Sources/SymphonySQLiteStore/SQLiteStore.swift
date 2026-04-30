import Foundation
import SQLite3
import SymphonyCore
import SymphonyInterfaces

public actor SQLiteStore: ProjectStore, TaskStore, RunStore, EventStore, SyncOutboxStore, SyncMetadataStore {
    public nonisolated let fileURL: URL

    private var database: OpaquePointer?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL) throws {
        self.fileURL = fileURL

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var db: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(fileURL.path, &db, flags, nil) == SQLITE_OK, let db else {
            defer {
                sqlite3_close(db)
            }
            throw SQLiteStoreError.openFailed(fileURL.path, SQLiteStore.errorMessage(db))
        }

        database = db
        try SQLiteStore.migrate(database: db)
    }

    deinit {
        sqlite3_close(database)
    }

    public static func defaultStore(appName: String = "Composer") throws -> SQLiteStore {
        let directory = try applicationSupportDirectory(appName: appName)
        return try SQLiteStore(fileURL: directory.appendingPathComponent("composer.sqlite3"))
    }

    public func listProjects() async throws -> [Project] {
        try readRows("SELECT json FROM projects ORDER BY name COLLATE NOCASE ASC") { statement in
            try decode(Project.self, fromColumn: 0, in: statement)
        }
    }

    public func project(id: ProjectID) async throws -> Project? {
        try readOptionalRow("SELECT json FROM projects WHERE id = ?") { statement in
            try bind(id.rawValue, to: 1, in: statement)
        } decode: { statement in
            try decode(Project.self, fromColumn: 0, in: statement)
        }
    }

    public func upsertProject(_ project: Project) async throws {
        let sql = """
        INSERT INTO projects (id, name, created_at, updated_at, json)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          name = excluded.name,
          created_at = excluded.created_at,
          updated_at = excluded.updated_at,
          json = excluded.json
        """

        try write(sql) { statement in
            try bind(project.id.rawValue, to: 1, in: statement)
            try bind(project.name, to: 2, in: statement)
            try bind(project.createdAt, to: 3, in: statement)
            try bind(project.updatedAt, to: 4, in: statement)
            try bindEncoded(project, to: 5, in: statement)
        }
    }

    public func deleteProject(id: ProjectID) async throws {
        try write("DELETE FROM projects WHERE id = ?") { statement in
            try bind(id.rawValue, to: 1, in: statement)
        }
    }

    public func listTasks(projectID: ProjectID?) async throws -> [WorkItem] {
        if let projectID {
            return try readRows(
                """
                SELECT json FROM tasks
                WHERE project_id = ?
                ORDER BY priority DESC, updated_at DESC
                """
            ) { statement in
                try bind(projectID.rawValue, to: 1, in: statement)
            } decode: { statement in
                try decode(WorkItem.self, fromColumn: 0, in: statement)
            }
        }

        return try readRows(
            "SELECT json FROM tasks ORDER BY priority DESC, updated_at DESC"
        ) { statement in
            try decode(WorkItem.self, fromColumn: 0, in: statement)
        }
    }

    public func task(id: TaskID) async throws -> WorkItem? {
        try readOptionalRow("SELECT json FROM tasks WHERE id = ?") { statement in
            try bind(id.rawValue, to: 1, in: statement)
        } decode: { statement in
            try decode(WorkItem.self, fromColumn: 0, in: statement)
        }
    }

    public func upsertTask(_ task: WorkItem) async throws {
        let sql = """
        INSERT INTO tasks (id, project_id, identifier, state, priority, created_at, updated_at, json)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          project_id = excluded.project_id,
          identifier = excluded.identifier,
          state = excluded.state,
          priority = excluded.priority,
          created_at = excluded.created_at,
          updated_at = excluded.updated_at,
          json = excluded.json
        """

        try write(sql) { statement in
            try bind(task.id.rawValue, to: 1, in: statement)
            try bind(task.projectID.rawValue, to: 2, in: statement)
            try bind(task.identifier, to: 3, in: statement)
            try bind(task.state.rawValue, to: 4, in: statement)
            try bind(task.priority.rawValue, to: 5, in: statement)
            try bind(task.createdAt, to: 6, in: statement)
            try bind(task.updatedAt, to: 7, in: statement)
            try bindEncoded(task, to: 8, in: statement)
        }
    }

    public func deleteTask(id: TaskID) async throws {
        try write("DELETE FROM tasks WHERE id = ?") { statement in
            try bind(id.rawValue, to: 1, in: statement)
        }
    }

    public func listRuns(taskID: TaskID?) async throws -> [RunAttempt] {
        if let taskID {
            return try readRows(
                """
                SELECT json FROM runs
                WHERE task_id = ?
                ORDER BY started_at IS NULL ASC, started_at DESC
                """
            ) { statement in
                try bind(taskID.rawValue, to: 1, in: statement)
            } decode: { statement in
                try decode(RunAttempt.self, fromColumn: 0, in: statement)
            }
        }

        return try readRows(
            "SELECT json FROM runs ORDER BY started_at IS NULL ASC, started_at DESC"
        ) { statement in
            try decode(RunAttempt.self, fromColumn: 0, in: statement)
        }
    }

    public func upsertRun(_ run: RunAttempt) async throws {
        let sql = """
        INSERT INTO runs (id, task_id, status, started_at, finished_at, json)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          task_id = excluded.task_id,
          status = excluded.status,
          started_at = excluded.started_at,
          finished_at = excluded.finished_at,
          json = excluded.json
        """

        try write(sql) { statement in
            try bind(run.id.rawValue, to: 1, in: statement)
            try bind(run.taskID.rawValue, to: 2, in: statement)
            try bind(run.status.rawValue, to: 3, in: statement)
            try bind(run.startedAt, to: 4, in: statement)
            try bind(run.finishedAt, to: 5, in: statement)
            try bindEncoded(run, to: 6, in: statement)
        }
    }

    public func appendEvent(_ event: RuntimeEvent) async throws {
        let sql = """
        INSERT INTO event_log (id, task_id, run_id, kind, created_at, json)
        VALUES (?, ?, ?, ?, ?, ?)
        """

        try write(sql) { statement in
            try bind(event.id, to: 1, in: statement)
            try bind(event.taskID?.rawValue, to: 2, in: statement)
            try bind(event.runID?.rawValue, to: 3, in: statement)
            try bind(event.kind.rawValue, to: 4, in: statement)
            try bind(event.createdAt, to: 5, in: statement)
            try bindEncoded(event, to: 6, in: statement)
        }
    }

    public func listEvents(taskID: TaskID?, limit: Int) async throws -> [RuntimeEvent] {
        let clampedLimit = max(0, limit)
        guard clampedLimit > 0 else {
            return []
        }

        if let taskID {
            return try readRows(
                """
                SELECT json FROM event_log
                WHERE task_id = ?
                ORDER BY created_at DESC, sequence DESC
                LIMIT ?
                """
            ) { statement in
                try bind(taskID.rawValue, to: 1, in: statement)
                try bind(clampedLimit, to: 2, in: statement)
            } decode: { statement in
                try decode(RuntimeEvent.self, fromColumn: 0, in: statement)
            }
        }

        return try readRows(
            "SELECT json FROM event_log ORDER BY created_at DESC, sequence DESC LIMIT ?"
        ) { statement in
            try bind(clampedLimit, to: 1, in: statement)
        } decode: { statement in
            try decode(RuntimeEvent.self, fromColumn: 0, in: statement)
        }
    }

    public func enqueueSyncOutboxEntry(_ entry: SyncOutboxEntry) async throws {
        let sql = """
        INSERT INTO sync_outbox (
          id, aggregate, aggregate_id, operation, status, attempt_count,
          available_at, last_error, external_reference, created_at, updated_at, json
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """

        try write(sql) { statement in
            try bindSyncOutboxEntry(entry, in: statement)
        }
    }

    public func listPendingSyncOutboxEntries(limit: Int, now: Date) async throws -> [SyncOutboxEntry] {
        let clampedLimit = max(0, limit)
        guard clampedLimit > 0 else {
            return []
        }

        return try readRows(
            """
            SELECT json FROM sync_outbox
            WHERE status = ? AND available_at <= ?
            ORDER BY available_at ASC, created_at ASC
            LIMIT ?
            """
        ) { statement in
            try bind(SyncOutboxStatus.pending.rawValue, to: 1, in: statement)
            try bind(now, to: 2, in: statement)
            try bind(clampedLimit, to: 3, in: statement)
        } decode: { statement in
            try decode(SyncOutboxEntry.self, fromColumn: 0, in: statement)
        }
    }

    public func updateSyncOutboxEntry(_ entry: SyncOutboxEntry) async throws {
        let sql = """
        INSERT INTO sync_outbox (
          id, aggregate, aggregate_id, operation, status, attempt_count,
          available_at, last_error, external_reference, created_at, updated_at, json
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          aggregate = excluded.aggregate,
          aggregate_id = excluded.aggregate_id,
          operation = excluded.operation,
          status = excluded.status,
          attempt_count = excluded.attempt_count,
          available_at = excluded.available_at,
          last_error = excluded.last_error,
          external_reference = excluded.external_reference,
          created_at = excluded.created_at,
          updated_at = excluded.updated_at,
          json = excluded.json
        """

        try write(sql) { statement in
            try bindSyncOutboxEntry(entry, in: statement)
        }
    }

    public func upsertSyncMetadataRecord(_ record: SyncMetadataRecord) async throws {
        let sql = """
        INSERT INTO sync_metadata (
          aggregate, aggregate_id, external_reference, revision, remote_updated_at,
          last_pulled_at, last_pushed_at, has_local_changes, updated_at, json
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(aggregate, aggregate_id) DO UPDATE SET
          external_reference = excluded.external_reference,
          revision = excluded.revision,
          remote_updated_at = excluded.remote_updated_at,
          last_pulled_at = excluded.last_pulled_at,
          last_pushed_at = excluded.last_pushed_at,
          has_local_changes = excluded.has_local_changes,
          updated_at = excluded.updated_at,
          json = excluded.json
        """

        try write(sql) { statement in
            try bind(record.aggregate.rawValue, to: 1, in: statement)
            try bind(record.aggregateID, to: 2, in: statement)
            try bind(record.externalReference, to: 3, in: statement)
            try bind(record.version.revision, to: 4, in: statement)
            try bind(record.version.updatedAt, to: 5, in: statement)
            try bind(record.lastPulledAt, to: 6, in: statement)
            try bind(record.lastPushedAt, to: 7, in: statement)
            try bind(record.hasLocalChanges ? 1 : 0, to: 8, in: statement)
            try bind(record.updatedAt, to: 9, in: statement)
            try bindEncoded(record, to: 10, in: statement)
        }
    }

    public func syncMetadataRecord(
        aggregate: SyncOutboxAggregate,
        aggregateID: String
    ) async throws -> SyncMetadataRecord? {
        try readOptionalRow(
            """
            SELECT json FROM sync_metadata
            WHERE aggregate = ? AND aggregate_id = ?
            """
        ) { statement in
            try bind(aggregate.rawValue, to: 1, in: statement)
            try bind(aggregateID, to: 2, in: statement)
        } decode: { statement in
            try decode(SyncMetadataRecord.self, fromColumn: 0, in: statement)
        }
    }

    public func upsertSyncCursorRecord(_ record: SyncCursorRecord) async throws {
        let sql = """
        INSERT INTO sync_cursors (scope, cursor, updated_at, json)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(scope) DO UPDATE SET
          cursor = excluded.cursor,
          updated_at = excluded.updated_at,
          json = excluded.json
        """

        try write(sql) { statement in
            try bind(record.scope, to: 1, in: statement)
            try bind(record.cursor?.rawValue, to: 2, in: statement)
            try bind(record.updatedAt, to: 3, in: statement)
            try bindEncoded(record, to: 4, in: statement)
        }
    }

    public func syncCursorRecord(scope: String) async throws -> SyncCursorRecord? {
        try readOptionalRow("SELECT json FROM sync_cursors WHERE scope = ?") { statement in
            try bind(scope, to: 1, in: statement)
        } decode: { statement in
            try decode(SyncCursorRecord.self, fromColumn: 0, in: statement)
        }
    }

    private static func applicationSupportDirectory(appName: String) throws -> URL {
        guard let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw SQLiteStoreError.applicationSupportDirectoryUnavailable
        }

        return baseURL.appendingPathComponent(appName, isDirectory: true)
    }

    private static func migrate(database: OpaquePointer) throws {
        try execute("PRAGMA foreign_keys = ON", database: database)
        let version = try userVersion(database: database)
        if version < 1 {
            try migrateToVersion1(database: database)
        }
        if version < 2 {
            try migrateToVersion2(database: database)
        }
        if version < 3 {
            try migrateToVersion3(database: database)
        }
    }

    private static func migrateToVersion1(database: OpaquePointer) throws {
        try execute("BEGIN IMMEDIATE", database: database)
        do {
            try execute("""
            CREATE TABLE IF NOT EXISTS projects (
              id TEXT PRIMARY KEY NOT NULL,
              name TEXT NOT NULL,
              created_at REAL NOT NULL,
              updated_at REAL NOT NULL,
              json BLOB NOT NULL
            )
            """, database: database)
            try execute("CREATE INDEX IF NOT EXISTS idx_projects_name ON projects(name COLLATE NOCASE)", database: database)

            try execute("""
            CREATE TABLE IF NOT EXISTS tasks (
              id TEXT PRIMARY KEY NOT NULL,
              project_id TEXT NOT NULL,
              identifier TEXT NOT NULL,
              state TEXT NOT NULL,
              priority INTEGER NOT NULL,
              created_at REAL NOT NULL,
              updated_at REAL NOT NULL,
              json BLOB NOT NULL,
              FOREIGN KEY(project_id) REFERENCES projects(id) ON DELETE CASCADE
            )
            """, database: database)
            try execute("CREATE INDEX IF NOT EXISTS idx_tasks_project_state ON tasks(project_id, state)", database: database)
            try execute("CREATE INDEX IF NOT EXISTS idx_tasks_project_sort ON tasks(project_id, priority DESC, updated_at DESC)", database: database)

            try execute("""
            CREATE TABLE IF NOT EXISTS runs (
              id TEXT PRIMARY KEY NOT NULL,
              task_id TEXT NOT NULL,
              status TEXT NOT NULL,
              started_at REAL,
              finished_at REAL,
              json BLOB NOT NULL,
              FOREIGN KEY(task_id) REFERENCES tasks(id) ON DELETE CASCADE
            )
            """, database: database)
            try execute("CREATE INDEX IF NOT EXISTS idx_runs_task_started ON runs(task_id, started_at DESC)", database: database)

            try execute("""
            CREATE TABLE IF NOT EXISTS events (
              id TEXT PRIMARY KEY NOT NULL,
              task_id TEXT,
              run_id TEXT,
              kind TEXT NOT NULL,
              created_at REAL NOT NULL,
              json BLOB NOT NULL,
              FOREIGN KEY(task_id) REFERENCES tasks(id) ON DELETE CASCADE,
              FOREIGN KEY(run_id) REFERENCES runs(id) ON DELETE SET NULL
            )
            """, database: database)
            try execute("CREATE INDEX IF NOT EXISTS idx_events_task_created ON events(task_id, created_at DESC)", database: database)
            try execute("CREATE INDEX IF NOT EXISTS idx_events_created ON events(created_at DESC)", database: database)
            try execute("PRAGMA user_version = 1", database: database)
            try execute("COMMIT", database: database)
        } catch {
            try? execute("ROLLBACK", database: database)
            throw error
        }
    }

    private static func migrateToVersion2(database: OpaquePointer) throws {
        try execute("BEGIN IMMEDIATE", database: database)
        do {
            try execute("""
            CREATE TABLE IF NOT EXISTS event_log (
              sequence INTEGER PRIMARY KEY AUTOINCREMENT,
              id TEXT NOT NULL,
              task_id TEXT,
              run_id TEXT,
              kind TEXT NOT NULL,
              created_at REAL NOT NULL,
              json BLOB NOT NULL
            )
            """, database: database)
            try execute("CREATE INDEX IF NOT EXISTS idx_event_log_task_created ON event_log(task_id, created_at DESC, sequence DESC)", database: database)
            try execute("CREATE INDEX IF NOT EXISTS idx_event_log_created ON event_log(created_at DESC, sequence DESC)", database: database)
            try execute("""
            INSERT INTO event_log (id, task_id, run_id, kind, created_at, json)
            SELECT id, task_id, run_id, kind, created_at, json
            FROM events
            WHERE NOT EXISTS (
              SELECT 1 FROM event_log WHERE event_log.id = events.id
            )
            ORDER BY created_at ASC
            """, database: database)
            try execute("PRAGMA user_version = 2", database: database)
            try execute("COMMIT", database: database)
        } catch {
            try? execute("ROLLBACK", database: database)
            throw error
        }
    }

    private static func migrateToVersion3(database: OpaquePointer) throws {
        try execute("BEGIN IMMEDIATE", database: database)
        do {
            try execute("""
            CREATE TABLE IF NOT EXISTS sync_outbox (
              id TEXT PRIMARY KEY NOT NULL,
              aggregate TEXT NOT NULL,
              aggregate_id TEXT NOT NULL,
              operation TEXT NOT NULL,
              status TEXT NOT NULL,
              attempt_count INTEGER NOT NULL,
              available_at REAL NOT NULL,
              last_error TEXT,
              external_reference TEXT,
              created_at REAL NOT NULL,
              updated_at REAL NOT NULL,
              json BLOB NOT NULL
            )
            """, database: database)
            try execute("CREATE INDEX IF NOT EXISTS idx_sync_outbox_pending ON sync_outbox(status, available_at ASC, created_at ASC)", database: database)
            try execute("CREATE INDEX IF NOT EXISTS idx_sync_outbox_aggregate ON sync_outbox(aggregate, aggregate_id)", database: database)

            try execute("""
            CREATE TABLE IF NOT EXISTS sync_metadata (
              aggregate TEXT NOT NULL,
              aggregate_id TEXT NOT NULL,
              external_reference TEXT,
              revision TEXT,
              remote_updated_at REAL,
              last_pulled_at REAL,
              last_pushed_at REAL,
              has_local_changes INTEGER NOT NULL,
              updated_at REAL NOT NULL,
              json BLOB NOT NULL,
              PRIMARY KEY(aggregate, aggregate_id)
            )
            """, database: database)
            try execute("CREATE INDEX IF NOT EXISTS idx_sync_metadata_external_reference ON sync_metadata(external_reference)", database: database)
            try execute("CREATE INDEX IF NOT EXISTS idx_sync_metadata_local_changes ON sync_metadata(has_local_changes, updated_at DESC)", database: database)

            try execute("""
            CREATE TABLE IF NOT EXISTS sync_cursors (
              scope TEXT PRIMARY KEY NOT NULL,
              cursor TEXT,
              updated_at REAL NOT NULL,
              json BLOB NOT NULL
            )
            """, database: database)

            try execute("PRAGMA user_version = 3", database: database)
            try execute("COMMIT", database: database)
        } catch {
            try? execute("ROLLBACK", database: database)
            throw error
        }
    }

    private static func userVersion(database: OpaquePointer) throws -> Int {
        let sql = "PRAGMA user_version"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteStoreError.statementFailed(sql, errorMessage(database))
        }

        defer {
            sqlite3_finalize(statement)
        }

        let result = sqlite3_step(statement)
        switch result {
        case SQLITE_ROW:
            return Int(sqlite3_column_int(statement, 0))
        case SQLITE_DONE:
            return 0
        default:
            throw SQLiteStoreError.statementFailed(sql, errorMessage(database))
        }
    }

    private func execute(_ sql: String) throws {
        guard let database else {
            throw SQLiteStoreError.closed
        }

        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw SQLiteStoreError.statementFailed(sql, SQLiteStore.errorMessage(database))
        }
    }

    private static func execute(_ sql: String, database: OpaquePointer) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw SQLiteStoreError.statementFailed(sql, errorMessage(database))
        }
    }

    private func write(_ sql: String, bind: (OpaquePointer) throws -> Void) throws {
        try withStatement(sql) { statement in
            try bind(statement)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw SQLiteStoreError.statementFailed(sql, SQLiteStore.errorMessage(database))
            }
        }
    }

    private func readRows<T>(
        _ sql: String,
        decode: (OpaquePointer) throws -> T
    ) throws -> [T] {
        try readRows(sql, bind: { _ in }, decode: decode)
    }

    private func readRows<T>(
        _ sql: String,
        bind: (OpaquePointer) throws -> Void,
        decode: (OpaquePointer) throws -> T
    ) throws -> [T] {
        try withStatement(sql) { statement in
            try bind(statement)

            var rows: [T] = []
            while true {
                let result = sqlite3_step(statement)
                switch result {
                case SQLITE_ROW:
                    rows.append(try decode(statement))
                case SQLITE_DONE:
                    return rows
                default:
                    throw SQLiteStoreError.statementFailed(sql, SQLiteStore.errorMessage(database))
                }
            }
        }
    }

    private func readOptionalRow<T>(
        _ sql: String,
        bind: (OpaquePointer) throws -> Void,
        decode: (OpaquePointer) throws -> T
    ) throws -> T? {
        try withStatement(sql) { statement in
            try bind(statement)

            let result = sqlite3_step(statement)
            switch result {
            case SQLITE_ROW:
                return try decode(statement)
            case SQLITE_DONE:
                return nil
            default:
                throw SQLiteStoreError.statementFailed(sql, SQLiteStore.errorMessage(database))
            }
        }
    }

    private func withStatement<T>(_ sql: String, body: (OpaquePointer) throws -> T) throws -> T {
        guard let database else {
            throw SQLiteStoreError.closed
        }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteStoreError.statementFailed(sql, SQLiteStore.errorMessage(database))
        }

        defer {
            sqlite3_finalize(statement)
        }

        return try body(statement)
    }

    private func bindSyncOutboxEntry(_ entry: SyncOutboxEntry, in statement: OpaquePointer) throws {
        try bind(entry.id, to: 1, in: statement)
        try bind(entry.aggregate.rawValue, to: 2, in: statement)
        try bind(entry.aggregateID, to: 3, in: statement)
        try bind(entry.operation.rawValue, to: 4, in: statement)
        try bind(entry.status.rawValue, to: 5, in: statement)
        try bind(entry.attemptCount, to: 6, in: statement)
        try bind(entry.availableAt, to: 7, in: statement)
        try bind(entry.lastError, to: 8, in: statement)
        try bind(entry.externalReference, to: 9, in: statement)
        try bind(entry.createdAt, to: 10, in: statement)
        try bind(entry.updatedAt, to: 11, in: statement)
        try bindEncoded(entry, to: 12, in: statement)
    }

    private func bind(_ value: String?, to index: Int32, in statement: OpaquePointer) throws {
        let result: Int32
        if let value {
            result = sqlite3_bind_text(statement, index, value, -1, SQLiteStore.transientDestructor)
        } else {
            result = sqlite3_bind_null(statement, index)
        }

        guard result == SQLITE_OK else {
            throw SQLiteStoreError.bindFailed(SQLiteStore.errorMessage(database))
        }
    }

    private func bind(_ value: Int, to index: Int32, in statement: OpaquePointer) throws {
        guard sqlite3_bind_int64(statement, index, sqlite3_int64(value)) == SQLITE_OK else {
            throw SQLiteStoreError.bindFailed(SQLiteStore.errorMessage(database))
        }
    }

    private func bind(_ value: Date?, to index: Int32, in statement: OpaquePointer) throws {
        let result: Int32
        if let value {
            result = sqlite3_bind_double(statement, index, value.timeIntervalSince1970)
        } else {
            result = sqlite3_bind_null(statement, index)
        }

        guard result == SQLITE_OK else {
            throw SQLiteStoreError.bindFailed(SQLiteStore.errorMessage(database))
        }
    }

    private func bindEncoded<T: Encodable>(_ value: T, to index: Int32, in statement: OpaquePointer) throws {
        let data = try encoder.encode(value)
        try data.withUnsafeBytes { buffer in
            guard sqlite3_bind_blob(
                statement,
                index,
                buffer.baseAddress,
                Int32(buffer.count),
                SQLiteStore.transientDestructor
            ) == SQLITE_OK else {
                throw SQLiteStoreError.bindFailed(SQLiteStore.errorMessage(database))
            }
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, fromColumn column: Int32, in statement: OpaquePointer) throws -> T {
        let byteCount = Int(sqlite3_column_bytes(statement, column))
        guard let bytes = sqlite3_column_blob(statement, column) else {
            throw SQLiteStoreError.decodeFailed
        }

        let data = Data(bytes: bytes, count: byteCount)
        return try decoder.decode(type, from: data)
    }

    private static var transientDestructor: sqlite3_destructor_type {
        unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    }

    private static func errorMessage(_ database: OpaquePointer?) -> String {
        guard let database, let message = sqlite3_errmsg(database) else {
            return "Unknown SQLite error"
        }

        return String(cString: message)
    }
}

public enum SQLiteStoreError: Error, Equatable, CustomStringConvertible {
    case applicationSupportDirectoryUnavailable
    case openFailed(String, String)
    case statementFailed(String, String)
    case bindFailed(String)
    case decodeFailed
    case closed

    public var description: String {
        switch self {
        case .applicationSupportDirectoryUnavailable:
            "Application Support directory is unavailable"
        case let .openFailed(path, message):
            "Could not open SQLite store at \(path): \(message)"
        case let .statementFailed(sql, message):
            "SQLite statement failed: \(message) [\(sql)]"
        case let .bindFailed(message):
            "SQLite bind failed: \(message)"
        case .decodeFailed:
            "Could not decode SQLite row payload"
        case .closed:
            "SQLite store is closed"
        }
    }
}
