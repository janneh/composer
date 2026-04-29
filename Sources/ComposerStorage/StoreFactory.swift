import Foundation
import SymphonyInterfaces
import SymphonyLocalStore
import SymphonySQLiteStore

public enum StoreBackend: String, CaseIterable, Sendable {
    case json
    case sqlite

    public init(argument: String) throws {
        switch argument.normalizedStoreArgument {
        case "json", "localjson", "local":
            self = .json
        case "sqlite", "sqlite3", "db":
            self = .sqlite
        default:
            throw StoreConfigurationError.unknownBackend(argument)
        }
    }
}

public struct StoreConfiguration: Sendable {
    public var backend: StoreBackend
    public var fileURL: URL?
    public var appName: String

    public init(
        backend: StoreBackend = .json,
        fileURL: URL? = nil,
        appName: String = "Composer"
    ) {
        self.backend = backend
        self.fileURL = fileURL
        self.appName = appName
    }
}

public struct StoreSelection: Sendable {
    public var backend: StoreBackend
    public var fileURL: URL
    public var store: any ComposerStore

    public init(backend: StoreBackend, fileURL: URL, store: any ComposerStore) {
        self.backend = backend
        self.fileURL = fileURL
        self.store = store
    }
}

public enum StoreFactory {
    public static func makeStore(configuration: StoreConfiguration = StoreConfiguration()) throws -> StoreSelection {
        switch configuration.backend {
        case .json:
            let store = try makeJSONStore(configuration: configuration)
            return StoreSelection(backend: .json, fileURL: store.fileURL, store: store)
        case .sqlite:
            let store = try makeSQLiteStore(configuration: configuration)
            return StoreSelection(backend: .sqlite, fileURL: store.fileURL, store: store)
        }
    }

    private static func makeJSONStore(configuration: StoreConfiguration) throws -> LocalJSONStore {
        if let fileURL = configuration.fileURL {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return LocalJSONStore(fileURL: fileURL)
        }

        return try LocalJSONStore.defaultStore(appName: configuration.appName)
    }

    private static func makeSQLiteStore(configuration: StoreConfiguration) throws -> SQLiteStore {
        if let fileURL = configuration.fileURL {
            return try SQLiteStore(fileURL: fileURL)
        }

        return try SQLiteStore.defaultStore(appName: configuration.appName)
    }
}

public enum StoreConfigurationError: Error, Equatable, CustomStringConvertible, LocalizedError {
    case unknownBackend(String)

    public var description: String {
        switch self {
        case let .unknownBackend(value):
            "Unknown store backend '\(value)'. Use json or sqlite."
        }
    }

    public var errorDescription: String? {
        description
    }
}

private extension String {
    var normalizedStoreArgument: String {
        lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }
}
