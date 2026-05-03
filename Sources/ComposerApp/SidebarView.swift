import SwiftUI
import ComposerStorage
import SymphonyCore

struct SidebarView: View {
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
