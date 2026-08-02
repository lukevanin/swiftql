//
//  SQLModelSendableConformanceTests.swift
//  SwiftQL
//
//  Issue #531: a `public` model declared with `@SQLTable` or `@SQLResult` conforms to `Sendable`,
//  so a value built entirely from column values can be shared across isolation domains without
//  the conformance being written out by hand -- or, worse, without the checking being switched
//  off with `nonisolated(unsafe)`.
//
//  These fixtures are `public` on purpose. Swift infers `Sendable` for an `internal` struct of
//  `Sendable` stored properties on its own, so an internal fixture would pass whether or not the
//  macro did anything; it withholds the inference from a type other modules can see, which is
//  exactly the case the macro covers and exactly the case that warned in `SwiftQLExamples`.
//

import Foundation
import SwiftQL
import XCTest


/// A public table model of plain column types, the shape `SwiftQLExamples.Person` has.
@SQLTable(name: "SendableConformancePerson")
public struct SendableConformancePersonTable {

    public var id: String

    public var occupationId: String?

    public var name: String

    public var age: Int
}


/// A second table with a different column mix -- `Double`, `Bool`, `Data`, `Date` -- so the
/// conformance is shown to follow from the macro rather than from one fixture's property types.
@SQLTable(name: "SendableConformanceMeasurement")
public struct SendableConformanceMeasurementTable {

    public var id: Int

    public var value: Double

    public var calibrated: Bool

    public var payload: Data

    public var recordedAt: Date
}


/// A public projection, to pin that `@SQLResult` derives the conformance on the same terms.
@SQLResult
public struct SendableConformanceProjection {

    public var id: String

    public var total: Int?
}


/// A model that states the conformance itself. The macro generates nothing here, and the
/// declaration keeps its own conformance rather than colliding with a second one.
@SQLTable(name: "SendableConformanceExplicit")
public struct SendableConformanceExplicitTable: Sendable {

    public var id: String

    public var name: String
}


/// Compiles only if `T` conforms to `Sendable`. The requirement is an ordinary generic
/// constraint, so it is checked in every language mode rather than only under strict concurrency.
private func requireSendable<T: Sendable>(_: T.Type) {}


final class SQLModelSendableConformanceTests: XCTestCase {

    // The `static let` of models is the exact declaration that warned in
    // `Examples/Sources/SwiftQLExamples/ExampleDatabase.swift`: a non-`Sendable` element type
    // makes the array non-`Sendable`, which makes the static property unsafe to share.
    static let seedPeople: [SendableConformancePersonTable] = [
        SendableConformancePersonTable(id: "fred", occupationId: "eng", name: "Fred", age: 31),
        SendableConformancePersonTable(id: "ida", occupationId: nil, name: "Ida", age: 68),
    ]

    func test_publicTableModelConformsToSendable() {
        requireSendable(SendableConformancePersonTable.self)
        requireSendable(SendableConformanceMeasurementTable.self)
    }

    func test_publicResultModelConformsToSendable() {
        requireSendable(SendableConformanceProjection.self)
    }

    func test_modelStatingTheConformanceItselfKeepsIt() {
        requireSendable(SendableConformanceExplicitTable.self)
    }

    // A collection of models is `Sendable` too, which is what the failing example needed.
    func test_collectionsOfModelsAreSendable() {
        requireSendable([SendableConformancePersonTable].self)
        requireSendable([String: SendableConformanceProjection].self)
        XCTAssertEqual(Self.seedPeople.count, 2)
    }
}
