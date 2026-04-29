import XCTest
import ComposerStorage
@testable import ComposerApp

final class AppStorageConfigurationTests: XCTestCase {
    func testLaunchConfigurationDefaultsToJSON() throws {
        let defaults = makeDefaults()

        let configuration = try AppStorageConfiguration.fromLaunchConfiguration(
            environment: [:],
            defaults: defaults
        )

        XCTAssertEqual(configuration.backend, .json)
        XCTAssertNil(configuration.fileURL)
        XCTAssertTrue(configuration.watchesFileChanges)
    }

    func testLaunchConfigurationReadsDefaults() throws {
        let defaults = makeDefaults()
        defaults.set("sqlite", forKey: AppStorageConfiguration.backendDefaultsKey)
        defaults.set("~/composer-test.sqlite3", forKey: AppStorageConfiguration.pathDefaultsKey)

        let configuration = try AppStorageConfiguration.fromLaunchConfiguration(
            environment: [:],
            defaults: defaults
        )

        XCTAssertEqual(configuration.backend, .sqlite)
        XCTAssertEqual(configuration.fileURL?.path, NSString(string: "~/composer-test.sqlite3").expandingTildeInPath)
        XCTAssertFalse(configuration.watchesFileChanges)
    }

    func testEnvironmentOverridesDefaults() throws {
        let defaults = makeDefaults()
        defaults.set("json", forKey: AppStorageConfiguration.backendDefaultsKey)
        defaults.set("/tmp/default-store.json", forKey: AppStorageConfiguration.pathDefaultsKey)

        let configuration = try AppStorageConfiguration.fromLaunchConfiguration(
            environment: [
                AppStorageConfiguration.backendEnvironmentKey: "sqlite3",
                AppStorageConfiguration.pathEnvironmentKey: "/tmp/env-store.sqlite3"
            ],
            defaults: defaults
        )

        XCTAssertEqual(configuration.backend, .sqlite)
        XCTAssertEqual(configuration.fileURL?.path, "/tmp/env-store.sqlite3")
    }

    @MainActor
    func testAppModelCanUseSQLiteStoreSelection() async throws {
        let fileURL = temporaryDirectory().appendingPathComponent("app.sqlite3")
        let selection = try StoreFactory.makeStore(
            configuration: StoreConfiguration(backend: .sqlite, fileURL: fileURL)
        )
        let model = AppModel(storeSelection: selection)

        await model.load()

        XCTAssertEqual(model.storageBackend, .sqlite)
        XCTAssertEqual(model.storeFileURL, fileURL)
        XCTAssertEqual(model.projects.map(\.name), ["Local Project"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "composer-app-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("composer-app-tests-\(UUID().uuidString)", isDirectory: true)
    }
}
