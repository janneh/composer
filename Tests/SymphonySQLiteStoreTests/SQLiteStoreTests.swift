import XCTest
import SQLite3
import SymphonyCore
@testable import SymphonySQLiteStore

final class SQLiteStoreTests: XCTestCase {
    func testPersistsProjectsTasksRunsAndEvents() async throws {
        let store = try makeStore()
        let createdAt = Date(timeIntervalSince1970: 100)
        let updatedAt = Date(timeIntervalSince1970: 101)
        let project = Project(
            id: ProjectID(rawValue: "project-1"),
            name: "Composer",
            defaultAgent: AgentConfiguration(kind: .codex, model: "default"),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        let task = WorkItem(
            id: TaskID(rawValue: "task-1"),
            projectID: project.id,
            identifier: "LOCAL-1",
            title: "Add SQLite store",
            state: .ready,
            priority: .high,
            labels: ["storage"],
            preferredAgent: AgentConfiguration(kind: .claude),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        let run = RunAttempt(
            id: RunID(rawValue: "run-1"),
            taskID: task.id,
            agent: AgentConfiguration(kind: .codex),
            status: .running,
            workspace: WorkspaceReference(
                path: "/tmp/composer-workspaces/local-1",
                cleanupPolicy: .removeOnCompletion,
                preparedAt: Date(timeIntervalSince1970: 150)
            ),
            startedAt: Date(timeIntervalSince1970: 200)
        )
        let event = RuntimeEvent(
            id: "event-1",
            taskID: task.id,
            runID: run.id,
            kind: .runStarted,
            message: "Run started",
            payload: ["provider": "codex"],
            createdAt: Date(timeIntervalSince1970: 300)
        )

        try await store.upsertProject(project)
        try await store.upsertTask(task)
        try await store.upsertRun(run)
        try await store.appendEvent(event)

        let persistedProject = try await store.project(id: project.id)
        let persistedTask = try await store.task(id: task.id)
        let runs = try await store.listRuns(taskID: task.id)
        let events = try await store.listEvents(taskID: task.id, limit: 10)

        XCTAssertEqual(persistedProject, project)
        XCTAssertEqual(persistedTask, task)
        XCTAssertEqual(runs, [run])
        XCTAssertEqual(events, [event])
    }

    func testSortsTasksLikeLocalStore() async throws {
        let store = try makeStore()
        let project = Project(id: ProjectID(rawValue: "project-1"), name: "Composer")
        let olderHigh = WorkItem(
            id: TaskID(rawValue: "task-1"),
            projectID: project.id,
            identifier: "LOCAL-1",
            title: "Older high",
            priority: .high,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let newerNormal = WorkItem(
            id: TaskID(rawValue: "task-2"),
            projectID: project.id,
            identifier: "LOCAL-2",
            title: "Newer normal",
            priority: .normal,
            updatedAt: Date(timeIntervalSince1970: 300)
        )
        let newerHigh = WorkItem(
            id: TaskID(rawValue: "task-3"),
            projectID: project.id,
            identifier: "LOCAL-3",
            title: "Newer high",
            priority: .high,
            updatedAt: Date(timeIntervalSince1970: 200)
        )

        try await store.upsertProject(project)
        try await store.upsertTask(olderHigh)
        try await store.upsertTask(newerNormal)
        try await store.upsertTask(newerHigh)

        let tasks = try await store.listTasks(projectID: project.id)
        XCTAssertEqual(tasks.map(\.id), [newerHigh.id, olderHigh.id, newerNormal.id])
    }

    func testDeleteProjectCascadesProjectData() async throws {
        let store = try makeStore()
        let project = Project(id: ProjectID(rawValue: "project-1"), name: "Composer")
        let task = WorkItem(id: TaskID(rawValue: "task-1"), projectID: project.id, identifier: "LOCAL-1", title: "Task")
        let run = RunAttempt(id: RunID(rawValue: "run-1"), taskID: task.id, agent: AgentConfiguration(kind: .codex))
        let event = RuntimeEvent(
            id: "event-1",
            taskID: task.id,
            runID: run.id,
            kind: .runQueued,
            message: "Queued",
            createdAt: Date(timeIntervalSince1970: 100)
        )

        try await store.upsertProject(project)
        try await store.upsertTask(task)
        try await store.upsertRun(run)
        try await store.appendEvent(event)
        try await store.deleteProject(id: project.id)

        let persistedProject = try await store.project(id: project.id)
        let persistedTask = try await store.task(id: task.id)
        let runs = try await store.listRuns(taskID: task.id)
        let events = try await store.listEvents(taskID: task.id, limit: 10)

        XCTAssertNil(persistedProject)
        XCTAssertNil(persistedTask)
        XCTAssertEqual(runs, [])
        XCTAssertEqual(events, [event])
    }

    func testEventLogAllowsRepeatedEventIDsAndPreservesAppendOrder() async throws {
        let store = try makeStore()
        let date = Date(timeIntervalSince1970: 100)
        let first = RuntimeEvent(
            id: "event-1",
            kind: .taskUpdated,
            message: "First",
            createdAt: date
        )
        let second = RuntimeEvent(
            id: "event-1",
            kind: .taskUpdated,
            message: "Second",
            createdAt: date
        )

        try await store.appendEvent(first)
        try await store.appendEvent(second)

        let events = try await store.listEvents(taskID: nil, limit: 10)
        XCTAssertEqual(events.map(\.message), ["Second", "First"])
    }

    func testPersistsSyncOutboxEntries() async throws {
        let store = try makeStore()
        let date = Date(timeIntervalSince1970: 100)
        let due = SyncOutboxEntry(
            id: "outbox-1",
            aggregate: .task,
            aggregateID: "task-1",
            operation: .update,
            payload: ["state": "ready"],
            availableAt: date,
            createdAt: date,
            updatedAt: date
        )
        let future = SyncOutboxEntry(
            id: "outbox-2",
            aggregate: .project,
            aggregateID: "project-1",
            operation: .update,
            availableAt: date.addingTimeInterval(60),
            createdAt: date.addingTimeInterval(1),
            updatedAt: date.addingTimeInterval(1)
        )

        try await store.enqueueSyncOutboxEntry(future)
        try await store.enqueueSyncOutboxEntry(due)

        let pending = try await store.listPendingSyncOutboxEntries(limit: 10, now: date)
        XCTAssertEqual(pending, [due])

        var sent = due
        sent.status = .sent
        sent.externalReference = "remote-task-1"
        sent.receiptMetadata = ["revision": "2"]
        sent.updatedAt = date.addingTimeInterval(10)
        try await store.updateSyncOutboxEntry(sent)

        let remaining = try await store.listPendingSyncOutboxEntries(limit: 10, now: date.addingTimeInterval(120))
        XCTAssertEqual(remaining, [future])
    }

    func testPersistsSyncMetadataAndCursors() async throws {
        let store = try makeStore()
        let date = Date(timeIntervalSince1970: 100)
        let record = SyncMetadataRecord(
            aggregate: .task,
            aggregateID: "task-1",
            externalReference: "linear-task-1",
            version: SyncRecordVersion(revision: "rev-1", updatedAt: date),
            lastPulledAt: date.addingTimeInterval(10),
            lastPushedAt: date.addingTimeInterval(20),
            hasLocalChanges: true,
            updatedAt: date.addingTimeInterval(30)
        )
        let cursor = SyncCursorRecord(
            scope: "linear:team-1",
            cursor: "cursor-1",
            updatedAt: date.addingTimeInterval(40)
        )

        try await store.upsertSyncMetadataRecord(record)
        try await store.upsertSyncCursorRecord(cursor)

        let persistedRecord = try await store.syncMetadataRecord(aggregate: .task, aggregateID: "task-1")
        let persistedCursor = try await store.syncCursorRecord(scope: "linear:team-1")
        XCTAssertEqual(persistedRecord, record)
        XCTAssertEqual(persistedCursor, cursor)
    }

    func testSearchTasksUsesFullTextIndexAndProjectFilter() async throws {
        let store = try makeStore()
        let project = Project(id: ProjectID(rawValue: "project-1"), name: "Composer")
        let otherProject = Project(id: ProjectID(rawValue: "project-2"), name: "Other")
        let syncTask = WorkItem(
            id: TaskID(rawValue: "task-1"),
            projectID: project.id,
            identifier: "LOCAL-1",
            title: "Build sync metadata search",
            description: "Index task descriptions",
            labels: ["storage", "search"]
        )
        let otherTask = WorkItem(
            id: TaskID(rawValue: "task-2"),
            projectID: otherProject.id,
            identifier: "OTHER-1",
            title: "Search in another project"
        )

        try await store.upsertProject(project)
        try await store.upsertProject(otherProject)
        try await store.upsertTask(syncTask)
        try await store.upsertTask(otherTask)

        let projectResults = try await store.searchTasks(query: "metadata", projectID: project.id, limit: 10)
        let allResults = try await store.searchTasks(query: "search", projectID: nil, limit: 10)

        XCTAssertEqual(projectResults.map(\.id), [syncTask.id])
        XCTAssertEqual(Set(allResults.map(\.id)), [syncTask.id, otherTask.id])
    }

    func testSearchTasksIgnoresEmptyQueryAndLimit() async throws {
        let store = try makeStore()
        let project = Project(id: ProjectID(rawValue: "project-1"), name: "Composer")
        let task = WorkItem(
            id: TaskID(rawValue: "task-1"),
            projectID: project.id,
            identifier: "LOCAL-1",
            title: "Build search"
        )

        try await store.upsertProject(project)
        try await store.upsertTask(task)

        let emptyResults = try await store.searchTasks(query: "   ", projectID: nil, limit: 10)
        let zeroLimitResults = try await store.searchTasks(query: "search", projectID: nil, limit: 0)

        XCTAssertEqual(emptyResults, [])
        XCTAssertEqual(zeroLimitResults, [])
    }

    func testSearchIndexMigrationBackfillsExistingTaskContent() async throws {
        let fileURL = makeStoreFileURL()
        let project = Project(id: ProjectID(rawValue: "project-1"), name: "Composer")
        let task = WorkItem(
            id: TaskID(rawValue: "task-1"),
            projectID: project.id,
            identifier: "LOCAL-1",
            title: "Migrate durable search",
            description: "Backfill hydraulic queues",
            labels: ["legacy"]
        )

        do {
            let store = try SQLiteStore(fileURL: fileURL)
            try await store.upsertProject(project)
            try await store.upsertTask(task)
        }

        try withRawDatabase(fileURL: fileURL) { database in
            try executeRaw("DROP TABLE task_search", database: database)
            try executeRaw("PRAGMA user_version = 3", database: database)
        }

        let migratedStore = try SQLiteStore(fileURL: fileURL)
        let results = try await migratedStore.searchTasks(query: "hydraulic", projectID: project.id, limit: 10)

        XCTAssertEqual(results.map(\.id), [task.id])
    }

    private func makeStore() throws -> SQLiteStore {
        try SQLiteStore(fileURL: makeStoreFileURL())
    }

    private func makeStoreFileURL() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("composer-sqlite-tests-\(UUID().uuidString)", isDirectory: true)
        return directory.appendingPathComponent("store.sqlite3")
    }

    private func withRawDatabase(fileURL: URL, body: (OpaquePointer) throws -> Void) throws {
        var database: OpaquePointer?
        guard sqlite3_open_v2(fileURL.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK,
              let database else {
            defer {
                sqlite3_close(database)
            }
            throw RawSQLiteError.openFailed(fileURL.path)
        }

        defer {
            sqlite3_close(database)
        }

        try body(database)
    }

    private func executeRaw(_ sql: String, database: OpaquePointer) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            let message = sqlite3_errmsg(database).map { String(cString: $0) } ?? "Unknown SQLite error"
            throw RawSQLiteError.statementFailed(sql, message)
        }
    }
}

private enum RawSQLiteError: Error {
    case openFailed(String)
    case statementFailed(String, String)
}
