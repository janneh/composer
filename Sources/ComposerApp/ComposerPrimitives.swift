import Foundation
import SwiftUI
import ComposerStorage
import SymphonyCore

struct HeaderActionButton: View {
    var title: String
    var systemImage: String
    var action: () -> Void
    var isProminent = false

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .medium))

                Text(title)
                    .font(.system(size: 14, weight: .regular))
                    .lineLimit(1)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .contentShape(RoundedRectangle(cornerRadius: ComposerTheme.smallRadius))
        }
        .buttonStyle(.plain)
    }

    private var foreground: Color {
        guard isEnabled else {
            return ComposerTheme.quietText
        }
        return isProminent ? ComposerTheme.accent : Color.primary
    }
}

struct ProjectMetaChip: View {
    var title: String
    var systemImage: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .regular))
            Text(title)
                .font(ComposerTheme.chipFont)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .foregroundStyle(ComposerTheme.mutedText)
    }
}

struct PriorityBadge: View {
    var priority: WorkPriority

    var body: some View {
        Text(priority.title)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: ComposerTheme.smallRadius))
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

struct LabelRow: View {
    var labels: [String]

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(labels, id: \.self) { label in
                Text(label)
                    .font(.system(size: 11, weight: .regular))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .frame(maxWidth: 132)
                    .foregroundStyle(ComposerTheme.mutedText)
                    .background(ComposerTheme.subtlePanelBackground)
                    .clipShape(RoundedRectangle(cornerRadius: ComposerTheme.smallRadius))
            }
        }
    }
}

struct FlowLayout: Layout {
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

extension String {
    var abbreviatedPath: String {
        let home = NSHomeDirectory()
        if hasPrefix(home) {
            return "~" + dropFirst(home.count)
        }
        return self
    }

    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var agentParameters: [String: String] {
        split(whereSeparator: { $0 == "," || $0 == "\n" })
            .reduce(into: [:]) { result, rawPair in
                let pair = String(rawPair).trimmingCharacters(in: .whitespacesAndNewlines)
                guard let separator = pair.firstIndex(of: "=") else {
                    return
                }
                let key = String(pair[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
                let value = String(pair[pair.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty else {
                    return
                }
                result[key] = value
            }
    }
}

extension StoreBackend {
    var title: String {
        switch self {
        case .json:
            "JSON Store"
        case .sqlite:
            "SQLite Store"
        }
    }
}

func formatAgentParameters(_ parameters: [String: String]) -> String {
    parameters.keys
        .sorted()
        .map { "\($0)=\(parameters[$0]!)" }
        .joined(separator: ", ")
}
