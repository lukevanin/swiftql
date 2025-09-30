//import SwiftSyntaxMacros
//import SwiftSyntaxMacrosTestSupport
//import XCTest
//import XLMacros

//let testMacros: [String: Macro.Type] = [
//    "stringify": StringifyMacro.self,
//    "SQLTable": SQLTableMacro.self,
//    "SQLTable": SQLTableMacro.self,
//]

//final class XLTests: XCTestCase {
//    func testMacro() {
//        assertMacroExpansion(
//            """
//            #stringify(a + b)
//            """,
//            expandedSource: """
//            (a + b, "a + b")
//            """,
//            macros: testMacros
//        )
//    }
//
//    func testMacroWithStringLiteral() {
//        assertMacroExpansion(
//            #"""
//            #stringify("Hello, \(name)")
//            """#,
//            expandedSource: #"""
//            ("Hello, \(name)", #""Hello, \(name)""#)
//            """#,
//            macros: testMacros
//        )
//    }
    
//    func test_SQLTable() {
//        assertMacroExpansion(
//            """
//            @SQLTable
//            struct Book {
//                var id: Int
//                @MyDate(format: .iso8601) var date: Date
//            }
//            """,
//            expandedSource:
//            """
//            struct Book {
//                var id: Int
//                var date: Date
//            }
//            """,
//            macros: testMacros
//        )
//    }
//}
