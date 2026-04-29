import Foundation
import SymphonyCore
import SymphonyInterfaces

public enum CodexSandboxMode: String, Codable, CaseIterable, Hashable, Sendable {
    case readOnly = "read-only"
    case workspaceWrite = "workspace-write"
    case dangerFullAccess = "danger-full-access"
}

public enum CodexApprovalPolicy: String, Codable, CaseIterable, Hashable, Sendable {
    case untrusted
    case onRequest = "on-request"
    case never
}

public struct CodexRunnerConfiguration: Hashable, Sendable {
    public var executableURL: URL
    public var executableArgumentsPrefix: [String]
    public var sandboxMode: CodexSandboxMode
    public var approvalPolicy: CodexApprovalPolicy
    public var extraArguments: [String]

    public init(
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/env"),
        executableArgumentsPrefix: [String] = ["codex"],
        sandboxMode: CodexSandboxMode = .workspaceWrite,
        approvalPolicy: CodexApprovalPolicy = .onRequest,
        extraArguments: [String] = []
    ) {
        self.executableURL = executableURL
        self.executableArgumentsPrefix = executableArgumentsPrefix
        self.sandboxMode = sandboxMode
        self.approvalPolicy = approvalPolicy
        self.extraArguments = extraArguments
    }
}

public struct CodexCommand: Equatable, Sendable {
    public var executableURL: URL
    public var arguments: [String]
    public var stdin: String
    public var environment: [String: String]

    public init(executableURL: URL, arguments: [String], stdin: String, environment: [String: String]) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.stdin = stdin
        self.environment = environment
    }
}

public struct CodexCommandBuilder: Sendable {
    public var configuration: CodexRunnerConfiguration

    public init(configuration: CodexRunnerConfiguration = CodexRunnerConfiguration()) {
        self.configuration = configuration
    }

    public func command(for request: AgentRunRequest) -> CodexCommand {
        var arguments = configuration.executableArgumentsPrefix
        arguments.append(contentsOf: [
            "exec",
            "--json",
            "--color",
            "never",
            "-C",
            request.workspacePath,
            "--sandbox",
            configuration.sandboxMode.rawValue,
            "--ask-for-approval",
            configuration.approvalPolicy.rawValue
        ])

        if let model = request.agent.model {
            arguments.append(contentsOf: ["-m", model])
        }

        if let profile = request.agent.profile {
            arguments.append(contentsOf: ["-p", profile])
        }

        for key in request.agent.parameters.keys.sorted() {
            arguments.append(contentsOf: ["-c", "\(key)=\(request.agent.parameters[key]!)"])
        }

        arguments.append(contentsOf: configuration.extraArguments)
        arguments.append("-")

        return CodexCommand(
            executableURL: configuration.executableURL,
            arguments: arguments,
            stdin: request.workflowPrompt,
            environment: request.environment
        )
    }
}

public struct CodexJSONEventParser: Sendable {
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
        let message = stringValue(in: object, keys: ["message", "msg", "text", "summary", "output", "error", "reason", "prompt"])
            ?? trimmed

        if type.contains("tool") || type.contains("command") {
            let name = stringValue(in: object, keys: ["toolName", "tool_name", "name", "command"]) ?? type
            let inputSummary = stringValue(in: object, keys: ["inputSummary", "input_summary", "arguments", "args"])
            return .toolUse(name: name, inputSummary: inputSummary)
        }

        if type.contains("partial") || type.contains("delta") {
            return .partialOutput(message)
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

        return .progress(message: message)
    }

    private func stringValue(in object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String, !value.isEmpty {
                return value
            }
            if let value = object[key] {
                return String(describing: value)
            }
        }

        return nil
    }
}

public final class CodexAgentRunner: AgentRunner, @unchecked Sendable {
    public let kind: AgentKind = .codex
    public let capabilities = AgentCapabilities(
        supportsStreaming: true,
        supportsResume: false,
        supportsCancellation: true,
        supportsInteractiveInput: false
    )

    private let commandBuilder: CodexCommandBuilder
    private let parser: CodexJSONEventParser
    private let lock = NSLock()
    private var processes: [AgentSessionID: Process] = [:]
    private var streams: [AgentSessionID: AsyncThrowingStream<AgentRunEvent, Error>] = [:]

    public init(
        configuration: CodexRunnerConfiguration = CodexRunnerConfiguration(),
        parser: CodexJSONEventParser = CodexJSONEventParser()
    ) {
        self.commandBuilder = CodexCommandBuilder(configuration: configuration)
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
        continuation.yield(.started(message: "Codex started"))

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
                    continuation.yield(.completed(summary: "Codex finished"))
                }
            } else if !emittedTerminalEvent {
                let message = output.trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.yield(.failed(message: message.isEmpty ? "Codex failed with exit code \(process.terminationStatus)" : message))
            }

            continuation.finish()
            self.removeSession(sessionID)
        }

        return session
    }

    public func send(_ input: AgentInput, to sessionID: AgentSessionID) async throws {
        throw CodexAgentRunnerError.interactiveInputUnsupported
    }

    public func cancel(sessionID: AgentSessionID) async throws {
        guard let process = process(for: sessionID) else {
            throw CodexAgentRunnerError.sessionNotFound(sessionID)
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

public enum CodexAgentRunnerError: Error, Equatable, CustomStringConvertible, LocalizedError {
    case interactiveInputUnsupported
    case sessionNotFound(AgentSessionID)

    public var description: String {
        switch self {
        case .interactiveInputUnsupported:
            return "Codex exec sessions do not support interactive input yet."
        case let .sessionNotFound(sessionID):
            return "Codex session not found: \(sessionID.rawValue)"
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
