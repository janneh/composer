import Foundation
import SymphonyCore
import SymphonyLocalStore

@main
struct ComposerCLI {
    static func main() async {
        do {
            try await Command().run(arguments: Array(CommandLine.arguments.dropFirst()))
        } catch let error as CLIError {
            FileHandle.standardError.writeLine("error: \(error.message)")
            exit(1)
        } catch {
            FileHandle.standardError.writeLine("error: \(error.localizedDescription)")
            exit(1)
        }
    }
}

private struct Command {
    func run(arguments rawArguments: [String]) async throws {
        var arguments = rawArguments
        let storePath = try removeStorePath(arguments: &arguments)

        guard let namespace = arguments.first else {
            printHelp()
            return
        }

        arguments.removeFirst()

        switch namespace {
        case "help", "--help", "-h":
            printHelp()
        case "project", "projects":
            let store = try makeStore(path: storePath)
            try await runProjectCommand(arguments: arguments, store: store)
        case "task", "tasks":
            let store = try makeStore(path: storePath)
            try await runTaskCommand(arguments: arguments, store: store)
        default:
            throw CLIError("Unknown command '\(namespace)'. Run composerctl help.")
        }
    }

    private func removeStorePath(arguments: inout [String]) throws -> String? {
        if let index = arguments.firstIndex(of: "--store") {
            guard index + 1 < arguments.count else {
                throw CLIError("Missing value for --store.")
            }
            let path = arguments[index + 1]
            arguments.removeSubrange(index...(index + 1))
            return path
        }

        if let index = arguments.firstIndex(where: { $0.hasPrefix("--store=") }) {
            let token = arguments.remove(at: index)
            let path = String(token.dropFirst("--store=".count))
            guard !path.isEmpty else {
                throw CLIError("Missing value for --store.")
            }
            return path
        }

        return nil
    }

    private func makeStore(path: String?) throws -> LocalJSONStore {
        if let path {
            return LocalJSONStore(fileURL: URL(fileURLWithPath: path))
        }
        return try LocalJSONStore.defaultStore()
    }

    private func runProjectCommand(arguments: [String], store: LocalJSONStore) async throws {
        var arguments = arguments
        guard let action = arguments.first else {
            throw CLIError("Missing project action. Use 'project list' or 'project add'.")
        }
        arguments.removeFirst()
        let options = try Options(arguments)

        switch action {
        case "list":
            let projects = try await store.listProjects()
            if options.has("json") {
                try printJSON(projects)
            } else {
                printProjectTable(projects)
            }
        case "add":
            let name = try options.required("name")
            let agent = try options.value("agent").map(parseAgentKind) ?? .codex
            let now = Date()
            let project = Project(
                name: name,
                repositoryPath: options.value("repo"),
                workflowPath: options.value("workflow"),
                defaultAgent: AgentConfiguration(kind: agent, model: options.value("model")),
                createdAt: now,
                updatedAt: now
            )
            try await store.upsertProject(project)
            print("Created project \(project.name) (\(project.id.rawValue))")
        default:
            throw CLIError("Unknown project action '\(action)'.")
        }
    }

    private func runTaskCommand(arguments: [String], store: LocalJSONStore) async throws {
        var arguments = arguments
        guard let action = arguments.first else {
            throw CLIError("Missing task action. Use 'task list', 'task add', or 'task move'.")
        }
        arguments.removeFirst()
        let options = try Options(arguments)

        switch action {
        case "list":
            let project = try await resolveProject(options.value("project"), store: store, required: false)
            var tasks = try await store.listTasks(projectID: project?.id)
            if let stateValue = options.value("state") {
                let state = try parseWorkState(stateValue)
                tasks = tasks.filter { $0.state == state }
            }

            if options.has("json") {
                try printJSON(tasks)
            } else {
                printTaskTable(tasks, projects: try await store.listProjects())
            }
        case "add":
            let project = try await resolveProject(options.value("project"), store: store, required: true)
            guard let project else {
                throw CLIError("No project available. Create one with 'composerctl project add --name NAME'.")
            }

            let existingTasks = try await store.listTasks(projectID: project.id)
            let blockedBy = try await resolveTaskIDs(options.values("blocked-by"), store: store, projectID: project.id)
            let agent = try options.value("agent").map(parseAgentKind)
            let now = Date()
            let task = WorkItem(
                projectID: project.id,
                identifier: options.value("identifier") ?? nextIdentifier(existingTasks),
                title: try options.required("title"),
                description: options.value("description") ?? "",
                state: try options.value("state").map(parseWorkState) ?? .backlog,
                priority: try options.value("priority").map(parsePriority) ?? .normal,
                labels: normalizedLabels(options.values("label")),
                blockedBy: blockedBy,
                preferredAgent: agent.map { AgentConfiguration(kind: $0, model: options.value("model")) },
                createdAt: now,
                updatedAt: now
            )

            try await store.upsertTask(task)
            try await store.appendEvent(RuntimeEvent(taskID: task.id, kind: .taskCreated, message: "Task created from composerctl"))
            print("Created task \(task.identifier) (\(task.id.rawValue))")
        case "move":
            let taskSelector = try options.required("task")
            let state = try parseWorkState(try options.required("state"))
            let project = try await resolveProject(options.value("project"), store: store, required: false)
            let task = try await resolveTask(taskSelector, store: store, projectID: project?.id)
            let moved = task.moving(to: state)
            try await store.upsertTask(moved)
            try await store.appendEvent(RuntimeEvent(taskID: task.id, kind: .taskMoved, message: "Moved to \(state.title) from composerctl"))
            print("Moved task \(task.identifier) to \(state.title)")
        default:
            throw CLIError("Unknown task action '\(action)'.")
        }
    }

    private func resolveProject(_ selector: String?, store: LocalJSONStore, required: Bool) async throws -> Project? {
        let projects = try await store.listProjects()

        guard let selector, !selector.isEmpty else {
            if projects.count == 1 {
                return projects[0]
            }
            if required {
                throw CLIError("Specify --project when there is not exactly one project.")
            }
            return nil
        }

        let normalizedSelector = selector.normalizedForLookup
        if let project = projects.first(where: { $0.id.rawValue == selector || $0.name.normalizedForLookup == normalizedSelector }) {
            return project
        }

        throw CLIError("Project '\(selector)' was not found.")
    }

    private func resolveTask(_ selector: String, store: LocalJSONStore, projectID: ProjectID?) async throws -> WorkItem {
        let tasks = try await store.listTasks(projectID: projectID)
        let normalizedSelector = selector.normalizedForLookup
        let matches = tasks.filter { task in
            task.id.rawValue == selector ||
            task.identifier.normalizedForLookup == normalizedSelector ||
            task.title.normalizedForLookup == normalizedSelector
        }

        guard let match = matches.first else {
            throw CLIError("Task '\(selector)' was not found.")
        }
        guard matches.count == 1 else {
            throw CLIError("Task '\(selector)' is ambiguous. Use its UUID or add --project.")
        }

        return match
    }

    private func resolveTaskIDs(_ selectors: [String], store: LocalJSONStore, projectID: ProjectID) async throws -> [TaskID] {
        var resolved: [TaskID] = []
        for selector in selectors {
            let task = try await resolveTask(selector, store: store, projectID: projectID)
            if !resolved.contains(task.id) {
                resolved.append(task.id)
            }
        }
        return resolved
    }

    private func nextIdentifier(_ tasks: [WorkItem]) -> String {
        let nextNumber = tasks.count + 1
        return "LOCAL-\(nextNumber)"
    }

    private func normalizedLabels(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values
            .flatMap { $0.split(separator: ",") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { label in
                guard !label.isEmpty, !seen.contains(label) else {
                    return false
                }
                seen.insert(label)
                return true
            }
    }
}

private struct Options {
    private var valuesByName: [String: [String]] = [:]

    init(_ arguments: [String]) throws {
        var index = 0
        while index < arguments.count {
            let token = arguments[index]
            guard token.hasPrefix("--") else {
                throw CLIError("Unexpected argument '\(token)'. Use --name value style options.")
            }

            let trimmed = String(token.dropFirst(2))
            if let equalsIndex = trimmed.firstIndex(of: "=") {
                let name = String(trimmed[..<equalsIndex])
                let value = String(trimmed[trimmed.index(after: equalsIndex)...])
                try append(value: value, for: name)
                index += 1
            } else if index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") {
                try append(value: arguments[index + 1], for: trimmed)
                index += 2
            } else {
                try append(value: "true", for: trimmed)
                index += 1
            }
        }
    }

    func value(_ name: String) -> String? {
        valuesByName[name]?.last
    }

    func values(_ name: String) -> [String] {
        valuesByName[name] ?? []
    }

    func has(_ name: String) -> Bool {
        valuesByName[name] != nil
    }

    func required(_ name: String) throws -> String {
        guard let value = value(name), !value.isEmpty, value != "true" else {
            throw CLIError("Missing required option --\(name).")
        }
        return value
    }

    private mutating func append(value: String, for rawName: String) throws {
        guard !rawName.isEmpty else {
            throw CLIError("Option names cannot be empty.")
        }
        valuesByName[rawName, default: []].append(value)
    }
}

private func parseWorkState(_ value: String) throws -> WorkState {
    switch value.normalizedForLookup {
    case "backlog": .backlog
    case "ready": .ready
    case "running": .running
    case "humanreview", "review", "human": .humanReview
    case "merging", "merge": .merging
    case "done", "closed", "complete", "completed": .done
    case "failed", "failure": .failed
    case "blocked", "block": .blocked
    case "canceled", "cancelled", "cancel": .canceled
    default:
        throw CLIError("Invalid state '\(value)'.")
    }
}

private func parsePriority(_ value: String) throws -> WorkPriority {
    switch value.normalizedForLookup {
    case "low": .low
    case "normal", "medium": .normal
    case "high": .high
    case "urgent", "critical": .urgent
    default:
        throw CLIError("Invalid priority '\(value)'.")
    }
}

private func parseAgentKind(_ value: String) throws -> AgentKind {
    switch value.normalizedForLookup {
    case "codex": .codex
    case "claude": .claude
    case "gemini": .gemini
    case "custom": .custom
    default:
        throw CLIError("Invalid agent '\(value)'.")
    }
}

private func printProjectTable(_ projects: [Project]) {
    guard !projects.isEmpty else {
        print("No projects")
        return
    }

    print("ID\tNAME\tAGENT\tREPO")
    for project in projects {
        print([
            project.id.rawValue,
            project.name,
            project.defaultAgent.kind.rawValue,
            project.repositoryPath ?? ""
        ].joined(separator: "\t"))
    }
}

private func printTaskTable(_ tasks: [WorkItem], projects: [Project]) {
    guard !tasks.isEmpty else {
        print("No tasks")
        return
    }

    let projectsByID = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0.name) })
    print("ID\tKEY\tPROJECT\tSTATE\tPRIORITY\tAGENT\tTITLE")
    for task in tasks {
        print([
            task.id.rawValue,
            task.identifier,
            projectsByID[task.projectID] ?? task.projectID.rawValue,
            task.state.rawValue,
            task.priority.title,
            task.preferredAgent?.kind.rawValue ?? "",
            task.title
        ].joined(separator: "\t"))
    }
}

private func printJSON<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(value)
    guard let string = String(data: data, encoding: .utf8) else {
        throw CLIError("Could not encode JSON output.")
    }
    print(string)
}

private func printHelp() {
    print(
        """
        composerctl

        Global options:
          --store PATH                         Use an explicit local store JSON file

        Project commands:
          project list [--json]
          project add --name NAME [--repo PATH] [--workflow PATH] [--agent codex|claude|gemini|custom] [--model MODEL]

        Task commands:
          task list [--project NAME_OR_ID] [--state STATE] [--json]
          task add --project NAME_OR_ID --title TITLE [--description TEXT] [--identifier KEY] [--state STATE] [--priority PRIORITY] [--label LABEL] [--agent AGENT] [--model MODEL] [--blocked-by TASK]
          task move --task TASK --state STATE [--project NAME_OR_ID]
        """
    )
}

private struct CLIError: Error {
    var message: String

    init(_ message: String) {
        self.message = message
    }
}

private extension String {
    var normalizedForLookup: String {
        lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

private extension FileHandle {
    func writeLine(_ line: String) {
        if let data = (line + "\n").data(using: .utf8) {
            write(data)
        }
    }
}
