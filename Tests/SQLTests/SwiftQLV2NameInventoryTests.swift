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
    /// standard library declares: every `Swift.<name>` must fail with "no
    /// type named". Spawning the compiler needs `Process`, which iOS lacks.
    func testNoProposedOrUnprefixedNameIsAStandardLibraryType() throws {
        #if os(macOS) || os(Linux)
        let declared = try Self.declared.get()
        let inventory = try Self.inventory.get()
        let names = Set(inventory.aliases.map(\.newName))
            .union(declared.filter { !$0.hasPrefix("XL") })
            .sorted()

        let declaredByStandardLibrary = try Self.namesNotMissing(
            from: ["Swift", "_Concurrency", "_StringProcessing"],
            names
        )
        XCTAssertEqual(
            declaredByStandardLibrary,
            [],
            "The standard library already declares these. List each one as an unresolved "
                + "collision in ProposedV2Names.swift rather than proposing it."
        )
        #else
        throw XCTSkip("Spawning the compiler needs Process.")
        #endif
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
                for statement in try fileScopeStatements(in: source, file: url.lastPathComponent) {
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

    /// A line that holds only attributes, such as `@available(...)`.
    private static let attributesOnly = try! NSRegularExpression(
        pattern: #"^(?:@[A-Za-z_][A-Za-z0-9_.]*(?:\([^()]*\))?\s*)+$"#
    )

    /// The statements of `source` that sit outside every brace, one per
    /// line, with comments removed and every string literal emptied, raw
    /// ones included, so a brace or parenthesis inside one is not counted.
    /// Lines that hold only attributes join the line after them, so a
    /// declaration keeps the attributes written above it.
    ///
    /// A file whose braces do not balance means the scan lost track of a
    /// literal, such as a regex literal, which it does not parse. It throws
    /// rather than report types from the wrong depth.
    private static func fileScopeStatements(in source: String, file: String) throws -> [String] {
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
        /// up to and including `terminator`. A raw string has no escapes.
        func skipString(until terminator: String, multiline: Bool, raw: Bool) {
            while !characters.isEmpty, !characters.starts(with: terminator) {
                if !multiline, characters.first == "\n" { return }
                characters = characters.dropFirst(!raw && characters.first == "\\" ? 2 : 1)
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
            } else if character == "#",
                      characters.drop(while: { $0 == "#" }).first == "\"" {
                // A raw string: its terminator repeats the opening hashes.
                let hashes = String(characters.prefix(while: { $0 == "#" }))
                characters = characters.dropFirst(hashes.count)
                let multiline = characters.starts(with: "\"\"\"")
                let quote = multiline ? "\"\"\"" : "\""
                characters = characters.dropFirst(quote.count)
                skipString(until: quote + hashes, multiline: multiline, raw: true)
                if depth == 0 { current += "\"\"" }
            } else if characters.starts(with: "\"\"\"") {
                characters = characters.dropFirst(3)
                skipString(until: "\"\"\"", multiline: true, raw: false)
                if depth == 0 { current += "\"\"" }
            } else if character == "\"" {
                characters = characters.dropFirst()
                skipString(until: "\"", multiline: false, raw: false)
                if depth == 0 { current += "\"\"" }
            } else {
                characters = characters.dropFirst()
                switch character {
                case "{":
                    if depth == 0 { endLine() }
                    depth += 1
                case "}":
                    depth -= 1
                    guard depth >= 0 else {
                        throw InventoryError.formatChanged("\(file): a closing brace has no opening one.")
                    }
                case "\n" where depth == 0:
                    endLine()
                default:
                    if depth == 0 { current.append(character) }
                }
            }
        }
        endLine()
        guard depth == 0 else {
            throw InventoryError.formatChanged("\(file): \(depth) braces are never closed.")
        }
        return statements
    }

    #if os(macOS) || os(Linux)
    /// The `module.name` pairs the compiler does not report missing, found by
    /// type checking one alias per pair in one compiler run. Only a "no type
    /// named" error counts as missing: an availability error, for example,
    /// means the module does declare the name.
    private static func namesNotMissing(
        from modules: [String],
        _ names: [String]
    ) throws -> [String] {
        let pairs = modules.flatMap { module in names.map { "\(module).\($0)" } }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Probe.swift")
        let source = pairs.enumerated()
            .map { "typealias Probe\($0.offset) = \($0.element)\n" }
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

        let missingLines = Set(try matches(
            of: #"Probe\.swift:([0-9]+):[0-9]+: error: no type named '[^']*' in module '[^']*'$"#,
            in: diagnostics
        ).compactMap { Int($0[0]) })
        // If nothing was missing, the compiler did not run as expected.
        guard !missingLines.isEmpty else {
            throw InventoryError.formatChanged("swiftc reported no missing types:\n\(diagnostics)")
        }
        return pairs.enumerated()
            .filter { !missingLines.contains($0.offset + 1) }
            .map(\.element)
    }
    #endif

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
