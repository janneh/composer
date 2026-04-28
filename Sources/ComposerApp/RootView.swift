import SwiftUI
import SymphonyCore

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } content: {
            BoardView()
        } detail: {
            InspectorView(task: model.selectedTask)
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task {
                        await model.createTask()
                    }
                } label: {
                    Label("New Task", systemImage: "plus")
                }
                .help("New Task")

                Button {
                    Task {
                        _ = await model.dispatchPreview()
                    }
                } label: {
                    Label("Dispatch Preview", systemImage: "play")
                }
                .help("Dispatch Preview")
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

private struct SidebarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List(selection: Binding(
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
                    Label(project.name, systemImage: "folder")
                        .tag(project.id)
                }
            }

            Section("Smart Views") {
                Label("Ready", systemImage: "play.circle")
                Label("Running", systemImage: "bolt.circle")
                Label("Needs Review", systemImage: "checklist")
                Label("Failed", systemImage: "exclamationmark.triangle")
                Label("Blocked", systemImage: "nosign")
            }
        }
        .navigationTitle("Composer")
    }
}

private struct BoardView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(WorkState.boardStates) { state in
                    BoardColumn(state: state, tasks: model.tasks(in: state))
                        .frame(width: 280)
                }
            }
            .padding(16)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(model.selectedProject?.name ?? "Board")
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

            ScrollView {
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
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color(nsColor: .quaternaryLabelColor).opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
        }
    }
}

private struct InspectorView: View {
    var task: WorkItem?

    var body: some View {
        Group {
            if let task {
                Form {
                    Section("Details") {
                        LabeledContent("Identifier", value: task.identifier)
                        LabeledContent("State", value: task.state.title)
                        LabeledContent("Priority", value: task.priority.title)
                        LabeledContent("Agent", value: task.preferredAgent?.kind.title ?? "Project Default")
                    }

                    Section("Description") {
                        Text(task.description.isEmpty ? "No description" : task.description)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Section("Labels") {
                        if task.labels.isEmpty {
                            Text("No labels")
                                .foregroundStyle(.secondary)
                        } else {
                            LabelRow(labels: task.labels)
                        }
                    }
                }
                .formStyle(.grouped)
                .navigationTitle(task.title)
            } else {
                ContentUnavailableView("No Task Selected", systemImage: "rectangle.stack")
            }
        }
        .frame(minWidth: 280)
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
