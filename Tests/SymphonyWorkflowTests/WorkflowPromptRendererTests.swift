import XCTest
import SymphonyCore
@testable import SymphonyWorkflow

final class WorkflowPromptRendererTests: XCTestCase {
    func testRendersWorkflowProjectTaskAndRunContext() throws {
        let project = Project(
            id: ProjectID(rawValue: "project-1"),
            name: "Composer",
            repositoryPath: "/repo",
            defaultAgent: AgentConfiguration(kind: .codex, model: "gpt-5"),
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        let blockerID = TaskID(rawValue: "task-blocker")
        let task = WorkItem(
            id: TaskID(rawValue: "task-1"),
            projectID: project.id,
            identifier: "LOCAL-1",
            title: "Render prompts",
            description: "Use the workflow body and task context.",
            state: .ready,
            priority: .high,
            labels: ["workflow", "runtime"],
            blockedBy: [blockerID],
            preferredAgent: AgentConfiguration(kind: .claude, model: "sonnet"),
            links: [
                ExternalLink(
                    id: "link-1",
                    title: "Spec",
                    url: URL(string: "https://example.com/spec")!,
                    kind: "docs"
                )
            ],
            createdAt: Date(timeIntervalSince1970: 300),
            updatedAt: Date(timeIntervalSince1970: 400)
        )
        let run = RunAttempt(
            id: RunID(rawValue: "run-1"),
            taskID: task.id,
            agent: AgentConfiguration(kind: .claude, model: "sonnet"),
            status: .queued,
            workspace: WorkspaceReference(
                path: "/repo/.composer/workspaces/local-1",
                cleanupPolicy: .removeOnSuccess,
                preparedAt: Date(timeIntervalSince1970: 450)
            ),
            startedAt: Date(timeIntervalSince1970: 500),
            summary: "Queued for preview"
        )
        let document = WorkflowDocument(
            fileURL: URL(fileURLWithPath: "/repo/WORKFLOW.md"),
            content: "",
            frontMatter: WorkflowFrontMatter(fields: [
                "agents": .stringList(["codex", "claude"]),
                "enabled": .bool(true)
            ]),
            body: "Follow the repository instructions."
        )

        let prompt = try WorkflowPromptRenderer().render(
            document: document,
            context: WorkflowPromptContext(project: project, task: task, run: run)
        )

        XCTAssertTrue(prompt.contains("# Workflow Instructions"))
        XCTAssertTrue(prompt.contains("Follow the repository instructions."))
        XCTAssertTrue(prompt.contains("# Workflow Metadata"))
        XCTAssertTrue(prompt.contains("- agents: codex, claude"))
        XCTAssertTrue(prompt.contains("- enabled: true"))
        XCTAssertTrue(prompt.contains("# Project Context"))
        XCTAssertTrue(prompt.contains("- Name: Composer"))
        XCTAssertTrue(prompt.contains("- Workflow file: /repo/WORKFLOW.md"))
        XCTAssertTrue(prompt.contains("# Task Context"))
        XCTAssertTrue(prompt.contains("- Identifier: LOCAL-1"))
        XCTAssertTrue(prompt.contains("- Labels: workflow, runtime"))
        XCTAssertTrue(prompt.contains("- Blocked by: task-blocker"))
        XCTAssertTrue(prompt.contains("## Task Description"))
        XCTAssertTrue(prompt.contains("Use the workflow body and task context."))
        XCTAssertTrue(prompt.contains("- Spec [docs]: https://example.com/spec"))
        XCTAssertTrue(prompt.contains("# Run Context"))
        XCTAssertTrue(prompt.contains("- ID: run-1"))
        XCTAssertTrue(prompt.contains("- Workspace: /repo/.composer/workspaces/local-1"))
        XCTAssertTrue(prompt.contains("- Workspace cleanup: removeOnSuccess"))
        XCTAssertTrue(prompt.contains("- Summary: Queued for preview"))
    }

    func testRendersStrictWorkflowTemplateWithIssueAndAttemptContext() throws {
        let project = Project(
            id: ProjectID(rawValue: "project-1"),
            name: "Composer",
            repositoryPath: "/repo",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        let task = WorkItem(
            id: TaskID(rawValue: "task-1"),
            projectID: project.id,
            identifier: "LOCAL-1",
            title: "Render prompts",
            description: "Use strict template rendering.",
            state: .ready,
            priority: .urgent,
            labels: ["workflow", "urgent"],
            blockedBy: [TaskID(rawValue: "blocker-1")],
            createdAt: Date(timeIntervalSince1970: 300),
            updatedAt: Date(timeIntervalSince1970: 400)
        )
        let document = WorkflowDocument(
            fileURL: URL(fileURLWithPath: "/repo/WORKFLOW.md"),
            content: "",
            body: """
            Ticket {{ issue.identifier }}: {{ issue.title }}
            Labels: {{ issue.labels | join: " / " }}
            {% if issue.labels contains "urgent" %}Priority path{% endif %}
            {% if attempt %}Attempt {{ attempt }}{% else %}First run{% endif %}
            {% for blocker in issue.blocked_by %}Blocked by {{ blocker.id }}{% endfor %}
            """
        )

        let firstPrompt = try WorkflowPromptRenderer().render(
            document: document,
            context: WorkflowPromptContext(project: project, task: task, run: RunAttempt(taskID: task.id, agent: .init(kind: .codex)))
        )
        let retryPrompt = try WorkflowPromptRenderer().render(
            document: document,
            context: WorkflowPromptContext(
                project: project,
                task: task,
                run: RunAttempt(
                    taskID: task.id,
                    agent: .init(kind: .codex),
                    status: .running,
                    startedAt: Date(timeIntervalSince1970: 500)
                )
            )
        )

        XCTAssertTrue(firstPrompt.contains("Ticket LOCAL-1: Render prompts"))
        XCTAssertTrue(firstPrompt.contains("Labels: workflow / urgent"))
        XCTAssertTrue(firstPrompt.contains("Priority path"))
        XCTAssertTrue(firstPrompt.contains("First run"))
        XCTAssertTrue(firstPrompt.contains("Blocked by blocker-1"))
        XCTAssertTrue(retryPrompt.contains("Attempt 1"))
        XCTAssertFalse(retryPrompt.contains("{{ issue.identifier }}"))
        XCTAssertFalse(retryPrompt.contains("{% if attempt %}"))
    }

    func testStrictWorkflowTemplateRejectsUnknownVariables() throws {
        let project = Project(name: "Composer")
        let task = WorkItem(
            projectID: project.id,
            identifier: "LOCAL-1",
            title: "Render prompts"
        )
        let document = WorkflowDocument(
            fileURL: URL(fileURLWithPath: "/repo/WORKFLOW.md"),
            content: "",
            body: "Ticket {{ issue.identifer }}"
        )

        XCTAssertThrowsError(try WorkflowPromptRenderer().render(
            document: document,
            context: WorkflowPromptContext(project: project, task: task)
        )) { error in
            XCTAssertEqual(error as? WorkflowTemplateError, .unknownVariable("issue.identifer"))
        }
    }

    func testStrictWorkflowTemplateRejectsUnknownFilters() throws {
        let project = Project(name: "Composer")
        let task = WorkItem(
            projectID: project.id,
            identifier: "LOCAL-1",
            title: "Render prompts"
        )
        let document = WorkflowDocument(
            fileURL: URL(fileURLWithPath: "/repo/WORKFLOW.md"),
            content: "",
            body: "Ticket {{ issue.identifier | typo }}"
        )

        XCTAssertThrowsError(try WorkflowPromptRenderer().render(
            document: document,
            context: WorkflowPromptContext(project: project, task: task)
        )) { error in
            XCTAssertEqual(error as? WorkflowTemplateError, .unknownFilter("typo"))
        }
    }

    func testFileWorkflowProviderLoadsAndRendersPrompt() async throws {
        let repositoryURL = temporaryDirectory()
        try FileManager.default.createDirectory(at: repositoryURL, withIntermediateDirectories: true)
        try """
        ---
        name: Composer
        ---
        Ship {{ issue.identifier }}.
        """.write(to: repositoryURL.appendingPathComponent("WORKFLOW.md"), atomically: true, encoding: .utf8)
        let project = Project(
            id: ProjectID(rawValue: "project-1"),
            name: "Composer",
            repositoryPath: repositoryURL.path,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let task = WorkItem(
            id: TaskID(rawValue: "task-1"),
            projectID: project.id,
            identifier: "LOCAL-1",
            title: "Provider prompt",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        let prompt = try await FileWorkflowProvider().prompt(for: task, project: project)

        XCTAssertTrue(prompt.contains("Ship LOCAL-1."))
        XCTAssertTrue(prompt.contains("- name: Composer"))
        XCTAssertTrue(prompt.contains("- Identifier: LOCAL-1"))
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("workflow-prompt-renderer-tests-\(UUID().uuidString)", isDirectory: true)
    }
}
