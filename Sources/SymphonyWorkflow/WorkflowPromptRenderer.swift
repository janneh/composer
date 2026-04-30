import Foundation
import SymphonyCore
import SymphonyInterfaces

public struct WorkflowPromptContext: Sendable {
    public var project: Project
    public var task: WorkItem
    public var run: RunAttempt?

    public init(project: Project, task: WorkItem, run: RunAttempt? = nil) {
        self.project = project
        self.task = task
        self.run = run
    }
}

public struct WorkflowPromptRenderer: Sendable {
    public init() {}

    public func render(document: WorkflowDocument, context: WorkflowPromptContext) -> String {
        var sections: [String] = []
        sections.append(renderWorkflowInstructions(document))

        if let frontMatter = document.frontMatter, !frontMatter.fields.isEmpty {
            sections.append(renderWorkflowMetadata(frontMatter))
        }

        sections.append(renderProject(context.project, workflowURL: document.fileURL))
        sections.append(renderTask(context.task))

        if let run = context.run {
            sections.append(renderRun(run))
        }

        return sections.joined(separator: "\n\n")
    }

    private func renderWorkflowInstructions(_ document: WorkflowDocument) -> String {
        let body = document.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let instructions = body.isEmpty ? "No workflow instructions were provided." : body
        return """
        # Workflow Instructions

        \(instructions)
        """
    }

    private func renderWorkflowMetadata(_ frontMatter: WorkflowFrontMatter) -> String {
        let fields = frontMatter.fields
            .keys
            .sorted()
            .map { key in "- \(key): \(renderValue(frontMatter.fields[key]!))" }
            .joined(separator: "\n")

        return """
        # Workflow Metadata

        \(fields)
        """
    }

    private func renderProject(_ project: Project, workflowURL: URL) -> String {
        """
        # Project Context

        - ID: \(project.id.rawValue)
        - Name: \(project.name)
        - Repository: \(project.repositoryPath ?? "Not set")
        - Workflow file: \(workflowURL.path)
        - Default agent: \(renderAgent(project.defaultAgent))
        - Created: \(format(project.createdAt))
        - Updated: \(format(project.updatedAt))
        """
    }

    private func renderTask(_ task: WorkItem) -> String {
        var lines = [
            "# Task Context",
            "",
            "- ID: \(task.id.rawValue)",
            "- Identifier: \(task.identifier)",
            "- Title: \(task.title)",
            "- State: \(task.state.rawValue)",
            "- Priority: \(task.priority.title)",
            "- Labels: \(renderList(task.labels))",
            "- Blocked by: \(renderList(task.blockedBy.map(\.rawValue)))",
            "- Preferred agent: \(task.preferredAgent.map(renderAgent) ?? "Project default")",
            "- Created: \(format(task.createdAt))",
            "- Updated: \(format(task.updatedAt))"
        ]

        let description = task.description.trimmingCharacters(in: .whitespacesAndNewlines)
        if !description.isEmpty {
            lines.append(contentsOf: ["", "## Task Description", "", description])
        }

        if !task.links.isEmpty {
            lines.append(contentsOf: ["", "## Links", ""])
            lines.append(contentsOf: task.links.map { "- \($0.title) [\($0.kind)]: \($0.url.absoluteString)" })
        }

        return lines.joined(separator: "\n")
    }

    private func renderRun(_ run: RunAttempt) -> String {
        let workspacePath = run.workspace?.path ?? "Not prepared"
        let cleanupPolicy = run.workspace?.cleanupPolicy.rawValue ?? "Not set"
        let preparedAt = (run.workspace?.preparedAt).map(format) ?? "Not prepared"

        return """
        # Run Context

        - ID: \(run.id.rawValue)
        - Status: \(run.status.rawValue)
        - Agent: \(renderAgent(run.agent))
        - Session: \(run.sessionID?.rawValue ?? "Not started")
        - Resume token: \(run.resumeToken ?? "Not available")
        - Workspace: \(workspacePath)
        - Workspace cleanup: \(cleanupPolicy)
        - Workspace prepared: \(preparedAt)
        - Started: \(run.startedAt.map(format) ?? "Not started")
        - Finished: \(run.finishedAt.map(format) ?? "Not finished")
        - Summary: \(run.summary ?? "Not available")
        """
    }

    private func renderValue(_ value: WorkflowFrontMatterValue) -> String {
        switch value {
        case let .string(value):
            return value
        case let .bool(value):
            return value ? "true" : "false"
        case let .integer(value):
            return "\(value)"
        case let .number(value):
            return "\(value)"
        case let .stringList(values):
            return renderList(values)
        }
    }

    private func renderAgent(_ agent: AgentConfiguration) -> String {
        var parts = [agent.kind.rawValue]
        if let model = agent.model {
            parts.append("model=\(model)")
        }
        if let profile = agent.profile {
            parts.append("profile=\(profile)")
        }
        if !agent.parameters.isEmpty {
            let parameters = agent.parameters.keys.sorted().map { "\($0)=\(agent.parameters[$0]!)" }
            parts.append("parameters=\(parameters.joined(separator: ","))")
        }
        return parts.joined(separator: " ")
    }

    private func renderList(_ values: [String]) -> String {
        values.isEmpty ? "None" : values.joined(separator: ", ")
    }

    private func format(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

public struct FileWorkflowProvider: WorkflowProvider {
    public var loader: WorkflowLoader
    public var renderer: WorkflowPromptRenderer

    public init(
        loader: WorkflowLoader = WorkflowLoader(),
        renderer: WorkflowPromptRenderer = WorkflowPromptRenderer()
    ) {
        self.loader = loader
        self.renderer = renderer
    }

    public func prompt(for task: WorkItem, project: Project, run: RunAttempt?) async throws -> String {
        let document = try loader.load(project: project)
        return renderer.render(
            document: document,
            context: WorkflowPromptContext(project: project, task: task, run: run)
        )
    }

    public func validate(project: Project) async throws -> [WorkflowDiagnostic] {
        loader.validate(project: project)
    }
}
