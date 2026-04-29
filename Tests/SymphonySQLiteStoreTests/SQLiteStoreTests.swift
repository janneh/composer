import XCTest
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
        let event = RuntimeEvent(id: "event-1", taskID: task.id, runID: run.id, kind: .runQueued, message: "Queued")

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
        XCTAssertEqual(events, [])
    }

    private func makeStore() throws -> SQLiteStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("composer-sqlite-tests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("store.sqlite3")
        return try SQLiteStore(fileURL: fileURL)
    }
}
