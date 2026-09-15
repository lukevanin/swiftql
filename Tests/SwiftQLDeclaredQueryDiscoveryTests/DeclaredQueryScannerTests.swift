//
//  DeclaredQueryScannerTests.swift
//  SwiftQLDeclaredQueryDiscoveryTests
//
//  Issue #659: the scan that finds a target's declared queries, and the
//  registry source rendered from it.
//

import Foundation
import SwiftQLDeclaredQueryDiscovery
import XCTest


final class DeclaredQueryScannerTests: XCTestCase {

    private func scan(_ source: String) -> DeclaredQueryScan {
        DeclaredQueryScanner.scan(source: source, file: "/tmp/Queries.swift")
    }

    private func scan(files: [String: String]) -> DeclaredQueryScan {
        DeclaredQueryScanner.scan(files.keys.sorted().map { name in
            DeclaredQueryScanner.SourceFile(path: "/tmp/\(name)", source: files[name] ?? "")
        })
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
        XCTAssertEqual(result.imports, [
            DeclaredQueryImport(declaration: "import Foundation", condition: nil, module: "Foundation"),
            DeclaredQueryImport(declaration: "import SwiftQL", condition: nil, module: "SwiftQL"),
        ])
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
        XCTAssertEqual(
            result.skipped[0].reason,
            "The @SQLQueries extension on GRDBDatabase is private or fileprivate, which the generated registry cannot reach. It is not in the declared-query registry and is not validated. Give it internal or wider access to validate it. To leave it out without this warning, mark it '// swiftql-registry: ignore'."
        )
        XCTAssertTrue(result.skipped[1].reason.contains("'hidden'"))
        XCTAssertTrue(result.skipped[2].reason.contains("generic or constrained"))
        XCTAssertTrue(result.skipped[2].reason.contains(DeclaredQueryScanner.exclusionMarker))
    }

    func testAnExtensionOfAGenericTypeDeclaredInAnotherFileIsSkipped() {
        let result = scan(files: [
            "Types.swift": """
                struct Box<Value> {}

                enum Outer<Value> {
                    enum Inner {}
                }
                """,
            "Queries.swift": """
                extension Box {
                    @SQLQuery
                    func boxed() -> [Person] { sqlResult { _ in fatalError() } }
                }

                extension Outer.Inner {
                    @SQLQuery
                    func nested() -> [Person] { sqlResult { _ in fatalError() } }
                }
                """,
        ])

        XCTAssertEqual(result.declarations, [])
        XCTAssertEqual(result.skipped.count, 2)
        XCTAssertTrue(result.skipped.allSatisfy { $0.reason.contains("generic or constrained") })
    }

    func testTheExclusionMarkerLeavesADeclarationOutWithoutAWarning() {
        let result = scan("""
            extension Box where Value == Int {
                // swiftql-registry: ignore
                @SQLQuery
                func constrained() -> [Person] { sqlResult { _ in fatalError() } }
            }
            """)

        XCTAssertEqual(result.declarations, [])
        XCTAssertEqual(result.skipped, [])
        XCTAssertEqual(result.excluded.map(\.line), [3])
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
        XCTAssertEqual(result.declarations.map(\.typeCondition), [nil, nil, nil])
    }

    func testATypesConditionComesFromItsOwnDeclarationInAnyFile() {
        let result = scan(files: [
            "Types.swift": """
                #if DEBUG
                struct DebugDatabase {
                    struct Nested {}
                }
                #endif
                """,
            "Queries.swift": """
                extension DebugDatabase {
                    @SQLQuery
                    func rows() -> [Person] { sqlResult { _ in fatalError() } }
                }

                extension DebugDatabase.Nested {
                    @SQLQuery
                    func nestedRows() -> [Person] { sqlResult { _ in fatalError() } }
                }
                """,
        ])

        XCTAssertEqual(result.declarations.map(\.condition), [nil, nil])
        XCTAssertEqual(result.declarations.map(\.typeCondition), ["((DEBUG))", "((DEBUG))"])
    }

    func testImportsKeepTheirConditionsAndAttributes() {
        let result = scan("""
            #if canImport(UIKit)
            import UIKit
            #endif
            @testable import Store
            @preconcurrency import Dispatch

            extension GRDBDatabase {
                @SQLQuery
                func rows() -> [Person] { sqlResult { _ in fatalError() } }
            }
            """)

        XCTAssertEqual(result.imports, [
            DeclaredQueryImport(declaration: "import UIKit", condition: "((canImport(UIKit)))", module: "UIKit"),
            DeclaredQueryImport(declaration: "@testable import Store", condition: nil, module: "Store"),
            DeclaredQueryImport(declaration: "@preconcurrency import Dispatch", condition: nil, module: "Dispatch"),
        ])
    }

    func testAnExtensionOfAGenericTypealiasIsSkipped() {
        let result = scan(files: [
            "Types.swift": """
                struct Box<Value> {}
                typealias Boxed<Value> = Box<Value>
                typealias Database = GRDBDatabase
                """,
            "Queries.swift": """
                extension Boxed {
                    @SQLQuery
                    func boxed() -> [Person] { sqlResult { _ in fatalError() } }
                }

                extension Database {
                    @SQLQuery
                    func aliased() -> [Person] { sqlResult { _ in fatalError() } }
                }
                """,
        ])

        XCTAssertEqual(result.declarations.map(\.databaseType), ["Database"])
        XCTAssertEqual(result.skipped.count, 1)
        XCTAssertTrue(result.skipped[0].reason.contains("'boxed'"))
    }

    func testATypeNestedInAnExtensionOfAnUndeclaredTypeIsSkipped() {
        let result = scan(files: [
            "Types.swift": """
                extension Array {
                    struct Inner {}
                }
                """,
            "Queries.swift": """
                extension Array.Inner {
                    @SQLQuery
                    func nested() -> [Person] { sqlResult { _ in fatalError() } }
                }

                extension SwiftQL.GRDBDatabase {
                    @SQLQuery
                    func qualified() -> [Person] { sqlResult { _ in fatalError() } }
                }
                """,
        ])

        XCTAssertEqual(result.declarations.map(\.databaseType), ["SwiftQL.GRDBDatabase"])
        XCTAssertEqual(result.skipped.count, 1)
        XCTAssertTrue(result.skipped[0].reason.contains("does not declare"))
    }

    func testAnAttributeInsideAnIfInTheAttributeListIsReported() {
        let result = scan("""
            extension GRDBDatabase {
                #if DEBUG
                @SQLQuery
                #endif
                func maybeDeclared() -> [Person] { sqlResult { _ in fatalError() } }
            }
            """)

        XCTAssertEqual(result.declarations, [])
        XCTAssertEqual(result.skipped.count, 1)
        XCTAssertTrue(result.skipped[0].reason.contains("#if in the attribute list"))
    }

    func testTheRegistryKeepsOneImportPerModule() {
        let source = DeclaredQueryRegistryRenderer.render(
            targetName: "Fixture",
            scan: scan(files: [
                "A.swift": """
                    internal import SwiftQL

                    extension GRDBDatabase {
                        @SQLQuery
                        func a() -> [Person] { sqlResult { _ in fatalError() } }
                    }
                    """,
                "B.swift": """
                    import SwiftQL

                    extension GRDBDatabase {
                        @SQLQuery
                        func b() -> [Person] { sqlResult { _ in fatalError() } }
                    }
                    """,
            ])
        )
        let lines = source.components(separatedBy: "\n")

        XCTAssertEqual(lines.filter { $0.hasSuffix("import SwiftQL") }, ["internal import SwiftQL"], source)
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

    ///
    /// Type-checks a rendered registry with the Swift compiler, with warnings
    /// as errors, under both values of the conditions it uses. Stubs stand in
    /// for SwiftQL and for the members the macros generate.
    ///
    func testTheGeneratedRegistryCompilesUnderEveryConditionValue() throws {
        let scanned = scan(files: [
            "Types.swift": """
                #if DEBUG
                struct DebugDatabase {
                    @SQLQuery
                    func rows() -> [Person] { sqlResult { _ in fatalError() } }
                }
                #endif

                struct Box<Value> {}
                """,
            "Queries.swift": """
                import SwiftQL
                #if canImport(SwiftQLNoSuchModuleForRegistryTests)
                import SwiftQLNoSuchModuleForRegistryTests
                #endif

                @SQLQueries
                extension GRDBDatabase {
                    struct Query {}
                }

                extension Box {
                    @SQLQuery
                    func boxed() -> [Person] { sqlResult { _ in fatalError() } }
                }
                """,
        ])
        let registry = DeclaredQueryRegistryRenderer.render(targetName: "Fixture", scan: scanned)
            .replacingOccurrences(of: "import SwiftQL\n", with: "")
        let stubs = """

            public struct XLDeclaredQuery {}

            public enum XLDeclaredQueryError: Error {
                case missingDatabaseInstance(typeName: String)
            }

            struct GRDBDatabase {
                var declaredQueries: [XLDeclaredQuery] { [] }
            }

            #if DEBUG
            struct DebugDatabase {
                func rowsDeclaredQuery() -> XLDeclaredQuery { XLDeclaredQuery() }
            }
            #endif

            """
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeclaredQueryRegistry-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Registry.swift")
        try (registry + stubs).write(to: file, atomically: true, encoding: .utf8)

        for definesDebug in [false, true] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["swiftc", "-typecheck", "-warnings-as-errors"]
                + (definesDebug ? ["-D", "DEBUG"] : [])
                + [file.path]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = output
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            XCTAssertEqual(
                process.terminationStatus,
                0,
                "DEBUG=\(definesDebug):\n\(String(decoding: data, as: UTF8.self))\n\(registry)"
            )
        }
    }

    func testAnEmptyRegistryReturnsNoQueries() {
        let source = DeclaredQueryRegistryRenderer.render(targetName: "Empty", scan: DeclaredQueryScan())

        XCTAssertTrue(source.contains("names.reserveCapacity(0)"), source)
        XCTAssertTrue(source.contains("        return queries\n"), source)
    }
}
