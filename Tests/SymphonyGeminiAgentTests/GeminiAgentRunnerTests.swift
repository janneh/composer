import XCTest
import SymphonyCore
@testable import SymphonyGeminiAgent

final class GeminiAgentRunnerTests: XCTestCase {
    func testBuildsGeminiPromptCommand() {
        let configuration = GeminiRunnerConfiguration(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            executableArgumentsPrefix: ["gemini"],
            approvalMode: .autoEdit,
            useSandbox: true,
            includeAllFiles: true,
            extraArguments: ["--debug"]
        )
        let request = AgentRunRequest(
            task: WorkItem(projectID: ProjectID(rawValue: "project-1"), identifier: "LOCAL-1", title: "Run Gemini"),
            project: Project(id: ProjectID(rawValue: "project-1"), name: "Composer"),
            workflowPrompt: "Ship the task.",
            workspacePath: "/tmp/workspace",
            agent: AgentConfiguration(
                kind: .gemini,
                model: "gemini-2.5-pro",
                parameters: ["include-directories": "/tmp/shared"]
            ),
            environment: ["GEMINI_API_KEY": "test"]
        )

        let command = GeminiCommandBuilder(configuration: configuration).command(for: request)

        XCTAssertEqual(command.executableURL.path, "/usr/bin/env")
        XCTAssertEqual(command.workingDirectoryURL.path, "/tmp/workspace")
        XCTAssertEqual(command.environment, ["GEMINI_API_KEY": "test"])
        XCTAssertEqual(command.arguments, [
            "gemini",
            "--prompt",
            "Ship the task.",
            "--approval-mode",
            "auto_edit",
            "--model",
            "gemini-2.5-pro",
            "--sandbox",
            "--all-files",
            "--include-directories",
            "/tmp/shared",
            "--debug"
        ])
    }

    func testParsesGeminiOutputIntoNormalizedEvents() {
        let parser = GeminiOutputParser()

        XCTAssertEqual(
            parser.parseLine(#"{"type":"started","message":"Started"}"#),
            .started(message: "Started")
        )
        XCTAssertEqual(
            parser.parseLine(#"{"type":"tool_use","name":"Shell","input":{"command":"git status"}}"#),
            .toolUse(name: "Shell", inputSummary: #"{"command":"git status"}"#)
        )
        XCTAssertEqual(
            parser.parseLine(#"{"type":"waiting_for_input","prompt":"Approve?"}"#),
            .waitingForInput(prompt: "Approve?")
        )
        XCTAssertEqual(
            parser.parseLine(#"{"type":"completed","summary":"Done"}"#),
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

    func testRunnerAdvertisesGeminiCapabilities() {
        let runner = GeminiAgentRunner()

        XCTAssertEqual(runner.kind, .gemini)
        XCTAssertTrue(runner.capabilities.supportsStreaming)
        XCTAssertTrue(runner.capabilities.supportsCancellation)
        XCTAssertFalse(runner.capabilities.supportsInteractiveInput)
    }
}
