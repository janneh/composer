import XCTest
@testable import SymphonyCore

final class SymphonyCoreTests: XCTestCase {
    func testOnlyReadyStateDispatchesByDefault() {
        XCTAssertTrue(WorkState.ready.canDispatch)
        XCTAssertFalse(WorkState.backlog.canDispatch)
        XCTAssertFalse(WorkState.running.canDispatch)
        XCTAssertFalse(WorkState.done.canDispatch)
    }

    func testMovingTaskUpdatesState() {
        let projectID = ProjectID(rawValue: "project")
        let task = WorkItem(projectID: projectID, identifier: "LOCAL-1", title: "Test")
        let moved = task.moving(to: .ready)

        XCTAssertEqual(moved.id, task.id)
        XCTAssertEqual(moved.state, .ready)
        XCTAssertGreaterThanOrEqual(moved.updatedAt, task.updatedAt)
    }
}
