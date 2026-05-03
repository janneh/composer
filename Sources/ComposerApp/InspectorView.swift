import SwiftUI
import SymphonyCore

struct InspectorView: View {
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

struct TaskDraft: Equatable {
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
