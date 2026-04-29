import XCTest
import SymphonyCore
@testable import SymphonyClaudeAgent

final class ClaudeAgentRunnerTests: XCTestCase {
    func testBuildsClaudePrintStreamCommand() {
        let configuration = ClaudeRunnerConfiguration(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            executableArgumentsPrefix: ["claude"],
            permissionMode: .default,
            extraArguments: ["--bare"]
        )
        let request = AgentRunRequest(
            task: WorkItem(projectID: ProjectID(rawValue: "project-1"), identifier: "LOCAL-1", title: "Run Claude"),
            project: Project(id: ProjectID(rawValue: "project-1"), name: "Composer"),
            workflowPrompt: "Ship the task.",
            workspacePath: "/tmp/workspace",
            agent: AgentConfiguration(
                kind: .claude,
                model: "sonnet",
                profile: "reviewer",
                parameters: ["effort": "high"]
            ),
            environment: ["ANTHROPIC_API_KEY": "test"]
        )

        let command = ClaudeCommandBuilder(configuration: configuration).command(for: request)

        XCTAssertEqual(command.executableURL.path, "/usr/bin/env")
        XCTAssertEqual(command.workingDirectoryURL.path, "/tmp/workspace")
        XCTAssertEqual(command.stdin, "Ship the task.")
        XCTAssertEqual(command.environment, ["ANTHROPIC_API_KEY": "test"])
        XCTAssertEqual(command.arguments, [
            "claude",
            "--print",
            "--input-format",
            "text",
            "--output-format",
            "stream-json",
            "--include-partial-messages",
            "--permission-mode",
            "default",
            "--model",
            "sonnet",
            "--agent",
            "reviewer",
            "--effort",
            "high",
            "--bare"
        ])
    }

    func testParsesClaudeStreamEventsIntoNormalizedEvents() {
        let parser = ClaudeStreamEventParser()

        XCTAssertEqual(
            parser.parseLine(#"{"type":"system","message":"Started"}"#),
            .started(message: "Started")
        )
        XCTAssertEqual(
            parser.parseLine(#"{"type":"assistant","message":{"content":[{"type":"text","text":"partial"}]}}"#),
            .partialOutput("partial")
        )
        XCTAssertEqual(
            parser.parseLine(#"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"git status"}}]}}"#),
            .toolUse(name: "Bash", inputSummary: #"{"command":"git status"}"#)
        )
        XCTAssertEqual(
            parser.parseLine(#"{"type":"waiting_for_input","prompt":"Approve?"}"#),
            .waitingForInput(prompt: "Approve?")
        )
        XCTAssertEqual(
            parser.parseLine(#"{"type":"result","result":"Done"}"#),
            .completed(summary: "Done")
        )
        XCTAssertEqual(
            parser.parseLine(#"{"type":"error","message":"Failed"}"#),
            .failed(message: "Failed")
        )
        XCTAssertEqual(
            parser.parseLine("plain output"),
            .partialOutput("plain output")
        )
    }

    func testRunnerAdvertisesClaudeCapabilities() {
        let runner = ClaudeAgentRunner()

        XCTAssertEqual(runner.kind, .claude)
        XCTAssertTrue(runner.capabilities.supportsStreaming)
        XCTAssertTrue(runner.capabilities.supportsCancellation)
        XCTAssertFalse(runner.capabilities.supportsInteractiveInput)
    }
}
