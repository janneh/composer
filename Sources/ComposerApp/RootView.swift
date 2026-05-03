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
            .navigationSplitViewColumnWidth(
                min: ComposerLayout.sidebarMinWidth,
                ideal: ComposerLayout.sidebarIdealWidth,
                max: ComposerLayout.sidebarMaxWidth
            )
        } detail: {
            ProjectWorkspaceView(
                onNewTask: createTask,
                onDispatchPreview: presentDispatchPreview,
                onDispatchReady: dispatchReady,
                onEditProject: { editingProject = model.selectedProject }
            )
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: ComposerLayout.windowMinWidth, minHeight: ComposerLayout.windowMinHeight)
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
