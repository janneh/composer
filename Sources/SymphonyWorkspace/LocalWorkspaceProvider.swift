import Foundation
import SymphonyCore
import SymphonyInterfaces

public struct WorkspaceConfiguration: Equatable, Sendable {
    public var rootDirectory: URL
    public var cleanupPolicy: WorkspaceCleanupPolicy
    public var reuseExisting: Bool

    public init(
        rootDirectory: URL = WorkspaceConfiguration.defaultRootDirectory(),
        cleanupPolicy: WorkspaceCleanupPolicy = .keep,
        reuseExisting: Bool = true
    ) {
        self.rootDirectory = rootDirectory.standardizedFileURL
        self.cleanupPolicy = cleanupPolicy
        self.reuseExisting = reuseExisting
    }

    public static func defaultRootDirectory(appName: String = "Composer") -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".\(appName.lowercased())", isDirectory: true)
            .appendingPathComponent("workspaces", isDirectory: true)
            .standardizedFileURL
    }
}

public actor LocalWorkspaceProvider: WorkspaceProvider {
    private let configuration: WorkspaceConfiguration

    public init(configuration: WorkspaceConfiguration = WorkspaceConfiguration()) {
        self.configuration = configuration
    }

    public func prepareWorkspace(for task: WorkItem, project: Project) async throws -> WorkspaceReference {
        let sourceURL = try repositoryURL(for: project)
        let destinationURL = workspaceURL(for: task, project: project)

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            guard configuration.reuseExisting else {
                throw LocalWorkspaceProviderError.workspaceAlreadyExists(destinationURL.path)
            }
            return WorkspaceReference(path: destinationURL.path, cleanupPolicy: configuration.cleanupPolicy)
        }

        try await ensureGitRepository(at: sourceURL)
        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        do {
            try await runGit([
                "-C",
                sourceURL.path,
                "worktree",
                "add",
                "--detach",
                destinationURL.path,
                "HEAD"
            ])
        } catch {
            try? FileManager.default.removeItem(at: destinationURL)
            throw error
        }

        return WorkspaceReference(path: destinationURL.path, cleanupPolicy: configuration.cleanupPolicy)
    }

    public func cleanupWorkspace(_ workspace: WorkspaceReference, for task: WorkItem, project: Project) async throws {
        let destinationURL = URL(fileURLWithPath: workspace.path, isDirectory: true).standardizedFileURL
        guard FileManager.default.fileExists(atPath: destinationURL.path) else {
            return
        }

        if let sourceURL = try? repositoryURL(for: project),
           (try? await isGitRepository(at: sourceURL)) == true {
            do {
                try await runGit(["-C", sourceURL.path, "worktree", "remove", "--force", destinationURL.path])
                return
            } catch {}
        }

        try FileManager.default.removeItem(at: destinationURL)
    }

    public func workspacePath(for task: WorkItem, project: Project) -> String {
        workspaceURL(for: task, project: project).path
    }

    private func repositoryURL(for project: Project) throws -> URL {
        guard let repositoryPath = project.repositoryPath?.trimmedNonEmpty else {
            throw LocalWorkspaceProviderError.missingRepositoryPath(project.id)
        }

        let url = URL(fileURLWithPath: (repositoryPath as NSString).expandingTildeInPath, isDirectory: true)
            .standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw LocalWorkspaceProviderError.repositoryNotFound(url.path)
        }

        return url
    }

    private func workspaceURL(for task: WorkItem, project: Project) -> URL {
        configuration.rootDirectory
            .appendingPathComponent(project.workspaceSegment, isDirectory: true)
            .appendingPathComponent(task.workspaceSegment, isDirectory: true)
            .standardizedFileURL
    }

    private func ensureGitRepository(at url: URL) async throws {
        guard try await isGitRepository(at: url) else {
            throw LocalWorkspaceProviderError.notGitRepository(url.path)
        }
    }

    private func isGitRepository(at url: URL) async throws -> Bool {
        do {
            let output = try await runGit(["-C", url.path, "rev-parse", "--is-inside-work-tree"])
            return output.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
        } catch let error as LocalWorkspaceProviderError {
            if case .gitCommandFailed = error {
                return false
            }
            throw error
        }
    }

    @discardableResult
    private func runGit(_ arguments: [String]) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments

        let standardOutput = Pipe()
        let standardError = Pipe()
        process.standardOutput = standardOutput
        process.standardError = standardError

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw LocalWorkspaceProviderError.gitCommandFailed(
                arguments: arguments,
                exitCode: -1,
                output: error.localizedDescription
            )
        }

        let output = standardOutput.fileHandleForReading.readDataToEndOfFile().utf8String
        let errorOutput = standardError.fileHandleForReading.readDataToEndOfFile().utf8String
        let combinedOutput = [output, errorOutput]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        guard process.terminationStatus == 0 else {
            throw LocalWorkspaceProviderError.gitCommandFailed(
                arguments: arguments,
                exitCode: process.terminationStatus,
                output: combinedOutput
            )
        }

        return output
    }
}

public enum LocalWorkspaceProviderError: Error, Equatable, CustomStringConvertible, LocalizedError {
    case missingRepositoryPath(ProjectID)
    case repositoryNotFound(String)
    case notGitRepository(String)
    case workspaceAlreadyExists(String)
    case gitCommandFailed(arguments: [String], exitCode: Int32, output: String)

    public var description: String {
        switch self {
        case let .missingRepositoryPath(projectID):
            return "Project \(projectID.rawValue) has no repository path."
        case let .repositoryNotFound(path):
            return "Repository path does not exist: \(path)"
        case let .notGitRepository(path):
            return "Repository path is not a Git work tree: \(path)"
        case let .workspaceAlreadyExists(path):
            return "Workspace already exists: \(path)"
        case let .gitCommandFailed(arguments, exitCode, output):
            let command = (["git"] + arguments).joined(separator: " ")
            let details = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if details.isEmpty {
                return "Git command failed with exit code \(exitCode): \(command)"
            }
            return "Git command failed with exit code \(exitCode): \(command)\n\(details)"
        }
    }

    public var errorDescription: String? {
        description
    }
}

private extension Project {
    var workspaceSegment: String {
        "\(name)-\(id.rawValue)".safeWorkspaceSegment
    }
}

private extension WorkItem {
    var workspaceSegment: String {
        "\(identifier)-\(id.rawValue)".safeWorkspaceSegment
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var safeWorkspaceSegment: String {
        var result = ""
        var previousWasSeparator = false

        for character in lowercased() {
            if character.isLetter || character.isNumber || character == "." || character == "_" {
                result.append(character)
                previousWasSeparator = false
            } else if !previousWasSeparator {
                result.append("-")
                previousWasSeparator = true
            }
        }

        let trimmed = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "workspace" : trimmed
    }
}

private extension Data {
    var utf8String: String {
        String(data: self, encoding: .utf8) ?? ""
    }
}
