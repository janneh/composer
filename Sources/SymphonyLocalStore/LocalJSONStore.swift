import Foundation
import SymphonyCore
import SymphonyInterfaces

public actor LocalJSONStore: ProjectStore, TaskStore, RunStore, EventStore {
    private struct Snapshot: Codable {
        var projects: [Project]
        var tasks: [WorkItem]
        var runs: [RunAttempt]
        var events: [RuntimeEvent]

        static let empty = Snapshot(projects: [], tasks: [], runs: [], events: [])
    }

    private let fileURL: URL
    private var cachedSnapshot: Snapshot?

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func defaultStore(appName: String = "Composer") throws -> LocalJSONStore {
        let directory = try applicationSupportDirectory(appName: appName)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return LocalJSONStore(fileURL: directory.appendingPathComponent("local-store.json"))
    }

    private static func applicationSupportDirectory(appName: String) throws -> URL {
        guard let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw LocalStoreError.applicationSupportDirectoryUnavailable
        }

        return baseURL.appendingPathComponent(appName, isDirectory: true)
    }

    public func listProjects() async throws -> [Project] {
        try load().projects.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func project(id: ProjectID) async throws -> Project? {
        try load().projects.first { $0.id == id }
    }

    public func upsertProject(_ project: Project) async throws {
        var snapshot = try load()
        if let index = snapshot.projects.firstIndex(where: { $0.id == project.id }) {
            snapshot.projects[index] = project
        } else {
            snapshot.projects.append(project)
        }
        try save(snapshot)
    }

    public func deleteProject(id: ProjectID) async throws {
        var snapshot = try load()
        snapshot.projects.removeAll { $0.id == id }
        snapshot.tasks.removeAll { $0.projectID == id }
        try save(snapshot)
    }

    public func listTasks(projectID: ProjectID?) async throws -> [WorkItem] {
        let tasks = try load().tasks
        let filtered = projectID.map { id in
            tasks.filter { $0.projectID == id }
        } ?? tasks

        return filtered.sorted { lhs, rhs in
            if lhs.priority.rawValue != rhs.priority.rawValue {
                return lhs.priority.rawValue > rhs.priority.rawValue
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    public func task(id: TaskID) async throws -> WorkItem? {
        try load().tasks.first { $0.id == id }
    }

    public func upsertTask(_ task: WorkItem) async throws {
        var snapshot = try load()
        if let index = snapshot.tasks.firstIndex(where: { $0.id == task.id }) {
            snapshot.tasks[index] = task
        } else {
            snapshot.tasks.append(task)
        }
        try save(snapshot)
    }

    public func deleteTask(id: TaskID) async throws {
        var snapshot = try load()
        snapshot.tasks.removeAll { $0.id == id }
        snapshot.runs.removeAll { $0.taskID == id }
        snapshot.events.removeAll { $0.taskID == id }
        try save(snapshot)
    }

    public func listRuns(taskID: TaskID?) async throws -> [RunAttempt] {
        let runs = try load().runs
        let filtered = taskID.map { id in
            runs.filter { $0.taskID == id }
        } ?? runs

        return filtered.sorted {
            ($0.startedAt ?? .distantPast) > ($1.startedAt ?? .distantPast)
        }
    }

    public func upsertRun(_ run: RunAttempt) async throws {
        var snapshot = try load()
        if let index = snapshot.runs.firstIndex(where: { $0.id == run.id }) {
            snapshot.runs[index] = run
        } else {
            snapshot.runs.append(run)
        }
        try save(snapshot)
    }

    public func appendEvent(_ event: RuntimeEvent) async throws {
        var snapshot = try load()
        snapshot.events.append(event)
        try save(snapshot)
    }

    public func listEvents(taskID: TaskID?, limit: Int) async throws -> [RuntimeEvent] {
        let events = try load().events
        let filtered = taskID.map { id in
            events.filter { $0.taskID == id }
        } ?? events

        return Array(filtered.sorted { $0.createdAt > $1.createdAt }.prefix(max(0, limit)))
    }

    private func load() throws -> Snapshot {
        if let cachedSnapshot {
            return cachedSnapshot
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            cachedSnapshot = .empty
            return .empty
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(Snapshot.self, from: data)
        cachedSnapshot = snapshot
        return snapshot
    }

    private func save(_ snapshot: Snapshot) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: [.atomic])
        cachedSnapshot = snapshot
    }
}

public enum LocalStoreError: Error {
    case applicationSupportDirectoryUnavailable
}
