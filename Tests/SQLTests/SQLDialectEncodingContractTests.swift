import XCTest
@testable import SwiftQL


private struct DialectCapabilityProbe: XLEncodable {

    let named: Bool

    let indexed: Bool

    func makeSQL(context: inout XLBuilder) {
        if named {
            context.namedBinding("name")
        }
        if indexed {
            context.indexedBinding(2)
        }
        if !named && !indexed {
            context.integer(1)
        }
    }
}


private struct NestedParameterLayoutProbe: XLEncodable {

    func makeSQL(context: inout XLBuilder) {
        context.namedBinding("name")
        context.block(
            beginsWith: "(",
            endsWith: ")",
            separator: .elided
        ) { nested in
            nested.indexedBinding(2)
            nested.namedBinding("name")
        }
    }
}


private struct LegacyReferenceMetadataProbe: XLEncodable {

    let required = XLNamedBindingReference<Int>(name: "required")

    let nullable = XLNamedBindingReference<Optional<String>>(name: "nullable")

    func makeSQL(context: inout XLBuilder) {
        required.makeSQL(context: &context)
        nullable.makeSQL(context: &context)
        required.makeSQL(context: &context)
    }
}


private struct TypedParameterLayoutProbe: XLEncodable {

    let slots: [XLParameterSlot]

    func makeSQL(context: inout XLBuilder) {
        for slot in slots {
            context.parameter(slot)
        }
    }
}


private struct ParameterDeclarationProbe: XLEncodable {

    let declarations: [XLParameterDeclaration]

    func makeSQL(context: inout XLBuilder) {
        for declaration in declarations {
            context.parameter(declaration)
        }
    }
}


private struct MixedLegacyAndTypedParameterProbe: XLEncodable {

    let legacyFirst: Bool

    let reference = XLNamedBindingReference<Int>(name: "value")

    func makeSQL(context: inout XLBuilder) {
        if legacyFirst {
            context.namedBinding("value")
            reference.makeSQL(context: &context)
        }
        else {
            reference.makeSQL(context: &context)
            context.namedBinding("value")
        }
    }
}


private struct SemanticSeparatorProbe: XLEncodable {

    let separator: XLSeparator

    func makeSQL(context: inout XLBuilder) {
        context.list(separator: separator) { list in
            list.listItem { $0.integer(1) }
            list.listItem { $0.integer(2) }
        }
    }
}


private struct LiteralSeparatorProbe: XLEncodable {

    func makeSQL(context: inout XLBuilder) {
        context.list(separator: " | ") { list in
            list.listItem { $0.integer(1) }
            list.listItem { $0.integer(2) }
        }
    }
}


final class SQLDialectEncodingContractTests: XCTestCase {

    func testSemanticSeparatorsPreserveEstablishedSQLiteSpellings() {
        func requireSendable<T: Sendable>(_ value: T) {}

        requireSendable(XLSeparator.list)
        XCTAssertEqual(XLSeparator.list, .comma)
        XCTAssertEqual(XLSeparator.list.rawValue, ", ")
        XCTAssertEqual(XLSeparator.tuple, .space)
        XCTAssertEqual(XLSeparator.tuple.rawValue, " ")
        XCTAssertEqual(XLSeparator(rawValue: ", "), .comma)

        let encoder = XLiteEncoder(formatter: XLiteFormatter())
        XCTAssertEqual(
            encoder.makeSQL(SemanticSeparatorProbe(separator: .list)).sql,
            "1, 2"
        )
        XCTAssertEqual(
            encoder.makeSQL(SemanticSeparatorProbe(separator: .tuple)).sql,
            "1 2"
        )
        XCTAssertEqual(
            encoder.makeSQL(LiteralSeparatorProbe()).sql,
            "1 | 2"
        )
    }

    private func parameterSlot(
        index: Int,
        key: XLBindingKey,
        valueTypeIdentifier: String = "example.user-id",
        valueTypeName: String = "Example.UserID",
        nullability: XLParameterNullability = .required,
        codecIdentity: XLValueCodecIdentity? = nil
    ) -> XLParameterSlot {
        XLParameterSlot(
            index: XLLogicalParameterIndex(index),
            key: key,
            valueTypeIdentifier: XLValueTypeIdentifier(
                rawValue: valueTypeIdentifier
            ),
            valueTypeName: valueTypeName,
            nullability: nullability,
            codecIdentity: codecIdentity,
            codingContext: XLValueCodingContext(
                site: .parameter,
                path: XLValueCodingPath("probe")
            )
        )
    }

    private func parameterDeclaration(
        key: XLBindingKey,
        valueTypeIdentifier: String = "example.user-id",
        valueTypeName: String = "Example.UserID",
        nullability: XLParameterNullability = .required,
        codecIdentity: XLValueCodecIdentity? = nil
    ) -> XLParameterDeclaration {
        XLParameterDeclaration(
            key: key,
            valueTypeIdentifier: XLValueTypeIdentifier(
                rawValue: valueTypeIdentifier
            ),
            valueTypeName: valueTypeName,
            nullability: nullability,
            codecIdentity: codecIdentity,
            codingContext: XLValueCodingContext(
                site: .parameter,
                path: XLValueCodingPath("declaration-probe")
            )
        )
    }

    func testBuilderDefaultBetweenComposesGenericBinaryOperators() {
        var builder: XLBuilder = XLiteBuilder(formatter: XLiteFormatter())

        builder.between(
            term: { context in
                context.name("value")
                context.entity("term")
            },
            minimum: { context in
                context.integer(1)
                context.entity("minimum")
            },
            maximum: { context in
                context.integer(3)
                context.entity("maximum")
            }
        )

        XCTAssertEqual(builder.build(), "\"value\" BETWEEN 1 AND 3")
        XCTAssertEqual(
            builder.entities(),
            ["term", "minimum", "maximum"]
        )
    }

    func testEncoderDerivesPlaceholderCapabilitiesFromRenderedSQL() {
        let encoder = XLiteEncoder(
            dialect: XLSQLiteDialect(version: XLDialectVersion(3, 46))
        )

        let literal = encoder.makeSQL(
            DialectCapabilityProbe(named: false, indexed: false)
        )
        let named = encoder.makeSQL(
            DialectCapabilityProbe(named: true, indexed: false)
        )
        let indexed = encoder.makeSQL(
            DialectCapabilityProbe(named: false, indexed: true)
        )
        let both = encoder.makeSQL(
            DialectCapabilityProbe(named: true, indexed: true)
        )

        XCTAssertEqual(literal.dialectRequirement.capabilities, [])
        XCTAssertEqual(named.dialectRequirement.capabilities, [.namedBindings])
        XCTAssertEqual(indexed.dialectRequirement.capabilities, [.indexedBindings])
        XCTAssertEqual(
            both.dialectRequirement.capabilities,
            [.namedBindings, .indexedBindings]
        )
        XCTAssertNil(both.dialectRequirement.minimumVersion)
    }

    func testEncodedNamedBindingRejectsDialectWithoutNamedBindings() {
        let encoding = XLiteEncoder(formatter: XLiteFormatter()).makeSQL(
            DialectCapabilityProbe(named: true, indexed: false)
        )
        let unsupported = XLDialectDescriptor(
            identity: XLSQLiteDialect.identity,
            capabilities: [.indexedBindings]
        )

        XCTAssertThrowsError(
            try encoding.dialectRequirement.validate(unsupported)
        ) { error in
            XCTAssertEqual(
                error as? XLDatabaseContractError,
                .capabilityMismatch(
                    dialect: XLSQLiteDialect.identity,
                    required: [.namedBindings],
                    available: [.indexedBindings]
                )
            )
        }
    }

    func testEncoderCapturesLegacyParametersAcrossNestedBuildersInFirstUseOrder() {
        let encoding = XLiteEncoder(formatter: XLiteFormatter()).makeSQL(
            NestedParameterLayoutProbe()
        )

        XCTAssertNil(encoding.parameterLayoutError)
        XCTAssertEqual(
            encoding.parameterLayout.slots.map(\.index),
            [XLLogicalParameterIndex(0), XLLogicalParameterIndex(1)]
        )
        XCTAssertEqual(
            encoding.parameterLayout.slots.map(\.key),
            [.named("name"), .indexed(2)]
        )
        XCTAssertEqual(
            encoding.parameterLayout.slots.map(\.nullability),
            [.nullable, .nullable]
        )
        XCTAssertTrue(
            encoding.parameterLayout.slots.allSatisfy {
                $0.codecIdentity == nil
            }
        )
    }

    func testNamedReferencesCaptureConcreteTypeAndNullabilityMetadata() throws {
        let encoding = try XLiteEncoder(formatter: XLiteFormatter())
            .makeValidatedSQL(LegacyReferenceMetadataProbe())

        XCTAssertEqual(encoding.parameterLayout.count, 2)
        XCTAssertEqual(
            encoding.parameterLayout.slots.map(\.key),
            [.named("required"), .named("nullable")]
        )
        XCTAssertEqual(
            encoding.parameterLayout.slots.map(\.valueTypeIdentifier),
            [
                XLValueTypeIdentifier(rawValue: "swift.int"),
                XLValueTypeIdentifier(rawValue: "swift.string"),
            ]
        )
        XCTAssertEqual(
            encoding.parameterLayout.slots.map(\.nullability),
            [.required, .nullable]
        )
        XCTAssertTrue(
            encoding.parameterLayout.slots.allSatisfy {
                $0.codecIdentity == nil
            }
        )
    }

    func testEncoderPreservesTypedParameterMetadataAndCoalescesRepeatedOccurrences() throws {
        let valueTypeIdentifier = XLValueTypeIdentifier(rawValue: "example.user-id")
        let codecIdentity = XLValueCodecIdentity(
            key: XLValueCodecKey(id: "example.user-id.text", version: 1),
            valueTypeIdentifier: valueTypeIdentifier,
            dialectIdentifier: XLSQLiteDialect.identity,
            storageIdentifier: XLValueStorageIdentifier(rawValue: "sqlite.text")
        )
        let slot = parameterSlot(
            index: 0,
            key: .named("userID"),
            valueTypeIdentifier: valueTypeIdentifier.rawValue,
            nullability: .nullable,
            codecIdentity: codecIdentity
        )

        let encoding = try XLiteEncoder(formatter: XLiteFormatter()).makeValidatedSQL(
            TypedParameterLayoutProbe(slots: [slot, slot])
        )

        XCTAssertEqual(encoding.parameterLayout.slots, [slot])
        XCTAssertEqual(encoding.sql, ":userID :userID")
        XCTAssertEqual(
            encoding.dialectRequirement.capabilities,
            [.namedBindings]
        )
    }

    func testEncoderAssignsDeclarationIndicesByFirstUseAndCoalescesRepeats() throws {
        let named = parameterDeclaration(key: .named("userID"))
        let indexed = parameterDeclaration(
            key: .indexed(4),
            valueTypeIdentifier: "example.limit",
            valueTypeName: "Swift.Int"
        )

        let encoding = try XLiteEncoder(formatter: XLiteFormatter()).makeValidatedSQL(
            ParameterDeclarationProbe(declarations: [named, indexed, named])
        )

        XCTAssertEqual(
            encoding.parameterLayout.slots,
            [
                named.slot(at: XLLogicalParameterIndex(0)),
                indexed.slot(at: XLLogicalParameterIndex(1)),
            ]
        )
        XCTAssertEqual(encoding.sql, ":userID ?5 :userID")
    }

    func testEncoderRejectsDistinctLogicalKeysThatAliasOneSQLiteParameter() {
        let named = parameterDeclaration(key: .named("value"))
        let indexed = parameterDeclaration(
            key: .indexed(0),
            valueTypeIdentifier: "example.other-value"
        )
        let encoder = XLiteEncoder(formatter: XLiteFormatter())

        let encoding = encoder.makeSQL(
            ParameterDeclarationProbe(declarations: [named, indexed])
        )

        let namedSlot = named.slot(at: XLLogicalParameterIndex(0))
        let indexedSlot = indexed.slot(at: XLLogicalParameterIndex(1))
        XCTAssertEqual(encoding.sql, ":value ?1")
        XCTAssertEqual(
            encoding.parameterLayoutError,
            .conflictingPhysicalParameterIndex(
                index: 1,
                existing: namedSlot,
                incoming: indexedSlot
            )
        )
        XCTAssertThrowsError(
            try encoder.makeValidatedSQL(
                ParameterDeclarationProbe(declarations: [named, indexed])
            )
        ) { error in
            XCTAssertEqual(
                error as? XLInvocationBindingError,
                encoding.parameterLayoutError
            )
        }
    }

    func testEncoderRejectsMixedLegacyAndTypedAliasesInEitherOrder() {
        let encoder = XLiteEncoder(formatter: XLiteFormatter())

        for legacyFirst in [true, false] {
            let encoding = encoder.makeSQL(
                MixedLegacyAndTypedParameterProbe(legacyFirst: legacyFirst)
            )

            guard case .conflictingParameterKey(let key, _, _)? =
                encoding.parameterLayoutError else {
                return XCTFail(
                    "Expected a deterministic key conflict when legacyFirst=\(legacyFirst), received \(String(describing: encoding.parameterLayoutError))"
                )
            }
            XCTAssertEqual(key, .named("value"))
            XCTAssertThrowsError(
                try encoder.makeValidatedSQL(
                    MixedLegacyAndTypedParameterProbe(
                        legacyFirst: legacyFirst
                    )
                )
            ) { error in
                guard case .conflictingParameterKey(let key, _, _)? =
                    error as? XLInvocationBindingError else {
                    return XCTFail(
                        "Expected a deterministic key conflict, received \(error)"
                    )
                }
                XCTAssertEqual(key, .named("value"))
            }
        }
    }

    func testEncoderRetainsConflictingRepeatedDeclarationMetadata() {
        let first = parameterDeclaration(key: .named("userID"))
        let conflict = parameterDeclaration(
            key: .named("userID"),
            valueTypeIdentifier: "example.account-id",
            valueTypeName: "Example.AccountID"
        )
        let encoder = XLiteEncoder(formatter: XLiteFormatter())

        let encoding = encoder.makeSQL(
            ParameterDeclarationProbe(declarations: [first, conflict])
        )

        let firstSlot = first.slot(at: XLLogicalParameterIndex(0))
        XCTAssertEqual(encoding.parameterLayout.slots, [firstSlot])
        XCTAssertEqual(
            encoding.parameterLayoutError,
            .conflictingParameterIndex(
                index: XLLogicalParameterIndex(0),
                existing: firstSlot,
                incoming: conflict.slot(at: XLLogicalParameterIndex(0))
            )
        )
    }

    func testNonthrowingEncodingRetainsFirstTypedParameterConflict() throws {
        let first = parameterSlot(index: 0, key: .named("userID"))
        let conflict = parameterSlot(index: 1, key: .named("userID"))
        let probe = TypedParameterLayoutProbe(slots: [first, conflict])
        let encoder = XLiteEncoder(formatter: XLiteFormatter())

        let encoding = encoder.makeSQL(probe)

        XCTAssertEqual(encoding.parameterLayout.slots, [first])
        XCTAssertEqual(
            encoding.parameterLayoutError,
            .conflictingParameterKey(
                key: .named("userID"),
                existing: first,
                incoming: conflict
            )
        )
        XCTAssertThrowsError(try encoder.makeValidatedSQL(probe)) { error in
            XCTAssertEqual(
                error as? XLInvocationBindingError,
                encoding.parameterLayoutError
            )
        }
    }

    // MARK: - Issue #166 rendering fast paths

    /// `scopedName` special-cases the one- and two-component names that dominate
    /// qualified references to avoid the intermediate `map` array. The output
    /// must stay identical to the general `map`/`joined` implementation for every
    /// component count, including the three-plus case that still uses it.
    func testScopedNameFastPathMatchesNaiveJoinAcrossComponentCounts() {
        let formatter = XLiteFormatter()
        let inputs: [[String]] = [
            [],
            ["id"],
            ["t0", "id"],
            ["main", "person", "id"],
            ["a", "b", "c", "d"],
        ]
        for values in inputs {
            let naive = values.map(formatter.name).joined(separator: ".")
            XCTAssertEqual(
                formatter.scopedName(values),
                naive,
                "scopedName diverged from map/joined for \(values)"
            )
        }
        XCTAssertEqual(formatter.scopedName([]), "")
        XCTAssertEqual(formatter.scopedName(["id"]), "\"id\"")
        XCTAssertEqual(formatter.scopedName(["t0", "id"]), "\"t0\".\"id\"")
        XCTAssertEqual(
            formatter.scopedName(["main", "person", "id"]),
            "\"main\".\"person\".\"id\""
        )
    }

    /// `build()` returns a single already-rendered token directly instead of
    /// re-joining it, and must still join multiple tokens with the builder's
    /// separator (space for expression builders, ", " for list builders).
    func testSingleTokenBuildersReturnTheirTokenAndMultiTokenBuildersJoin() {
        var single: XLBuilder = XLiteBuilder(formatter: XLiteFormatter())
        single.name("solo")
        XCTAssertEqual(single.build(), "\"solo\"")

        var multi: XLBuilder = XLiteBuilder(formatter: XLiteFormatter())
        multi.name("left")
        multi.name("right")
        XCTAssertEqual(multi.build(), "\"left\" \"right\"")

        var listSingle: XLBuilder = XLiteBuilder(formatter: XLiteFormatter())
        listSingle.list(separator: XLSeparator.list.rawValue) { items in
            items.listItem { $0.name("only") }
        }
        XCTAssertEqual(listSingle.build(), "\"only\"")

        var listMulti: XLBuilder = XLiteBuilder(formatter: XLiteFormatter())
        listMulti.list(separator: XLSeparator.list.rawValue) { items in
            items.listItem { $0.name("a") }
            items.listItem { $0.name("b") }
        }
        XCTAssertEqual(listMulti.build(), "\"a\", \"b\"")
    }
}
