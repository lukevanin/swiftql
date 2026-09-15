//
//  DeclaredQueryScannerTests.swift
//  SwiftQLDeclaredQueryDiscoveryTests
//
//  Issue #659: the scan that finds a target's declared queries, and the
//  registry source rendered from it.
//

import SwiftQLDeclaredQueryDiscovery
import XCTest


final class DeclaredQueryScannerTests: XCTestCase {

    private func scan(_ source: String) -> DeclaredQueryScan {
        DeclaredQueryScanner.scan(source: source, file: "/tmp/Queries.swift")
    }

    func testFindsContainersAndPeersOnTheirDatabaseTypes() {
        let result = scan("""
            import Foundation
            import SwiftQL

            @SQLQueries
            extension GRDBDatabase {
                private struct Query {
                    func people() -> [Person] { sqlResult { _ in fatalError() } }
                }
            }

            extension GRDBDatabase {
                @SQLQuery
                func person(id: String) -> Person? { sqlResult { _ in fatalError() } }

                @SQLQuery
                mutating func renamed() -> [Person] { sqlResult { _ in fatalError() } }
            }

            enum Outer {
                final class Database {
                    @SQLQuery
                    func rows() -> [Row] { sqlResult { _ in fatalError() } }
                }
            }
            """)

        XCTAssertEqual(result.declarations.map(\.databaseType), [
            "GRDBDatabase", "GRDBDatabase", "GRDBDatabase", "Outer.Database",
        ])
        XCTAssertEqual(result.declarations.map(\.form), [
            .container,
            .peer(functionName: "person", isMutating: false),
            .peer(functionName: "renamed", isMutating: true),
            .peer(functionName: "rows", isMutating: false),
        ])
        XCTAssertEqual(result.declarations.map(\.line), [4, 12, 15, 21])
        XCTAssertEqual(result.imports, ["Foundation", "SwiftQL"])
        XCTAssertEqual(result.skipped, [])
    }

    func testReportsDeclarationsTheRegistryCannotReach() {
        let result = scan("""
            @SQLQueries
            private extension GRDBDatabase {
                struct Query {}
            }

            extension GRDBDatabase {
                @SQLQuery
                fileprivate func hidden() -> [Person] { sqlResult { _ in fatalError() } }
            }

            extension Box where Value == Int {
                @SQLQuery
                func constrained() -> [Person] { sqlResult { _ in fatalError() } }
            }
            """)

        XCTAssertEqual(result.declarations, [])
        XCTAssertEqual(result.skipped.map(\.line), [1, 7, 12])
        XCTAssertTrue(result.skipped[0].reason.contains("private or fileprivate"))
        XCTAssertTrue(result.skipped[1].reason.contains("'hidden'"))
        XCTAssertTrue(result.skipped[2].reason.contains("generic or constrained"))
    }

    func testKeepsTheConditionADeclarationIsCompiledUnder() {
        let result = scan("""
            extension GRDBDatabase {
                #if DEBUG
                @SQLQuery
                func debugRows() -> [Person] { sqlResult { _ in fatalError() } }
                #elseif os(Linux)
                @SQLQuery
                func linuxRows() -> [Person] { sqlResult { _ in fatalError() } }
                #else
                @SQLQuery
                func otherRows() -> [Person] { sqlResult { _ in fatalError() } }
                #endif
            }
            """)

        XCTAssertEqual(result.declarations.map(\.condition), [
            "((DEBUG))",
            "(!(DEBUG) && (os(Linux)))",
            "(!(DEBUG) && !(os(Linux)))",
        ])
    }

    func testAFileWithoutEitherMacroIsNotParsed() {
        XCTAssertEqual(scan("struct Plain {}"), DeclaredQueryScan())
    }

    func testTheRegistryTypeNameIsAnIdentifierFromTheTargetName() {
        XCTAssertEqual(DeclaredQueryRegistryRenderer.typeName(forTarget: "TodoKit"), "TodoKitDeclaredQueries")
        XCTAssertEqual(DeclaredQueryRegistryRenderer.typeName(forTarget: "my-app_core"), "MyApp_coreDeclaredQueries")
        XCTAssertEqual(DeclaredQueryRegistryRenderer.typeName(forTarget: "2fa"), "_2faDeclaredQueries")
    }

    func testTheRegistryReadsEveryDeclarationFromAMatchingInstance() {
        let source = DeclaredQueryRegistryRenderer.render(
            targetName: "TodoKit",
            scan: scan("""
                import SwiftQL

                @SQLQueries
                extension GRDBDatabase {
                    struct Query {}
                }

                extension GRDBDatabase {
                    #if DEBUG
                    @SQLQuery
                    mutating func debugRows() -> [Person] { sqlResult { _ in fatalError() } }
                    #endif
                }
                """)
        )

        XCTAssertTrue(source.contains("public enum TodoKitDeclaredQueries {"), source)
        XCTAssertTrue(source.contains("public static func queries(for databases: [Any]) throws -> [XLDeclaredQuery] {"), source)
        XCTAssertTrue(source.contains("guard var database = element as? GRDBDatabase else {"), source)
        XCTAssertTrue(source.contains("            queries += database.declaredQueries\n"), source)
        XCTAssertTrue(source.contains("            #if ((DEBUG))\n            queries.append(database.debugRowsDeclaredQuery())\n            #endif\n"), source)
        XCTAssertTrue(source.contains("throw XLDeclaredQueryError.missingDatabaseInstance(typeName: \"GRDBDatabase\")"), source)
        XCTAssertTrue(source.contains("import SwiftQL\n"), source)
    }

    func testAnEmptyRegistryReturnsNoQueries() {
        let source = DeclaredQueryRegistryRenderer.render(targetName: "Empty", scan: DeclaredQueryScan())

        XCTAssertTrue(source.contains("public static let databaseTypeNames: [String] = []"), source)
        XCTAssertTrue(source.contains("    public static func queries(for databases: [Any]) throws -> [XLDeclaredQuery] {\n        []\n    }"), source)
    }
}
