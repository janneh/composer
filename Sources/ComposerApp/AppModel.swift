import Foundation
import SwiftUI
import SymphonyCore
import SymphonyLocalStore
import SymphonyRuntime

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var projects: [Project] = []
    @Published private(set) var tasks: [WorkItem] = []
    @Published private(set) var selectedTaskEvents: [RuntimeEvent] = []
    @Published var selectedProjectID: ProjectID?
    @Published var selectedTaskID: TaskID?
    @Published var errorMessage: String?

    private let store: LocalJSONStore
    private let orchestrator: Orchestrator

    init() {
        let store = Self.makeStore()
        self.store = store
        orchestrator = Orchestrator(
            taskStore: store,
            projectStore: store,
            runners: [
                NoopAgentRunner(kind: .codex),
                NoopAgentRunner(kind: .claude),
                NoopAgentRunner(kind: .gemini)
            ]
        )
    }

    var selectedProject: Project? {
        guard let selectedProjectID else {
            return projects.first
        }
        return projects.first { $0.id == selectedProjectID }
    }

    var selectedTask: WorkItem? {
        guard let selectedTaskID else {
            return nil
        }
        return tasks.first { $0.id == selectedTaskID }
    }

    func tasks(in state: WorkState) -> [WorkItem] {
        tasks.filter { $0.state == state }
    }

    func load() async {
        do {
            projects = try await store.listProjects()
            if projects.isEmpty {
                try await seedInitialProject()
                projects = try await store.listProjects()
            }

            selectedProjectID = selectedProjectID ?? projects.first?.id
            try await refreshTasks()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshTasks() async throws {
        tasks = try await store.listTasks(projectID: selectedProjectID)
        if selectedTaskID == nil {
            selectedTaskID = tasks.first?.id
        } else if let selectedTaskID, !tasks.contains(where: { $0.id == selectedTaskID }) {
            self.selectedTaskID = tasks.first?.id
        }
        selectedTaskEvents = try await loadSelectedTaskEvents()
    }

    func selectProject(_ project: Project) async {
        selectedProjectID = project.id
        selectedTaskID = nil
        do {
            try await refreshTasks()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectTask(_ task: WorkItem) {
        selectedTaskID = task.id
        Task {
            await refreshSelectedTaskEvents()
        }
    }

    func createTask() async {
        guard let projectID = selectedProject?.id else {
            return
        }

        do {
            let nextNumber = tasks.count + 1
            let task = WorkItem(
                projectID: projectID,
                identifier: "LOCAL-\(nextNumber)",
                title: "Untitled task",
                description: "",
                state: .backlog,
                priority: .normal,
                labels: ["local"]
            )
            try await store.upsertTask(task)
            try await store.appendEvent(RuntimeEvent(taskID: task.id, kind: .taskCreated, message: "Task created"))
            selectedTaskID = task.id
            try await refreshTasks()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func move(_ task: WorkItem, to state: WorkState) async {
        do {
            let moved = task.moving(to: state)
            try await store.upsertTask(moved)
            try await store.appendEvent(RuntimeEvent(taskID: task.id, kind: .taskMoved, message: "Moved to \(state.title)"))
            selectedTaskID = task.id
            try await refreshTasks()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateTask(_ task: WorkItem) async {
        do {
            var updated = task
            updated.updatedAt = Date()
            try await store.upsertTask(updated)
            try await store.appendEvent(RuntimeEvent(taskID: task.id, kind: .taskUpdated, message: "Task updated"))
            selectedTaskID = task.id
            try await refreshTasks()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func dispatchPreview() async -> DispatchPlan? {
        do {
            return try await orchestrator.previewDispatch(projectID: selectedProjectID)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private static func makeStore() -> LocalJSONStore {
        do {
            return try LocalJSONStore.defaultStore()
        } catch {
            let fallback = FileManager.default.temporaryDirectory
                .appendingPathComponent("Composer-local-store.json")
            return LocalJSONStore(fileURL: fallback)
        }
    }

    private func refreshSelectedTaskEvents() async {
        do {
            selectedTaskEvents = try await loadSelectedTaskEvents()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadSelectedTaskEvents() async throws -> [RuntimeEvent] {
        guard let selectedTaskID else {
            return []
        }
        return try await store.listEvents(taskID: selectedTaskID, limit: 50)
    }

    private func seedInitialProject() async throws {
        let project = Project(
            name: "Local Project",
            defaultAgent: AgentConfiguration(kind: .codex, model: "default")
        )
        try await store.upsertProject(project)

        let seededTasks = [
            WorkItem(
                projectID: project.id,
                identifier: "LOCAL-1",
                title: "Create Symphony-compatible task schema",
                description: "Define the local task shape so storage and external trackers can implement the same contract.",
                state: .ready,
                priority: .high,
                labels: ["core", "local-first"],
                preferredAgent: AgentConfiguration(kind: .codex)
            ),
            WorkItem(
                projectID: project.id,
                identifier: "LOCAL-2",
                title: "Add Claude runner adapter",
                description: "Map Claude Code stream-json output into normalized agent run events.",
                state: .backlog,
                priority: .normal,
                labels: ["agent", "claude"],
                preferredAgent: AgentConfiguration(kind: .claude)
            ),
            WorkItem(
                projectID: project.id,
                identifier: "LOCAL-3",
                title: "Design sync outbox boundary",
                description: "Keep local mutations append-only so cloud sync can be introduced without rewriting the app model.",
                state: .humanReview,
                priority: .normal,
                labels: ["sync", "architecture"],
                preferredAgent: AgentConfiguration(kind: .gemini)
            )
        ]

        for task in seededTasks {
            try await store.upsertTask(task)
        }
    }
}
