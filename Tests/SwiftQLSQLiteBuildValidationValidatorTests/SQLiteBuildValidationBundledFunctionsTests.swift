import Foundation
import GRDB
import SwiftQLCore
import XCTest
@testable import SwiftQLSQLiteBuildValidationValidator


/// Issue #683: the validator installs the functions the runtime installs,
/// read from one table in SwiftQLCore rather than from a copy of it.
final class SQLiteBuildValidationBundledFunctionsTests: XCTestCase {

    func testValidatorInstallsExactlyTheRuntimeBundledFunctions() {
        XCTAssertEqual(
            SQLiteBuildValidationBundledFunctions.all.map(\.definition),
            XLCustomFunctionRegistration.bundled.keys.sorted()
        )
        XCTAssertFalse(XLCustomFunctionRegistration.bundled.isEmpty)
    }

    func testEveryBundledFunctionIsOnTheValidatorConnection() throws {
        let queue = try DatabaseQueue()
        try queue.inDatabase { database in
            SQLiteBuildValidationBundledFunctions.register(on: database)
            let functions = try Row.fetchAll(database, sql: "PRAGMA function_list")
                .compactMap { row -> XLCustomFunctionDefinition? in
                    guard let name = row["name"] as String?, let arguments = row["narg"] as Int? else {
                        return nil
                    }
                    return XLCustomFunctionDefinition(name: name, numberOfArguments: arguments)
                }
            for definition in XLCustomFunctionRegistration.bundled.keys {
                XCTAssertTrue(functions.contains(definition), "\(definition) is not on the connection.")
            }
        }
    }

    /// The validator's `regexp` is the runtime's: the same matches, and the
    /// same refusal of an invalid pattern.
    func testValidatorRegexpBehavesAsTheRuntimeRegexp() throws {
        let queue = try DatabaseQueue()
        try queue.inDatabase { database in
            SQLiteBuildValidationBundledFunctions.register(on: database)
            XCTAssertEqual(try Int.fetchOne(database, sql: "SELECT 'alpha-123' REGEXP '[0-9]+$'"), 1)
            XCTAssertEqual(try Int.fetchOne(database, sql: "SELECT 'alpha' REGEXP '^b'"), 0)
            XCTAssertNil(try Int.fetchOne(database, sql: "SELECT NULL REGEXP 'a'"))
            XCTAssertThrowsError(try Int.fetchOne(database, sql: "SELECT 'a' REGEXP '('")) { error in
                XCTAssertTrue(
                    (error as? DatabaseError)?.message?.contains("(") == true,
                    "\(error)"
                )
            }
        }
    }
}
