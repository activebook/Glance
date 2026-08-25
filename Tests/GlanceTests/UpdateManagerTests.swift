import XCTest
@testable import Glance

final class UpdateManagerTests: XCTestCase {
    @MainActor
    func test_versionComparison_patchBump() {
        let manager = UpdateManager.shared
        XCTAssertTrue(manager.isRemoteVersionNewer(remote: "v0.1.2", current: "0.1.1"))
        XCTAssertTrue(manager.isRemoteVersionNewer(remote: "0.1.2", current: "0.1.1"))
        XCTAssertFalse(manager.isRemoteVersionNewer(remote: "v0.1.1", current: "0.1.1"))
        XCTAssertFalse(manager.isRemoteVersionNewer(remote: "v0.1.0", current: "0.1.1"))
    }

    @MainActor
    func test_versionComparison_minorBump() {
        let manager = UpdateManager.shared
        XCTAssertTrue(manager.isRemoteVersionNewer(remote: "v0.2.0", current: "0.1.9"))
        XCTAssertFalse(manager.isRemoteVersionNewer(remote: "v0.1.9", current: "0.2.0"))
    }

    @MainActor
    func test_versionComparison_majorBump() {
        let manager = UpdateManager.shared
        XCTAssertTrue(manager.isRemoteVersionNewer(remote: "v1.0.0", current: "0.9.9"))
        XCTAssertFalse(manager.isRemoteVersionNewer(remote: "v0.9.9", current: "1.0.0"))
    }

    @MainActor
    func test_versionComparison_differentLengthComponents() {
        let manager = UpdateManager.shared
        XCTAssertTrue(manager.isRemoteVersionNewer(remote: "1.0.0.1", current: "1.0.0"))
        XCTAssertFalse(manager.isRemoteVersionNewer(remote: "1.0", current: "1.0.0"))
    }
}
