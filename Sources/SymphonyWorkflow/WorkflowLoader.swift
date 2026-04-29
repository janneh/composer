import Foundation
import SymphonyCore
import SymphonyInterfaces

public struct WorkflowDocument: Hashable, Sendable {
    public var fileURL: URL
    public var content: String

    public init(fileURL: URL, content: String) {
        self.fileURL = fileURL
        self.content = content
    }
}

public struct WorkflowLoader {
    public var fileManager: FileManager
    public var currentDirectoryURL: URL

    public init(
        fileManager: FileManager = .default,
        currentDirectoryURL: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    ) {
        self.fileManager = fileManager
        self.currentDirectoryURL = currentDirectoryURL
    }

    public func load(project: Project) throws -> WorkflowDocument {
        let fileURL = try resolveWorkflowURL(project: project)
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        return WorkflowDocument(fileURL: fileURL, content: content)
    }

    public func resolveWorkflowURL(project: Project) throws -> URL {
        let candidates = workflowCandidates(for: project)
        if let existing = candidates.first(where: fileExists) {
            return existing
        }

        throw WorkflowLoaderError.workflowNotFound(projectID: project.id, candidates: candidates)
    }

    public func validate(project: Project) -> [WorkflowDiagnostic] {
        do {
            _ = try resolveWorkflowURL(project: project)
            return []
        } catch let error as WorkflowLoaderError {
            return [WorkflowDiagnostic(severity: .error, message: error.description)]
        } catch {
            return [WorkflowDiagnostic(severity: .error, message: error.localizedDescription)]
        }
    }

    private func workflowCandidates(for project: Project) -> [URL] {
        if let workflowPath = project.workflowPath?.trimmedNonEmpty {
            return [resolve(path: workflowPath, relativeTo: project.repositoryPath)]
        }

        guard let repositoryPath = project.repositoryPath?.trimmedNonEmpty else {
            return []
        }

        return [resolve(path: "WORKFLOW.md", relativeTo: repositoryPath)]
    }

    private func resolve(path: String, relativeTo basePath: String?) -> URL {
        let expandedPath = (path as NSString).expandingTildeInPath
        if expandedPath.hasPrefix("/") {
            return URL(fileURLWithPath: expandedPath).standardizedFileURL
        }

        let baseURL = basePath?.trimmedNonEmpty.map { path in
            URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        } ?? currentDirectoryURL

        return baseURL.appendingPathComponent(expandedPath).standardizedFileURL
    }

    private func fileExists(at fileURL: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }
}

public enum WorkflowLoaderError: Error, Equatable, CustomStringConvertible {
    case workflowNotFound(projectID: ProjectID, candidates: [URL])

    public var description: String {
        switch self {
        case let .workflowNotFound(projectID, candidates):
            let candidateList = candidates.map(\.path).joined(separator: ", ")
            if candidateList.isEmpty {
                return "No WORKFLOW.md found for project \(projectID.rawValue): set a repository path or workflow path."
            }
            return "No WORKFLOW.md found for project \(projectID.rawValue) at: \(candidateList)"
        }
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
