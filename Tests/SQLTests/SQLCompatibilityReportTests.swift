import GRDB
import XCTest


// SwiftQL 1.x pinned this the other way round: every compatibility lane had to
// compile in Swift 5 language mode. v2.0 adopts Swift 6 language mode (issue
// #133), so the tripwire now guards the opposite direction and fails the build
// if a lane silently falls back.
#if !swift(>=6.0)
#error("SwiftQL 2.x compatibility lanes must compile in Swift 6 language mode")
#endif


final class XLCompatibilityReportTests: XCTestCase {

    func testSQLiteRuntimeVersionIsReported() throws {
        let databaseQueue = try DatabaseQueue()
        let runtime: (version: String, sourceID: String) = try databaseQueue.read { database in
            let row = try XCTUnwrap(
                Row.fetchOne(
                    database,
                    sql: """
                        SELECT
                            sqlite_version() AS version,
                            sqlite_source_id() AS sourceID
                        """
                )
            )

            return (row["version"], row["sourceID"])
        }

        XCTAssertFalse(runtime.version.isEmpty)
        XCTAssertFalse(runtime.sourceID.isEmpty)
        print(
            "SWIFTQL_SQLITE_RUNTIME " +
            "sqlite_version=\(runtime.version) " +
            "sqlite_source_id=\(runtime.sourceID)"
        )
    }
}
