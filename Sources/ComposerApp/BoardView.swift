import SwiftUI
import SymphonyCore

struct BoardView: View {
    @EnvironmentObject private var model: AppModel

    var onSelectTask: (WorkItem) -> Void
    var onDeleteTask: (WorkItem) -> Void

    var body: some View {
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical]) {
                HStack(alignment: .top, spacing: ComposerLayout.columnSpacing) {
                    ForEach(WorkState.boardStates) { state in
                        BoardColumn(
                            state: state,
                            tasks: model.tasks(in: state),
                            onSelectTask: onSelectTask,
                            onDeleteTask: onDeleteTask
                        )
                        .frame(width: ComposerLayout.boardColumnWidth)
                    }
                }
                .padding(2)
                .frame(minHeight: geometry.size.height, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .defaultScrollAnchor(.topLeading)
            .background(Color.clear)
        }
        .frame(minHeight: ComposerLayout.boardMinHeight)
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
