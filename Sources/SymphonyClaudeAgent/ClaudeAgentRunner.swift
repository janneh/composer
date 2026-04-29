import Foundation
import SymphonyCore
import SymphonyInterfaces

public enum ClaudePermissionMode: String, Codable, CaseIterable, Hashable, Sendable {
    case acceptEdits
    case auto
    case bypassPermissions
    case `default`
    case dontAsk
    case plan
}

public struct ClaudeRunnerConfiguration: Hashable, Sendable {
    public var executableURL: URL
    public var executableArgumentsPrefix: [String]
    public var permissionMode: ClaudePermissionMode
    public var extraArguments: [String]

    public init(
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/env"),
        executableArgumentsPrefix: [String] = ["claude"],
        permissionMode: ClaudePermissionMode = .default,
        extraArguments: [String] = []
    ) {
        self.executableURL = executableURL
        self.executableArgumentsPrefix = executableArgumentsPrefix
        self.permissionMode = permissionMode
        self.extraArguments = extraArguments
    }
}

public struct ClaudeCommand: Equatable, Sendable {
    public var executableURL: URL
    public var arguments: [String]
    public var workingDirectoryURL: URL
    public var stdin: String
    public var environment: [String: String]

    public init(
        executableURL: URL,
        arguments: [String],
        workingDirectoryURL: URL,
        stdin: String,
        environment: [String: String]
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.workingDirectoryURL = workingDirectoryURL
        self.stdin = stdin
        self.environment = environment
    }
}

public struct ClaudeCommandBuilder: Sendable {
    public var configuration: ClaudeRunnerConfiguration

    public init(configuration: ClaudeRunnerConfiguration = ClaudeRunnerConfiguration()) {
        self.configuration = configuration
    }

    public func command(for request: AgentRunRequest) -> ClaudeCommand {
        var arguments = configuration.executableArgumentsPrefix
        arguments.append(contentsOf: [
            "--print",
            "--input-format",
            "text",
            "--output-format",
            "stream-json",
            "--include-partial-messages",
            "--permission-mode",
            configuration.permissionMode.rawValue
        ])

        if let model = request.agent.model {
            arguments.append(contentsOf: ["--model", model])
        }

        if let profile = request.agent.profile {
            arguments.append(contentsOf: ["--agent", profile])
        }

        if let effort = request.agent.parameters["effort"] {
            arguments.append(contentsOf: ["--effort", effort])
        }

        arguments.append(contentsOf: configuration.extraArguments)

        return ClaudeCommand(
            executableURL: configuration.executableURL,
            arguments: arguments,
            workingDirectoryURL: URL(fileURLWithPath: request.workspacePath, isDirectory: true),
            stdin: request.workflowPrompt,
            environment: request.environment
        )
    }
}

public struct ClaudeStreamEventParser: Sendable {
    public init() {}

    public func parseLine(_ line: String) -> AgentRunEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .partialOutput(trimmed)
        }

        let type = stringValue(in: object, keys: ["type", "event", "kind"])?.lowercased() ?? "event"

        if type == "assistant", let event = assistantEvent(from: object) {
            return event
        }

        if type.contains("tool") || type.contains("command") {
            let name = stringValue(in: object, keys: ["name", "tool_name", "toolName", "command"]) ?? type
            let inputSummary = stringValue(in: object, keys: ["input", "input_summary", "inputSummary"])
            return .toolUse(name: name, inputSummary: inputSummary)
        }

        let message = stringValue(in: object, keys: ["message", "result", "summary", "text", "error", "reason", "prompt"])
            ?? trimmed

        if type.contains("partial") || type.contains("delta") {
            return .partialOutput(message)
        }

        if type.contains("approval") || type.contains("input") || type.contains("waiting") {
            return .waitingForInput(prompt: message)
        }

        if type == "result" || type.contains("complete") || type.contains("finished") || type.contains("final") {
            return .completed(summary: message)
        }

        if type.contains("error") || type.contains("fail") {
            return .failed(message: message)
        }

        if type.contains("start") || type == "system" {
            return .started(message: message)
        }

        return .progress(message: message)
    }

    private func assistantEvent(from object: [String: Any]) -> AgentRunEvent? {
        guard let message = object["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]] else {
            return nil
        }

        for item in content {
            let itemType = stringValue(in: item, keys: ["type"])?.lowercased()
            if itemType == "tool_use" {
                let name = stringValue(in: item, keys: ["name"]) ?? "tool"
                let inputSummary = stringValue(in: item, keys: ["input"])
                return .toolUse(name: name, inputSummary: inputSummary)
            }

            if itemType == "text", let text = stringValue(in: item, keys: ["text"]) {
                return .partialOutput(text)
            }
        }

        return nil
    }

    private func stringValue(in object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String, !value.isEmpty {
                return value
            }
            if let value = object[key] {
                if JSONSerialization.isValidJSONObject(value),
                   let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
                   let json = String(data: data, encoding: .utf8) {
                    return json
                }
                return String(describing: value)
            }
        }

        return nil
    }
}

public final class ClaudeAgentRunner: AgentRunner, @unchecked Sendable {
    public let kind: AgentKind = .claude
    public let capabilities = AgentCapabilities(
        supportsStreaming: true,
        supportsResume: false,
        supportsCancellation: true,
        supportsInteractiveInput: false
    )

    private let commandBuilder: ClaudeCommandBuilder
    private let parser: ClaudeStreamEventParser
    private let lock = NSLock()
    private var processes: [AgentSessionID: Process] = [:]
    private var streams: [AgentSessionID: AsyncThrowingStream<AgentRunEvent, Error>] = [:]

    public init(
        configuration: ClaudeRunnerConfiguration = ClaudeRunnerConfiguration(),
        parser: ClaudeStreamEventParser = ClaudeStreamEventParser()
    ) {
        self.commandBuilder = ClaudeCommandBuilder(configuration: configuration)
        self.parser = parser
    }

    public func start(request: AgentRunRequest, runID: RunID) async throws -> AgentSession {
        let sessionID = AgentSessionID()
        let session = AgentSession(id: sessionID, runID: runID)
        var continuation: AsyncThrowingStream<AgentRunEvent, Error>.Continuation!
        let stream = AsyncThrowingStream<AgentRunEvent, Error> { streamContinuation in
            continuation = streamContinuation
        }
        let command = commandBuilder.command(for: request)
        let process = Process()
        process.executableURL = command.executableURL
        process.arguments = command.arguments
        process.currentDirectoryURL = command.workingDirectoryURL
        process.environment = ProcessInfo.processInfo.environment.merging(command.environment) { _, override in
            override
        }

        let standardInput = Pipe()
        let combinedOutput = Pipe()
        process.standardInput = standardInput
        process.standardOutput = combinedOutput
        process.standardError = combinedOutput

        try process.run()
        if let data = command.stdin.data(using: .utf8) {
            standardInput.fileHandleForWriting.write(data)
        }
        try? standardInput.fileHandleForWriting.close()

        set(process: process, stream: stream, for: sessionID)
        continuation.yield(.started(message: "Claude started"))

        Task.detached(priority: .utility) { [parser] in
            let outputData = combinedOutput.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(data: outputData, encoding: .utf8) ?? ""
            var emittedTerminalEvent = false

            for line in output.components(separatedBy: .newlines) {
                guard let event = parser.parseLine(line) else {
                    continue
                }
                if event.isTerminal {
                    emittedTerminalEvent = true
                }
                continuation.yield(event)
            }

            if process.terminationStatus == 0 {
                if !emittedTerminalEvent {
                    continuation.yield(.completed(summary: "Claude finished"))
                }
            } else if !emittedTerminalEvent {
                let message = output.trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.yield(.failed(message: message.isEmpty ? "Claude failed with exit code \(process.terminationStatus)" : message))
            }

            continuation.finish()
            self.removeSession(sessionID)
        }

        return session
    }

    public func send(_ input: AgentInput, to sessionID: AgentSessionID) async throws {
        throw ClaudeAgentRunnerError.interactiveInputUnsupported
    }

    public func cancel(sessionID: AgentSessionID) async throws {
        guard let process = process(for: sessionID) else {
            throw ClaudeAgentRunnerError.sessionNotFound(sessionID)
        }

        process.terminate()
    }

    public func events(for sessionID: AgentSessionID) -> AsyncThrowingStream<AgentRunEvent, Error> {
        lock.withLock {
            streams[sessionID] ?? AsyncThrowingStream { continuation in
                continuation.finish()
            }
        }
    }

    private func set(
        process: Process,
        stream: AsyncThrowingStream<AgentRunEvent, Error>,
        for sessionID: AgentSessionID
    ) {
        lock.withLock {
            processes[sessionID] = process
            streams[sessionID] = stream
        }
    }

    private func process(for sessionID: AgentSessionID) -> Process? {
        lock.withLock {
            processes[sessionID]
        }
    }

    private func removeSession(_ sessionID: AgentSessionID) {
        lock.withLock {
            processes[sessionID] = nil
            streams[sessionID] = nil
        }
    }
}

public enum ClaudeAgentRunnerError: Error, Equatable, CustomStringConvertible, LocalizedError {
    case interactiveInputUnsupported
    case sessionNotFound(AgentSessionID)

    public var description: String {
        switch self {
        case .interactiveInputUnsupported:
            return "Claude print sessions do not support interactive input yet."
        case let .sessionNotFound(sessionID):
            return "Claude session not found: \(sessionID.rawValue)"
        }
    }

    public var errorDescription: String? {
        description
    }
}

private extension AgentRunEvent {
    var isTerminal: Bool {
        switch self {
        case .completed, .failed:
            true
        case .started, .progress, .toolUse, .partialOutput, .waitingForInput:
            false
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
