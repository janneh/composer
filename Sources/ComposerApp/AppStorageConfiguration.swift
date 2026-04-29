import Foundation
import ComposerStorage

struct AppStorageConfiguration: Equatable, Sendable {
    static let backendEnvironmentKey = "COMPOSER_STORE_BACKEND"
    static let pathEnvironmentKey = "COMPOSER_STORE_PATH"
    static let backendDefaultsKey = "ComposerStoreBackend"
    static let pathDefaultsKey = "ComposerStorePath"

    var backend: StoreBackend
    var fileURL: URL?

    init(backend: StoreBackend = .json, fileURL: URL? = nil) {
        self.backend = backend
        self.fileURL = fileURL
    }

    static func fromLaunchConfiguration(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaults: UserDefaults = .standard
    ) throws -> AppStorageConfiguration {
        let backendValue = configuredValue(
            environmentKey: backendEnvironmentKey,
            defaultsKey: backendDefaultsKey,
            environment: environment,
            defaults: defaults
        )
        let pathValue = configuredValue(
            environmentKey: pathEnvironmentKey,
            defaultsKey: pathDefaultsKey,
            environment: environment,
            defaults: defaults
        )

        return AppStorageConfiguration(
            backend: try backendValue.map(StoreBackend.init(argument:)) ?? .json,
            fileURL: pathValue.map(makeFileURL)
        )
    }

    var storeConfiguration: StoreConfiguration {
        StoreConfiguration(backend: backend, fileURL: fileURL)
    }

    var watchesFileChanges: Bool {
        backend == .json
    }

    private static func configuredValue(
        environmentKey: String,
        defaultsKey: String,
        environment: [String: String],
        defaults: UserDefaults
    ) -> String? {
        if let value = environment[environmentKey]?.trimmedNonEmpty {
            return value
        }

        return defaults.string(forKey: defaultsKey)?.trimmedNonEmpty
    }

    private static func makeFileURL(path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
