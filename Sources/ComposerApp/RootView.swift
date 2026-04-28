import Foundation
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

private struct TaskEditorView: View {
    var task: WorkItem
    var taskCandidates: [WorkItem]
    var events: [RuntimeEvent]
    @Binding var draft: TaskDraft
    var onSave: (WorkItem) -> Void
    var onReset: () -> Void

    var body: some View {
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
        updated.preferredAgent = agentKind.map { AgentConfiguration(kind: $0) }
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
