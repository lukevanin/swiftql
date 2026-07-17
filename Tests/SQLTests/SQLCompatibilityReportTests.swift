import GRDB
import XCTest


#if swift(>=6.0)
#error("SwiftQL 1.x compatibility lanes must compile in Swift 5 language mode")
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
