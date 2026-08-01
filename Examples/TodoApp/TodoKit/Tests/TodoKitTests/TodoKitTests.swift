import XCTest
@testable import TodoKit

final class TodoKitTests: XCTestCase {
    func testPlaceholder() throws {
        XCTAssertEqual(try TodoDatabase.ephemeral().launchProbeCount(), 0)
    }
}
