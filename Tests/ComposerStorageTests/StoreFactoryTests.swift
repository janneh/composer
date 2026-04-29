import XCTest
import ComposerStorage
import SymphonyCore

final class StoreFactoryTests: XCTestCase {
    func testParsesBackendArguments() throws {
        XCTAssertEqual(try StoreBackend(argument: "json"), .json)
        XCTAssertEqual(try StoreBackend(argument: "local-json"), .json)
        XCTAssertEqual(try StoreBackend(argument: "sqlite"), .sqlite)
        XCTAssertEqual(try StoreBackend(argument: "sqlite3"), .sqlite)
    }

    func testRejectsUnknownBackend() {
        XCTAssertThrowsError(try StoreBackend(argument: "linear")) { error in
            XCTAssertEqual(error as? StoreConfigurationError, .unknownBackend("linear"))
        }
    }

    func testCreatesJSONStoreAtConfiguredPath() async throws {
        let fileURL = temporaryDirectory().appendingPathComponent("store.json")
        let selection = try StoreFactory.makeStore(
            configuration: StoreConfiguration(backend: .json, fileURL: fileURL)
        )
        let project = Project(
            id: ProjectID(rawValue: "project-json"),
            name: "JSON",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 101)
        )

        try await selection.store.upsertProject(project)
        let projects = try await selection.store.listProjects()

        XCTAssertEqual(selection.backend, .json)
        XCTAssertEqual(selection.fileURL, fileURL)
        XCTAssertEqual(projects, [project])
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testCreatesSQLiteStoreAtConfiguredPath() async throws {
        let fileURL = temporaryDirectory().appendingPathComponent("store.sqlite3")
        let selection = try StoreFactory.makeStore(
            configuration: StoreConfiguration(backend: .sqlite, fileURL: fileURL)
        )
        let project = Project(
            id: ProjectID(rawValue: "project-sqlite"),
            name: "SQLite",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 101)
        )

        try await selection.store.upsertProject(project)
        let projects = try await selection.store.listProjects()

        XCTAssertEqual(selection.backend, .sqlite)
        XCTAssertEqual(selection.fileURL, fileURL)
        XCTAssertEqual(projects, [project])
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("composer-storage-tests-\(UUID().uuidString)", isDirectory: true)
    }
}
