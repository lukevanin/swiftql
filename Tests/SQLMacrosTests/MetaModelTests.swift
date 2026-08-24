//
//  MetaModelTests.swift
//  SwiftQL
//
//  Direct tests for the two halves issue #564 split `MetaBuilder` into: the
//  binding walk, which is the subtlest rule in the parse half, and the
//  emitters, which now take a hand-built `MetaModel` instead of parsed source.
//
//  Everything here used to be asserted only through whole macro expansions,
//  where a wrong answer reads as a diff in generated Swift rather than as the
//  rule it broke.
//

import SwiftParser
import SwiftSyntax
import XCTest

@testable import SQLMacros


final class MetaPropertyBindingWalkTests: XCTestCase {

    func testASinglePlainBindingResolvesToOneColumn() throws {
        let columns = try resolve("let id: String")

        XCTAssertEqual(columns.map(\.name), ["id"])
        XCTAssertEqual(columns.map(\.type), ["String"])
        XCTAssertEqual(columns.map(\.optional), [false])
    }

    /// The rule the reverse walk exists for: an annotation applies backwards
    /// across the contiguous bindings that have none of their own. Both
    /// properties here are `Int`, and they come back in source order.
    func testATrailingAnnotationCarriesBackwardsAcrossBindings() throws {
        let columns = try resolve("let a, b, c: Int")

        XCTAssertEqual(columns.map(\.name), ["a", "b", "c"])
        XCTAssertEqual(columns.map(\.type), ["Int", "Int", "Int"])
    }

    /// The carry stops at a binding with its own annotation, so a declaration
    /// can mix types.
    func testAnOwnAnnotationStopsTheCarry() throws {
        let columns = try resolve("let a: String, b, c: Int")

        XCTAssertEqual(columns.map(\.name), ["a", "b", "c"])
        XCTAssertEqual(columns.map(\.type), ["String", "Int", "Int"])
    }

    func testOptionalityIsResolvedPerBindingAndCarriesWithTheAnnotation() throws {
        let columns = try resolve("let a, b: Int?")

        XCTAssertEqual(columns.map(\.name), ["a", "b"])
        XCTAssertEqual(columns.map(\.type), ["Int", "Int"])
        XCTAssertEqual(columns.map(\.optional), [true, true])
    }

    /// `Optional<T>` and `T?` name the same column type, so the macro cannot
    /// treat them as different columns.
    func testOptionalSugarAndOptionalGenericResolveIdentically() throws {
        let sugar = try resolve("let value: Int?")
        let generic = try resolve("let value: Optional<Int>")
        let qualified = try resolve("let value: Swift.Optional<Int>")

        XCTAssertEqual(sugar.map(\.type), generic.map(\.type))
        XCTAssertEqual(sugar.map(\.type), qualified.map(\.type))
        XCTAssertEqual(sugar.map(\.optional), [true])
        XCTAssertEqual(generic.map(\.optional), [true])
        XCTAssertEqual(qualified.map(\.optional), [true])
    }

    /// A binding with an initial value and no annotation stops the carry --
    /// its type would have to be inferred, and the macro cannot infer it.
    func testABindingWithOnlyAnInitialValueIsReported() throws {
        let (columns, diagnostics) = try resolveReportingDiagnostics("var value = 42")

        XCTAssertTrue(columns.isEmpty)
        XCTAssertEqual(diagnosticIDs(diagnostics), ["missing-type-annotation"])
    }

    func testABindingWithNoAnnotationAndNoCarryIsReported() throws {
        let (columns, diagnostics) = try resolveReportingDiagnostics("var value")

        XCTAssertTrue(columns.isEmpty)
        XCTAssertEqual(diagnosticIDs(diagnostics), ["missing-type-annotation"])
    }

    /// An unsupported annotation is reported once, and the bindings it covers
    /// are skipped rather than each producing its own cascade of errors about
    /// a type that was already rejected.
    func testAnUnsupportedAnnotationIsReportedOnceAndSuppressesTheBindingsItCovers() throws {
        let (columns, diagnostics) = try resolveReportingDiagnostics(
            "let a, b: (Int, String)"
        )

        XCTAssertTrue(columns.isEmpty)
        XCTAssertEqual(diagnosticIDs(diagnostics), ["unsupported-column-type"])
    }

    /// A computed property has no storage, but its annotation still carries:
    /// the bindings before it are resolvable and are not collateral damage.
    func testAComputedBindingIsReportedWhileStillCarryingItsAnnotation() throws {
        let (columns, diagnostics) = try resolveReportingDiagnostics(
            "var a, b: Int { 0 }"
        )

        XCTAssertEqual(columns.map(\.name), ["a"])
        XCTAssertEqual(columns.map(\.type), ["Int"])
        XCTAssertEqual(diagnosticIDs(diagnostics), ["computed-property"])
    }

    /// A tuple pattern names no single property. Reported, and its annotation
    /// carries for the same reason.
    func testATuplePatternIsReportedWhileStillCarryingItsAnnotation() throws {
        let (columns, diagnostics) = try resolveReportingDiagnostics(
            "let a, (b, c): Int"
        )

        XCTAssertEqual(columns.map(\.name), ["a"])
        XCTAssertEqual(diagnosticIDs(diagnostics), ["unsupported-pattern"])
    }

    /// A `let` that already has a value cannot be assigned by the generated
    /// memberwise initializer, so it is not a column the macro can write.
    func testAnImmutableBindingWithAnInitialValueIsReported() throws {
        let (columns, diagnostics) = try resolveReportingDiagnostics(
            "let value: Int = 42",
            mutability: .immutable
        )

        XCTAssertTrue(columns.isEmpty)
        XCTAssertEqual(diagnosticIDs(diagnostics), ["immutable-initial-value"])
    }

    /// Backticks let a reserved word name a property. They stay in the Swift
    /// name and are stripped from the SQL name.
    func testABacktickedNameKeepsItsBackticksAndLosesThemInSQL() throws {
        let columns = try resolve("let `default`: Int")

        XCTAssertEqual(columns.map(\.name), ["`default`"])
        XCTAssertEqual(columns.map(\.alias), ["default"])
    }

    /// A name the macro also generates would produce a duplicate declaration,
    /// so it is refused rather than silently colliding.
    func testAReservedNameIsReported() throws {
        let (columns, diagnostics) = try resolveReportingDiagnostics("let Row: Int")

        XCTAssertTrue(columns.isEmpty)
        XCTAssertEqual(diagnosticIDs(diagnostics), ["reserved-property-name"])
    }

    /// A codec key belongs to the declaration, so the walk attaches it only
    /// when there is exactly one binding for it to belong to. Deciding which of
    /// several bindings it names is not possible.
    func testACodecKeyIsCarriedOntoTheOnlyBindingItCanBelongTo() throws {
        let columns = try resolve("let value: Int", codecKeyExpression: ".myCodec")

        XCTAssertEqual(columns.map(\.codecKeyExpression), [".myCodec"])
    }

    /// One declaration with several problems reports all of them, so an author
    /// fixes the declaration once rather than one error per rebuild.
    func testEveryProblemInOneDeclarationIsReported() throws {
        let (_, diagnostics) = try resolveReportingDiagnostics(
            "var a = 1, b: (Int, String), c"
        )

        XCTAssertEqual(
            Set(diagnosticIDs(diagnostics)),
            ["missing-type-annotation", "unsupported-column-type"]
        )
    }

    // MARK: - Helpers

    private func resolve(
        _ source: String,
        mutability: MetaProperty.Mutability = .immutable,
        codecKeyExpression: String? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> [MetaProperty] {
        let (columns, diagnostics) = try resolveReportingDiagnostics(
            source,
            mutability: mutability,
            codecKeyExpression: codecKeyExpression
        )
        XCTAssertEqual(
            diagnosticIDs(diagnostics),
            [],
            "Expected no diagnostics for \(source)",
            file: file,
            line: line
        )
        return columns
    }

    private func resolveReportingDiagnostics(
        _ source: String,
        mutability: MetaProperty.Mutability = .immutable,
        codecKeyExpression: String? = nil
    ) throws -> ([MetaProperty], MacroDiagnosticCollector) {
        let declaration = try XCTUnwrap(
            Parser.parse(source: source).statements.first?
                .item.as(VariableDeclSyntax.self),
            "Could not parse '\(source)' as a variable declaration"
        )
        var diagnostics = MacroDiagnosticCollector()
        let columns = MetaPropertyBindingWalk.resolve(
            bindings: declaration.bindings,
            mutability: mutability,
            codecKeyExpression: codecKeyExpression,
            diagnostics: &diagnostics
        )
        return (columns, diagnostics)
    }

    /// The diagnostic ids, in the order they were collected. `MessageID.id` is
    /// not readable from here, so the id is recovered from the description,
    /// which spells it as `SQLMacros.<id>`.
    private func diagnosticIDs(
        _ diagnostics: MacroDiagnosticCollector
    ) -> [String] {
        diagnostics.diagnostics.map { diagnostic in
            let identity = String(describing: diagnostic.diagMessage.diagnosticID)
            guard
                let opening = identity.range(of: #"id: ""#),
                let closing = identity.range(
                    of: #"""#,
                    range: opening.upperBound ..< identity.endIndex
                )
            else {
                return identity
            }
            return String(identity[opening.upperBound ..< closing.lowerBound])
        }
    }
}


final class MetaModelTests: XCTestCase {

    /// The derived property sets are what the emitters select shapes from, so
    /// each has to be derived from the declared properties and not from each
    /// other.
    func testDerivedPropertySetsFollowFromTheDeclaredProperties() {
        let model = MetaModel(
            structName: "Person",
            tableName: "people",
            properties: [
                MetaProperty(mutability: .mutable, name: "id", alias: "id", optional: false, type: "String"),
                MetaProperty(mutability: .immutable, name: "age", alias: "age", optional: true, type: "Int"),
            ]
        )

        XCTAssertEqual(model.properties.map(\.optional), [false, true])
        XCTAssertEqual(model.optionalProperties.map(\.optional), [true, true])
        XCTAssertEqual(model.anonymousProperties.map(\.optional), [false, true])
        XCTAssertEqual(model.anonymousOptionalProperties.map(\.optional), [true, true])
        XCTAssertEqual(model.mutableProperties.map(\.name), ["id"])
    }

    /// A generated generic or local must not shadow anything already in scope:
    /// the model's own name, its generic parameters, a column alias, or a word
    /// appearing in a property's type. A generated generic named like a
    /// concrete type would silently change what that type means inside the
    /// generated signature.
    func testIdentifierReservationsCoverEverythingAGeneratedNameCouldShadow() {
        let model = MetaModel(
            structName: "Person",
            tableName: "people",
            genericParameterNames: ["Element"],
            properties: [
                MetaProperty(mutability: .mutable, name: "id", alias: "identifier", optional: false, type: "MyModule.Identifier"),
            ]
        )

        let reservations = model.generatedIdentifierReservations

        XCTAssertTrue(reservations.contains("Person"))
        XCTAssertTrue(reservations.contains("Element"))
        XCTAssertTrue(reservations.contains("identifier"))
        XCTAssertTrue(reservations.contains("MyModule"))
        XCTAssertTrue(reservations.contains("Identifier"))
    }
}
