import XCTest
import SymphonyCore
@testable import SymphonyCodexAgent

final class CodexAgentRunnerTests: XCTestCase {
    func testBuildsCodexExecJSONCommand() {
        let configuration = CodexRunnerConfiguration(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            executableArgumentsPrefix: ["codex"],
            sandboxMode: .workspaceWrite,
            approvalPolicy: .onRequest,
            extraArguments: ["--skip-git-repo-check"]
        )
        let request = AgentRunRequest(
            task: WorkItem(projectID: ProjectID(rawValue: "project-1"), identifier: "LOCAL-1", title: "Run Codex"),
            project: Project(id: ProjectID(rawValue: "project-1"), name: "Composer"),
            workflowPrompt: "Ship the task.",
            workspacePath: "/tmp/workspace",
            agent: AgentConfiguration(
                kind: .codex,
                model: "gpt-5.2",
                profile: "composer",
                parameters: ["reasoning.effort": "\"high\""]
            ),
            environment: ["CODEX_HOME": "/tmp/codex-home"]
        )

        let command = CodexCommandBuilder(configuration: configuration).command(for: request)

        XCTAssertEqual(command.executableURL.path, "/usr/bin/env")
        XCTAssertEqual(command.stdin, "Ship the task.")
        XCTAssertEqual(command.environment, ["CODEX_HOME": "/tmp/codex-home"])
        XCTAssertEqual(command.arguments, [
            "codex",
            "exec",
            "--json",
            "--color",
            "never",
            "-C",
            "/tmp/workspace",
            "--sandbox",
            "workspace-write",
            "--ask-for-approval",
            "on-request",
            "-m",
            "gpt-5.2",
            "-p",
            "composer",
            "-c",
            "reasoning.effort=\"high\"",
            "--skip-git-repo-check",
            "-"
        ])
    }

    func testParsesCodexJSONEventsIntoNormalizedEvents() {
        let parser = CodexJSONEventParser()

        XCTAssertEqual(
            parser.parseLine(#"{"type":"session_started","message":"Started"}"#),
            .started(message: "Started")
        )
        XCTAssertEqual(
            parser.parseLine(#"{"type":"tool_use","name":"apply_patch","input_summary":"Edited file"}"#),
            .toolUse(name: "apply_patch", inputSummary: "Edited file")
        )
        XCTAssertEqual(
            parser.parseLine(#"{"type":"message_delta","text":"partial"}"#),
            .partialOutput("partial")
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

    func testRunnerAdvertisesCodexCapabilities() {
        let runner = CodexAgentRunner()

        XCTAssertEqual(runner.kind, .codex)
        XCTAssertTrue(runner.capabilities.supportsStreaming)
        XCTAssertTrue(runner.capabilities.supportsCancellation)
        XCTAssertFalse(runner.capabilities.supportsInteractiveInput)
    }
}
