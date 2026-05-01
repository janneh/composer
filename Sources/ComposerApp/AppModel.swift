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

    private let runtimeEnvironment: AppRuntimeEnvironment
    private let store: any ComposerStore
    private let runtimeService: any RuntimeService
    private let workflowLoader: WorkflowLoader
    private var storeChangeTask: Task<Void, Never>?
    private var reloadTask: Task<Void, Never>?
    private(set) var storageBackend: StoreBackend
    private(set) var storeFileURL: URL
    private(set) var canDispatchReady: Bool

    init(runtimeEnvironment: AppRuntimeEnvironment = .live()) {
        self.runtimeEnvironment = runtimeEnvironment
        store = runtimeEnvironment.store
        runtimeService = runtimeEnvironment.runtimeService
        workflowLoader = runtimeEnvironment.workflowLoader
        storageBackend = runtimeEnvironment.storageBackend
        storeFileURL = runtimeEnvironment.storeFileURL
        canDispatchReady = runtimeEnvironment.supportsRunDispatch
        errorMessage = runtimeEnvironment.startupWarning
        configureStoreWatcher()
    }

    convenience init(storeSelection: StoreSelection, workflowLoader: WorkflowLoader = WorkflowLoader()) {
        self.init(runtimeEnvironment: AppRuntimeEnvironment(storeSelection: storeSelection, workflowLoader: workflowLoader))
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
            replaceProjects(try await store.listProjects())
            if projects.isEmpty {
                try await createInitialProject()
                replaceProjects(try await store.listProjects())
            }

            if let selectedProjectID {
                if !projects.contains(where: { $0.id == selectedProjectID }) {
                    self.selectedProjectID = projects.first?.id
                }
            } else {
                selectedProjectID = projects.first?.id
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
        let loadedTasks = try await store.listTasks(projectID: selectedProjectID)
        replaceTasks(loadedTasks)
        if let selectedTaskID, !loadedTasks.contains(where: { $0.id == selectedTaskID }) {
            self.selectedTaskID = nil
        }
        replaceSelectedTaskEvents(try await loadSelectedTaskEvents())
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
            replaceProjects(try await store.listProjects())
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
            replaceProjects(try await store.listProjects())
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

    func deleteTask(_ task: WorkItem) async {
        do {
            let now = Date()
            var updatedTasksByID: [TaskID: WorkItem] = [:]
            let dependentTasks = tasks.filter { $0.blockedBy.contains(task.id) }

            for dependentTask in dependentTasks {
                var updated = dependentTask
                updated.blockedBy.removeAll { $0 == task.id }
                updated.updatedAt = now
                updatedTasksByID[updated.id] = updated
                try await store.upsertTask(updated)
                try await store.appendEvent(RuntimeEvent(
                    taskID: updated.id,
                    kind: .taskUpdated,
                    message: "Removed dependency on deleted task \(task.identifier)"
                ))
            }

            try await store.appendEvent(RuntimeEvent(
                kind: .taskDeleted,
                message: "Task \(task.identifier) deleted",
                payload: [
                    "taskID": task.id.rawValue,
                    "identifier": task.identifier,
                    "title": task.title
                ]
            ))
            try await store.deleteTask(id: task.id)

            if selectedTaskID == task.id {
                selectedTaskID = nil
            }

            let remainingTasks = tasks.compactMap { existingTask -> WorkItem? in
                if existingTask.id == task.id {
                    return nil
                }
                return updatedTasksByID[existingTask.id] ?? existingTask
            }
            replaceTasks(Self.sortTasks(remainingTasks))
            replaceSelectedTaskEvents(try await loadSelectedTaskEvents())
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func dispatchPreview() async -> DispatchPlan? {
        do {
            return try await runtimeService.previewDispatch(projectID: selectedProjectID)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func dispatchReady() async -> DispatchExecution? {
        do {
            let execution = try await runtimeService.dispatchReady(projectID: selectedProjectID)
            try await refreshTasks()
            return execution
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func configureStoreWatcher() {
        storeChangeTask?.cancel()
        guard let storeChanges = runtimeEnvironment.storeChanges() else {
            return
        }

        storeChangeTask = Task { [weak self] in
            do {
                for try await _ in storeChanges {
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
            replaceSelectedTaskEvents(try await loadSelectedTaskEvents())
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
            replaceWorkflowDiagnostics([])
            return
        }

        replaceWorkflowDiagnostics(workflowLoader.validate(project: selectedProject))
    }

    private func createInitialProject() async throws {
        let project = Project(
            name: "Local Project",
            defaultAgent: AgentConfiguration(kind: .codex, model: "default")
        )
        try await store.upsertProject(project)
    }

    private func replaceProjects(_ nextProjects: [Project]) {
        if projects != nextProjects {
            projects = nextProjects
        }
    }

    private func replaceTasks(_ nextTasks: [WorkItem]) {
        if tasks != nextTasks {
            tasks = nextTasks
        }
    }

    private func replaceSelectedTaskEvents(_ nextEvents: [RuntimeEvent]) {
        if selectedTaskEvents != nextEvents {
            selectedTaskEvents = nextEvents
        }
    }

    private func replaceWorkflowDiagnostics(_ nextDiagnostics: [WorkflowDiagnostic]) {
        if workflowDiagnostics != nextDiagnostics {
            workflowDiagnostics = nextDiagnostics
        }
    }

    private static func sortTasks(_ tasks: [WorkItem]) -> [WorkItem] {
        tasks.sorted { lhs, rhs in
            if lhs.priority.rawValue != rhs.priority.rawValue {
                return lhs.priority.rawValue > rhs.priority.rawValue
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }
}
