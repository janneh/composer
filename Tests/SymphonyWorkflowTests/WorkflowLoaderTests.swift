import XCTest
import SymphonyCore
@testable import SymphonyWorkflow

final class WorkflowLoaderTests: XCTestCase {
    func testLoadsDefaultWorkflowFromRepositoryPath() throws {
        let repositoryURL = temporaryDirectory()
        try FileManager.default.createDirectory(at: repositoryURL, withIntermediateDirectories: true)
        let workflowURL = repositoryURL.appendingPathComponent("WORKFLOW.md")
        try "# Workflow\nRun the task.\n".write(to: workflowURL, atomically: true, encoding: .utf8)
        let project = Project(name: "Composer", repositoryPath: repositoryURL.path)

        let document = try WorkflowLoader().load(project: project)

        XCTAssertEqual(document.fileURL, workflowURL.standardizedFileURL)
        XCTAssertEqual(document.content, "# Workflow\nRun the task.\n")
    }

    func testLoadsExplicitAbsoluteWorkflowPath() throws {
        let directoryURL = temporaryDirectory()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let workflowURL = directoryURL.appendingPathComponent("Custom.workflow.md")
        try "Custom workflow\n".write(to: workflowURL, atomically: true, encoding: .utf8)
        let project = Project(name: "Composer", workflowPath: workflowURL.path)

        let document = try WorkflowLoader().load(project: project)

        XCTAssertEqual(document.fileURL, workflowURL.standardizedFileURL)
        XCTAssertEqual(document.content, "Custom workflow\n")
    }

    func testLoadsExplicitRelativeWorkflowPathFromRepositoryPath() throws {
        let repositoryURL = temporaryDirectory()
        let workflowDirectoryURL = repositoryURL.appendingPathComponent(".composer", isDirectory: true)
        try FileManager.default.createDirectory(at: workflowDirectoryURL, withIntermediateDirectories: true)
        let workflowURL = workflowDirectoryURL.appendingPathComponent("workflow.md")
        try "Relative workflow\n".write(to: workflowURL, atomically: true, encoding: .utf8)
        let project = Project(
            name: "Composer",
            repositoryPath: repositoryURL.path,
            workflowPath: ".composer/workflow.md"
        )

        let document = try WorkflowLoader().load(project: project)

        XCTAssertEqual(document.fileURL, workflowURL.standardizedFileURL)
        XCTAssertEqual(document.content, "Relative workflow\n")
    }

    func testRelativeWorkflowPathFallsBackToCurrentDirectory() throws {
        let directoryURL = temporaryDirectory()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let workflowURL = directoryURL.appendingPathComponent("WORKFLOW.md")
        try "Current directory workflow\n".write(to: workflowURL, atomically: true, encoding: .utf8)
        let project = Project(name: "Composer", workflowPath: "WORKFLOW.md")

        let document = try WorkflowLoader(currentDirectoryURL: directoryURL).load(project: project)

        XCTAssertEqual(document.fileURL, workflowURL.standardizedFileURL)
        XCTAssertEqual(document.content, "Current directory workflow\n")
    }

    func testValidateReportsMissingWorkflow() {
        let project = Project(
            id: ProjectID(rawValue: "project-missing"),
            name: "Composer",
            repositoryPath: temporaryDirectory().path
        )

        let diagnostics = WorkflowLoader().validate(project: project)

        XCTAssertEqual(diagnostics.count, 1)
        XCTAssertEqual(diagnostics[0].severity, .error)
        XCTAssertTrue(diagnostics[0].message.contains("No WORKFLOW.md found for project project-missing"))
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("symphony-workflow-tests-\(UUID().uuidString)", isDirectory: true)
    }
}
