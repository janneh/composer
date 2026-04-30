import Foundation
import ComposerStorage
import SymphonyCore
import SymphonyInterfaces
import SymphonyRuntime
import SymphonyWorkflow

struct AppRuntimeEnvironment {
    var storeSelection: StoreSelection
    var runtimeService: any RuntimeService
    var workflowLoader: WorkflowLoader
    var startupWarning: String?
    var supportsRunDispatch: Bool

    var store: any ComposerStore {
        storeSelection.store
    }

    var storageBackend: StoreBackend {
        storeSelection.backend
    }

    var storeFileURL: URL {
        storeSelection.fileURL
    }

    init(
        storeSelection: StoreSelection,
        workflowLoader: WorkflowLoader = WorkflowLoader(),
        runtimeConnection: AppRuntimeConnection = .local,
        runtimeService: (any RuntimeService)? = nil,
        runners: [any AgentRunner]? = nil,
        startupWarning: String? = nil
    ) {
        self.storeSelection = storeSelection
        self.workflowLoader = workflowLoader
        self.startupWarning = startupWarning
        supportsRunDispatch = runtimeService != nil || runtimeConnection.supportsRunDispatch
        let orchestrator = Orchestrator(
            taskStore: storeSelection.store,
            projectStore: storeSelection.store,
            runners: runners ?? Self.defaultPreviewRunners()
        )
        let localService = LocalRuntimeService(orchestrator: orchestrator)
        self.runtimeService = runtimeService ?? Self.makeRuntimeService(
            localService: localService,
            connection: runtimeConnection,
            storeSelection: storeSelection
        )
    }

    static func live(workflowLoader: WorkflowLoader = WorkflowLoader()) -> AppRuntimeEnvironment {
        let runtimeConnection = AppRuntimeConnection.fromLaunchConfiguration()
        do {
            let configuration = try AppStorageConfiguration.fromLaunchConfiguration()
            let selection = try StoreFactory.makeStore(configuration: configuration.storeConfiguration)
            return AppRuntimeEnvironment(
                storeSelection: selection,
                workflowLoader: workflowLoader,
                runtimeConnection: runtimeConnection
            )
        } catch {
            let fallback = FileManager.default.temporaryDirectory
                .appendingPathComponent("Composer-local-store.json")
            do {
                let selection = try StoreFactory.makeStore(
                    configuration: StoreConfiguration(backend: .json, fileURL: fallback)
                )
                return AppRuntimeEnvironment(
                    storeSelection: selection,
                    workflowLoader: workflowLoader,
                    runtimeConnection: runtimeConnection,
                    startupWarning: "Storage configuration failed: \(error.localizedDescription). Using \(fallback.path)."
                )
            } catch {
                preconditionFailure("Could not create fallback Composer store: \(error.localizedDescription)")
            }
        }
    }

    func storeChanges() -> AsyncThrowingStream<Void, Error>? {
        guard storageBackend == .json else {
            return nil
        }

        return StoreFileWatcher.changes(fileURL: storeFileURL)
    }

    private static func defaultPreviewRunners() -> [any AgentRunner] {
        [
            NoopAgentRunner(kind: .codex),
            NoopAgentRunner(kind: .claude),
            NoopAgentRunner(kind: .gemini)
        ]
    }

    private static func makeRuntimeService(
        localService: LocalRuntimeService,
        connection: AppRuntimeConnection,
        storeSelection: StoreSelection
    ) -> any RuntimeService {
        switch connection {
        case .local:
            return localService
        case let .helper(machServiceName):
            #if canImport(ObjectiveC)
            return RuntimeXPCClient(
                machServiceName: machServiceName,
                storeContext: RuntimeServiceStoreContext(
                    backend: storeSelection.backend.rawValue,
                    path: storeSelection.fileURL.path
                )
            )
            #else
            return localService
            #endif
        }
    }
}

enum AppRuntimeConnection: Equatable, Sendable {
    static let modeEnvironmentKey = "COMPOSER_RUNTIME_MODE"
    static let machServiceEnvironmentKey = "COMPOSER_RUNTIME_MACH_SERVICE"
    static let modeDefaultsKey = "ComposerRuntimeMode"
    static let machServiceDefaultsKey = "ComposerRuntimeMachService"

    case local
    case helper(machServiceName: String)

    var supportsRunDispatch: Bool {
        switch self {
        case .local:
            return false
        case .helper:
            return true
        }
    }

    static func fromLaunchConfiguration(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaults: UserDefaults = .standard
    ) -> AppRuntimeConnection {
        let mode = configuredValue(
            environmentKey: modeEnvironmentKey,
            defaultsKey: modeDefaultsKey,
            environment: environment,
            defaults: defaults
        )?.normalizedRuntimeMode

        let machServiceName = configuredValue(
            environmentKey: machServiceEnvironmentKey,
            defaultsKey: machServiceDefaultsKey,
            environment: environment,
            defaults: defaults
        ) ?? RuntimeXPCClient.defaultMachServiceName

        switch mode {
        case "helper", "xpc", "launchagent":
            return .helper(machServiceName: machServiceName)
        default:
            return .local
        }
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
}

private extension String {
    var normalizedRuntimeMode: String {
        lowercased().filter { $0.isLetter || $0.isNumber }
    }

    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
