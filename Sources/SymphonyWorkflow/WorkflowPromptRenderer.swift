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

    public func render(document: WorkflowDocument, context: WorkflowPromptContext) throws -> String {
        var sections: [String] = []
        sections.append(try renderWorkflowInstructions(document, context: context))

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

    private func renderWorkflowInstructions(_ document: WorkflowDocument, context: WorkflowPromptContext) throws -> String {
        let body = document.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let instructions: String
        if body.isEmpty {
            instructions = "No workflow instructions were provided."
        } else {
            instructions = try WorkflowTemplate(template: body)
                .render(scope: makeTemplateScope(context: context))
        }
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

    private func makeTemplateScope(context: WorkflowPromptContext) -> WorkflowTemplateScope {
        let issue = issueTemplateValue(context.task)
        let attempt = attemptTemplateValue(context.run)
        return WorkflowTemplateScope(values: [
            "project": projectTemplateValue(context.project),
            "issue": issue,
            "task": issue,
            "attempt": attempt,
            "run": runTemplateValue(context.run)
        ])
    }

    private func projectTemplateValue(_ project: Project) -> WorkflowTemplateValue {
        .object([
            "id": .string(project.id.rawValue),
            "name": .string(project.name),
            "repository_path": optionalString(project.repositoryPath),
            "repositoryPath": optionalString(project.repositoryPath),
            "workflow_path": optionalString(project.workflowPath),
            "workflowPath": optionalString(project.workflowPath),
            "default_agent": agentTemplateValue(project.defaultAgent),
            "defaultAgent": agentTemplateValue(project.defaultAgent),
            "created_at": .string(format(project.createdAt)),
            "createdAt": .string(format(project.createdAt)),
            "updated_at": .string(format(project.updatedAt)),
            "updatedAt": .string(format(project.updatedAt))
        ])
    }

    private func issueTemplateValue(_ task: WorkItem) -> WorkflowTemplateValue {
        let url = task.links.first { $0.kind == "linear" }?.url ?? task.links.first?.url
        return .object([
            "id": .string(task.id.rawValue),
            "project_id": .string(task.projectID.rawValue),
            "projectID": .string(task.projectID.rawValue),
            "identifier": .string(task.identifier),
            "title": .string(task.title),
            "description": task.description.isEmpty ? .null : .string(task.description),
            "state": .string(task.state.rawValue),
            "state_title": .string(task.state.title),
            "stateTitle": .string(task.state.title),
            "priority": .int(task.priority.rawValue),
            "priority_title": .string(task.priority.title),
            "priorityTitle": .string(task.priority.title),
            "branch_name": .null,
            "branchName": .null,
            "url": optionalString(url?.absoluteString),
            "labels": .array(task.labels.map { .string($0) }),
            "blocked_by": .array(task.blockedBy.map { blockerID in
                .object([
                    "id": .string(blockerID.rawValue),
                    "identifier": .null,
                    "state": .null
                ])
            }),
            "blockedBy": .array(task.blockedBy.map { .string($0.rawValue) }),
            "preferred_agent": task.preferredAgent.map(agentTemplateValue) ?? .null,
            "preferredAgent": task.preferredAgent.map(agentTemplateValue) ?? .null,
            "links": .array(task.links.map(linkTemplateValue)),
            "created_at": .string(format(task.createdAt)),
            "createdAt": .string(format(task.createdAt)),
            "updated_at": .string(format(task.updatedAt)),
            "updatedAt": .string(format(task.updatedAt))
        ])
    }

    private func runTemplateValue(_ run: RunAttempt?) -> WorkflowTemplateValue {
        guard let run else {
            return .null
        }

        return .object([
            "id": .string(run.id.rawValue),
            "task_id": .string(run.taskID.rawValue),
            "taskID": .string(run.taskID.rawValue),
            "agent": agentTemplateValue(run.agent),
            "status": .string(run.status.rawValue),
            "session_id": optionalString(run.sessionID?.rawValue),
            "sessionID": optionalString(run.sessionID?.rawValue),
            "resume_token": optionalString(run.resumeToken),
            "resumeToken": optionalString(run.resumeToken),
            "workspace": workspaceTemplateValue(run.workspace),
            "started_at": optionalDate(run.startedAt),
            "startedAt": optionalDate(run.startedAt),
            "finished_at": optionalDate(run.finishedAt),
            "finishedAt": optionalDate(run.finishedAt),
            "summary": optionalString(run.summary)
        ])
    }

    private func attemptTemplateValue(_ run: RunAttempt?) -> WorkflowTemplateValue {
        guard let run else {
            return .null
        }

        if run.startedAt != nil || run.status != .queued {
            return .int(1)
        }

        return .null
    }

    private func workspaceTemplateValue(_ workspace: WorkspaceReference?) -> WorkflowTemplateValue {
        guard let workspace else {
            return .null
        }

        return .object([
            "path": .string(workspace.path),
            "cleanup_policy": .string(workspace.cleanupPolicy.rawValue),
            "cleanupPolicy": .string(workspace.cleanupPolicy.rawValue),
            "prepared_at": .string(format(workspace.preparedAt)),
            "preparedAt": .string(format(workspace.preparedAt))
        ])
    }

    private func agentTemplateValue(_ agent: AgentConfiguration) -> WorkflowTemplateValue {
        .object([
            "kind": .string(agent.kind.rawValue),
            "model": optionalString(agent.model),
            "profile": optionalString(agent.profile),
            "parameters": .object(agent.parameters.mapValues { .string($0) })
        ])
    }

    private func linkTemplateValue(_ link: ExternalLink) -> WorkflowTemplateValue {
        .object([
            "id": .string(link.id),
            "title": .string(link.title),
            "url": .string(link.url.absoluteString),
            "kind": .string(link.kind)
        ])
    }

    private func optionalString(_ value: String?) -> WorkflowTemplateValue {
        guard let value, !value.isEmpty else {
            return .null
        }

        return .string(value)
    }

    private func optionalDate(_ date: Date?) -> WorkflowTemplateValue {
        date.map { .string(format($0)) } ?? .null
    }
}

public enum WorkflowTemplateError: Error, Equatable, CustomStringConvertible, LocalizedError {
    case unclosedDelimiter(String)
    case unexpectedTag(String)
    case missingTag(String)
    case invalidTag(String)
    case invalidExpression(String)
    case unknownVariable(String)
    case unknownFilter(String)
    case expectedArray(String)

    public var description: String {
        switch self {
        case let .unclosedDelimiter(delimiter):
            return "Unclosed workflow template delimiter '\(delimiter)'."
        case let .unexpectedTag(tag):
            return "Unexpected workflow template tag '\(tag)'."
        case let .missingTag(tag):
            return "Missing workflow template tag '\(tag)'."
        case let .invalidTag(tag):
            return "Invalid workflow template tag '\(tag)'."
        case let .invalidExpression(expression):
            return "Invalid workflow template expression '\(expression)'."
        case let .unknownVariable(variable):
            return "Unknown workflow template variable '\(variable)'."
        case let .unknownFilter(filter):
            return "Unknown workflow template filter '\(filter)'."
        case let .expectedArray(expression):
            return "Workflow template expression '\(expression)' must resolve to an array."
        }
    }

    public var errorDescription: String? {
        description
    }
}

private enum WorkflowTemplateValue: Equatable, Sendable {
    case null
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([WorkflowTemplateValue])
    case object([String: WorkflowTemplateValue])

    var rendered: String {
        switch self {
        case .null:
            return ""
        case let .string(value):
            return value
        case let .int(value):
            return "\(value)"
        case let .double(value):
            return "\(value)"
        case let .bool(value):
            return value ? "true" : "false"
        case let .array(values):
            return values.map(\.rendered).joined(separator: ", ")
        case let .object(values):
            return values.keys.sorted().map { key in "\(key): \(values[key]!.rendered)" }.joined(separator: ", ")
        }
    }

    var isTruthy: Bool {
        switch self {
        case .null:
            return false
        case let .bool(value):
            return value
        case let .string(value):
            return !value.isEmpty
        case let .int(value):
            return value != 0
        case let .double(value):
            return value != 0
        case let .array(values):
            return !values.isEmpty
        case let .object(values):
            return !values.isEmpty
        }
    }

    var isBlank: Bool {
        switch self {
        case .null:
            return true
        case let .string(value):
            return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case let .array(values):
            return values.isEmpty
        case let .object(values):
            return values.isEmpty
        case let .bool(value):
            return !value
        case .int, .double:
            return false
        }
    }
}

private struct WorkflowTemplateScope: Sendable {
    private var frames: [[String: WorkflowTemplateValue]]

    init(values: [String: WorkflowTemplateValue]) {
        self.frames = [values]
    }

    private init(frames: [[String: WorkflowTemplateValue]]) {
        self.frames = frames
    }

    func pushing(_ name: String, value: WorkflowTemplateValue) -> WorkflowTemplateScope {
        var frames = frames
        frames.append([name: value])
        return WorkflowTemplateScope(frames: frames)
    }

    func resolve(path: String) throws -> WorkflowTemplateValue {
        let components = path.split(separator: ".").map(String.init)
        guard let first = components.first, isValidPath(path) else {
            throw WorkflowTemplateError.invalidExpression(path)
        }

        guard var value = frames.reversed().compactMap({ $0[first] }).first else {
            throw WorkflowTemplateError.unknownVariable(first)
        }

        if components.count == 1 {
            return value
        }

        var resolved = first
        for component in components.dropFirst() {
            resolved += ".\(component)"
            guard case let .object(values) = value, let next = values[component] else {
                throw WorkflowTemplateError.unknownVariable(resolved)
            }
            value = next
        }

        return value
    }

    private func isValidPath(_ path: String) -> Bool {
        path.split(separator: ".").allSatisfy { component in
            guard let first = component.first, first.isLetter || first == "_" else {
                return false
            }

            return component.allSatisfy { character in
                character.isLetter || character.isNumber || character == "_" || character == "-"
            }
        }
    }
}

private struct WorkflowTemplate {
    private let nodes: [WorkflowTemplateNode]

    init(template: String) throws {
        let tokens = try WorkflowTemplateTokenizer.tokenize(template)
        var parser = WorkflowTemplateParser(tokens: tokens)
        self.nodes = try parser.parse()
    }

    func render(scope: WorkflowTemplateScope) throws -> String {
        try render(nodes, scope: scope)
    }

    private func render(_ nodes: [WorkflowTemplateNode], scope: WorkflowTemplateScope) throws -> String {
        var output = ""

        for node in nodes {
            switch node {
            case let .text(value):
                output += value
            case let .output(expression):
                output += try evaluate(expression, scope: scope).rendered
            case let .ifBlock(condition, trueNodes, falseNodes):
                let selectedNodes = try evaluateCondition(condition, scope: scope) ? trueNodes : falseNodes
                output += try render(selectedNodes, scope: scope)
            case let .forBlock(variable, collectionExpression, body):
                let collection = try evaluate(collectionExpression, scope: scope)
                guard case let .array(values) = collection else {
                    throw WorkflowTemplateError.expectedArray(collectionExpression)
                }
                for value in values {
                    output += try render(body, scope: scope.pushing(variable, value: value))
                }
            }
        }

        return output
    }

    private func evaluate(_ expression: String, scope: WorkflowTemplateScope) throws -> WorkflowTemplateValue {
        let segments = try splitOutsideQuotes(expression, separator: "|").map { $0.trimmed }
        guard let first = segments.first, !first.isEmpty else {
            throw WorkflowTemplateError.invalidExpression(expression)
        }

        var value = try evaluateTerm(first, scope: scope)
        for filter in segments.dropFirst() {
            value = try applyFilter(filter, to: value, scope: scope)
        }

        return value
    }

    private func evaluateTerm(_ expression: String, scope: WorkflowTemplateScope) throws -> WorkflowTemplateValue {
        let trimmed = expression.trimmed
        guard !trimmed.isEmpty else {
            throw WorkflowTemplateError.invalidExpression(expression)
        }

        if let quoted = parseQuotedString(trimmed) {
            return .string(quoted)
        }

        switch trimmed {
        case "true":
            return .bool(true)
        case "false":
            return .bool(false)
        case "null", "nil":
            return .null
        default:
            break
        }

        if let integer = Int(trimmed) {
            return .int(integer)
        }

        if let number = Double(trimmed), trimmed.contains(".") {
            return .double(number)
        }

        return try scope.resolve(path: trimmed)
    }

    private func evaluateCondition(_ condition: String, scope: WorkflowTemplateScope) throws -> Bool {
        let words = try splitWords(condition)
        guard !words.isEmpty else {
            throw WorkflowTemplateError.invalidExpression(condition)
        }

        if words.first == "not" {
            let remaining = words.dropFirst().joined(separator: " ")
            return try !evaluateCondition(remaining, scope: scope)
        }

        if words.count == 3, words[1] == "contains" {
            let lhs = try evaluate(words[0], scope: scope)
            let rhs = try evaluateTerm(words[2], scope: scope)
            switch lhs {
            case let .array(values):
                return values.contains(rhs) || values.map(\.rendered).contains(rhs.rendered)
            case let .string(value):
                return value.contains(rhs.rendered)
            default:
                return false
            }
        }

        if words.count == 3, words[1] == "==" || words[1] == "!=" {
            let matches = try evaluate(words[0], scope: scope) == evaluateTerm(words[2], scope: scope)
            return words[1] == "==" ? matches : !matches
        }

        guard words.count == 1 else {
            throw WorkflowTemplateError.invalidExpression(condition)
        }

        return try evaluate(words[0], scope: scope).isTruthy
    }

    private func applyFilter(
        _ filter: String,
        to value: WorkflowTemplateValue,
        scope: WorkflowTemplateScope
    ) throws -> WorkflowTemplateValue {
        let parts = try splitOutsideQuotes(filter, separator: ":")
        guard let rawName = parts.first?.trimmed, !rawName.isEmpty else {
            throw WorkflowTemplateError.invalidExpression(filter)
        }

        let argumentString = parts.dropFirst().joined(separator: ":").trimmed
        let arguments = argumentString.isEmpty
            ? []
            : try splitOutsideQuotes(argumentString, separator: ",").map { try evaluateTerm($0, scope: scope) }

        switch rawName {
        case "default":
            guard let fallback = arguments.first else {
                throw WorkflowTemplateError.invalidExpression(filter)
            }
            return value.isBlank ? fallback : value
        case "join":
            guard case let .array(values) = value else {
                throw WorkflowTemplateError.expectedArray(filter)
            }
            let separator = arguments.first?.rendered ?? " "
            return .string(values.map(\.rendered).joined(separator: separator))
        case "upcase":
            return .string(value.rendered.uppercased())
        case "downcase":
            return .string(value.rendered.lowercased())
        case "capitalize":
            let rendered = value.rendered
            guard let first = rendered.first else {
                return .string(rendered)
            }
            return .string(first.uppercased() + rendered.dropFirst())
        case "strip":
            return .string(value.rendered.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            throw WorkflowTemplateError.unknownFilter(rawName)
        }
    }

    private func parseQuotedString(_ value: String) -> String? {
        guard value.count >= 2, let first = value.first, let last = value.last else {
            return nil
        }

        guard (first == "\"" && last == "\"") || (first == "'" && last == "'") else {
            return nil
        }

        return String(value.dropFirst().dropLast())
    }
}

private enum WorkflowTemplateNode {
    case text(String)
    case output(String)
    case ifBlock(condition: String, trueNodes: [WorkflowTemplateNode], falseNodes: [WorkflowTemplateNode])
    case forBlock(variable: String, collectionExpression: String, body: [WorkflowTemplateNode])
}

private enum WorkflowTemplateToken {
    case text(String)
    case output(String)
    case tag(String)
}

private enum WorkflowTemplateTokenizer {
    static func tokenize(_ template: String) throws -> [WorkflowTemplateToken] {
        var tokens: [WorkflowTemplateToken] = []
        var index = template.startIndex

        while index < template.endIndex {
            let suffix = template[index...]
            let outputRange = suffix.range(of: "{{")
            let tagRange = suffix.range(of: "{%")

            let nextRange: Range<String.Index>?
            let isOutput: Bool
            switch (outputRange, tagRange) {
            case let (.some(outputRange), .some(tagRange)):
                if outputRange.lowerBound < tagRange.lowerBound {
                    nextRange = outputRange
                    isOutput = true
                } else {
                    nextRange = tagRange
                    isOutput = false
                }
            case let (.some(outputRange), .none):
                nextRange = outputRange
                isOutput = true
            case let (.none, .some(tagRange)):
                nextRange = tagRange
                isOutput = false
            case (.none, .none):
                tokens.append(.text(String(template[index...])))
                return tokens
            }

            guard let delimiterRange = nextRange else {
                continue
            }

            if delimiterRange.lowerBound > index {
                tokens.append(.text(String(template[index..<delimiterRange.lowerBound])))
            }

            let closeDelimiter = isOutput ? "}}" : "%}"
            let contentStart = delimiterRange.upperBound
            guard let closeRange = template[contentStart...].range(of: closeDelimiter) else {
                throw WorkflowTemplateError.unclosedDelimiter(isOutput ? "{{" : "{%")
            }

            let content = String(template[contentStart..<closeRange.lowerBound]).trimmed
            tokens.append(isOutput ? .output(content) : .tag(content))
            index = closeRange.upperBound
        }

        return tokens
    }
}

private struct WorkflowTemplateParser {
    var tokens: [WorkflowTemplateToken]
    var index = 0

    mutating func parse() throws -> [WorkflowTemplateNode] {
        let (nodes, stopTag) = try parseNodes(stoppingAt: [])
        if let stopTag {
            throw WorkflowTemplateError.unexpectedTag(stopTag)
        }
        return nodes
    }

    private mutating func parseNodes(stoppingAt stopTags: Set<String>) throws -> ([WorkflowTemplateNode], String?) {
        var nodes: [WorkflowTemplateNode] = []

        while index < tokens.count {
            switch tokens[index] {
            case let .text(value):
                nodes.append(.text(value))
                index += 1
            case let .output(expression):
                nodes.append(.output(expression))
                index += 1
            case let .tag(content):
                let name = tagName(content)
                if stopTags.contains(name) {
                    guard content == name else {
                        throw WorkflowTemplateError.invalidTag(content)
                    }
                    index += 1
                    return (nodes, name)
                }

                switch name {
                case "if":
                    index += 1
                    nodes.append(try parseIf(content))
                case "for":
                    index += 1
                    nodes.append(try parseFor(content))
                case "else", "endif", "endfor":
                    throw WorkflowTemplateError.unexpectedTag(name)
                default:
                    throw WorkflowTemplateError.invalidTag(content)
                }
            }
        }

        return (nodes, nil)
    }

    private mutating func parseIf(_ content: String) throws -> WorkflowTemplateNode {
        let condition = content.removingTagName("if")
        guard !condition.isEmpty else {
            throw WorkflowTemplateError.invalidTag(content)
        }

        let (trueNodes, firstStop) = try parseNodes(stoppingAt: ["else", "endif"])
        switch firstStop {
        case "endif":
            return .ifBlock(condition: condition, trueNodes: trueNodes, falseNodes: [])
        case "else":
            let (falseNodes, secondStop) = try parseNodes(stoppingAt: ["endif"])
            guard secondStop == "endif" else {
                throw WorkflowTemplateError.missingTag("endif")
            }
            return .ifBlock(condition: condition, trueNodes: trueNodes, falseNodes: falseNodes)
        default:
            throw WorkflowTemplateError.missingTag("endif")
        }
    }

    private mutating func parseFor(_ content: String) throws -> WorkflowTemplateNode {
        let words = try splitWords(content)
        guard words.count == 4, words[0] == "for", words[2] == "in", isValidVariableName(words[1]) else {
            throw WorkflowTemplateError.invalidTag(content)
        }

        let (body, stopTag) = try parseNodes(stoppingAt: ["endfor"])
        guard stopTag == "endfor" else {
            throw WorkflowTemplateError.missingTag("endfor")
        }

        return .forBlock(variable: words[1], collectionExpression: words[3], body: body)
    }

    private func tagName(_ content: String) -> String {
        content.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
    }

    private func isValidVariableName(_ value: String) -> Bool {
        guard let first = value.first, first.isLetter || first == "_" else {
            return false
        }

        return value.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }
}

private func splitWords(_ value: String) throws -> [String] {
    var words: [String] = []
    var current = ""
    var quote: Character?

    for character in value {
        if character == "\"" || character == "'" {
            if quote == character {
                quote = nil
            } else if quote == nil {
                quote = character
            }
            current.append(character)
            continue
        }

        if character.isWhitespace, quote == nil {
            if !current.isEmpty {
                words.append(current)
                current = ""
            }
        } else {
            current.append(character)
        }
    }

    guard quote == nil else {
        throw WorkflowTemplateError.invalidExpression(value)
    }

    if !current.isEmpty {
        words.append(current)
    }

    return words
}

private func splitOutsideQuotes(_ value: String, separator: Character) throws -> [String] {
    var parts: [String] = []
    var current = ""
    var quote: Character?

    for character in value {
        if character == "\"" || character == "'" {
            if quote == character {
                quote = nil
            } else if quote == nil {
                quote = character
            }
            current.append(character)
            continue
        }

        if character == separator, quote == nil {
            parts.append(current)
            current = ""
        } else {
            current.append(character)
        }
    }

    guard quote == nil else {
        throw WorkflowTemplateError.invalidExpression(value)
    }

    parts.append(current)
    return parts
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func removingTagName(_ tagName: String) -> String {
        guard hasPrefix(tagName) else {
            return self
        }

        return String(dropFirst(tagName.count)).trimmed
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
        return try renderer.render(
            document: document,
            context: WorkflowPromptContext(project: project, task: task, run: run)
        )
    }

    public func validate(project: Project) async throws -> [WorkflowDiagnostic] {
        loader.validate(project: project)
    }
}
