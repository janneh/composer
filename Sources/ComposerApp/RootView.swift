import Foundation
import AppKit
import SwiftUI
import ComposerStorage
import SymphonyCore
import SymphonyInterfaces
import SymphonyRuntime

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingNewProject = false
    @State private var editingProject: Project?
    @State private var dispatchPreview: DispatchPreviewPresentation?

    var body: some View {
        NavigationSplitView {
            SidebarView(
                onNewProject: { showingNewProject = true },
                onNewTask: createTask,
                onDispatchPreview: presentDispatchPreview,
                onDispatchReady: dispatchReady,
                onRefresh: refresh
            )
            .navigationSplitViewColumnWidth(min: 240, ideal: 260, max: 300)
        } detail: {
            ProjectWorkspaceView(
                onNewTask: createTask,
                onDispatchPreview: presentDispatchPreview,
                onDispatchReady: dispatchReady,
                onEditProject: { editingProject = model.selectedProject }
            )
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 920, minHeight: 620)
        .background {
            ComposerMaterialBackground(tint: ComposerTheme.sidebarBackground, tintOpacity: 0.72)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(ComposerTheme.strongBorder)
                .frame(height: 1)
                .allowsHitTesting(false)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showingNewProject = true
                } label: {
                    Label("New Project", systemImage: "folder.badge.plus")
                        .labelStyle(.iconOnly)
                }
                .help("New Project")

                Button {
                    editingProject = model.selectedProject
                } label: {
                    Label("Project Settings", systemImage: "slider.horizontal.3")
                        .labelStyle(.iconOnly)
                }
                .disabled(model.selectedProject == nil)
                .help("Project Settings")

                Button {
                    createTask()
                } label: {
                    Label("New Task", systemImage: "plus")
                        .labelStyle(.iconOnly)
                }
                .disabled(model.selectedProject == nil)
                .help("New Task")

                Button {
                    presentDispatchPreview()
                } label: {
                    Label("Dispatch Preview", systemImage: "play")
                        .labelStyle(.iconOnly)
                }
                .disabled(model.selectedProject == nil)
                .help("Dispatch Preview")

                Button {
                    dispatchReady()
                } label: {
                    Label("Dispatch Ready", systemImage: "play.fill")
                        .labelStyle(.iconOnly)
                }
                .disabled(model.selectedProject == nil || !model.canDispatchReady)
                .help("Dispatch Ready")

                Button {
                    refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                }
                .help("Refresh")
            }
        }
        .toolbarBackground(.regularMaterial, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .composerWindowMaterial()
        .sheet(isPresented: $showingNewProject) {
            ProjectEditorSheet(title: "New Project") { draft in
                Task {
                    await model.createProject(
                        name: draft.name,
                        repositoryPath: draft.repositoryPath,
                        workflowPath: draft.workflowPath,
                        defaultAgent: draft.agentConfiguration
                    )
                }
            }
        }
        .sheet(item: $editingProject) { project in
            ProjectEditorSheet(title: "Project Settings", project: project) { draft in
                Task {
                    await model.updateProject(draft.apply(to: project))
                }
            }
        }
        .sheet(item: $dispatchPreview) { preview in
            DispatchPreviewSheet(preview: preview) { task in
                model.selectTask(task)
                dispatchPreview = nil
            }
        }
        .alert("Composer Error", isPresented: errorBinding) {
            Button("OK") {
                model.errorMessage = nil
            }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { newValue in
                if !newValue {
                    model.errorMessage = nil
                }
            }
        )
    }

    private func createTask() {
        Task {
            await model.createTask()
        }
    }

    private func presentDispatchPreview() {
        Task { @MainActor in
            if let plan = await model.dispatchPreview() {
                dispatchPreview = DispatchPreviewPresentation(plan: plan)
            }
        }
    }

    private func dispatchReady() {
        Task {
            _ = await model.dispatchReady()
        }
    }

    private func refresh() {
        Task {
            await model.reload()
        }
    }
}

private extension View {
    @ViewBuilder
    func composerWindowMaterial() -> some View {
        if #available(macOS 15.0, *) {
            self.containerBackground(.regularMaterial, for: .window)
        } else {
            self
        }
    }
}

private struct DispatchPreviewPresentation: Identifiable {
    var id = UUID()
    var plan: DispatchPlan
    var generatedAt = Date()
}

private enum ComposerTheme {
    static let canvas = Color.dynamicComposerColor(light: 0xFFFFFF, dark: 0x101012)
    static let windowChrome = Color.dynamicComposerColor(light: 0xFFFFFF, dark: 0x202024)
    static let sidebarBackground = Color.dynamicComposerColor(light: 0xF4F4F6, dark: 0x19191C)
    static let panelBackground = Color.dynamicComposerColor(light: 0xFFFFFF, dark: 0x202024)
    static let raisedPanelBackground = Color.dynamicComposerColor(light: 0xFBFBFC, dark: 0x242428)
    static let subtlePanelBackground = Color.dynamicComposerColor(light: 0xF5F5F6, dark: 0x2A2A2E)
    static let border = Color.dynamicComposerColor(light: 0xE7E7EA, dark: 0x34343A)
    static let strongBorder = Color.dynamicComposerColor(light: 0xD9D9DE, dark: 0x45454C)
    static let mutedText = Color.dynamicComposerColor(light: 0x898A90, dark: 0xA5A6AD)
    static let quietText = Color.dynamicComposerColor(light: 0xB0B1B6, dark: 0x73747B)
    static let accent = Color.dynamicComposerColor(light: 0x2487FF, dark: 0x5EA2FF)
    static let sendButton = Color.dynamicComposerColor(light: 0x8D8F94, dark: 0x6E7077)

    static let titleFont = Font.system(size: 28, weight: .medium)
    static let sectionFont = Font.system(size: 13, weight: .regular)
    static let bodyFont = Font.system(size: 14, weight: .regular)
    static let smallFont = Font.system(size: 12, weight: .regular)
    static let labelFont = Font.system(size: 12, weight: .medium)
    static let chipFont = Font.system(size: 13, weight: .regular)

    static let smallRadius: CGFloat = 6
    static let cardRadius: CGFloat = 8
    static let panelRadius: CGFloat = 8
}

private struct ComposerMaterialBackground: View {
    var tint: Color
    var tintOpacity: Double

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.regularMaterial)
            tint
                .opacity(tintOpacity)
        }
        .ignoresSafeArea()
    }
}

private extension Color {
    static func dynamicComposerColor(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let bestMatch = appearance.bestMatch(from: [.darkAqua, .aqua])
            return NSColor(hex: bestMatch == .darkAqua ? dark : light)
        })
    }
}

private extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

private struct DispatchPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    var preview: DispatchPreviewPresentation
    var onSelectTask: (WorkItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Dispatch Preview")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Text(preview.generatedAt, style: .time)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            HStack(spacing: 10) {
                DispatchMetric(title: "Ready", value: preview.plan.ready.count, color: .green)
                DispatchMetric(title: "Blocked", value: preview.plan.blocked.count, color: .orange)
                DispatchMetric(title: "Missing Runner", value: preview.plan.missingRunner.count, color: .red)
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    DispatchSection(
                        title: "Ready To Run",
                        systemImage: "play.circle",
                        tasks: preview.plan.ready,
                        emptyMessage: "No ready tasks",
                        onSelectTask: onSelectTask
                    )

                    DispatchSection(
                        title: "Blocked",
                        systemImage: "nosign",
                        tasks: preview.plan.blocked,
                        emptyMessage: "No blocked dispatch candidates",
                        onSelectTask: onSelectTask
                    )

                    DispatchSection(
                        title: "Missing Runner",
                        systemImage: "exclamationmark.triangle",
                        tasks: preview.plan.missingRunner,
                        emptyMessage: "No missing runners",
                        onSelectTask: onSelectTask
                    )
                }
            }

            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560, height: 560)
    }
}

private struct DispatchMetric: View {
    var title: String
    var value: Int
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.title3)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct DispatchSection: View {
    var title: String
    var systemImage: String
    var tasks: [WorkItem]
    var emptyMessage: String
    var onSelectTask: (WorkItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.headline)

            if tasks.isEmpty {
                Text(emptyMessage)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 6) {
                    ForEach(tasks) { task in
                        Button {
                            onSelectTask(task)
                        } label: {
                            DispatchTaskRow(task: task)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct DispatchTaskRow: View {
    var task: WorkItem

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(task.identifier)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    Text(task.priority.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(task.title)
                    .lineLimit(2)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct ProjectEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    var title: String
    var onSave: (ProjectDraft) -> Void
    @State private var draft: ProjectDraft

    init(title: String, project: Project? = nil, onSave: @escaping (ProjectDraft) -> Void) {
        self.title = title
        self.onSave = onSave
        _draft = State(initialValue: ProjectDraft(project: project))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)

            Form {
                Section("Project") {
                    TextField("Name", text: $draft.name)
                    TextField("Repository path", text: $draft.repositoryPathText)
                    TextField("Workflow path", text: $draft.workflowPathText)
                }

                Section("Default Agent") {
                    Picker("Agent", selection: $draft.agentKind) {
                        ForEach(AgentKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }

                    TextField("Model", text: $draft.modelText)
                    TextField("Profile", text: $draft.profileText)
                    TextField("Parameters", text: $draft.parametersText)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") {
                    dismiss()
                }

                Spacer()

                Button("Save") {
                    onSave(draft.normalized)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!draft.isValid)
            }
        }
        .padding(20)
        .frame(width: 480, height: 520)
    }
}

private struct ProjectDraft: Identifiable {
    var id: String
    var name: String
    var repositoryPathText: String
    var workflowPathText: String
    var agentKind: AgentKind
    var modelText: String
    var profileText: String
    var parametersText: String

    init(project: Project?) {
        id = project?.id.rawValue ?? UUID().uuidString
        name = project?.name ?? ""
        repositoryPathText = project?.repositoryPath ?? ""
        workflowPathText = project?.workflowPath ?? ""
        agentKind = project?.defaultAgent.kind ?? .codex
        modelText = project?.defaultAgent.model ?? ""
        profileText = project?.defaultAgent.profile ?? ""
        parametersText = formatAgentParameters(project?.defaultAgent.parameters ?? [:])
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var normalized: ProjectDraft {
        var copy = self
        copy.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.repositoryPathText = repositoryPathText.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.workflowPathText = workflowPathText.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.modelText = modelText.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.profileText = profileText.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.parametersText = parametersText.trimmingCharacters(in: .whitespacesAndNewlines)
        return copy
    }

    var repositoryPath: String? {
        repositoryPathText.nilIfEmpty
    }

    var workflowPath: String? {
        workflowPathText.nilIfEmpty
    }

    var agentConfiguration: AgentConfiguration {
        AgentConfiguration(
            kind: agentKind,
            model: modelText.nilIfEmpty,
            profile: profileText.nilIfEmpty,
            parameters: parametersText.agentParameters
        )
    }

    func apply(to project: Project) -> Project {
        var updated = project
        let draft = normalized
        updated.name = draft.name
        updated.repositoryPath = draft.repositoryPath
        updated.workflowPath = draft.workflowPath
        updated.defaultAgent = draft.agentConfiguration
        return updated
    }
}

private struct SidebarView: View {
    @EnvironmentObject private var model: AppModel

    var onNewProject: () -> Void
    var onNewTask: () -> Void
    var onDispatchPreview: () -> Void
    var onDispatchReady: () -> Void
    var onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                SidebarActionButton(title: "New task", systemImage: "square.and.pencil", action: onNewTask)
                    .disabled(model.selectedProject == nil)
                SidebarActionButton(title: "Dispatch ready", systemImage: "play.circle", action: onDispatchReady)
                    .disabled(model.selectedProject == nil || !model.canDispatchReady)
                SidebarActionButton(title: "Preview dispatch", systemImage: "clock.arrow.circlepath", action: onDispatchPreview)
                    .disabled(model.selectedProject == nil)
                SidebarActionButton(title: "Refresh", systemImage: "arrow.clockwise", action: onRefresh)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 28)

            HStack {
                SidebarSectionTitle("Projects")
                Spacer()
                Button(action: onNewProject) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(ComposerTheme.mutedText)
                .help("New Project")
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 10)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(model.projects) { project in
                        Button {
                            Task {
                                await model.selectProject(project)
                            }
                        } label: {
                            SidebarProjectRow(
                                project: project,
                                isSelected: model.selectedProjectID == project.id
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
            }

            Spacer(minLength: 12)

            StorageFooterView(backend: model.storageBackend, fileURL: model.storeFileURL)
        }
        .font(ComposerTheme.bodyFont)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            ComposerMaterialBackground(tint: ComposerTheme.sidebarBackground, tintOpacity: 0.72)
        }
        .navigationTitle("")
    }
}

private struct SidebarActionButton: View {
    var title: String
    var systemImage: String
    var action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .regular))
                    .frame(width: 18)

                Text(title)
                    .font(.system(size: 15, weight: .regular))
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .foregroundStyle(isEnabled ? Color.primary : ComposerTheme.quietText)
            .padding(.horizontal, 4)
            .frame(height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SidebarSectionTitle: View {
    var title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(ComposerTheme.quietText)
    }
}

private struct SidebarProjectRow: View {
    var project: Project
    var isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(ComposerTheme.mutedText)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(project.name)
                    .font(.system(size: 15, weight: .regular))
                    .lineLimit(1)

                Text(project.repositoryPath?.abbreviatedPath ?? "No repository")
                    .font(ComposerTheme.smallFont)
                    .foregroundStyle(ComposerTheme.mutedText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
        .background(isSelected ? ComposerTheme.panelBackground.opacity(0.82) : Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: ComposerTheme.cardRadius)
                .stroke(isSelected ? ComposerTheme.border : Color.clear, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: ComposerTheme.cardRadius))
    }
}

private struct StorageFooterView: View {
    var backend: StoreBackend
    var fileURL: URL

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "gearshape")
                .font(.system(size: 16, weight: .regular))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(backend.title)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Color.primary)
                Text(fileURL.path.abbreviatedPath)
                    .font(ComposerTheme.smallFont)
                    .foregroundStyle(ComposerTheme.mutedText)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(Color.primary)
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ProjectWorkspaceView: View {
    @EnvironmentObject private var model: AppModel
    @State private var taskPendingDeletion: WorkItem?
    @SceneStorage("Composer.ProjectWorkspace.isTaskMenuVisible")
    private var isTaskMenuVisible = false

    var onNewTask: () -> Void
    var onDispatchPreview: () -> Void
    var onDispatchReady: () -> Void
    var onEditProject: () -> Void

    var body: some View {
        Group {
            if let project = model.selectedProject {
                GeometryReader { geometry in
                    projectWorkspace(project: project, size: geometry.size)
                }
            } else {
                ContentUnavailableView("No Project Selected", systemImage: "folder")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(ComposerTheme.canvas)
        .navigationTitle(model.selectedProject?.name ?? "Board")
        .onChange(of: model.selectedTaskID) { _, newValue in
            isTaskMenuVisible = newValue != nil
        }
        .alert(
            "Delete Task?",
            isPresented: deleteConfirmationBinding,
            presenting: taskPendingDeletion
        ) { task in
            Button("Delete", role: .destructive) {
                deleteTask(task)
            }
            Button("Cancel", role: .cancel) {
                taskPendingDeletion = nil
            }
        } message: { task in
            Text("This removes \(task.identifier), its run records, and any dependency references to it. This cannot be undone.")
        }
    }

    private func projectWorkspace(project: Project, size: CGSize) -> some View {
        VStack(spacing: 0) {
            ProjectHeaderView(
                project: project,
                taskCount: model.tasks.count,
                canDispatchReady: model.canDispatchReady,
                onNewTask: onNewTask,
                onDispatchPreview: onDispatchPreview,
                onDispatchReady: onDispatchReady,
                onEditProject: onEditProject,
                isTaskMenuVisible: showsTaskMenu,
                hasSelectedTask: model.selectedTask != nil,
                onToggleTaskMenu: toggleTaskMenu
            )

            workspaceContent(width: size.width)
        }
        .frame(width: size.width, height: size.height)
    }

    private func workspaceContent(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            if !model.workflowDiagnostics.isEmpty {
                WorkflowDiagnosticsBanner(diagnostics: model.workflowDiagnostics)
            }

            workspaceMainLayout(width: width)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 28)
        .padding(.top, 22)
        .padding(.bottom, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func workspaceMainLayout(width: CGFloat) -> some View {
        if width < 900 {
            VStack(alignment: .leading, spacing: 18) {
                boardPane()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                if showsTaskMenu {
                    inspectorPane()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
        } else {
            HStack(alignment: .top, spacing: 18) {
                boardPane()
                    .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                if showsTaskMenu {
                    inspectorPane()
                        .frame(width: 360)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
        }
    }

    private func boardPane() -> some View {
        BoardView(
            onSelectTask: selectTask,
            onDeleteTask: requestTaskDeletion
        )
    }

    private func inspectorPane() -> some View {
        InspectorView(
            task: model.selectedTask,
            onClose: closeTaskMenu,
            onDeleteTask: requestTaskDeletion
        )
    }

    private var showsTaskMenu: Bool {
        isTaskMenuVisible && model.selectedTask != nil
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { taskPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    taskPendingDeletion = nil
                }
            }
        )
    }

    private func selectTask(_ task: WorkItem) {
        model.selectTask(task)
        isTaskMenuVisible = true
    }

    private func closeTaskMenu() {
        isTaskMenuVisible = false
    }

    private func toggleTaskMenu() {
        guard model.selectedTask != nil else {
            return
        }
        isTaskMenuVisible.toggle()
    }

    private func requestTaskDeletion(_ task: WorkItem) {
        taskPendingDeletion = task
    }

    private func deleteTask(_ task: WorkItem) {
        taskPendingDeletion = nil
        if model.selectedTaskID == task.id {
            isTaskMenuVisible = false
        }
        Task {
            await model.deleteTask(task)
        }
    }
}

private struct ProjectHeaderView: View {
    var project: Project
    var taskCount: Int
    var canDispatchReady: Bool
    var onNewTask: () -> Void
    var onDispatchPreview: () -> Void
    var onDispatchReady: () -> Void
    var onEditProject: () -> Void
    var isTaskMenuVisible: Bool
    var hasSelectedTask: Bool
    var onToggleTaskMenu: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                HeaderActionButton(
                    title: "New task",
                    systemImage: "plus",
                    action: onNewTask
                )

                HeaderActionButton(
                    title: "Dispatch preview",
                    systemImage: "play",
                    action: onDispatchPreview
                )

                HeaderActionButton(
                    title: "Dispatch ready",
                    systemImage: "play.fill",
                    action: onDispatchReady,
                    isProminent: true
                )
                .disabled(!canDispatchReady)

                Spacer(minLength: 8)

                Button(action: onEditProject) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .foregroundStyle(ComposerTheme.mutedText)
                .help("Project Settings")

                Button(action: onToggleTaskMenu) {
                    Image(systemName: "rectangle.rightthird.inset.filled")
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .foregroundStyle(isTaskMenuVisible ? ComposerTheme.accent : ComposerTheme.mutedText)
                .disabled(!hasSelectedTask)
                .help(isTaskMenuVisible ? "Close Task Menu" : "Open Task Menu")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)

            Divider()

            HStack(spacing: 16) {
                ProjectMetaChip(
                    title: project.repositoryPath?.abbreviatedPath ?? "No repository",
                    systemImage: "folder.badge.gearshape"
                )

                ProjectMetaChip(
                    title: project.defaultAgent.kind.title,
                    systemImage: agentIcon
                )

                ProjectMetaChip(
                    title: "\(taskCount) \(taskCount == 1 ? "task" : "tasks")",
                    systemImage: "rectangle.stack"
                )

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(ComposerTheme.subtlePanelBackground.opacity(0.72))
        }
        .frame(maxWidth: .infinity)
        .background {
            ComposerMaterialBackground(tint: ComposerTheme.windowChrome, tintOpacity: 0.70)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ComposerTheme.border)
                .frame(height: 1)
        }
    }

    private var agentIcon: String {
        switch project.defaultAgent.kind {
        case .codex: "chevron.left.forwardslash.chevron.right"
        case .claude: "sparkles"
        case .gemini: "diamond"
        case .custom: "wrench.adjustable"
        }
    }
}

private struct HeaderActionButton: View {
    var title: String
    var systemImage: String
    var action: () -> Void
    var isProminent = false

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .medium))

                Text(title)
                    .font(.system(size: 14, weight: .regular))
                    .lineLimit(1)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .contentShape(RoundedRectangle(cornerRadius: ComposerTheme.smallRadius))
        }
        .buttonStyle(.plain)
    }

    private var foreground: Color {
        guard isEnabled else {
            return ComposerTheme.quietText
        }
        return isProminent ? ComposerTheme.accent : Color.primary
    }
}

private struct ProjectMetaChip: View {
    var title: String
    var systemImage: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .regular))
            Text(title)
                .font(ComposerTheme.chipFont)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .foregroundStyle(ComposerTheme.mutedText)
    }
}

private struct BoardView: View {
    @EnvironmentObject private var model: AppModel

    var onSelectTask: (WorkItem) -> Void
    var onDeleteTask: (WorkItem) -> Void

    var body: some View {
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical]) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(WorkState.boardStates) { state in
                        BoardColumn(
                            state: state,
                            tasks: model.tasks(in: state),
                            onSelectTask: onSelectTask,
                            onDeleteTask: onDeleteTask
                        )
                            .frame(width: 276)
                    }
                }
                .padding(2)
                .frame(minHeight: geometry.size.height, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .defaultScrollAnchor(.topLeading)
            .background(Color.clear)
        }
        .frame(minHeight: 160)
    }
}

private struct WorkflowDiagnosticsBanner: View {
    var diagnostics: [WorkflowDiagnostic]
    @State private var isShowingWorkflowHelp = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(diagnostics.enumerated()), id: \.offset) { _, diagnostic in
                    Label {
                        Text(diagnostic.message)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: iconName(for: diagnostic.severity))
                    }
                    .font(.callout)
                    .foregroundStyle(color(for: diagnostic.severity))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                isShowingWorkflowHelp.toggle()
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(color(for: diagnostics.first?.severity ?? .info))
            .help("About WORKFLOW.md")
            .popover(isPresented: $isShowingWorkflowHelp, arrowEdge: .top) {
                WorkflowHelpPopover()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: ComposerTheme.cardRadius)
                .stroke(backgroundColor.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: ComposerTheme.cardRadius))
    }

    private var backgroundColor: Color {
        if diagnostics.contains(where: { $0.severity == .error }) {
            return .red
        }
        if diagnostics.contains(where: { $0.severity == .warning }) {
            return .orange
        }
        return .blue
    }

    private func iconName(for severity: WorkflowDiagnostic.Severity) -> String {
        switch severity {
        case .info: "info.circle"
        case .warning: "exclamationmark.triangle"
        case .error: "xmark.octagon"
        }
    }

    private func color(for severity: WorkflowDiagnostic.Severity) -> Color {
        switch severity {
        case .info: .blue
        case .warning: .orange
        case .error: .red
        }
    }
}

private struct WorkflowHelpPopover: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About WORKFLOW.md")
                .font(.system(size: 14, weight: .semibold))

            Text("WORKFLOW.md is the project playbook Composer uses when it dispatches a task. It describes how an agent should turn a task into a run prompt, including project rules, expected steps, and any template variables Composer should fill in.")
                .fixedSize(horizontal: false, vertical: true)

            Text("Composer requires it before dispatch so every run has explicit project instructions instead of sending an underspecified task to an agent.")
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("To fix this:")
                    .font(.system(size: 12, weight: .semibold))
                WorkflowHelpStep("Set this project to a repository that contains WORKFLOW.md at its root.")
                WorkflowHelpStep("Or set an explicit workflow path in Project Settings.")
                WorkflowHelpStep("Create WORKFLOW.md, then use Refresh.")
            }
        }
        .font(ComposerTheme.smallFont)
        .foregroundStyle(Color.primary)
        .padding(14)
        .frame(width: 340, alignment: .leading)
        .background(ComposerTheme.panelBackground)
    }
}

private struct WorkflowHelpStep: View {
    var text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: "circle.fill")
                .font(.system(size: 4))
                .foregroundStyle(ComposerTheme.mutedText)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct BoardColumn: View {
    @EnvironmentObject private var model: AppModel

    var state: WorkState
    var tasks: [WorkItem]
    var onSelectTask: (WorkItem) -> Void
    var onDeleteTask: (WorkItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(state.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.primary)
                Spacer()
                Text("\(tasks.count)")
                    .font(ComposerTheme.smallFont)
                    .foregroundStyle(ComposerTheme.mutedText)
                    .monospacedDigit()
                    .padding(.horizontal, 7)
                    .frame(height: 22)
                    .background(ComposerTheme.subtlePanelBackground)
                    .clipShape(RoundedRectangle(cornerRadius: ComposerTheme.smallRadius))
            }
            .frame(height: 26)

            if tasks.isEmpty {
                Text("No tasks")
                    .font(ComposerTheme.bodyFont)
                    .foregroundStyle(ComposerTheme.mutedText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 2)
                    .padding(.vertical, 10)
            } else {
                LazyVStack(spacing: 9) {
                    ForEach(tasks) { task in
                        TaskCard(task: task, isSelected: model.selectedTaskID == task.id)
                            .onTapGesture {
                                onSelectTask(task)
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    onDeleteTask(task)
                                } label: {
                                    Label("Delete Task", systemImage: "trash")
                                }
                            }
                            .draggable(task.id.rawValue)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .padding(12)
        .frame(minHeight: 132, alignment: .top)
        .background(columnBackground)
        .overlay(
            RoundedRectangle(cornerRadius: ComposerTheme.cardRadius)
                .stroke(ComposerTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: ComposerTheme.cardRadius))
        .dropDestination(for: String.self) { items, _ in
            guard let rawID = items.first,
                  let task = model.tasks.first(where: { $0.id.rawValue == rawID }) else {
                return false
            }

            Task {
                await model.move(task, to: state)
            }
            return true
        }
    }

    private var columnBackground: Color {
        switch state {
        case .running:
            ComposerTheme.accent.opacity(0.08)
        default:
            ComposerTheme.raisedPanelBackground
        }
    }
}

private struct TaskCard: View {
    var task: WorkItem
    var isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(task.identifier)
                    .font(ComposerTheme.labelFont)
                    .foregroundStyle(ComposerTheme.mutedText)
                Spacer(minLength: 8)
                PriorityBadge(priority: task.priority)
            }

            Text(task.title)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            if !task.labels.isEmpty {
                LabelRow(labels: task.labels)
            }

            HStack(spacing: 6) {
                Image(systemName: agentIcon)
                    .imageScale(.small)
                Text((task.preferredAgent?.kind.title ?? "Default"))
                    .font(ComposerTheme.smallFont)
                Spacer()
                if !task.blockedBy.isEmpty {
                    Image(systemName: "link.badge.plus")
                        .imageScale(.small)
                        .foregroundStyle(.orange)
                }
            }
            .foregroundStyle(ComposerTheme.mutedText)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ComposerTheme.panelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: ComposerTheme.cardRadius)
                .stroke(isSelected ? ComposerTheme.accent : ComposerTheme.border, lineWidth: isSelected ? 1.5 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: ComposerTheme.cardRadius))
        .shadow(color: .black.opacity(0.035), radius: 8, x: 0, y: 4)
    }

    private var agentIcon: String {
        switch task.preferredAgent?.kind {
        case .codex: "chevron.left.forwardslash.chevron.right"
        case .claude: "sparkles"
        case .gemini: "diamond"
        case .custom: "wrench.adjustable"
        case nil: "gearshape"
        }
    }
}

private struct PriorityBadge: View {
    var priority: WorkPriority

    var body: some View {
        Text(priority.title)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: ComposerTheme.smallRadius))
    }

    private var color: Color {
        switch priority {
        case .low: .secondary
        case .normal: .blue
        case .high: .orange
        case .urgent: .red
        }
    }
}

private struct LabelRow: View {
    var labels: [String]

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(labels, id: \.self) { label in
                Text(label)
                    .font(.system(size: 11, weight: .regular))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .frame(maxWidth: 132)
                    .foregroundStyle(ComposerTheme.mutedText)
                    .background(ComposerTheme.subtlePanelBackground)
                    .clipShape(RoundedRectangle(cornerRadius: ComposerTheme.smallRadius))
            }
        }
    }
}

private struct InspectorView: View {
    @EnvironmentObject private var model: AppModel

    var task: WorkItem?
    var onClose: () -> Void
    var onDeleteTask: (WorkItem) -> Void
    @State private var draft: TaskDraft?

    var body: some View {
        Group {
            if let task {
                TaskEditorView(
                    task: task,
                    taskCandidates: model.tasks,
                    events: model.selectedTaskEvents,
                    draft: draftBinding(for: task),
                    onClose: onClose,
                    onSave: { updated in
                        Task {
                            await model.updateTask(updated)
                        }
                    },
                    onReset: {
                        draft = TaskDraft(task: task)
                    },
                    onDelete: {
                        onDeleteTask(task)
                    }
                )
                .onAppear {
                    resetDraftIfNeeded(for: task)
                }
                .onChange(of: task.id) { _, _ in
                    resetDraftIfNeeded(for: task)
                }
            } else {
                ContentUnavailableView("No Task Selected", systemImage: "rectangle.stack")
            }
        }
        .frame(minWidth: 280)
        .background(Color.clear)
    }

    private func draftBinding(for task: WorkItem) -> Binding<TaskDraft> {
        Binding(
            get: {
                if let draft, draft.sourceID == task.id {
                    return draft
                }
                return TaskDraft(task: task)
            },
            set: { newValue in
                draft = newValue
            }
        )
    }

    private func resetDraftIfNeeded(for task: WorkItem) {
        if draft?.sourceID != task.id {
            draft = TaskDraft(task: task)
        }
    }
}

private struct TaskEditorHeader: View {
    var task: WorkItem
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(task.identifier)
                    .font(ComposerTheme.labelFont)
                    .foregroundStyle(ComposerTheme.mutedText)

                Text(task.state.title)
                    .font(ComposerTheme.smallFont)
                    .foregroundStyle(ComposerTheme.mutedText)

                Spacer(minLength: 8)

                PriorityBadge(priority: task.priority)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(ComposerTheme.mutedText)
                .help("Close Task Menu")
            }

            Text(task.title)
                .font(.system(size: 15, weight: .medium))
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ComposerTheme.subtlePanelBackground)
    }
}

private struct TaskEditorView: View {
    var task: WorkItem
    var taskCandidates: [WorkItem]
    var events: [RuntimeEvent]
    @Binding var draft: TaskDraft
    var onClose: () -> Void
    var onSave: (WorkItem) -> Void
    var onReset: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            TaskEditorHeader(task: task, onClose: onClose)

            Divider()

            Form {
                Section("Identity") {
                    TextField("Identifier", text: $draft.identifier)
                    TextField("Title", text: $draft.title)
                }

                Section("Planning") {
                    Picker("State", selection: $draft.state) {
                        ForEach(WorkState.allCases) { state in
                            Text(state.title).tag(state)
                        }
                    }

                    Picker("Priority", selection: $draft.priority) {
                        ForEach(WorkPriority.allCases) { priority in
                            Text(priority.title).tag(priority)
                        }
                    }

                    Picker("Agent", selection: $draft.agentKind) {
                        Text("Project Default").tag(Optional<AgentKind>.none)
                        ForEach(AgentKind.allCases) { kind in
                            Text(kind.title).tag(Optional(kind))
                        }
                    }

                    if draft.agentKind != nil {
                        TextField("Model", text: $draft.agentModelText)
                        TextField("Profile", text: $draft.agentProfileText)
                        TextField("Parameters", text: $draft.agentParametersText)
                    }
                }

                Section("Description") {
                    TextEditor(text: $draft.description)
                        .font(.body)
                        .frame(minHeight: 120)
                }

                Section("Labels") {
                    TextField("Comma-separated labels", text: $draft.labelsText)
                    LabelRow(labels: draft.labels)
                }

                Section("Dependencies") {
                    let candidates = dependencyCandidates
                    if candidates.isEmpty {
                        Text("No available dependencies")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(candidates) { candidate in
                            Toggle(isOn: dependencyBinding(for: candidate.id)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(candidate.identifier)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(candidate.title)
                                        .lineLimit(2)
                                }
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                }

                Section("Events") {
                    if events.isEmpty {
                        Text("No events")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(events) { event in
                            RuntimeEventRow(event: event)
                        }
                    }
                }

                Section {
                    HStack {
                        Button("Delete", role: .destructive) {
                            onDelete()
                        }

                        Spacer()

                        Button("Revert") {
                            onReset()
                        }
                        .disabled(!draft.hasChanges(from: task))

                        Button("Save") {
                            onSave(draft.apply(to: task))
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!draft.isValid || !draft.hasChanges(from: task))
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(ComposerTheme.panelBackground)
        }
        .background(ComposerTheme.panelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: ComposerTheme.cardRadius)
                .stroke(ComposerTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: ComposerTheme.cardRadius))
    }

    private var dependencyCandidates: [WorkItem] {
        taskCandidates.filter { candidate in
            candidate.id != task.id && !candidate.blockedBy.contains(task.id)
        }
    }

    private func dependencyBinding(for id: TaskID) -> Binding<Bool> {
        Binding(
            get: {
                draft.blockedBy.contains(id)
            },
            set: { isSelected in
                if isSelected {
                    draft.addBlocker(id)
                } else {
                    draft.removeBlocker(id)
                }
            }
        )
    }
}

private struct RuntimeEventRow: View {
    var event: RuntimeEvent

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.message)
                    .lineLimit(2)
                Text(event.kind.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text(event.createdAt, style: .time)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 3)
    }

    private var iconName: String {
        switch event.kind {
        case .taskCreated: "plus.circle"
        case .taskUpdated: "pencil.circle"
        case .taskMoved: "arrow.right.circle"
        case .taskDeleted: "trash.circle"
        case .runQueued: "clock"
        case .runStarted: "play.circle"
        case .runEvent: "terminal"
        case .runFinished: "checkmark.circle"
        case .runFailed: "exclamationmark.triangle"
        case .userInputRequired: "person.crop.circle.badge.questionmark"
        }
    }

    private var iconColor: Color {
        switch event.kind {
        case .taskDeleted:
            .red
        case .runFailed:
            .red
        case .userInputRequired:
            .orange
        case .runFinished:
            .green
        default:
            .secondary
        }
    }
}

private struct TaskDraft: Equatable {
    var sourceID: TaskID
    var identifier: String
    var title: String
    var description: String
    var state: WorkState
    var priority: WorkPriority
    var labelsText: String
    var agentKind: AgentKind?
    var agentModelText: String
    var agentProfileText: String
    var agentParametersText: String
    var blockedBy: [TaskID]

    init(task: WorkItem) {
        sourceID = task.id
        identifier = task.identifier
        title = task.title
        description = task.description
        state = task.state
        priority = task.priority
        labelsText = task.labels.joined(separator: ", ")
        agentKind = task.preferredAgent?.kind
        agentModelText = task.preferredAgent?.model ?? ""
        agentProfileText = task.preferredAgent?.profile ?? ""
        agentParametersText = formatAgentParameters(task.preferredAgent?.parameters ?? [:])
        blockedBy = task.blockedBy
    }

    var labels: [String] {
        var seen: Set<String> = []
        return labelsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { label in
                guard !label.isEmpty, !seen.contains(label) else {
                    return false
                }
                seen.insert(label)
                return true
            }
    }

    var isValid: Bool {
        !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func hasChanges(from task: WorkItem) -> Bool {
        apply(to: task) != task
    }

    mutating func addBlocker(_ id: TaskID) {
        guard !blockedBy.contains(id), id != sourceID else {
            return
        }
        blockedBy.append(id)
    }

    mutating func removeBlocker(_ id: TaskID) {
        blockedBy.removeAll { $0 == id }
    }

    func apply(to task: WorkItem) -> WorkItem {
        var updated = task
        updated.identifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.state = state
        updated.priority = priority
        updated.labels = labels
        updated.blockedBy = blockedBy.filter { $0 != task.id }
        if let agentKind {
            updated.preferredAgent = AgentConfiguration(
                kind: agentKind,
                model: agentModelText.nilIfEmpty,
                profile: agentProfileText.nilIfEmpty,
                parameters: agentParametersText.agentParameters
            )
        } else {
            updated.preferredAgent = nil
        }
        return updated
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat

    init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: proposal.width ?? 260, subviews: subviews)
        return CGSize(
            width: proposal.width ?? rows.map(\.width).max() ?? 0,
            height: rows.map(\.height).reduce(0, +) + CGFloat(max(0, rows.count - 1)) * spacing
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for element in row.elements {
                element.subview.place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(element.size)
                )
                x += element.size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func rows(for width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let wouldExceed = current.width + size.width + (current.elements.isEmpty ? 0 : spacing) > width
            if wouldExceed, !current.elements.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.append(subview: subview, size: size, spacing: spacing)
        }

        if !current.elements.isEmpty {
            rows.append(current)
        }

        return rows
    }

    private struct Row {
        struct Element {
            var subview: LayoutSubview
            var size: CGSize
        }

        var elements: [Element] = []
        var width: CGFloat = 0
        var height: CGFloat = 0

        mutating func append(subview: LayoutSubview, size: CGSize, spacing: CGFloat) {
            if !elements.isEmpty {
                width += spacing
            }
            elements.append(Element(subview: subview, size: size))
            width += size.width
            height = max(height, size.height)
        }
    }
}

private extension String {
    var abbreviatedPath: String {
        let home = NSHomeDirectory()
        if hasPrefix(home) {
            return "~" + dropFirst(home.count)
        }
        return self
    }

    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var agentParameters: [String: String] {
        split(whereSeparator: { $0 == "," || $0 == "\n" })
            .reduce(into: [:]) { result, rawPair in
                let pair = String(rawPair).trimmingCharacters(in: .whitespacesAndNewlines)
                guard let separator = pair.firstIndex(of: "=") else {
                    return
                }
                let key = String(pair[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
                let value = String(pair[pair.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty else {
                    return
                }
                result[key] = value
            }
    }
}

private extension StoreBackend {
    var title: String {
        switch self {
        case .json:
            "JSON Store"
        case .sqlite:
            "SQLite Store"
        }
    }
}

private func formatAgentParameters(_ parameters: [String: String]) -> String {
    parameters.keys
        .sorted()
        .map { "\($0)=\(parameters[$0]!)" }
        .joined(separator: ", ")
}
