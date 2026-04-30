import Foundation
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
            SidebarView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        } detail: {
            ProjectWorkspaceView()
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 760, minHeight: 560)
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
                    Task {
                        await model.createTask()
                    }
                } label: {
                    Label("New Task", systemImage: "plus")
                        .labelStyle(.iconOnly)
                }
                .disabled(model.selectedProject == nil)
                .help("New Task")

                Button {
                    Task {
                        if let plan = await model.dispatchPreview() {
                            dispatchPreview = DispatchPreviewPresentation(plan: plan)
                        }
                    }
                } label: {
                    Label("Dispatch Preview", systemImage: "play")
                        .labelStyle(.iconOnly)
                }
                .disabled(model.selectedProject == nil)
                .help("Dispatch Preview")

                Button {
                    Task {
                        _ = await model.dispatchReady()
                    }
                } label: {
                    Label("Dispatch Ready", systemImage: "play.fill")
                        .labelStyle(.iconOnly)
                }
                .disabled(model.selectedProject == nil || !model.canDispatchReady)
                .help("Dispatch Ready")

                Button {
                    Task {
                        await model.reload()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                }
                .help("Refresh")
            }
        }
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
}

private struct DispatchPreviewPresentation: Identifiable {
    var id = UUID()
    var plan: DispatchPlan
    var generatedAt = Date()
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

    var body: some View {
        List(selection: Binding<ProjectID?>(
            get: { model.selectedProjectID },
            set: { newValue in
                guard let project = model.projects.first(where: { $0.id == newValue }) else {
                    return
                }
                Task {
                    await model.selectProject(project)
                }
            }
        )) {
            Section("Projects") {
                ForEach(model.projects) { project in
                    SidebarProjectRow(project: project)
                        .tag(project.id)
                }
            }
        }
        .navigationTitle("Composer")
        .safeAreaInset(edge: .bottom) {
            StorageFooterView(backend: model.storageBackend, fileURL: model.storeFileURL)
        }
    }
}

private struct SidebarProjectRow: View {
    var project: Project

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .lineLimit(1)

                Text(project.repositoryPath?.abbreviatedPath ?? "No repository")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct StorageFooterView: View {
    var backend: StoreBackend
    var fileURL: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(backend.title, systemImage: "externaldrive")
                .fontWeight(.medium)
            Text(fileURL.path.abbreviatedPath)
                .lineLimit(2)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }
}

private struct ProjectWorkspaceView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if let project = model.selectedProject {
                GeometryReader { geometry in
                    VStack(spacing: 0) {
                        ProjectHeaderView(project: project, taskCount: model.tasks.count)

                        if !model.workflowDiagnostics.isEmpty {
                            WorkflowDiagnosticsBanner(diagnostics: model.workflowDiagnostics)
                        }

                        Divider()

                        if geometry.size.width < 860 {
                            VSplitView {
                                BoardView()
                                    .frame(minHeight: 260)

                                InspectorView(task: model.selectedTask)
                                    .frame(minHeight: 220)
                            }
                        } else {
                            HSplitView {
                                BoardView()
                                    .frame(minWidth: 520)

                                InspectorView(task: model.selectedTask)
                                    .frame(minWidth: 300, idealWidth: 340, maxWidth: 420)
                            }
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
            } else {
                ContentUnavailableView("No Project Selected", systemImage: "folder")
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(model.selectedProject?.name ?? "Board")
    }
}

private struct ProjectHeaderView: View {
    var project: Project
    var taskCount: Int

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(project.name)
                    .font(.headline)
                    .lineLimit(1)

                Text(project.repositoryPath?.abbreviatedPath ?? "Set a repository path in Project Settings")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Text("\(taskCount) \(taskCount == 1 ? "task" : "tasks")")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

private struct BoardView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(WorkState.boardStates) { state in
                    BoardColumn(state: state, tasks: model.tasks(in: state))
                        .frame(width: 260)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct WorkflowDiagnosticsBanner: View {
    var diagnostics: [WorkflowDiagnostic]

    var body: some View {
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
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor.opacity(0.12))
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

private struct BoardColumn: View {
    @EnvironmentObject private var model: AppModel

    var state: WorkState
    var tasks: [WorkItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(state.title)
                    .font(.headline)
                Spacer()
                Text("\(tasks.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .frame(height: 28)

            if tasks.isEmpty {
                Text("No tasks")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(tasks) { task in
                        TaskCard(task: task, isSelected: model.selectedTaskID == task.id)
                            .onTapGesture {
                                model.selectTask(task)
                            }
                            .draggable(task.id.rawValue)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .padding(10)
        .frame(minHeight: 132, alignment: .top)
        .background(columnBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
            Color(nsColor: .controlAccentColor).opacity(0.10)
        default:
            Color(nsColor: .controlBackgroundColor)
        }
    }
}

private struct TaskCard: View {
    var task: WorkItem
    var isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(task.identifier)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                PriorityBadge(priority: task.priority)
            }

            Text(task.title)
                .font(.callout)
                .fontWeight(.medium)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            if !task.labels.isEmpty {
                LabelRow(labels: task.labels)
            }

            HStack(spacing: 6) {
                Image(systemName: agentIcon)
                    .imageScale(.small)
                Text((task.preferredAgent?.kind.title ?? "Default"))
                    .font(.caption)
                Spacer()
                if !task.blockedBy.isEmpty {
                    Image(systemName: "link.badge.plus")
                        .imageScale(.small)
                        .foregroundStyle(.orange)
                }
            }
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: isSelected ? 2 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 6))
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
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .frame(maxWidth: 132)
                    .background(Color(nsColor: .quaternaryLabelColor).opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
        }
    }
}

private struct InspectorView: View {
    @EnvironmentObject private var model: AppModel

    var task: WorkItem?
    @State private var draft: TaskDraft?

    var body: some View {
        Group {
            if let task {
                TaskEditorView(
                    task: task,
                    taskCandidates: model.tasks,
                    events: model.selectedTaskEvents,
                    draft: draftBinding(for: task),
                    onSave: { updated in
                        Task {
                            await model.updateTask(updated)
                        }
                    },
                    onReset: {
                        draft = TaskDraft(task: task)
                    }
                )
                .navigationTitle(task.title)
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
        .background(Color(nsColor: .windowBackgroundColor))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(task.identifier)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                Text(task.state.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                PriorityBadge(priority: task.priority)
            }

            Text(task.title)
                .font(.headline)
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }
}

private struct TaskEditorView: View {
    var task: WorkItem
    var taskCandidates: [WorkItem]
    var events: [RuntimeEvent]
    @Binding var draft: TaskDraft
    var onSave: (WorkItem) -> Void
    var onReset: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            TaskEditorHeader(task: task)

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
                        Button("Revert") {
                            onReset()
                        }
                        .disabled(!draft.hasChanges(from: task))

                        Spacer()

                        Button("Save") {
                            onSave(draft.apply(to: task))
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!draft.isValid || !draft.hasChanges(from: task))
                    }
                }
            }
            .formStyle(.grouped)
        }
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
