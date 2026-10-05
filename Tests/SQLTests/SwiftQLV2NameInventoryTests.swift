//
//  SwiftQLV2NameInventoryTests.swift
//  SwiftQL
//
//  Keeps the issue #702 collision fixture complete. `SwiftQLV2Names` lists
//  the proposed v2 spelling of every public `XL` type, and
//  `SwiftQLV2NameCollisionFixture` names each one unqualified beside GRDB,
//  Foundation, and SwiftUI. Neither file can notice a type it does not
//  mention, so this test compares both with the public types the sources
//  declare. It also checks what the fixture cannot: a proposed name the Swift
//  standard library declares is shadowed rather than ambiguous, so it builds.
//

import Foundation
import SwiftQLTestSupport
import XCTest


final class SwiftQLV2NameInventoryTests: XCTestCase {

    /// Read once for every test in the class: each scan reads every source
    /// file in SwiftQL and SwiftQLCore.
    private static let declared = Result { try publicTopLevelTypeNames() }
    private static let inventory = Result { try proposedNameInventory() }

    func testEveryPublicPrefixedTypeHasExactlyOneProposedV2Entry() throws {
        let declared = try Self.declared.get()
        let inventory = try Self.inventory.get()
        let prefixed = Set(declared.filter { $0.hasPrefix("XL") })

        var accounted: [String] = []
        accounted += inventory.aliases.map(\.oldName)
        accounted += inventory.unresolved.map(\.oldName)
        accounted += inventory.deprecated.filter { $0.hasPrefix("XL") }

        let counts = Dictionary(accounted.map { ($0, 1) }, uniquingKeysWith: +)
        XCTAssertEqual(
            counts.filter { $0.value > 1 }.keys.sorted(),
            [],
            "A type is listed more than once in ProposedV2Names.swift."
        )
        XCTAssertEqual(
            prefixed.subtracting(counts.keys).sorted(),
            [],
            "Give each new public XL type a proposed v2 alias in ProposedV2Names.swift, "
                + "or list it there as an unresolved collision."
        )
        XCTAssertEqual(
            Set(counts.keys).union(inventory.deprecated).subtracting(declared).sorted(),
            [],
            "ProposedV2Names.swift lists a type the sources no longer declare."
        )
        XCTAssertEqual(
            Dictionary(inventory.aliases.map { ($0.newName, 1) }, uniquingKeysWith: +)
                .filter { $0.value > 1 }.keys.sorted(),
            [],
            "Two types are proposed under the same v2 name."
        )
    }

    func testCollisionFixtureNamesEveryProposedAndUnprefixedType() throws {
        let declared = try Self.declared.get()
        let inventory = try Self.inventory.get()
        let fixture = try String(
            contentsOf: try swiftQLRepositoryRootURL().appendingPathComponent(
                "Tests/SwiftQLV2NameCollisionFixture/V2NameCollisionFixture.swift"
            ),
            encoding: .utf8
        )
        let named = Set(try Self.matches(
            of: #"^    typealias Check_([A-Za-z_][A-Za-z0-9_]*) = ([A-Za-z_][A-Za-z0-9_]*)$"#,
            in: fixture
        ).map { groups -> String in
            XCTAssertEqual(groups[0], groups[1], "A fixture alias must name the type it is named after.")
            return groups[1]
        })

        // The `Check_` members cannot shadow a type they name only while no
        // type name has an underscore.
        XCTAssertEqual(
            Set(inventory.aliases.map(\.newName)).union(declared).filter { $0.contains("_") }.sorted(),
            [],
            "A type name with an underscore could collide with a fixture member."
        )

        let unprefixed = Set(declared.filter { !$0.hasPrefix("XL") })
            .subtracting(inventory.deprecated)
        XCTAssertEqual(
            Set(inventory.aliases.map(\.newName)).union(unprefixed).subtracting(named).sorted(),
            [],
            "Name every proposed and unprefixed type in V2NameCollisionFixture.swift."
        )
        XCTAssertEqual(
            named.intersection(inventory.unresolved.map(\.newName)).sorted(),
            [],
            "An unresolved collision cannot be named in the fixture until it has a v2 name."
        )
    }

    /// A type from any other module shadows a standard library type of the
    /// same name instead of making it ambiguous, so the fixture builds even
    /// when a proposed name is `Result`. Ask the compiler which names the
    /// standard library declares: every `Swift.<name>` must fail to resolve.
    func testNoProposedOrUnprefixedNameIsAStandardLibraryType() throws {
        let declared = try Self.declared.get()
        let inventory = try Self.inventory.get()
        let names = Set(inventory.aliases.map(\.newName))
            .union(declared.filter { !$0.hasPrefix("XL") })
            .sorted()

        for module in ["Swift", "_Concurrency", "_StringProcessing"] {
            let resolved = try namesResolving(in: module, names)
            XCTAssertEqual(
                resolved,
                [],
                "\(module) already declares these names. List each one as an unresolved "
                    + "collision in ProposedV2Names.swift rather than proposing it."
            )
        }
    }

    // MARK: - Helpers

    private struct ProposedNameInventory {
        var aliases: [(newName: String, oldName: String)]
        var unresolved: [(oldName: String, newName: String)]
        var deprecated: [String]
    }

    private static func proposedNameInventory() throws -> ProposedNameInventory {
        let source = try String(
            contentsOf: try swiftQLRepositoryRootURL().appendingPathComponent(
                "Tests/SwiftQLV2Names/ProposedV2Names.swift"
            ),
            encoding: .utf8
        )
        let aliases = try matches(
            of: #"^public typealias ([A-Za-z_][A-Za-z0-9_]*) = (?:SwiftQL|SwiftQLCore)\.(XL[A-Za-z0-9_]*)$"#,
            in: source
        ).map { (newName: $0[0], oldName: $0[1]) }
        let unresolved = try matches(
            of: #"^//  unresolved: (XL[A-Za-z0-9_]*) -> ([A-Za-z_][A-Za-z0-9_]*) \("#,
            in: source
        ).map { (oldName: $0[0], newName: $0[1]) }
        let deprecated = try matches(
            of: #"^//  deprecated: ([A-Za-z_][A-Za-z0-9_]*) "#,
            in: source
        ).map { $0[0] }
        guard !aliases.isEmpty else {
            throw InventoryError.formatChanged("ProposedV2Names.swift has no aliases.")
        }
        return ProposedNameInventory(
            aliases: aliases,
            unresolved: unresolved,
            deprecated: deprecated
        )
    }

    /// The public types SwiftQL and SwiftQLCore declare at file scope.
    ///
    /// A declaration counts when it sits outside every brace, whatever its
    /// indentation, so one inside an `#if` block is found and a nested type
    /// is not.
    private static func publicTopLevelTypeNames() throws -> [String] {
        let root = try swiftQLRepositoryRootURL()
        let declaration = try NSRegularExpression(pattern:
            #"^(?:@[A-Za-z_][A-Za-z0-9_.]*(?:\([^()]*\))?\s*)*"#
            + #"(?:public|open)\s+(?:(?:final|indirect|nonisolated)\s+)*"#
            + #"(?:struct|class|enum|protocol|typealias|actor)\s+([A-Za-z_][A-Za-z0-9_]*)"#
        )
        var names: Set<String> = []
        for module in ["SwiftQLCore", "SwiftQL"] {
            let directory = root.appendingPathComponent("Sources/\(module)")
            guard let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: nil
            ) else {
                throw InventoryError.formatChanged("Cannot list \(directory.path).")
            }
            for case let url as URL in enumerator where url.pathExtension == "swift" {
                let source = try String(contentsOf: url, encoding: .utf8)
                for statement in fileScopeStatements(in: source) {
                    let range = NSRange(statement.startIndex ..< statement.endIndex, in: statement)
                    if let match = declaration.firstMatch(in: statement, range: range),
                       let name = Range(match.range(at: 1), in: statement) {
                        names.insert(String(statement[name]))
                    }
                }
            }
        }
        guard names.contains("XLExpression"), names.contains("GRDBDatabase") else {
            throw InventoryError.formatChanged("The type scan missed known public types.")
        }
        return names.sorted()
    }

    /// The statements of `source` that sit outside every brace, one per
    /// line, with comments removed and every string literal emptied, so a
    /// brace or parenthesis inside one is not counted. Lines that hold only
    /// attributes join the line after them, so a declaration keeps the
    /// attributes written above it.
    private static func fileScopeStatements(in source: String) -> [String] {
        let attributesOnly = try! NSRegularExpression(
            pattern: #"^(?:@[A-Za-z_][A-Za-z0-9_.]*(?:\([^()]*\))?\s*)+$"#
        )
        var statements: [String] = []
        var current = ""
        var depth = 0
        var characters = Array(source)[...]

        func endLine() {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            let range = NSRange(trimmed.startIndex ..< trimmed.endIndex, in: trimmed)
            if attributesOnly.firstMatch(in: trimmed, range: range) != nil {
                current = trimmed + " "
                return
            }
            if !trimmed.isEmpty {
                statements.append(trimmed)
            }
            current = ""
        }

        /// Skips a string literal whose opening delimiter has been consumed,
        /// up to and including `terminator`.
        func skipString(until terminator: String, multiline: Bool) {
            while !characters.isEmpty, !characters.starts(with: terminator) {
                if !multiline, characters.first == "\n" { return }
                characters = characters.dropFirst(characters.first == "\\" ? 2 : 1)
            }
            characters = characters.dropFirst(terminator.count)
        }

        while let character = characters.first {
            if characters.starts(with: "//") {
                characters = characters.drop(while: { $0 != "\n" })
            } else if characters.starts(with: "/*") {
                characters = characters.dropFirst(2)
                var nesting = 1
                while nesting > 0, !characters.isEmpty {
                    if characters.starts(with: "/*") {
                        nesting += 1
                        characters = characters.dropFirst(2)
                    } else if characters.starts(with: "*/") {
                        nesting -= 1
                        characters = characters.dropFirst(2)
                    } else {
                        characters = characters.dropFirst()
                    }
                }
            } else if characters.starts(with: "\"\"\"") {
                characters = characters.dropFirst(3)
                skipString(until: "\"\"\"", multiline: true)
                if depth == 0 { current += "\"\"" }
            } else if character == "\"" {
                characters = characters.dropFirst()
                skipString(until: "\"", multiline: false)
                if depth == 0 { current += "\"\"" }
            } else {
                characters = characters.dropFirst()
                switch character {
                case "{":
                    if depth == 0 { endLine() }
                    depth += 1
                case "}":
                    depth = max(0, depth - 1)
                case "\n" where depth == 0:
                    endLine()
                default:
                    if depth == 0 { current.append(character) }
                }
            }
        }
        endLine()
        return statements
    }

    /// The names in `names` that `module.<name>` resolves, found by type
    /// checking one alias per name: every line that does not fail names a
    /// type the module declares.
    private func namesResolving(in module: String, _ names: [String]) throws -> [String] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Probe.swift")
        let source = names.enumerated()
            .map { "typealias Probe\($0.offset) = \(module).\($0.element)\n" }
            .joined()
        try source.write(to: file, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swiftc", "-typecheck", file.path]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let diagnostics = String(decoding: data, as: UTF8.self)

        let failedLines = Set(try Self.matches(
            of: #"Probe\.swift:([0-9]+):[0-9]+: error:"#,
            in: diagnostics
        ).compactMap { Int($0[0]) })
        // If every line resolved, the compiler did not run at all.
        guard !failedLines.isEmpty else {
            throw InventoryError.formatChanged("swiftc reported no errors:\n\(diagnostics)")
        }
        return names.enumerated()
            .filter { !failedLines.contains($0.offset + 1) }
            .map(\.element)
    }

    private static func matches(of pattern: String, in text: String) throws -> [[String]] {
        let expression = try NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        return expression.matches(in: text, range: range).map { match in
            (1 ..< match.numberOfRanges).map { index in
                Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
            }
        }
    }

    private enum InventoryError: Error, CustomStringConvertible {
        case formatChanged(String)

        var description: String {
            switch self {
            case .formatChanged(let message):
                return message
            }
        }
    }
}
