import Foundation
import SwiftUI
import SymphonyCore

struct ProjectEditorSheet: View {
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

struct ProjectDraft: Identifiable {
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
