import Foundation
import Darwin
import ComposerStorage
import SymphonyClaudeAgent
import SymphonyCodexAgent
import SymphonyGeminiAgent
import SymphonyRuntime
import SymphonyWorkflow
import SymphonyWorkspace

private struct RuntimeHelperConfiguration {
    static let defaultMachServiceName = "dev.janneh.composer.runtime"
    static let storeBackendEnvironmentKey = "COMPOSER_STORE_BACKEND"
    static let storePathEnvironmentKey = "COMPOSER_STORE_PATH"
    static let machServiceEnvironmentKey = "COMPOSER_RUNTIME_MACH_SERVICE"

    var storeConfiguration: StoreConfiguration
    var machServiceName: String

    init(
        arguments: [String] = CommandLine.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws {
        var backend = try environment[Self.storeBackendEnvironmentKey]
            .flatMap { try StoreBackend(argument: $0) } ?? StoreBackend.json
        var fileURL = environment[Self.storePathEnvironmentKey].map(Self.fileURL(path:))
        var machServiceName = environment[Self.machServiceEnvironmentKey] ?? Self.defaultMachServiceName

        var index = 1
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--help", "-h":
                printUsage()
                exit(0)
            case "--store-backend":
                backend = try StoreBackend(argument: try Self.value(after: argument, in: arguments, at: index))
                index += 2
            case "--store":
                fileURL = Self.fileURL(path: try Self.value(after: argument, in: arguments, at: index))
                index += 2
            case "--mach-service":
                machServiceName = try Self.value(after: argument, in: arguments, at: index)
                index += 2
            default:
                throw RuntimeHelperError.unknownArgument(argument)
            }
        }

        storeConfiguration = StoreConfiguration(backend: backend, fileURL: fileURL)
        self.machServiceName = machServiceName
    }

    fileprivate static func fileURL(path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    private static func value(after argument: String, in arguments: [String], at index: Int) throws -> String {
        let valueIndex = index + 1
        guard valueIndex < arguments.count else {
            throw RuntimeHelperError.missingValue(argument)
        }
        return arguments[valueIndex]
    }
}

private enum RuntimeHelperError: Error, CustomStringConvertible, LocalizedError {
    case missingValue(String)
    case unknownArgument(String)

    var description: String {
        switch self {
        case let .missingValue(argument):
            return "Missing value for \(argument)."
        case let .unknownArgument(argument):
            return "Unknown argument \(argument)."
        }
    }

    var errorDescription: String? {
        description
    }
}

private final class RuntimeHelperDelegate: NSObject, NSXPCListenerDelegate {
    private let adapter: RuntimeServiceXPCAdapter

    init(adapter: RuntimeServiceXPCAdapter) {
        self.adapter = adapter
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = RuntimeXPCInterfaceFactory.makeInterface()
        connection.exportedObject = adapter
        connection.resume()
        return true
    }
}

private struct RuntimeStoreCacheKey: Hashable {
    var backend: StoreBackend
    var path: String?
}

private actor RuntimeServiceRegistry {
    private let defaultStoreConfiguration: StoreConfiguration
    private let defaultKey: RuntimeStoreCacheKey
    private var services: [RuntimeStoreCacheKey: LocalRuntimeService]

    init(defaultStoreConfiguration: StoreConfiguration, defaultStoreSelection: StoreSelection) {
        self.defaultStoreConfiguration = defaultStoreConfiguration
        defaultKey = Self.cacheKey(for: defaultStoreSelection)
        services = [
            defaultKey: makeRuntimeService(storeSelection: defaultStoreSelection)
        ]
    }

    func service(for context: RuntimeServiceStoreContext?) async throws -> any RuntimeService {
        if context == nil, let service = services[defaultKey] {
            return service
        }

        let configuration = try storeConfiguration(for: context)
        let selection = try StoreFactory.makeStore(configuration: configuration)
        let key = Self.cacheKey(for: selection)
        if let service = services[key] {
            return service
        }

        let service = makeRuntimeService(storeSelection: selection)
        services[key] = service
        return service
    }

    private func storeConfiguration(for context: RuntimeServiceStoreContext?) throws -> StoreConfiguration {
        guard let context else {
            return defaultStoreConfiguration
        }

        return StoreConfiguration(
            backend: try StoreBackend(argument: context.backend),
            fileURL: context.path.map(RuntimeHelperConfiguration.fileURL(path:))
        )
    }

    private static func cacheKey(for selection: StoreSelection) -> RuntimeStoreCacheKey {
        RuntimeStoreCacheKey(backend: selection.backend, path: selection.fileURL.path)
    }
}

private func makeRuntimeService(storeSelection: StoreSelection) -> LocalRuntimeService {
    let orchestrator = Orchestrator(
        taskStore: storeSelection.store,
        projectStore: storeSelection.store,
        runStore: storeSelection.store,
        eventStore: storeSelection.store,
        workflowProvider: FileWorkflowProvider(),
        workspaceProvider: LocalWorkspaceProvider(),
        runners: [
            CodexAgentRunner(),
            ClaudeAgentRunner(),
            GeminiAgentRunner()
        ]
    )
    return LocalRuntimeService(orchestrator: orchestrator)
}

private func printUsage() {
    print(
        """
        Usage: composer-runtime-helper [options]

        Options:
          --store-backend json|sqlite   Storage backend. Defaults to COMPOSER_STORE_BACKEND or json.
          --store PATH                  Store file path. Defaults to COMPOSER_STORE_PATH or backend default.
          --mach-service NAME           Mach service name. Defaults to COMPOSER_RUNTIME_MACH_SERVICE or dev.janneh.composer.runtime.
          --help                        Show this help.
        """
    )
}

do {
    let configuration = try RuntimeHelperConfiguration()
    let defaultStoreSelection = try StoreFactory.makeStore(configuration: configuration.storeConfiguration)
    let serviceRegistry = RuntimeServiceRegistry(
        defaultStoreConfiguration: configuration.storeConfiguration,
        defaultStoreSelection: defaultStoreSelection
    )
    let adapter = RuntimeServiceXPCAdapter(serviceFactory: { context in
        try await serviceRegistry.service(for: context)
    })
    let delegate = RuntimeHelperDelegate(adapter: adapter)
    let listener = NSXPCListener(machServiceName: configuration.machServiceName)
    listener.delegate = delegate
    listener.resume()

    print("Composer runtime helper listening on \(configuration.machServiceName) using \(defaultStoreSelection.backend.rawValue) store at \(defaultStoreSelection.fileURL.path)")
    withExtendedLifetime(delegate) {
        RunLoop.main.run()
    }
} catch {
    fputs("composer-runtime-helper: \(error.localizedDescription)\n", stderr)
    exit(1)
}
