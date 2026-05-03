import SwiftUI
import SymphonyInterfaces

struct WorkflowDiagnosticsBanner: View {
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
