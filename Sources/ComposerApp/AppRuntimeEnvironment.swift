import Foundation
import ComposerStorage
import SymphonyCore
import SymphonyInterfaces
import SymphonyRuntime
import SymphonyWorkflow

struct AppRuntimeEnvironment {
    var storeSelection: StoreSelection
    var orchestrator: Orchestrator
    var workflowLoader: WorkflowLoader
    var startupWarning: String?

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
        runners: [any AgentRunner]? = nil,
        startupWarning: String? = nil
    ) {
        self.storeSelection = storeSelection
        self.workflowLoader = workflowLoader
        self.startupWarning = startupWarning
        orchestrator = Orchestrator(
            taskStore: storeSelection.store,
            projectStore: storeSelection.store,
            runners: runners ?? Self.defaultPreviewRunners()
        )
    }

    static func live(workflowLoader: WorkflowLoader = WorkflowLoader()) -> AppRuntimeEnvironment {
        do {
            let configuration = try AppStorageConfiguration.fromLaunchConfiguration()
            let selection = try StoreFactory.makeStore(configuration: configuration.storeConfiguration)
            return AppRuntimeEnvironment(storeSelection: selection, workflowLoader: workflowLoader)
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
}
