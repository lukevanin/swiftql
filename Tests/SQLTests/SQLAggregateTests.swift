import Foundation
import GRDB
import SwiftQL
import XCTest


@SQLTable(name: "AggregateInput")
struct AggregateInput: Identifiable {
    let id: String
    let integerValue: Int
    let realValue: Double
    let nullableIntegerValue: Int?
    let nullableRealValue: Double?
    let textValue: String
}


@SQLResult
struct AggregateResult: Equatable {
    let minimum: Int?
    let maximum: Int?
    let sum: Int?
    let integerAverage: Double?
    let realAverage: Double?
    let nullableIntegerAverage: Double?
    let nullableRealAverage: Double?
    let concatenated: String?
    let pipeConcatenated: String?
    let rowCount: Int
    let integerCount: Int
    let coalescedSum: Int
}


final class XLAggregateTests: XCTestCase {

    private var encoder: XLiteEncoder!
    private var databasePool: DatabasePool!
    private var database: GRDBDatabase!
    private var databaseURL: URL!

    override func setUpWithError() throws {
        let formatter = XLiteFormatter()
        databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        encoder = XLiteEncoder(formatter: formatter)
        databasePool = try DatabasePool(path: databaseURL.path)
        database = try GRDBDatabase(databasePool: databasePool, formatter: formatter, logger: nil)

        try databasePool.write { database in
            try database.execute(
                sql: """
                    CREATE TABLE AggregateInput (
                        id TEXT NOT NULL,
                        integerValue INTEGER,
                        realValue REAL,
                        nullableIntegerValue INTEGER,
                        nullableRealValue REAL,
                        textValue TEXT
                    )
                    """
            )
        }
    }

    override func tearDownWithError() throws {
        database = nil
        try databasePool.close()
        databasePool = nil
        encoder = nil
        try FileManager.default.removeItem(at: databaseURL)
        databaseURL = nil
    }

    func testOptionalAggregateTypesAndRendering() {
        let integer = XLNamedBindingReference<Int>(name: "integer")
        let real = XLNamedBindingReference<Double>(name: "real")
        let nullableInteger = XLNamedBindingReference<Int?>(name: "nullableInteger")
        let nullableReal = XLNamedBindingReference<Double?>(name: "nullableReal")
        let text = XLNamedBindingReference<String>(name: "text")

        assertExpressionType(integer, Int.self)
        assertExpressionType(real, Double.self)
        assertExpressionType(text, String.self)
        assertExpressionType(integer.minOrNull(), Optional<Int>.self)
        assertExpressionType(integer.maxOrNull(), Optional<Int>.self)
        assertExpressionType(integer.sumOrNull(), Optional<Int>.self)
        assertExpressionType(integer.averageOrNull(), Optional<Double>.self)
        assertExpressionType(real.averageOrNull(), Optional<Double>.self)
        assertExpressionType(nullableInteger.averageOrNull(), Optional<Double>.self)
        assertExpressionType(nullableReal.averageOrNull(), Optional<Double>.self)
        assertExpressionType(text.groupConcatOrNull(), Optional<String>.self)
        assertExpressionType(text.groupConcatOrNull(separator: "|"), Optional<String>.self)
        assertExpressionType(integer.count(), Int.self)
        assertExpressionType(all(), XLAllColumns.self)
        assertExpressionType(count(all()), Int.self)
        assertExpressionType(integer.sumOrNull().coalesce(-99), Int.self)

        XCTAssertEqual(encoder.makeSQL(integer.minOrNull()).sql, "MIN(:integer)")
        XCTAssertEqual(encoder.makeSQL(integer.minOrNull(distinct: true)).sql, "MIN(DISTINCT :integer)")
        XCTAssertEqual(encoder.makeSQL(integer.maxOrNull()).sql, "MAX(:integer)")
        XCTAssertEqual(encoder.makeSQL(integer.maxOrNull(distinct: true)).sql, "MAX(DISTINCT :integer)")
        XCTAssertEqual(encoder.makeSQL(integer.sumOrNull()).sql, "SUM(:integer)")
        XCTAssertEqual(encoder.makeSQL(integer.sumOrNull(distinct: true)).sql, "SUM(DISTINCT :integer)")
        XCTAssertEqual(encoder.makeSQL(integer.averageOrNull()).sql, "AVG(:integer)")
        XCTAssertEqual(encoder.makeSQL(real.averageOrNull()).sql, "AVG(:real)")
        XCTAssertEqual(encoder.makeSQL(real.averageOrNull(distinct: true)).sql, "AVG(DISTINCT :real)")
        XCTAssertEqual(encoder.makeSQL(nullableInteger.averageOrNull()).sql, "AVG(:nullableInteger)")
        XCTAssertEqual(
            encoder.makeSQL(nullableReal.averageOrNull(distinct: true)).sql,
            "AVG(DISTINCT :nullableReal)"
        )
        XCTAssertEqual(encoder.makeSQL(text.groupConcatOrNull()).sql, "GROUP_CONCAT(:text)")
        XCTAssertEqual(
            encoder.makeSQL(text.groupConcatOrNull(distinct: true)).sql,
            "GROUP_CONCAT(DISTINCT :text)"
        )
        XCTAssertEqual(
            encoder.makeSQL(text.groupConcatOrNull(separator: "|")).sql,
            "GROUP_CONCAT(:text, '|')"
        )
        XCTAssertEqual(encoder.makeSQL(integer.count()).sql, "COUNT(:integer)")
        XCTAssertEqual(encoder.makeSQL(all()).sql, "*")
        XCTAssertEqual(encoder.makeSQL(count(all())).sql, "COUNT(*)")
        XCTAssertEqual(
            encoder.makeSQL(integer.sumOrNull().coalesce(-99)).sql,
            "COALESCE(SUM(:integer), -99)"
        )
    }

    // Compile-only: the deprecated context verifies v1 signatures without adding deprecation warnings to tests.
    @available(*, deprecated, message: "Exercises the source-compatible SwiftQL 1.x aggregate surface.")
    private func assertLegacyAggregateSignaturesRemainSourceCompatible() {
        let integer = XLNamedBindingReference<Int>(name: "integer")
        let real = XLNamedBindingReference<Double>(name: "real")
        let text = XLNamedBindingReference<String>(name: "text")
        let minimum: any XLExpression<Int> = integer.min()
        let maximum: any XLExpression<Int> = integer.max()
        let sum: any XLExpression<Int> = integer.sum()
        let average: any XLExpression<Double> = real.average()
        let concatenated: any XLExpression<String> = text.groupConcat()
        let pipeConcatenated: any XLExpression<String> = text.groupConcat(separator: "|")

        XCTAssertEqual(encoder.makeSQL(minimum).sql, "MIN(:integer)")
        XCTAssertEqual(encoder.makeSQL(maximum).sql, "MAX(:integer)")
        XCTAssertEqual(encoder.makeSQL(sum).sql, "SUM(:integer)")
        XCTAssertEqual(encoder.makeSQL(average).sql, "AVG(:real)")
        XCTAssertEqual(encoder.makeSQL(concatenated).sql, "GROUP_CONCAT(:text)")
        XCTAssertEqual(encoder.makeSQL(pipeConcatenated).sql, "GROUP_CONCAT(:text, '|')")
    }

    func testOptionalAggregatesWithPopulatedInput() throws {
        try databasePool.write { database in
            try database.execute(
                sql: """
                    INSERT INTO AggregateInput (
                        id,
                        integerValue,
                        realValue,
                        nullableIntegerValue,
                        nullableRealValue,
                        textValue
                    )
                    VALUES
                        ('one', 2, 1.0, 2, 1.0, 'beta'),
                        ('two', 3, 2.0, NULL, NULL, 'alpha'),
                        ('three', 3, 3.0, 4, 5.0, 'beta')
                    """
            )
        }

        let result = try fetchAggregateResult()
        XCTAssertEqual(result.minimum, 2)
        XCTAssertEqual(result.maximum, 3)
        XCTAssertEqual(result.sum, 8)
        XCTAssertEqual(try XCTUnwrap(result.integerAverage), 8.0 / 3.0, accuracy: 0.000_001)
        XCTAssertEqual(result.realAverage, 2.0)
        XCTAssertEqual(result.nullableIntegerAverage, 3.0)
        XCTAssertEqual(result.nullableRealAverage, 3.0)
        XCTAssertEqual(
            try XCTUnwrap(result.concatenated).split(separator: ",").map(String.init).sorted(),
            ["alpha", "beta", "beta"]
        )
        XCTAssertEqual(
            try XCTUnwrap(result.pipeConcatenated).split(separator: "|").map(String.init).sorted(),
            ["alpha", "beta", "beta"]
        )
        XCTAssertEqual(result.rowCount, 3)
        XCTAssertEqual(result.integerCount, 3)
        XCTAssertEqual(result.coalescedSum, 8)
    }

    func testOptionalAggregatesWithEmptyInput() throws {
        let result = try fetchAggregateResult()

        XCTAssertNil(result.minimum)
        XCTAssertNil(result.maximum)
        XCTAssertNil(result.sum)
        XCTAssertNil(result.integerAverage)
        XCTAssertNil(result.realAverage)
        XCTAssertNil(result.nullableIntegerAverage)
        XCTAssertNil(result.nullableRealAverage)
        XCTAssertNil(result.concatenated)
        XCTAssertNil(result.pipeConcatenated)
        XCTAssertEqual(result.rowCount, 0)
        XCTAssertEqual(result.integerCount, 0)
        XCTAssertEqual(result.coalescedSum, -99)
    }

    func testOptionalAggregatesWithPhysicalAllNullInput() throws {
        try databasePool.write { database in
            try database.execute(
                sql: """
                    INSERT INTO AggregateInput (
                        id,
                        integerValue,
                        realValue,
                        nullableIntegerValue,
                        nullableRealValue,
                        textValue
                    )
                    VALUES
                        ('one', NULL, NULL, NULL, NULL, NULL),
                        ('two', NULL, NULL, NULL, NULL, NULL)
                    """
            )
        }

        let result = try fetchAggregateResult()
        XCTAssertNil(result.minimum)
        XCTAssertNil(result.maximum)
        XCTAssertNil(result.sum)
        XCTAssertNil(result.integerAverage)
        XCTAssertNil(result.realAverage)
        XCTAssertNil(result.nullableIntegerAverage)
        XCTAssertNil(result.nullableRealAverage)
        XCTAssertNil(result.concatenated)
        XCTAssertNil(result.pipeConcatenated)
        XCTAssertEqual(result.rowCount, 2)
        XCTAssertEqual(result.integerCount, 0)
        XCTAssertEqual(result.coalescedSum, -99)
    }

    private func aggregateStatement() -> any XLQueryStatement<AggregateResult> {
        sql { schema in
            let input = schema.table(AggregateInput.self)
            Select(
                AggregateResult.columns(
                    minimum: input.integerValue.minOrNull(),
                    maximum: input.integerValue.maxOrNull(),
                    sum: input.integerValue.sumOrNull(),
                    integerAverage: input.integerValue.averageOrNull(),
                    realAverage: input.realValue.averageOrNull(),
                    nullableIntegerAverage: input.nullableIntegerValue.averageOrNull(),
                    nullableRealAverage: input.nullableRealValue.averageOrNull(),
                    concatenated: input.textValue.groupConcatOrNull(),
                    pipeConcatenated: input.textValue.groupConcatOrNull(separator: "|"),
                    rowCount: count(all()),
                    integerCount: input.integerValue.count(),
                    coalescedSum: input.integerValue.sumOrNull().coalesce(-99)
                )
            )
            From(input)
        }
    }

    private func fetchAggregateResult() throws -> AggregateResult {
        let results = try database.makeRequest(with: aggregateStatement()).fetchAll()
        XCTAssertEqual(results.count, 1)
        return try XCTUnwrap(results.first)
    }

    private func assertExpressionType<T>(_: any XLExpression<T>, _: T.Type) {
    }
}
