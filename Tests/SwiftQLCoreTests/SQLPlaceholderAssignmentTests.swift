import XCTest
@testable import SwiftQLCore


final class SQLPlaceholderAssignmentTests: XCTestCase {

    // MARK: - SQLite's rule is unchanged

    func testSQLiteNumbersNamedKeysAfterTheLargestExplicitIndex() {
        var assigner = XLitePlaceholderAssigner()

        // A named key takes the next physical index and is spelled by name.
        let first = assigner.assignment(for: .named("alpha"))
        XCTAssertEqual(first.placeholder, .named("alpha"))
        XCTAssertEqual(first.physicalIndex, 1)

        // An indexed key takes NNN directly, which is SQLite's rule and the
        // reason a named key can alias an explicit one.
        let explicit = assigner.assignment(for: .indexed(4))
        XCTAssertEqual(explicit.placeholder, .indexed(4))
        XCTAssertEqual(explicit.physicalIndex, 5)

        let second = assigner.assignment(for: .named("beta"))
        XCTAssertEqual(second.physicalIndex, 6)
    }

    func testAnAssignerReturnsTheSameAssignmentForARepeatedKey() {
        var assigner = XLitePlaceholderAssigner()
        let first = assigner.assignment(for: .named("alpha"))
        let again = assigner.assignment(for: .named("alpha"))
        XCTAssertEqual(first, again)

        // The repeat must not consume a physical index.
        XCTAssertEqual(assigner.assignment(for: .named("beta")).physicalIndex, 2)
    }

    // MARK: - A positional dialect renumbers a named key

    func testPositionalAssignerSpellsEveryKeyByPosition() {
        var assigner = XLPositionalPlaceholderAssigner()

        let first = assigner.assignment(for: .named("alpha"))
        XCTAssertEqual(first.placeholder, .indexed(0))
        XCTAssertEqual(first.physicalIndex, 1)

        let second = assigner.assignment(for: .named("beta"))
        XCTAssertEqual(second.placeholder, .indexed(1))
        XCTAssertEqual(second.physicalIndex, 2)

        // A repeated name is one parameter, bound once, so it keeps its
        // position rather than taking a new one.
        XCTAssertEqual(assigner.assignment(for: .named("alpha")), first)
        XCTAssertEqual(assigner.assignment(for: .named("gamma")).physicalIndex, 3)
    }

    func testPositionalAssignerRenumbersAnExplicitIndexByEncounterOrder() {
        var assigner = XLPositionalPlaceholderAssigner()

        // PostgreSQL numbers by position in the statement, so an explicit
        // SwiftQL index does not survive as a wire position.
        XCTAssertEqual(
            assigner.assignment(for: .indexed(7)).placeholder,
            .indexed(0)
        )
        XCTAssertEqual(
            assigner.assignment(for: .indexed(3)).placeholder,
            .indexed(1)
        )
    }

    // MARK: - Occurrences

    func testALayoutRecordsEveryOccurrenceAndOneSlotPerKey() throws {
        let slot = Self.slot(index: 0, key: .named("alpha"))

        // The same named parameter rendered twice.
        let layout = try XLParameterLayout(
            slots: [slot],
            occurrences: [
                XLParameterOccurrence(
                    index: XLLogicalParameterIndex(0),
                    key: .named("alpha"),
                    placeholder: .named("alpha"),
                    physicalIndex: 1
                ),
                XLParameterOccurrence(
                    index: XLLogicalParameterIndex(0),
                    key: .named("alpha"),
                    placeholder: .named("alpha"),
                    physicalIndex: 1
                ),
            ]
        )

        XCTAssertEqual(layout.slots.count, 1)
        XCTAssertEqual(layout.occurrences.count, 2)
        XCTAssertEqual(layout.occurrences(of: XLLogicalParameterIndex(0)).count, 2)
        XCTAssertEqual(layout.placeholder(for: .named("alpha")), .named("alpha"))
    }

    func testALayoutWithoutRecordedOccurrencesReportsNoPlaceholder() throws {
        let layout = try XLParameterLayout(slots: [Self.slot(index: 0, key: .named("alpha"))])
        XCTAssertTrue(layout.occurrences.isEmpty)

        // Nil means "not recorded", so a reader falls back rather than
        // assuming the statement has no parameters.
        XCTAssertNil(layout.placeholder(for: .named("alpha")))
    }

    // MARK: - The capability gate reads the placeholder

    func testAPositionalDialectBuildsADescriptorForANamedParameter() throws {
        let slot = Self.slot(index: 0, key: .named("alpha"))

        // The dialect has no named-binding capability at all. Before the
        // placeholder was separated from the key this could not build.
        let statement = XLStaticStatementDefinition(
            sql: "SELECT $1",
            dialectRequirement: XLDialectRequirement(
                identity: XLDialectIdentifier(rawValue: "tests.positional"),
                capabilities: [.indexedBindings]
            ),
            entities: ["entity"],
            parameterLayout: try XLParameterLayout(
                slots: [slot],
                occurrences: [
                    XLParameterOccurrence(
                        index: XLLogicalParameterIndex(0),
                        key: .named("alpha"),
                        placeholder: .indexed(0),
                        physicalIndex: 1
                    ),
                ]
            )
        )

        let descriptor = try Self.descriptor(statement: statement, slot: slot)
        XCTAssertEqual(descriptor.parameters.count, 1)

        // The logical key is untouched: Swift code still binds by name.
        XCTAssertEqual(descriptor.parameters[0].slot.key, .named("alpha"))
    }

    func testANamedPlaceholderStillRequiresTheNamedCapability() throws {
        let slot = Self.slot(index: 0, key: .named("alpha"))
        let statement = XLStaticStatementDefinition(
            sql: "SELECT :alpha",
            dialectRequirement: XLDialectRequirement(
                identity: XLDialectIdentifier(rawValue: "tests.positional"),
                capabilities: [.indexedBindings]
            ),
            entities: ["entity"],
            parameterLayout: try XLParameterLayout(
                slots: [slot],
                occurrences: [
                    XLParameterOccurrence(
                        index: XLLogicalParameterIndex(0),
                        key: .named("alpha"),
                        placeholder: .named("alpha"),
                        physicalIndex: 1
                    ),
                ]
            )
        )

        XCTAssertThrowsError(try Self.descriptor(statement: statement, slot: slot)) { error in
            guard case .parameterCapabilityMissing(_, let capability)? =
                error as? XLStaticQueryError else {
                return XCTFail("Expected a missing-capability error, got \(error)")
            }
            XCTAssertEqual(capability, .namedBindings)
        }
    }

    func testALayoutWithoutOccurrencesStillGatesOnTheKey() throws {
        // A statement rendered before occurrences existed records none. Its
        // named key must still demand the named capability.
        let slot = Self.slot(index: 0, key: .named("alpha"))
        let statement = XLStaticStatementDefinition(
            sql: "SELECT :alpha",
            dialectRequirement: XLDialectRequirement(
                identity: XLDialectIdentifier(rawValue: "tests.legacy"),
                capabilities: [.indexedBindings]
            ),
            entities: ["entity"],
            parameterLayout: try XLParameterLayout(slots: [slot])
        )

        XCTAssertThrowsError(try Self.descriptor(statement: statement, slot: slot))
    }

    // MARK: - The frozen identity is unaffected

    func testRecordingOccurrencesDoesNotChangeTheV1DescriptorIdentity() throws {
        let slot = Self.slot(index: 0, key: .named("alpha"))

        func statement(occurrences: [XLParameterOccurrence]) throws -> XLStaticStatementDefinition {
            XLStaticStatementDefinition(
                sql: "SELECT :alpha",
                dialectRequirement: XLDialectRequirement(
                    identity: XLSQLiteDialect.identity,
                    capabilities: [.namedBindings, .indexedBindings]
                ),
                entities: ["entity"],
                parameterLayout: try XLParameterLayout(
                    slots: [slot],
                    occurrences: occurrences
                )
            )
        }

        // A statement rendered before occurrences existed.
        let frozen = try Self.descriptor(
            statement: try statement(occurrences: []),
            slot: slot
        )

        // The same statement rendered now, which records them.
        let current = try Self.descriptor(
            statement: try statement(
                occurrences: [
                    XLParameterOccurrence(
                        index: XLLogicalParameterIndex(0),
                        key: .named("alpha"),
                        placeholder: .named("alpha"),
                        physicalIndex: 1
                    ),
                ]
            ),
            slot: slot
        )

        // v1 identity is frozen. It encodes the logical key and never the
        // placeholder, so a statement keeps the identity it already had.
        XCTAssertEqual(frozen.identity.canonicalBytes, current.identity.canonicalBytes)
        XCTAssertEqual(frozen.identity, current.identity)
    }

    // MARK: - Fixtures

    private static func slot(
        index: Int,
        key: XLBindingKey
    ) -> XLParameterSlot {
        XLParameterSlot(
            index: XLLogicalParameterIndex(index),
            key: key,
            valueTypeIdentifier: XLValueTypeIdentifier(rawValue: "tests.value"),
            valueTypeName: "Tests.Value",
            nullability: .required,
            codecIdentity: nil,
            codingContext: XLValueCodingContext(
                site: .parameter,
                path: XLValueCodingPath("alpha")
            )
        )
    }

    private static func descriptor(
        statement: XLStaticStatementDefinition,
        slot: XLParameterSlot
    ) throws -> XLStaticQueryDescriptor {
        try XLStaticQueryDescriptor(
            definitionIdentity: try XLQueryDefinitionIdentity(
                path: ["tests", "placeholder"],
                version: 1
            ),
            statement: statement,
            parameters: [
                XLStaticQueryParameterMetadata(
                    identity: try XLQuerySlotIdentity(path: ["alpha"]),
                    slot: slot,
                    storageIdentifier: XLValueStorageIdentifier(rawValue: "text")
                ),
            ],
            results: try XLStaticQueryResultMetadata(slots: []),
            cardinality: .command
        )
    }
}
