import Foundation
import SwiftUI
import ComposerStorage
import SymphonyCore
import SymphonyInterfaces
import SymphonyRuntime
import SymphonyWorkflow

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var projects: [Project] = []
    @Published private(set) var tasks: [WorkItem] = []
    @Published private(set) var selectedTaskEvents: [RuntimeEvent] = []
    @Published private(set) var workflowDiagnostics: [WorkflowDiagnostic] = []
    @Published var selectedProjectID: ProjectID?
    @Published var selectedTaskID: TaskID?
    @Published var errorMessage: String?

    private let store: any ComposerStore
    private let orchestrator: Orchestrator
    private let workflowLoader: WorkflowLoader
    private var storeChangeTask: Task<Void, Never>?
    private var reloadTask: Task<Void, Never>?
    private(set) var storageBackend: StoreBackend
    private(set) var storeFileURL: URL

    init(storeSelection: StoreSelection? = nil, workflowLoader: WorkflowLoader = WorkflowLoader()) {
        let resolvedSelection = storeSelection.map { ($0, nil) } ?? Self.makeStoreSelection()
        let selection = resolvedSelection.0
        store = selection.store
        self.workflowLoader = workflowLoader
        storageBackend = selection.backend
        storeFileURL = selection.fileURL
        errorMessage = resolvedSelection.1
        orchestrator = Orchestrator(
            taskStore: selection.store,
            projectStore: selection.store,
            runners: [
                NoopAgentRunner(kind: .codex),
                NoopAgentRunner(kind: .claude),
                NoopAgentRunner(kind: .gemini)
            ]
        )
        configureStoreWatcher()
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

    func reload() async {
        do {
            projects = try await store.listProjects()
            if projects.isEmpty {
                try await createInitialProject()
                projects = try await store.listProjects()
            }

            if let selectedProjectID, !projects.contains(where: { $0.id == selectedProjectID }) {
                self.selectedProjectID = projects.first?.id
            } else {
                selectedProjectID = selectedProjectID ?? projects.first?.id
            }

            try await refreshTasks()
            refreshWorkflowDiagnostics()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func scheduleReloadFromStoreChange() {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else {
                return
            }
            await self?.reload()
        }
    }

    func load() async {
        await reload()
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
            refreshWorkflowDiagnostics()
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

    func createProject(
        name: String,
        repositoryPath: String?,
        workflowPath: String?,
        defaultAgent: AgentConfiguration
    ) async {
        do {
            let now = Date()
            let project = Project(
                name: name,
                repositoryPath: repositoryPath,
                workflowPath: workflowPath,
                defaultAgent: defaultAgent,
                createdAt: now,
                updatedAt: now
            )
            try await store.upsertProject(project)
            projects = try await store.listProjects()
            selectedProjectID = project.id
            selectedTaskID = nil
            try await refreshTasks()
            refreshWorkflowDiagnostics()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateProject(_ project: Project) async {
        do {
            var updated = project
            updated.updatedAt = Date()
            try await store.upsertProject(updated)
            projects = try await store.listProjects()
            selectedProjectID = updated.id
            try await refreshTasks()
            refreshWorkflowDiagnostics()
        } catch {
            errorMessage = error.localizedDescription
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

    private static func makeStoreSelection() -> (StoreSelection, String?) {
        do {
            let configuration = try AppStorageConfiguration.fromLaunchConfiguration()
            return (try StoreFactory.makeStore(configuration: configuration.storeConfiguration), nil)
        } catch {
            let fallback = FileManager.default.temporaryDirectory
                .appendingPathComponent("Composer-local-store.json")
            do {
                let selection = try StoreFactory.makeStore(
                    configuration: StoreConfiguration(backend: .json, fileURL: fallback)
                )
                return (
                    selection,
                    "Storage configuration failed: \(error.localizedDescription). Using \(fallback.path)."
                )
            } catch {
                preconditionFailure("Could not create fallback Composer store: \(error.localizedDescription)")
            }
        }
    }

    private func configureStoreWatcher() {
        storeChangeTask?.cancel()
        guard storageBackend == .json else {
            return
        }

        let fileURL = storeFileURL
        storeChangeTask = Task { [weak self] in
            do {
                for try await _ in StoreFileWatcher.changes(fileURL: fileURL) {
                    guard !Task.isCancelled else {
                        return
                    }
                    await MainActor.run {
                        self?.scheduleReloadFromStoreChange()
                    }
                }
            } catch {
                await MainActor.run {
                    self?.errorMessage = error.localizedDescription
                }
            }
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

    private func refreshWorkflowDiagnostics() {
        guard let selectedProject else {
            workflowDiagnostics = []
            return
        }

        workflowDiagnostics = workflowLoader.validate(project: selectedProject)
    }

    private func createInitialProject() async throws {
        let project = Project(
            name: "Local Project",
            defaultAgent: AgentConfiguration(kind: .codex, model: "default")
        )
        try await store.upsertProject(project)
    }
}
