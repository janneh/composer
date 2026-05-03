import Foundation
import AppKit
import SwiftUI
import SymphonyCore
import SymphonyRuntime

struct DispatchPreviewPresentation: Identifiable {
    var id = UUID()
    var plan: DispatchPlan
    var generatedAt = Date()
}

struct DispatchPreviewSheet: View {
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
        .clipShape(RoundedRectangle(cornerRadius: ComposerTheme.cardRadius))
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
        .clipShape(RoundedRectangle(cornerRadius: ComposerTheme.cardRadius))
    }
}
