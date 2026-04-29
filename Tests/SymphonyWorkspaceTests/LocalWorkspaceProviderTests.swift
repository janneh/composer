import XCTest
import SymphonyCore
import SymphonyWorkspace

final class LocalWorkspaceProviderTests: XCTestCase {
    func testPrepareWorkspaceCreatesReusableGitWorktree() async throws {
        let rootURL = temporaryDirectory()
        let repositoryURL = rootURL.appendingPathComponent("repo", isDirectory: true)
        let workspaceRootURL = rootURL.appendingPathComponent("workspaces", isDirectory: true)
        try FileManager.default.createDirectory(at: repositoryURL, withIntermediateDirectories: true)
        try initializeGitRepository(at: repositoryURL)
        try "hello\n".write(to: repositoryURL.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try runGit(["-C", repositoryURL.path, "add", "README.md"])
        try runGit(["-C", repositoryURL.path, "commit", "-m", "Initial commit"])

        let project = Project(
            id: ProjectID(rawValue: "project-1"),
            name: "Composer App",
            repositoryPath: repositoryURL.path
        )
        let task = WorkItem(
            id: TaskID(rawValue: "task-1"),
            projectID: project.id,
            identifier: "LOCAL-1",
            title: "Prepare workspace"
        )
        let provider = LocalWorkspaceProvider(
            configuration: WorkspaceConfiguration(rootDirectory: workspaceRootURL)
        )

        let workspace = try await provider.prepareWorkspace(for: task, project: project)
        let repeatedWorkspace = try await provider.prepareWorkspace(for: task, project: project)
        let workspacePath = workspace.path

        XCTAssertEqual(repeatedWorkspace.path, workspacePath)
        XCTAssertEqual(workspace.cleanupPolicy, .keep)
        XCTAssertEqual(
            workspacePath,
            workspaceRootURL
                .appendingPathComponent("composer-app-project-1", isDirectory: true)
                .appendingPathComponent("local-1-task-1", isDirectory: true)
                .path
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: "\(workspacePath)/README.md"))
        XCTAssertEqual(
            try runGit(["-C", workspacePath, "rev-parse", "--is-inside-work-tree"])
                .trimmingCharacters(in: .whitespacesAndNewlines),
            "true"
        )

        try await provider.cleanupWorkspace(workspace, for: task, project: project)
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspacePath))
    }

    func testPrepareWorkspaceUsesConfiguredCleanupPolicy() async throws {
        let rootURL = temporaryDirectory()
        let repositoryURL = rootURL.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repositoryURL, withIntermediateDirectories: true)
        try initializeGitRepository(at: repositoryURL)
        try "hello\n".write(to: repositoryURL.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try runGit(["-C", repositoryURL.path, "add", "README.md"])
        try runGit(["-C", repositoryURL.path, "commit", "-m", "Initial commit"])

        let project = Project(
            id: ProjectID(rawValue: "project-1"),
            name: "Composer App",
            repositoryPath: repositoryURL.path
        )
        let task = WorkItem(
            id: TaskID(rawValue: "task-1"),
            projectID: project.id,
            identifier: "LOCAL-1",
            title: "Prepare workspace"
        )
        let provider = LocalWorkspaceProvider(
            configuration: WorkspaceConfiguration(
                rootDirectory: rootURL.appendingPathComponent("workspaces", isDirectory: true),
                cleanupPolicy: .removeOnSuccess
            )
        )

        let workspace = try await provider.prepareWorkspace(for: task, project: project)

        XCTAssertEqual(workspace.cleanupPolicy, .removeOnSuccess)
        XCTAssertFalse(workspace.preparedAt.timeIntervalSince1970.isZero)

        try await provider.cleanupWorkspace(workspace, for: task, project: project)
    }

    func testPrepareWorkspaceRequiresRepositoryPath() async throws {
        let provider = LocalWorkspaceProvider(
            configuration: WorkspaceConfiguration(rootDirectory: temporaryDirectory())
        )
        let project = Project(id: ProjectID(rawValue: "project-missing"), name: "Missing")
        let task = WorkItem(projectID: project.id, identifier: "LOCAL-1", title: "Prepare workspace")

        do {
            _ = try await provider.prepareWorkspace(for: task, project: project)
            XCTFail("Expected missing repository path error")
        } catch let error as LocalWorkspaceProviderError {
            XCTAssertEqual(error, .missingRepositoryPath(project.id))
        }
    }

    func testPrepareWorkspaceRejectsNonGitRepository() async throws {
        let rootURL = temporaryDirectory()
        let repositoryURL = rootURL.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repositoryURL, withIntermediateDirectories: true)

        let project = Project(
            id: ProjectID(rawValue: "project-plain"),
            name: "Plain",
            repositoryPath: repositoryURL.path
        )
        let task = WorkItem(projectID: project.id, identifier: "LOCAL-1", title: "Prepare workspace")
        let provider = LocalWorkspaceProvider(
            configuration: WorkspaceConfiguration(rootDirectory: rootURL.appendingPathComponent("workspaces"))
        )

        do {
            _ = try await provider.prepareWorkspace(for: task, project: project)
            XCTFail("Expected non-Git repository error")
        } catch let error as LocalWorkspaceProviderError {
            XCTAssertEqual(error, .notGitRepository(repositoryURL.path))
        }
    }

    func testRejectsExistingWorkspaceWhenReuseIsDisabled() async throws {
        let rootURL = temporaryDirectory()
        let repositoryURL = rootURL.appendingPathComponent("repo", isDirectory: true)
        let workspaceRootURL = rootURL.appendingPathComponent("workspaces", isDirectory: true)
        try FileManager.default.createDirectory(at: repositoryURL, withIntermediateDirectories: true)
        try initializeGitRepository(at: repositoryURL)
        try "hello\n".write(to: repositoryURL.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try runGit(["-C", repositoryURL.path, "add", "README.md"])
        try runGit(["-C", repositoryURL.path, "commit", "-m", "Initial commit"])

        let project = Project(
            id: ProjectID(rawValue: "project-1"),
            name: "Composer App",
            repositoryPath: repositoryURL.path
        )
        let task = WorkItem(
            id: TaskID(rawValue: "task-1"),
            projectID: project.id,
            identifier: "LOCAL-1",
            title: "Prepare workspace"
        )
        let reusingProvider = LocalWorkspaceProvider(
            configuration: WorkspaceConfiguration(rootDirectory: workspaceRootURL, reuseExisting: true)
        )
        let strictProvider = LocalWorkspaceProvider(
            configuration: WorkspaceConfiguration(rootDirectory: workspaceRootURL, reuseExisting: false)
        )

        let workspace = try await reusingProvider.prepareWorkspace(for: task, project: project)

        do {
            _ = try await strictProvider.prepareWorkspace(for: task, project: project)
            XCTFail("Expected existing workspace error")
        } catch let error as LocalWorkspaceProviderError {
            XCTAssertEqual(error, .workspaceAlreadyExists(workspace.path))
        }

        try await reusingProvider.cleanupWorkspace(workspace, for: task, project: project)
    }

    private func initializeGitRepository(at url: URL) throws {
        try runGit(["init", url.path])
        try runGit(["-C", url.path, "config", "user.email", "composer-tests@example.invalid"])
        try runGit(["-C", url.path, "config", "user.name", "Composer Tests"])
    }

    @discardableResult
    private func runGit(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments

        let standardOutput = Pipe()
        let standardError = Pipe()
        process.standardOutput = standardOutput
        process.standardError = standardError

        try process.run()
        process.waitUntilExit()

        let output = standardOutput.fileHandleForReading.readDataToEndOfFile().utf8String
        let errorOutput = standardError.fileHandleForReading.readDataToEndOfFile().utf8String
        let combinedOutput = [output, errorOutput]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        guard process.terminationStatus == 0 else {
            throw TestGitError(arguments: arguments, exitCode: process.terminationStatus, output: combinedOutput)
        }

        return output
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("composer-workspace-tests-\(UUID().uuidString)", isDirectory: true)
    }
}

private struct TestGitError: Error, CustomStringConvertible {
    var arguments: [String]
    var exitCode: Int32
    var output: String

    var description: String {
        "git \(arguments.joined(separator: " ")) failed with exit code \(exitCode): \(output)"
    }
}

private extension Data {
    var utf8String: String {
        String(data: self, encoding: .utf8) ?? ""
    }
}
