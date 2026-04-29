import Foundation
import SymphonyCore
import SymphonyInterfaces

public enum GeminiApprovalMode: String, Codable, CaseIterable, Hashable, Sendable {
    case `default`
    case autoEdit = "auto_edit"
    case yolo
}

public struct GeminiRunnerConfiguration: Hashable, Sendable {
    public var executableURL: URL
    public var executableArgumentsPrefix: [String]
    public var approvalMode: GeminiApprovalMode
    public var useSandbox: Bool
    public var includeAllFiles: Bool
    public var extraArguments: [String]

    public init(
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/env"),
        executableArgumentsPrefix: [String] = ["gemini"],
        approvalMode: GeminiApprovalMode = .default,
        useSandbox: Bool = false,
        includeAllFiles: Bool = false,
        extraArguments: [String] = []
    ) {
        self.executableURL = executableURL
        self.executableArgumentsPrefix = executableArgumentsPrefix
        self.approvalMode = approvalMode
        self.useSandbox = useSandbox
        self.includeAllFiles = includeAllFiles
        self.extraArguments = extraArguments
    }
}

public struct GeminiCommand: Equatable, Sendable {
    public var executableURL: URL
    public var arguments: [String]
    public var workingDirectoryURL: URL
    public var environment: [String: String]

    public init(executableURL: URL, arguments: [String], workingDirectoryURL: URL, environment: [String: String]) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.workingDirectoryURL = workingDirectoryURL
        self.environment = environment
    }
}

public struct GeminiCommandBuilder: Sendable {
    public var configuration: GeminiRunnerConfiguration

    public init(configuration: GeminiRunnerConfiguration = GeminiRunnerConfiguration()) {
        self.configuration = configuration
    }

    public func command(for request: AgentRunRequest) -> GeminiCommand {
        var arguments = configuration.executableArgumentsPrefix
        arguments.append(contentsOf: [
            "--prompt",
            request.workflowPrompt,
            "--approval-mode",
            configuration.approvalMode.rawValue
        ])

        if let model = request.agent.model {
            arguments.append(contentsOf: ["--model", model])
        }

        if configuration.useSandbox {
            arguments.append("--sandbox")
        }

        if configuration.includeAllFiles {
            arguments.append("--all-files")
        }

        if let includeDirectories = request.agent.parameters["include-directories"] {
            arguments.append(contentsOf: ["--include-directories", includeDirectories])
        }

        arguments.append(contentsOf: configuration.extraArguments)

        return GeminiCommand(
            executableURL: configuration.executableURL,
            arguments: arguments,
            workingDirectoryURL: URL(fileURLWithPath: request.workspacePath, isDirectory: true),
            environment: request.environment
        )
    }
}

public struct GeminiOutputParser: Sendable {
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
        let message = stringValue(in: object, keys: ["message", "text", "summary", "output", "error", "reason", "prompt"])
            ?? trimmed

        if type.contains("tool") || type.contains("command") {
            let name = stringValue(in: object, keys: ["name", "tool_name", "toolName", "command"]) ?? type
            let inputSummary = stringValue(in: object, keys: ["input", "input_summary", "inputSummary", "args"])
            return .toolUse(name: name, inputSummary: inputSummary)
        }

        if type.contains("approval") || type.contains("input") || type.contains("waiting") {
            return .waitingForInput(prompt: message)
        }

        if type.contains("complete") || type.contains("finished") || type.contains("final") {
            return .completed(summary: message)
        }

        if type.contains("error") || type.contains("fail") {
            return .failed(message: message)
        }

        if type.contains("start") {
            return .started(message: message)
        }

        return .partialOutput(message)
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

public final class GeminiAgentRunner: AgentRunner, @unchecked Sendable {
    public let kind: AgentKind = .gemini
    public let capabilities = AgentCapabilities(
        supportsStreaming: true,
        supportsResume: false,
        supportsCancellation: true,
        supportsInteractiveInput: false
    )

    private let commandBuilder: GeminiCommandBuilder
    private let parser: GeminiOutputParser
    private let lock = NSLock()
    private var processes: [AgentSessionID: Process] = [:]
    private var streams: [AgentSessionID: AsyncThrowingStream<AgentRunEvent, Error>] = [:]

    public init(
        configuration: GeminiRunnerConfiguration = GeminiRunnerConfiguration(),
        parser: GeminiOutputParser = GeminiOutputParser()
    ) {
        self.commandBuilder = GeminiCommandBuilder(configuration: configuration)
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

        let combinedOutput = Pipe()
        process.standardOutput = combinedOutput
        process.standardError = combinedOutput

        try process.run()
        set(process: process, stream: stream, for: sessionID)
        continuation.yield(.started(message: "Gemini started"))

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
                    continuation.yield(.completed(summary: "Gemini finished"))
                }
            } else if !emittedTerminalEvent {
                let message = output.trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.yield(.failed(message: message.isEmpty ? "Gemini failed with exit code \(process.terminationStatus)" : message))
            }

            continuation.finish()
            self.removeSession(sessionID)
        }

        return session
    }

    public func send(_ input: AgentInput, to sessionID: AgentSessionID) async throws {
        throw GeminiAgentRunnerError.interactiveInputUnsupported
    }

    public func cancel(sessionID: AgentSessionID) async throws {
        guard let process = process(for: sessionID) else {
            throw GeminiAgentRunnerError.sessionNotFound(sessionID)
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

public enum GeminiAgentRunnerError: Error, Equatable, CustomStringConvertible, LocalizedError {
    case interactiveInputUnsupported
    case sessionNotFound(AgentSessionID)

    public var description: String {
        switch self {
        case .interactiveInputUnsupported:
            return "Gemini prompt sessions do not support interactive input yet."
        case let .sessionNotFound(sessionID):
            return "Gemini session not found: \(sessionID.rawValue)"
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
