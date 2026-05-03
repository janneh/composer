import SwiftUI
import SymphonyCore

struct ProjectWorkspaceView: View {
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
        VStack(alignment: .leading, spacing: ComposerLayout.panelSpacing) {
            if !model.workflowDiagnostics.isEmpty {
                WorkflowDiagnosticsBanner(diagnostics: model.workflowDiagnostics)
            }

            workspaceMainLayout(width: width)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, ComposerLayout.workspaceHorizontalPadding)
        .padding(.top, ComposerLayout.workspaceTopPadding)
        .padding(.bottom, ComposerLayout.workspaceBottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func workspaceMainLayout(width: CGFloat) -> some View {
        if width < ComposerLayout.compactWorkspaceWidth {
            VStack(alignment: .leading, spacing: ComposerLayout.inspectorSpacing) {
                boardPane()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                if showsTaskMenu {
                    inspectorPane()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
        } else {
            HStack(alignment: .top, spacing: ComposerLayout.inspectorSpacing) {
                boardPane()
                    .frame(
                        minWidth: ComposerLayout.boardMinWidth,
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .topLeading
                    )

                if showsTaskMenu {
                    inspectorPane()
                        .frame(width: ComposerLayout.inspectorWidth)
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
