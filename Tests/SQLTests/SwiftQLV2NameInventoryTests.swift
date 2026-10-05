//
//  SwiftQLV2NameInventoryTests.swift
//  SwiftQL
//
//  Keeps the issue #702 collision fixture complete. `SwiftQLV2Names` lists
//  the proposed v2 spelling of every public `XL` type, and
//  `SwiftQLV2NameCollisionFixture` names each one unqualified beside GRDB,
//  Foundation, and SwiftUI. Neither file can notice a type it does not
//  mention, so this test compares both with the public types the sources
//  declare.
//

import Foundation
import SwiftQLTestSupport
import XCTest


final class SwiftQLV2NameInventoryTests: XCTestCase {

    func testEveryPublicPrefixedTypeHasExactlyOneProposedV2Entry() throws {
        let declared = try publicTopLevelTypeNames()
        let prefixed = Set(declared.filter { $0.hasPrefix("XL") })
        let inventory = try proposedNameInventory()

        var accounted: [String] = []
        accounted += inventory.aliases.map(\.oldName)
        accounted += inventory.unresolved
        accounted += inventory.deprecated

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
            Set(counts.keys).subtracting(prefixed).sorted(),
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
        let declared = try publicTopLevelTypeNames()
        let inventory = try proposedNameInventory()
        let fixture = try String(
            contentsOf: try swiftQLRepositoryRootURL().appendingPathComponent(
                "Tests/SwiftQLV2NameCollisionFixture/V2NameCollisionFixture.swift"
            ),
            encoding: .utf8
        )
        let named = Set(try matches(
            of: #"^    typealias ([A-Za-z_][A-Za-z0-9_]*)Name = ([A-Za-z_][A-Za-z0-9_]*)$"#,
            in: fixture
        ).map { groups -> String in
            XCTAssertEqual(groups[0], groups[1], "A fixture alias must name the type it is named after.")
            return groups[1]
        })

        // Deprecated unprefixed types, such as `JoinKind`, are not carried
        // into v2, so the fixture does not name them.
        let unprefixed = Set(declared.filter { !$0.hasPrefix("XL") })
            .subtracting(["JoinKind"])
        XCTAssertEqual(
            Set(inventory.aliases.map(\.newName)).union(unprefixed).subtracting(named).sorted(),
            [],
            "Name every proposed and unprefixed type in V2NameCollisionFixture.swift."
        )
        XCTAssertEqual(
            named.intersection(inventory.unresolvedNewNames).sorted(),
            [],
            "An unresolved collision cannot be named in the fixture until it has a v2 name."
        )
    }

    // MARK: - Helpers

    private struct ProposedNameInventory {
        var aliases: [(newName: String, oldName: String)]
        var unresolved: [String]
        var unresolvedNewNames: Set<String>
        var deprecated: [String]
    }

    private func proposedNameInventory() throws -> ProposedNameInventory {
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
        )
        let deprecated = try matches(
            of: #"^//  deprecated: (XL[A-Za-z0-9_]*) "#,
            in: source
        )
        XCTAssertFalse(aliases.isEmpty, "ProposedV2Names.swift has no aliases; its format changed.")
        return ProposedNameInventory(
            aliases: aliases,
            unresolved: unresolved.map { $0[0] },
            unresolvedNewNames: Set(unresolved.map { $0[1] }),
            deprecated: deprecated.map { $0[0] }
        )
    }

    /// The public types SwiftQL and SwiftQLCore declare at file scope. A
    /// nested type is indented, so anchoring the match at the start of a line
    /// leaves it out.
    private func publicTopLevelTypeNames() throws -> [String] {
        let root = try swiftQLRepositoryRootURL()
        var names: Set<String> = []
        for module in ["SwiftQLCore", "SwiftQL"] {
            let directory = root.appendingPathComponent("Sources/\(module)")
            let enumerator = try XCTUnwrap(FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: nil
            ))
            for case let url as URL in enumerator where url.pathExtension == "swift" {
                let source = try String(contentsOf: url, encoding: .utf8)
                for groups in try matches(
                    of: #"^(?:@[A-Za-z_]+(?:\([^)\n]*\))?[ \t]+)*(?:public|open)[ \t]+(?:final[ \t]+)?(?:struct|class|enum|protocol|typealias|actor)[ \t]+([A-Za-z_][A-Za-z0-9_]*)"#,
                    in: source
                ) {
                    names.insert(groups[0])
                }
            }
        }
        XCTAssertTrue(names.contains("XLExpression"), "The type scan found nothing; its pattern is wrong.")
        return names.sorted()
    }

    private func matches(of pattern: String, in text: String) throws -> [[String]] {
        let expression = try NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        return expression.matches(in: text, range: range).map { match in
            (1 ..< match.numberOfRanges).map { index in
                Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
            }
        }
    }
}
