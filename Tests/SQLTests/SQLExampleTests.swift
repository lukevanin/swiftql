//
//  SQLExampleTests.swift
//  
//
//  Created by Luke Van In on 2023/08/22.
//

import Foundation
#if canImport(Combine)
import Combine
#else
import OpenCombine
#endif
import XCTest
import GRDB
import SwiftQL

private enum DocumentationDateCodecError: Error {
    case invalidText(String)
    case unexpectedValue(XLSQLiteValue)
}

private let documentationDateType = XLValueTypeIdentifier(
    rawValue: "com.example.foundation-date"
)

private let decimalDateCodecKey = XLValueCodecKey(
    id: "com.example.date.decimal-seconds",
    version: 1
)

private let integerDateCodecKey = XLValueCodecKey(
    id: "com.example.date.integer-seconds",
    version: 1
)

private let decimalDateCodec = XLValueCodec<Date, XLSQLiteDialect>(
    key: decimalDateCodecKey,
    valueTypeIdentifier: documentationDateType,
    dialectIdentifier: XLSQLiteDialect.identity,
    storageIdentifier: XLValueStorageIdentifier(
        rawValue: XLSQLiteStorageClass.text.rawValue
    ),
    encode: { value, _, _ in
        .text(String(value.timeIntervalSince1970))
    },
    decode: { value, _, _ in
        guard case .text(let text) = value else {
            throw DocumentationDateCodecError.unexpectedValue(value)
        }
        guard let seconds = Double(text) else {
            throw DocumentationDateCodecError.invalidText(text)
        }
        return Date(timeIntervalSince1970: seconds)
    }
)

private let integerDateCodec = XLValueCodec<Date, XLSQLiteDialect>(
    key: integerDateCodecKey,
    valueTypeIdentifier: documentationDateType,
    dialectIdentifier: XLSQLiteDialect.identity,
    storageIdentifier: XLValueStorageIdentifier(
        rawValue: XLSQLiteStorageClass.integer.rawValue
    ),
    encode: { value, _, _ in
        .integer(Int64(value.timeIntervalSince1970))
    },
    decode: { value, _, _ in
        guard case .integer(let seconds) = value else {
            throw DocumentationDateCodecError.unexpectedValue(value)
        }
        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }
)


struct MyUUID: XLCustomType, XLComparable, Equatable, Sendable {

    private enum ReadError: LocalizedError {
        case invalidUUID(String)

        var errorDescription: String? {
            switch self {
            case .invalidUUID(let rawValue):
                "Data does not represent a valid UUID: \(rawValue)"
            }
        }
    }

    public typealias T = Self

    public let wrappedValue: UUID

    public init(_ wrappedValue: UUID) {
        self.wrappedValue = wrappedValue
    }

    public init(reader: XLFieldReader) throws {
        let rawValue = try reader.readText()
        guard let wrappedValue = UUID(uuidString: rawValue) else {
            throw ReadError.invalidUUID(rawValue)
        }
        self.wrappedValue = wrappedValue
    }

    public func bind(context: inout XLBindingContext) {
        context.bindText(value: wrappedValue.uuidString)
    }

    public func makeSQL(context: inout XLBuilder) {
        context.text(wrappedValue.uuidString)
    }

    public static func sqlDefault() -> MyUUID {
        MyUUID(UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)
    }
}


struct SQLDate: XLCustomType, XLComparable, Equatable {

    private enum ReadError: Error {
        case invalidJulianDay(Double)
    }

    public typealias T = Self

    public let wrappedValue: Date

    public init(_ wrappedValue: Date) {
        self.wrappedValue = wrappedValue
    }

    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    public init(reader: XLFieldReader) throws {
        let rawValue = try reader.readReal()
        guard let wrappedValue = Date(julianDay: rawValue) else {
            throw ReadError.invalidJulianDay(rawValue)
        }
        self.wrappedValue = wrappedValue
    }

    public func bind(context: inout XLBindingContext) {
        context.bindText(value: Self.dateFormatter.string(from: wrappedValue))
    }

    public static func wrapSQL(
        context: inout XLBuilder,
        builder: (inout XLBuilder) -> Void
    ) {
        context.simpleFunction(name: "julianday") { context in
            context.listItem { context in
                builder(&context)
            }
        }
    }

    public static func unwrapSQL(context: inout XLBuilder, builder: MakeExpression) {
        context.simpleFunction(name: "strftime") { context in
            context.listItem { context in
                context.text("%Y-%m-%dT%H:%M:%f")
            }
            context.listItem { context in
                builder(&context)
            }
        }
    }

    public func makeSQL(context: inout XLBuilder) {
        Self.wrapSQL(context: &context) { context in
            context.text(Self.dateFormatter.string(from: wrappedValue))
        }
    }

    public static func sqlDefault() -> SQLDate {
        SQLDate(Date(timeIntervalSince1970: 0))
    }
}


enum JobPriority: Int, XLEnum {

    typealias T = Self

    case low = 0

    case high = 1

    static func sqlDefault() -> JobPriority {
        .low
    }
}


enum JobState: String, XLEnum {

    typealias T = Self

    case queued

    case running

    static func sqlDefault() -> JobState {
        .queued
    }
}


@SQLTable struct Job: Equatable {

    let id: String

    let priority: JobPriority

    let state: JobState

    let previousState: JobState?
}


@SQLResult struct JobSummary: Equatable {

    let id: String

    let priority: JobPriority

    let state: JobState

    let previousState: JobState?
}


@SQLTable struct ExampleValue: Equatable {

    let id: String

    let value: Int
}


@SQLTable struct Measurement: Equatable {

    let id: String

    let value: Int

    let minimum: Int

    let maximum: Int
}


@SQLTable struct CustomTypeEmployee: Equatable {

    let id: MyUUID

    let name: String
}


@SQLTable struct CustomTypeInvoice: Equatable {

    let id: String

    let dueDate: SQLDate
}


@SQLTable struct Person: Equatable {

    var id: String
    
    var occupationId: String?

    var name: String
    
    var age: Int
}


@SQLTable struct Occupation: Equatable {

    var id: String

    var name: String
}


@SQLTable struct OccupationCount: Equatable {

    let occupation: String
    
    let numberOfPeople: Int?
}


@SQLResult struct OccupationPopulation: Equatable {

    let occupation: String

    let numberOfPeople: Int
}


@SQLTable struct PersonOccupation: Equatable {

    let person: String

    let occupation: String
}


@SQLTable struct PersonOptionalOccupation: Equatable {

    let person: String

    let occupation: String?
}


@SQLTable struct OccupationColor: Equatable {

    let occupation: String
    
    let color: String
}


@SQLTable struct OccupationOptionalColor: Equatable {

    let occupation: String
    
    let color: String?
}

@SQLTable struct PersonOptionalScore: Equatable {

    let person: String

    let score: Int?
}


@SQLTable struct Invoice: Equatable {
    
    let id: String
    
    let dueDate: Date
}

@SQLTable struct Restaurant: Equatable {
    
    let name: String
    
    let latitude: Double
    
    let longitude: Double
}

@SQLTable struct NearbyRestaurant: Equatable {
    
    let name: String
    
    let distance: Double
}

@SQLTable struct Event: Equatable {
    
    let id: String
    
    let name: String
    
    let startDate: Date
    
    let endDate: Date
}

@SQLTable struct EventDuration: Equatable {
    
    let name: String
    
    let startDate: Date
    
    let endDate: Date
    
    let duration: TimeInterval
}


///
/// Subtracts two dates and returns the number of seconds difference.
///
func -(lhs: any SwiftQL.XLExpression<Date>, rhs: any SwiftQL.XLExpression<Date>) -> some SwiftQL.XLExpression<TimeInterval> {
    XLBinaryOperatorExpression<Int>(op: "-", lhs: lhs, rhs: rhs).toDouble()
}


extension Date: XLCustomType, XLComparable {

    private enum ReadError: Error {
        case invalidJulianDay(Double)
    }
    
    // Define a formatter to use to encode and decode the date.
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
    
    public typealias T = Self
    
    // Decode the date from a SwiftQL result.
    public init(reader: XLFieldReader) throws {
        let rawValue = try reader.readReal()
        guard let value = Date(julianDay: rawValue) else {
            throw ReadError.invalidJulianDay(rawValue)
        }
        self = value
    }
    
    // Bind the date to a SwiftQL expression.
    public func bind(context: inout XLBindingContext) {
        let rawValue = Self.dateFormatter.string(from: self)
        context.bindText(value: rawValue)
    }
    
    public func makeSQL(context: inout XLBuilder) {
        Self.wrapSQL(context: &context) { context in
            context.text(Self.dateFormatter.string(from: self))
        }
    }
    
    // When the date is used in an expression, use the 'julianday' function to transform the string representation of
    // the date into a decimal number.
    public static func wrapSQL(context: inout XLBuilder, builder: (inout XLBuilder) -> Void) {
        context.simpleFunction(name: "julianday") { context in
            context.listItem { context in
                builder(&context)
            }
        }
    }
    
    // When the date is inserted or updated, use `strftime` to format the decimal representation into a string.
    public static func unwrapSQL(context: inout XLBuilder, builder: MakeExpression) {
        context.simpleFunction(name: "strftime") { context in
            context.listItem { context in
                context.text("%Y-%m-%dT%H:%M:%f")
            }
            context.listItem { context in
                builder(&context)
            }
        }
    }

    // Return a constant date by default.
    public static func sqlDefault() -> Date {
        Date(timeIntervalSince1970: 0)
    }
}


public struct HaversineDistance: XLCustomFunction {
    
    public typealias T = Double
    
    // Define the function signature. SQLite uses the name and number of parameters to differentiate functions.
    public static let definition = XLCustomFunctionDefinition(
        name: "haversineDistance",
        numberOfArguments: 4
    )
    
    // Define parameters which are passed to the function at runtime.
    private let fromLatitude: any SwiftQL.XLExpression
    private let fromLongitude: any SwiftQL.XLExpression
    private let toLatitude: any SwiftQL.XLExpression
    private let toLongitude: any SwiftQL.XLExpression
    
    init(
        fromLatitude: any SwiftQL.XLExpression<Double>,
        fromLongitude: any SwiftQL.XLExpression<Double>,
        toLatitude: any SwiftQL.XLExpression<Double>,
        toLongitude: any SwiftQL.XLExpression<Double>
    ) {
        self.fromLatitude = fromLatitude
        self.fromLongitude = fromLongitude
        self.toLatitude = toLatitude
        self.toLongitude = toLongitude
    }
    
    // Define how the function is formatted into a SwiftQL expression.
    public func makeSQL(context: inout XLBuilder) {
        context.simpleFunction(name: Self.definition.name) { context in
            context.listItem(expression: fromLatitude.makeSQL)
            context.listItem(expression: fromLongitude.makeSQL)
            context.listItem(expression: toLatitude.makeSQL)
            context.listItem(expression: toLongitude.makeSQL)
        }
    }
    
    // Define the implementation details for how the function works. SQLite calls this at runtime, and the results
    // are returned to SQLite.
    public static func execute(reader: XLColumnReader) throws -> Double {
        let latA = try radians(degrees: reader.readReal(at: 0))
        let lonA = try radians(degrees: reader.readReal(at: 1))
        let latB = try radians(degrees: reader.readReal(at: 2))
        let lonB = try radians(degrees: reader.readReal(at: 3))
        let deltaLat = latB - latA
        let deltaLon = lonB - lonA
        let a = pow(sin(deltaLat / 2), 2)
            + cos(latA) * cos(latB) * pow(sin(deltaLon / 2), 2)
        return 2 * 6371 * asin(Swift.min(1, sqrt(a)))
    }
    
    private static func radians(degrees: Double) -> Double {
        (degrees / 180) * .pi
    }
}


final class XLDocumentationTests: XCTestCase {
    
    var encoder: XLiteEncoder!
    var databasePool: DatabasePool!
    var database: GRDBDatabase!
    
    var johnDoe = Person(id: "per-1", occupationId: "occ-1", name: "John Doe", age: 31)
    var janeDoe = Person(id: "per-2", occupationId: "occ-2", name: "Jane Doe", age: 25)
    var yogiBear = Person(id: "per-3", occupationId: nil, name: "Yogi Bear", age: 68)
    
    var engineer = Occupation(id: "occ-1", name: "Engineer")
    var scientist = Occupation(id: "occ-2", name: "Scientist")
    var artist = Occupation(id: "occ-3", name: "Artist")
    
    var wwdcKeynote = Event(
        id: "event-1",
        name: "WWDC70 Keynote",
        startDate: Date.dateFormatter.date(from: "2023-06-05T17:00:00.000")!,
        endDate: Date.dateFormatter.date(from: "2023-06-07T17:00:00.000")!
    )
    
    var invoice01 = Invoice(
        id: "inv-01",
        dueDate: Date.dateFormatter.date(from: "2023-08-28T17:30:00.000")!
    )
    
    var magicaromaRestaurant = Restaurant(
        name: "Magica Roma",
        latitude: -33.891851,
        longitude: 18.561470
    )
    
    override func setUp() {
        let directory = FileManager.default.temporaryDirectory
        let filename = UUID().uuidString
        let fileURL = directory
            .appendingPathComponent(filename, isDirectory: false)
            .appendingPathExtension("sqlite")
        print("Connecting to database \(fileURL.path)")
        //        databasePool = try! DatabasePool(path: fileURL.path)
        //        database = try! GRDBDatabase(
        //            databasePool: databasePool,
        //            formatter: XLiteFormatter(
        //                identifierFormattingOptions: .sqlite
        //            )
        //        )
        
        // Use a database builder to install custom functions.
        let config = Configuration()
        var builder = try! GRDBDatabaseBuilder(url: fileURL, configuration: config, logger: nil)

        builder.addFunction(HaversineDistance.self)

        database = try! builder.build()
        
        databasePool = database.databasePool

        encoder = XLiteEncoder(
            formatter: XLiteFormatter(
                identifierFormattingOptions: .noEscape
            )
        )
        
        setupDatabase()
    }
    
    override func tearDown() {
        encoder = nil
        databasePool = nil
        database = nil
    }
    
    private func setupDatabase() {
        try! databasePool.write { database in
            try database.execute(
                literal: """
                    CREATE TABLE Person (
                        id TEXT NOT NULL,
                        occupationId TEXT NULL,
                        name TEXT NOT NULL,
                        age INT NOT NULL
                    );
                
                    CREATE TABLE Occupation (
                        id TEXT NOT NULL,
                        name TEXT NOT NULL
                    );

                    CREATE TABLE Invoice (
                        id TEXT NOT NULL,
                        dueDate TEXT NOT NULL
                    );

                    CREATE TABLE Restaurant (
                        name TEXT NOT NULL,
                        latitude REAL NOT NULL,
                        longitude REAL NOT NULL
                    );

                    CREATE TABLE Event (
                        id TEXT NOT NULL,
                        name TEXT NOT NULL,
                        startDate TEXT NOT NULL,
                        endDate TEXT NOT NULL
                    );
                """
            )
        }
        insert(engineer)
        insert(scientist)
        insert(artist)
        insert(johnDoe)
        insert(janeDoe)
        insert(yogiBear)
        insert(invoice01)
        insert(magicaromaRestaurant)
        insert(wwdcKeynote)
    }
    
    private func insert(_ occupation: Occupation) {
        try! databasePool.write { database in
            try database.execute(
                literal: """
                    INSERT INTO Occupation
                        (id, name)
                    VALUES
                        (\(occupation.id), \(occupation.name));
                """
            )
        }
    }
    
    private func insert(_ person: Person) {
        try! databasePool.write { database in
            try database.execute(
                literal: """
                    INSERT INTO Person
                        (id, occupationId, name, age)
                    VALUES
                        (\(person.id), \(person.occupationId), \(person.name), \(person.age));
                """
            )
        }
    }
    
    private func insert(_ invoice: Invoice) {
        let sql = """
            INSERT INTO Invoice
                (id, dueDate)
            VALUES
                ('\(invoice.id)', '\(Date.dateFormatter.string(from: invoice.dueDate))');
        """
        print("insert invoice:", sql)
        try! databasePool.write { database in
            try database.execute(sql: sql)
        }
    }
    
    private func insert(_ restaurant: Restaurant) {
        let sql = """
            INSERT INTO Restaurant
                (name, latitude, longitude)
            VALUES
                ('\(restaurant.name)', \(restaurant.latitude), \(restaurant.longitude));
        """
        try! databasePool.write { database in
            try database.execute(sql: sql, arguments: StatementArguments())
        }
    }
    
    private func insert(_ event: Event) {
        let sql = """
            INSERT INTO Event
                (id, name, startDate, endDate)
            VALUES
                ('\(event.id)', '\(event.name)', '\(Date.dateFormatter.string(from: event.startDate))', '\(Date.dateFormatter.string(from: event.endDate))');
        """
        print("insert event:", sql)
        try! databasePool.write { database in
            try database.execute(sql: sql, arguments: StatementArguments())
        }
    }

    func testExample_Select() throws {
        let statement = sqlQuery { schema in
            let person = schema.table(Person.self)
            return select(person).from(person)
        }
        let sql = encoder.makeSQL(statement).sql
        let rows = try database.makeRequest(with: statement).fetchAll()
        XCTAssertEqual(sql, "SELECT t0.id AS id, t0.occupationId AS occupationId, t0.name AS name, t0.age AS age FROM Person AS t0")
        XCTAssertEqual(rows, [johnDoe, janeDoe, yogiBear])
    }
    
    func testExample_Variable_ImplicitAlias() throws {
        let schema = XLSchema()
        let nameParameter = schema.binding(of: String.self)
        let person = schema.table(Person.self)
        let statement = select(person).from(person).where(person.name == nameParameter)
        let sql = encoder.makeSQL(statement).sql
        var request = database.makeRequest(with: statement)
        request.set(nameParameter, "John Doe")
        let rows = try request.fetchAll()
        XCTAssertEqual(sql, "SELECT t0.id AS id, t0.occupationId AS occupationId, t0.name AS name, t0.age AS age FROM Person AS t0 WHERE (t0.name == :p0)")
        XCTAssertEqual(rows, [johnDoe])
    }
    
    func testExample_Variable_ExplicitAlias() throws {
        let nameParameter = XLNamedBindingReference<String>(name: "name")
        let statement = sqlQuery { schema in
            let person = schema.table(Person.self)
            return select(person).from(person).where(person.name == nameParameter)
        }
        let sql = encoder.makeSQL(statement).sql
        var request = database.makeRequest(with: statement)
        request.set(nameParameter, "John Doe")
        let rows = try request.fetchAll()
        XCTAssertEqual(sql, "SELECT t0.id AS id, t0.occupationId AS occupationId, t0.name AS name, t0.age AS age FROM Person AS t0 WHERE (t0.name == :name)")
        XCTAssertEqual(rows, [johnDoe])
    }
    
    func testExample_Subquery() throws {
        let statement = sqlQuery { schema in
            let occupation = schema.table(Occupation.self)
            let person = schema.table(Person.self)
            let result = OccupationCount.columns(
                occupation: occupation.name,
                numberOfPeople: subquery {
                    select(person.id.count()).from(person).where(person.occupationId == occupation.id)
                }
            )
            return select(result).from(occupation)
        }
        let rows = try database.makeRequest(with: statement).fetchAll()
        XCTAssertEqual(encoder.makeSQL(statement).sql, "SELECT t0.name AS occupation, (SELECT COUNT(t1.id) FROM Person AS t1 WHERE (t1.occupationId IS t0.id)) AS numberOfPeople FROM Occupation AS t0")
        XCTAssertEqual(rows, [
            OccupationCount(occupation: "Engineer", numberOfPeople: 1),
            OccupationCount(occupation: "Scientist", numberOfPeople: 1),
            OccupationCount(occupation: "Artist", numberOfPeople: 0)
        ])
    }
    
    func testExample_LeftJoin_Statement_NullRows() throws {
        let statement = sql { schema in
            let person = schema.table(Person.self)
            let occupation = schema.nullableTable(Occupation.self)
            let row = PersonOptionalOccupation.columns(
                person: person.name,
                occupation: occupation.name
            )
            Select(row)
            From(person)
            Join.Left(occupation, on: occupation.id == person.occupationId)
        }
        let sql = encoder.makeSQL(statement).sql
        XCTAssertEqual(sql, "SELECT t0.name AS person, t1.name AS occupation FROM Person AS t0 LEFT JOIN Occupation AS t1 ON (t1.id IS t0.occupationId)")
        let rows = try database.makeRequest(with: statement).fetchAll()
        XCTAssertEqual(rows, [
            PersonOptionalOccupation(person: "John Doe", occupation: "Engineer"),
            PersonOptionalOccupation(person: "Jane Doe", occupation: "Scientist"),
            PersonOptionalOccupation(person: "Yogi Bear", occupation: nil),
        ])
    }

    func testExample_LeftJoin_Functional_NullRows() throws {
        let statement = sqlQuery { schema in
            let person = schema.table(Person.self)
            let occupation = schema.nullableTable(Occupation.self)
            let result = PersonOptionalOccupation.columns(
                person: person.name,
                occupation: occupation.name
            )
            return select(result).from(person).leftJoin(occupation, on: occupation.id == person.occupationId)
        }
        let sql = encoder.makeSQL(statement).sql
        XCTAssertEqual(sql, "SELECT t0.name AS person, t1.name AS occupation FROM Person AS t0 LEFT JOIN Occupation AS t1 ON (t1.id IS t0.occupationId)")
        let rows = try database.makeRequest(with: statement).fetchAll()
        XCTAssertEqual(rows, [
            PersonOptionalOccupation(person: "John Doe", occupation: "Engineer"),
            PersonOptionalOccupation(person: "Jane Doe", occupation: "Scientist"),
            PersonOptionalOccupation(person: "Yogi Bear", occupation: nil),
        ])
    }

    func testExample_Iif() throws {
        let statement = sqlQuery { schema in
            let person = schema.table(Person.self)
            let occupation = schema.nullableTable(Occupation.self)
            let result = PersonOccupation.columns(
                person: person.name,
                occupation: iif(occupation.name.isNull(), then: "Unemployed", else: "Employed")
            )
            return select(result).from(person).leftJoin(occupation, on: occupation.id == person.occupationId)
        }
        let sql = encoder.makeSQL(statement).sql
        XCTAssertEqual(sql, "SELECT t0.name AS person, IIF((t1.name ISNULL), 'Unemployed', 'Employed') AS occupation FROM Person AS t0 LEFT JOIN Occupation AS t1 ON (t1.id IS t0.occupationId)")
        let rows = try database.makeRequest(with: statement).fetchAll()
        XCTAssertEqual(rows, [
            PersonOccupation(person: "John Doe", occupation: "Employed"),
            PersonOccupation(person: "Jane Doe", occupation: "Employed"),
            PersonOccupation(person: "Yogi Bear", occupation: "Unemployed"),
        ])
    }
    
    func testExample_Coalesce() throws {
        let statement = sqlQuery { schema in
            let person = schema.table(Person.self)
            let occupation = schema.nullableTable(Occupation.self)
            let result = PersonOccupation.columns(
                person: person.name,
                occupation: occupation.name.coalesce("No occupation")
            )
            return select(result).from(person).leftJoin(occupation, on: occupation.id == person.occupationId)
        }
        let sql = encoder.makeSQL(statement).sql
        XCTAssertEqual(sql, "SELECT t0.name AS person, COALESCE(t1.name, 'No occupation') AS occupation FROM Person AS t0 LEFT JOIN Occupation AS t1 ON (t1.id IS t0.occupationId)")
        let rows = try database.makeRequest(with: statement).fetchAll()
        XCTAssertEqual(rows, [
            PersonOccupation(person: "John Doe", occupation: "Engineer"),
            PersonOccupation(person: "Jane Doe", occupation: "Scientist"),
            PersonOccupation(person: "Yogi Bear", occupation: "No occupation"),
        ])
    }
    
    func testExample_SwitchCaseWhenThen() throws {
        let statement = sqlQuery { schema in
            let occupation = schema.table(Occupation.self)
            let result = OccupationOptionalColor.columns(
                occupation: occupation.name,
                color: switchCase(occupation.name)
                    .when("Engineer", then: "Red")
                    .when("Scientist", then: "Blue")
            )
            return select(result).from(occupation)
        }
        let sql = encoder.makeSQL(statement).sql
        let rows = try database.makeRequest(with: statement).fetchAll()
        XCTAssertEqual(sql, "SELECT t0.name AS occupation, (CASE t0.name WHEN 'Engineer' THEN 'Red' WHEN 'Scientist' THEN 'Blue' END) AS color FROM Occupation AS t0")
        XCTAssertEqual(rows, [
            OccupationOptionalColor(occupation: "Engineer", color: "Red"),
            OccupationOptionalColor(occupation: "Scientist", color: "Blue"),
            OccupationOptionalColor(occupation: "Artist", color: nil),
        ])
    }
    
    func testExample_SwitchCaseWhenThenElse() throws {
        let statement = sqlQuery { schema in
            let occupation = schema.table(Occupation.self)
            let result = OccupationColor.columns(
                occupation: occupation.name,
                color: switchCase(occupation.name)
                    .when("Engineer", then: "Red")
                    .when("Scientist", then: "Blue")
                    .else("Green")
            )
            return select(result).from(occupation)
        }
        let sql = encoder.makeSQL(statement).sql
        let rows = try database.makeRequest(with: statement).fetchAll()
        XCTAssertEqual(sql, "SELECT t0.name AS occupation, (CASE t0.name WHEN 'Engineer' THEN 'Red' WHEN 'Scientist' THEN 'Blue' ELSE 'Green' END) AS color FROM Occupation AS t0")
        XCTAssertEqual(rows, [
            OccupationColor(occupation: "Engineer", color: "Red"),
            OccupationColor(occupation: "Scientist", color: "Blue"),
            OccupationColor(occupation: "Artist", color: "Green"),
        ])
    }
    
    func testExample_IfCaseWhenThen() throws {
        let statement = sqlQuery { schema in
            let occupation = schema.table(Occupation.self)
            let result = OccupationOptionalColor.columns(
                occupation: occupation.name,
                color: when(occupation.name == "Artist", then: "Cyan")
            )
            return select(result).from(occupation)
        }
        let sql = encoder.makeSQL(statement).sql
        let rows = try database.makeRequest(with: statement).fetchAll()
        XCTAssertEqual(sql, "SELECT t0.name AS occupation, (CASE WHEN (t0.name == 'Artist') THEN 'Cyan' END) AS color FROM Occupation AS t0")
        XCTAssertEqual(rows, [
            OccupationOptionalColor(occupation: "Engineer", color: nil),
            OccupationOptionalColor(occupation: "Scientist", color: nil),
            OccupationOptionalColor(occupation: "Artist", color: "Cyan"),
        ])
    }
    
    func testExample_IfCaseWhenThenElse() throws {
        let statement = sqlQuery { schema in
            let occupation = schema.table(Occupation.self)
            let result = OccupationColor.columns(
                occupation: occupation.name,
                color: when(occupation.name == "Artist", then: "Cyan").else("Magenta")
            )
            return select(result).from(occupation)
        }
        let sql = encoder.makeSQL(statement).sql
        let rows = try database.makeRequest(with: statement).fetchAll()
        XCTAssertEqual(sql, "SELECT t0.name AS occupation, (CASE WHEN (t0.name == 'Artist') THEN 'Cyan' ELSE 'Magenta' END) AS color FROM Occupation AS t0")
        XCTAssertEqual(rows, [
            OccupationColor(occupation: "Engineer", color: "Magenta"),
            OccupationColor(occupation: "Scientist", color: "Magenta"),
            OccupationColor(occupation: "Artist", color: "Cyan"),
        ])
    }
    
    func testExample_IfCaseWhenThen_IntegerResult() throws {
        let statement = sqlQuery { schema in
            let person = schema.table(Person.self)
            let result = PersonOptionalScore.columns(
                person: person.name,
                score: when(person.name == "Yogi Bear", then: 100)
            )
            return select(result).from(person)
        }
        let sql = encoder.makeSQL(statement).sql
        let rows = try database.makeRequest(with: statement).fetchAll()
        XCTAssertEqual(sql, "SELECT t0.name AS person, (CASE WHEN (t0.name == 'Yogi Bear') THEN 100 END) AS score FROM Person AS t0")
        XCTAssertEqual(rows, [
            PersonOptionalScore(person: "John Doe", score: nil),
            PersonOptionalScore(person: "Jane Doe", score: nil),
            PersonOptionalScore(person: "Yogi Bear", score: 100),
        ])
    }

    func testExample_IfCaseWhenThen_IntegerResult_MultipleConditions() throws {
        let statement = sqlQuery { schema in
            let person = schema.table(Person.self)
            let result = PersonOptionalScore.columns(
                person: person.name,
                score: when(person.name == "Yogi Bear", then: 100)
                    .when(person.name == "John Doe", then: 50)
            )
            return select(result).from(person)
        }
        let sql = encoder.makeSQL(statement).sql
        let rows = try database.makeRequest(with: statement).fetchAll()
        XCTAssertEqual(sql, "SELECT t0.name AS person, (CASE WHEN (t0.name == 'Yogi Bear') THEN 100 WHEN (t0.name == 'John Doe') THEN 50 END) AS score FROM Person AS t0")
        XCTAssertEqual(rows, [
            PersonOptionalScore(person: "John Doe", score: 50),
            PersonOptionalScore(person: "Jane Doe", score: nil),
            PersonOptionalScore(person: "Yogi Bear", score: 100),
        ])
    }

    func testExample_Date() throws {
        let statement = sqlQuery { schema in
            let invoice = schema.table(Invoice.self)
            return select(invoice).from(invoice)
        }
        let sql = encoder.makeSQL(statement).sql
        let rows = try database.makeRequest(with: statement).fetchAll()
        XCTAssertEqual(sql, "SELECT t0.id AS id, julianday(t0.dueDate) AS dueDate FROM Invoice AS t0")
        XCTAssertEqual(rows, [invoice01])
    }
    
    func testExample_DateConstant() throws {
        let statement = sqlQuery { schema in
            let invoice = schema.table(Invoice.self)
            return select(invoice)
                .from(invoice)
                .where(invoice.dueDate > Date(timeIntervalSince1970: 0))
        }
        let sql = encoder.makeSQL(statement).sql
        let rows = try database.makeRequest(with: statement).fetchAll()
        XCTAssertEqual(sql, "SELECT t0.id AS id, julianday(t0.dueDate) AS dueDate FROM Invoice AS t0 WHERE (julianday(t0.dueDate) > julianday('1970-01-01T00:00:00.000'))")
        XCTAssertEqual(rows, [invoice01])
    }
    
    func testExample_DateParameter() throws {
        let dateParameter = XLNamedBindingReference<Date>(name: "date")
        let statement = sqlQuery { schema in
            let invoice = schema.table(Invoice.self)
            return select(invoice)
                .from(invoice)
                .where(invoice.dueDate > dateParameter)
        }
        let sql = encoder.makeSQL(statement).sql
        var request = database.makeRequest(with: statement)
        request.set(dateParameter, Date(timeIntervalSince1970: 0))
        let rows = try request.fetchAll()
        XCTAssertEqual(sql, "SELECT t0.id AS id, julianday(t0.dueDate) AS dueDate FROM Invoice AS t0 WHERE (julianday(t0.dueDate) > julianday(:date))")
        XCTAssertEqual(rows, [invoice01])
    }
    
    func testExample_CustomFunction() throws {
        let myLatitude = XLNamedBindingReference<Double>(name: "myLatitude")
        let myLongitude = XLNamedBindingReference<Double>(name: "myLongitude")
        let statement = sqlQuery { schema in
            let restaurant = schema.table(Restaurant.self)
            let result = NearbyRestaurant.columns(
                name: restaurant.name,
                distance: HaversineDistance(
                    fromLatitude: myLatitude,
                    fromLongitude: myLongitude,
                    toLatitude: restaurant.latitude,
                    toLongitude: restaurant.longitude
                ).rounded(to: 2)
            )
            // SELECT
            //  restaurant.name AS _name,
            //  ROUND(haversineDistance(:myLatitude, :myLongitude, restaurant.latitude, restaurant.longitude), 2) AS _ distance
            // FROM
            //  Restaurant AS restaurant
            // ORDER BY
            //  _distance ASC
            return select(result).from(restaurant).orderBy(result.distance.ascending())
        }
        let sql = encoder.makeSQL(statement).sql
        let request = database.makeRequest(with: statement)
        let layout = request.parameterLayout
        let coordinates = try XLInvocationBindings<XLSQLiteValue>(
            layout: layout,
            bindings: [
                try XLInvocationBinding(
                    slot: try XCTUnwrap(
                        layout.slot(for: .named("myLatitude"))
                    ),
                    value: .real(-33.877873677687894)
                ),
                try XLInvocationBinding(
                    slot: try XCTUnwrap(
                        layout.slot(for: .named("myLongitude"))
                    ),
                    value: .real(18.488075015723)
                ),
            ]
        ).validatingComplete()
        let rows = try request.fetchAll(bindings: coordinates)
        XCTAssertEqual(sql, "SELECT t0.name AS name, ROUND(haversineDistance(:myLatitude, :myLongitude, t0.latitude, t0.longitude), 2) AS distance FROM Restaurant AS t0 ORDER BY distance ASC")
        XCTAssertEqual(rows, [NearbyRestaurant(name: "Magica Roma", distance: 6.95)])
    }
    
    func testExample_CustomOperator() throws {
        let statement = sqlQuery { schema in
            let event = schema.table(Event.self)
            let result = EventDuration.columns(
                name: event.name,
                startDate: event.startDate,
                endDate: event.endDate,
                duration: (event.endDate - event.startDate)
            )
            return select(result).from(event)
        }
        let sql = encoder.makeSQL(statement).sql
        let request = database.makeRequest(with: statement)
        let rows = try request.fetchAll()
        XCTAssertEqual(sql, "SELECT t0.name AS name, julianday(t0.startDate) AS startDate, julianday(t0.endDate) AS endDate, CAST((julianday(t0.endDate) - julianday(t0.startDate)) AS REAL) AS duration FROM Event AS t0")
        XCTAssertEqual(try rows.element(at: 0).name, "WWDC70 Keynote")
        XCTAssertEqual(try rows.element(at: 0).startDate, Date.dateFormatter.date(from: "2023-06-05T17:00:00.000")!)
        XCTAssertEqual(try rows.element(at: 0).endDate, Date.dateFormatter.date(from: "2023-06-07T17:00:00.000")!)
        XCTAssertEqual(try rows.element(at: 0).duration, 2, accuracy: 0.5)
    }
}


// These named scenarios are the stable targets used by the DocC example markers. They keep
// article examples connected to executable coverage without forcing short continuation snippets
// to become standalone programs.
extension XLDocumentationTests {

    func testDocumentationREADME() throws {
        let databaseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: databaseDirectory,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: databaseDirectory) }
        let databaseURL = databaseDirectory.appendingPathComponent("readme.sqlite")

        do {
            let database = try GRDBDatabase(url: databaseURL, logger: nil)

            try database.makeRequest(with: sqlCreate(Person.self)).execute()

            let query = sql { schema in
                let person = schema.table(Person.self)
                Select(person)
                From(person)
                Where(person.name == "Fred")
            }

            XCTAssertEqual(
                encoder.makeSQL(query).sql,
                "SELECT t0.id AS id, t0.occupationId AS occupationId, t0.name AS name, t0.age AS age FROM Person AS t0 WHERE (t0.name == 'Fred')"
            )

            let request = database.makeRequest(with: query)

            let people: [Person] = try request.fetchAll()
            let firstPerson: Person? = try request.fetchOne()

            XCTAssertTrue(people.isEmpty)
            XCTAssertNil(firstPerson)
        }
    }

    func testDocumentationQuickStart() throws {
        try testDocumentationREADME()
    }

    func testDocumentationGettingStartedCRUDAndBindings() throws {
        let createPersonStatement = sqlCreate(Person.self)
        XCTAssertEqual(
            encoder.makeSQL(createPersonStatement).sql,
            "CREATE TABLE IF NOT EXISTS Person (id NOT NULL, occupationId, name NOT NULL, age NOT NULL)"
        )
        try database.makeRequest(with: createPersonStatement).execute()

        let fredPerson = Person(
            id: "fred",
            occupationId: nil,
            name: "Fred",
            age: 31
        )
        try database.makeRequest(with: sqlInsert(fredPerson)).execute()

        let peopleNamedFredQuery = sql { schema in
            let person = schema.table(Person.self)
            Select(person)
            From(person)
            Where(person.name == "Fred")
        }
        XCTAssertEqual(
            encoder.makeSQL(peopleNamedFredQuery).sql,
            "SELECT t0.id AS id, t0.occupationId AS occupationId, t0.name AS name, t0.age AS age FROM Person AS t0 WHERE (t0.name == 'Fred')"
        )
        XCTAssertEqual(
            try database.makeRequest(with: peopleNamedFredQuery).fetchAll(),
            [fredPerson]
        )
        XCTAssertEqual(
            try database.makeRequest(with: peopleNamedFredQuery).fetchOne(),
            fredPerson
        )

        let peopleNamedFredShorthandQuery = sql {
            let person = $0.table(Person.self)
            Select(person)
            From(person)
            Where(person.name == "Fred")
        }
        XCTAssertEqual(
            encoder.makeSQL(peopleNamedFredShorthandQuery).sql,
            encoder.makeSQL(peopleNamedFredQuery).sql
        )

        let workingAgeQuery = sql { schema in
            let person = schema.table(Person.self)
            Select(person)
            From(person)
            Where(person.age >= 21 && person.age < 65)
        }
        let workingAgeRequest = database.makeRequest(with: workingAgeQuery)
        XCTAssertEqual(try workingAgeRequest.fetchAll().count, 3)

        let nameParameter = XLNamedBindingReference<String>(name: "name")
        let peopleByNameQuery = sql { schema in
            let person = schema.table(Person.self)
            Select(person)
            From(person)
            Where(person.name == nameParameter)
        }
        let peopleByNameRequest = database.makeRequest(with: peopleByNameQuery)
        XCTAssertEqual(
            encoder.makeSQL(peopleByNameQuery).sql,
            "SELECT t0.id AS id, t0.occupationId AS occupationId, t0.name AS name, t0.age AS age FROM Person AS t0 WHERE (t0.name == :name)"
        )
        let nameSlot = try XCTUnwrap(
            peopleByNameRequest.parameterLayout.slot(for: .named("name"))
        )
        let fredBindings = try XLInvocationBindings<XLSQLiteValue>(
            layout: peopleByNameRequest.parameterLayout,
            bindings: [
                try XLInvocationBinding(slot: nameSlot, value: .text("Fred"))
            ]
        ).validatingComplete()
        XCTAssertEqual(
            try peopleByNameRequest.fetchAll(bindings: fredBindings),
            [fredPerson]
        )

        let updateFredStatement = sql { schema in
            let person = schema.into(Person.self)
            Update(person)
            Setting<Person> { row in
                row.age = 42
            }
            Where(person.id == "fred")
        }
        try database.makeRequest(with: updateFredStatement).execute()

        let personIDParameter = XLNamedBindingReference<String>(name: "id")
        let ageParameter = XLNamedBindingReference<Int>(name: "age")
        let updateAgeStatement = sql { schema in
            let person = schema.into(Person.self)
            Update(person)
            Setting<Person> { row in
                row.age = ageParameter
            }
            Where(person.id == personIDParameter)
        }
        let updateAgeRequest = database.makeRequest(with: updateAgeStatement)
        let updateBindings = try XLInvocationBindings<XLSQLiteValue>(
            layout: updateAgeRequest.parameterLayout,
            bindings: [
                try XLInvocationBinding(
                    slot: try XCTUnwrap(
                        updateAgeRequest.parameterLayout.slot(for: .named("id"))
                    ),
                    value: .text("fred")
                ),
                try XLInvocationBinding(
                    slot: try XCTUnwrap(
                        updateAgeRequest.parameterLayout.slot(for: .named("age"))
                    ),
                    value: .integer(42)
                ),
            ]
        ).validatingComplete()
        try updateAgeRequest.execute(bindings: updateBindings)

        XCTAssertEqual(
            try peopleByNameRequest.fetchOne(bindings: fredBindings),
            Person(id: "fred", occupationId: nil, name: "Fred", age: 42)
        )

        let deleteIDParameter = XLNamedBindingReference<String>(name: "id")
        let deletePersonStatement = sql { schema in
            let person = schema.into(Person.self)
            Delete(person)
            Where(person.id == deleteIDParameter)
        }
        let deletePersonRequest = database.makeRequest(with: deletePersonStatement)
        let deleteBindings = try XLInvocationBindings<XLSQLiteValue>(
            layout: deletePersonRequest.parameterLayout,
            bindings: [
                try XLInvocationBinding(
                    slot: try XCTUnwrap(
                        deletePersonRequest.parameterLayout.slot(for: .named("id"))
                    ),
                    value: .text("fred")
                )
            ]
        ).validatingComplete()
        try deletePersonRequest.execute(bindings: deleteBindings)

        XCTAssertNil(
            try peopleByNameRequest.fetchOne(bindings: fredBindings)
        )
    }

    func testDocumentationExpressions() throws {
        try testExample_Coalesce()
        try testExample_IfCaseWhenThenElse()

        let literalBounds = sql { schema in
            let person = schema.table(Person.self)
            Select(person)
            From(person)
            Where(person.age.isBetween(18, 65))
        }
        XCTAssertTrue(
            encoder.makeSQL(literalBounds).sql.contains("BETWEEN 18 AND 65")
        )

        let minimumAge = XLNamedBindingReference<Int>(name: "minimumAge")
        let maximumAge = XLNamedBindingReference<Int>(name: "maximumAge")
        let bindingBounds = sql { schema in
            let person = schema.table(Person.self)
            Select(person)
            From(person)
            Where(person.age.isNotBetween(minimumAge, maximumAge))
        }
        XCTAssertTrue(
            encoder.makeSQL(bindingBounds).sql.contains(
                "NOT BETWEEN :minimumAge AND :maximumAge"
            )
        )

        let columnBounds = sql { schema in
            let measurement = schema.table(Measurement.self)
            Select(measurement)
            From(measurement)
            Where(
                measurement.value.isBetween(
                    measurement.minimum,
                    measurement.maximum
                )
            )
        }
        XCTAssertTrue(
            encoder.makeSQL(columnBounds).sql.contains(" BETWEEN ")
        )

        let escapedWildcard = sql { schema in
            let person = schema.table(Person.self)
            Select(person)
            From(person)
            Where(person.name.like("%\\_%", escape: "\\"))
        }
        XCTAssertTrue(
            encoder.makeSQL(escapedWildcard).sql.contains(
                "LIKE '%\\_%' ESCAPE '\\'"
            )
        )

        let _: (XLExecutionTests) -> () throws -> Void = XLExecutionTests.testSelectWhereLike
        let _: (XLExecutionTests) -> () throws -> Void =
            XLExecutionTests.testSelectWhereLikeWithEscapeMatchesWildcardsLiterally
        let _: (XLExecutionTests) -> () throws -> Void =
            XLExecutionTests.testLikeEscapeRejectsMultiCharacterEscapeAtExecution
        let notInList = sql { schema in
            let person = schema.table(Person.self)
            Select(person)
            From(person)
            Where(person.occupationId.notIn(["eng", "sci"]))
        }
        XCTAssertTrue(
            encoder.makeSQL(notInList).sql.contains("NOT IN ('eng', 'sci')")
        )

        let _: (XLExecutionTests) -> () throws -> Void = XLExecutionTests.testSelectWhereIn
        let _: (XLExecutionTests) -> () throws -> Void =
            XLExecutionTests.testSelectWhereNotInValueList
        let _: (XLExecutionTests) -> () throws -> Void =
            XLExecutionTests.testNotInValueListAndEmptySetSemantics
        let _: (XLExecutionTests) -> () throws -> Void =
            XLExecutionTests.testBetweenExecutesWithLiteralBindingAndColumnBounds
        let _: (XLSyntaxTests) -> () -> Void = XLSyntaxTests.test_TextBinding_In_Subquery
        let _: (XLSyntaxTests) -> () -> Void =
            XLSyntaxTests.testBetweenOperatorPreservesNestedBooleanAndComparisonPrecedence
    }

    func testDocumentationRealValues() throws {
        do {
            _ = try XLiteEncoder(dialect: XLSQLiteDialect())
                .makeValidatedSQL(Double.infinity)
            XCTFail("Expected inline infinity to fail validation.")
        }
        catch let error as XLSQLValueEncodingError {
            XCTAssertEqual(
                error,
                .nonFiniteRealLiteral(
                    value: .positiveInfinity,
                    expressionType: String(reflecting: Double.self)
                )
            )
        }
    }

    func testDocumentationEnumValues() throws {
        try database.makeRequest(with: sqlCreate(Job.self)).execute()

        let swiftQLJob = Job(
            id: "build-docs",
            priority: .high,
            state: .running,
            previousState: nil
        )
        try database.makeRequest(with: sqlInsert(swiftQLJob)).execute()

        try databasePool.write { database in
            try database.execute(
                sql: "INSERT INTO Job (id, priority, state, previousState) VALUES (?, ?, ?, ?)",
                arguments: ["raw-values", 0, "running", "queued"]
            )
        }

        let stateParameter = XLNamedBindingReference<JobState>(name: "state")
        let runningJobs = sql { schema in
            let job = schema.table(Job.self)
            let summary = JobSummary.columns(
                id: job.id,
                priority: job.priority,
                state: job.state,
                previousState: job.previousState
            )
            Select(summary)
            From(job)
            Where(job.state == stateParameter)
            OrderBy(summary.id.ascending())
        }
        let request = database.makeRequest(with: runningJobs)
        let stateSlot = try XCTUnwrap(
            request.parameterLayout.slot(for: .named("state"))
        )
        let runningBindings = try XLInvocationBindings<XLSQLiteValue>(
            layout: request.parameterLayout,
            bindings: [
                try XLInvocationBinding(
                    slot: stateSlot,
                    value: .text(JobState.running.rawValue)
                )
            ]
        ).validatingComplete()

        XCTAssertEqual(
            try request.fetchAll(bindings: runningBindings),
            [
                JobSummary(
                    id: "build-docs",
                    priority: .high,
                    state: .running,
                    previousState: nil
                ),
                JobSummary(
                    id: "raw-values",
                    priority: .low,
                    state: .running,
                    previousState: .queued
                ),
            ]
        )

        try databasePool.write { database in
            try database.execute(
                sql: """
                    INSERT INTO Job (id, priority, state, previousState) VALUES
                        ('invalid-priority', 99, 'queued', NULL),
                        ('invalid-state', 0, 'retired', NULL),
                        ('invalid-optional-state', 0, 'queued', 'retired')
                    """
            )
        }

        assertJobDecodeError(
            id: "invalid-priority",
            equals: XLColumnReadError(
                index: 1,
                expectedType: "JobPriority",
                failure: .invalidValue(actualValue: "99")
            )
        )
        assertJobDecodeError(
            id: "invalid-state",
            equals: XLColumnReadError(
                index: 2,
                expectedType: "JobState",
                failure: .invalidValue(actualValue: #""retired""#)
            )
        )
        assertJobDecodeError(
            id: "invalid-optional-state",
            equals: XLColumnReadError(
                index: 3,
                expectedType: "JobState",
                failure: .invalidValue(actualValue: #""retired""#)
            )
        )

        let allJobs = sql { schema in
            let job = schema.table(Job.self)
            Select(job)
            From(job)
        }
        XCTAssertThrowsError(try database.makeRequest(with: allJobs).fetchAll()) { error in
            XCTAssertTrue(error is XLColumnReadError)
        }
    }

    private func assertJobDecodeError(
        id: String,
        equals expectedError: XLColumnReadError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let jobByID = sql { schema in
            let job = schema.table(Job.self)
            Select(job)
            From(job)
            Where(job.id == id)
        }
        XCTAssertThrowsError(
            try database.makeRequest(with: jobByID).fetchOne(),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error as? XLColumnReadError, expectedError, file: file, line: line)
        }
    }

    func testDocumentationFunctionalQueriesAndMutations() throws {
        try testExample_Select()
        try testExample_LeftJoin_Functional_NullRows()

        let nameParameter = XLNamedBindingReference<String>(name: "name")
        let peopleByNameStatement = sqlQuery { schema in
            let person = schema.table(Person.self)
            return select(person)
                .from(person)
                .where(person.name == nameParameter)
        }
        let peopleByNameRequest = database.makeRequest(
            with: peopleByNameStatement
        )
        let nameBindings = try XLInvocationBindings<XLSQLiteValue>(
            layout: peopleByNameRequest.parameterLayout,
            bindings: [
                try XLInvocationBinding(
                    slot: try XCTUnwrap(
                        peopleByNameRequest.parameterLayout.slot(
                            for: .named("name")
                        )
                    ),
                    value: .text("John Doe")
                )
            ]
        ).validatingComplete()
        XCTAssertEqual(
            try peopleByNameRequest.fetchAll(bindings: nameBindings),
            [johnDoe]
        )

        let groupedStatement = sqlQuery { schema in
            let person = schema.table(Person.self)
            let occupation = schema.nullableTable(Occupation.self)
            let result = OccupationPopulation.columns(
                occupation: occupation.name.coalesce("No occupation"),
                numberOfPeople: person.id.count()
            )
            return select(result)
                .from(person)
                .leftJoin(occupation, on: occupation.id == person.occupationId)
                .groupBy(occupation.id)
                .orderBy(result.occupation.ascending())
        }
        XCTAssertEqual(
            try database.makeRequest(with: groupedStatement).fetchAll(),
            [
                OccupationPopulation(occupation: "Engineer", numberOfPeople: 1),
                OccupationPopulation(occupation: "No occupation", numberOfPeople: 1),
                OccupationPopulation(occupation: "Scientist", numberOfPeople: 1),
            ]
        )

        try database.makeRequest(with: sqlCreate(ExampleValue.self)).execute()
        try database.makeRequest(
            with: sqlInsert(ExampleValue(id: "example-id", value: 0))
        ).execute()

        let idParameter = XLNamedBindingReference<String>(name: "id")
        let valueParameter = XLNamedBindingReference<Int>(name: "value")
        let updateStatement: any XLUpdateStatement<ExampleValue> = sqlUpdate { schema in
            let table = schema.into(ExampleValue.self)
            return update(
                table,
                set: ExampleValue.MetaUpdate(value: valueParameter)
            )
            .where(table.id == idParameter)
        }
        let updateRequest = database.makeRequest(with: updateStatement)
        let updateBindings = try XLInvocationBindings<XLSQLiteValue>(
            layout: updateRequest.parameterLayout,
            bindings: [
                try XLInvocationBinding(
                    slot: try XCTUnwrap(
                        updateRequest.parameterLayout.slot(for: .named("id"))
                    ),
                    value: .text("example-id")
                ),
                try XLInvocationBinding(
                    slot: try XCTUnwrap(
                        updateRequest.parameterLayout.slot(for: .named("value"))
                    ),
                    value: .integer(42)
                ),
            ]
        ).validatingComplete()
        try updateRequest.execute(bindings: updateBindings)

        let updatedValue = sql { schema in
            let table = schema.table(ExampleValue.self)
            Select(table)
            From(table)
            Where(table.id == "example-id")
        }
        XCTAssertEqual(
            try database.makeRequest(with: updatedValue).fetchOne(),
            ExampleValue(id: "example-id", value: 42)
        )

        let _: (XLSyntaxTests) -> () -> Void = XLSyntaxTests.testUpdateWhere
        let _: (XLSyntaxTests) -> () -> Void = XLSyntaxTests.testCreateTableUsingSelect
    }

    func testDocumentationGenericTableParameters() throws {
        try database.makeRequest(with: sqlCreate(GenericTable<String>.self)).execute()

        let nameRecord = GenericTable(id: "foo-name", type: "name", value: "Fred")
        try database.makeRequest(with: sqlInsert(nameRecord)).execute()
        let nameQuery = sql { schema in
            let table = schema.table(GenericTable<String>.self)
            Select(table)
            From(table)
            Where(table.type == "name")
        }
        XCTAssertEqual(try database.makeRequest(with: nameQuery).fetchOne()?.value, "Fred")

        let uuid = MyUUID(UUID(uuidString: "72472fdd-a897-4b35-9bd9-0f23688f45f7")!)
        let uuidRecord = GenericTable(id: "foo-id", type: "id", value: uuid)
        try database.makeRequest(with: sqlInsert(uuidRecord)).execute()
        let uuidQuery = sql { schema in
            let table = schema.table(GenericTable<MyUUID>.self)
            Select(table)
            From(table)
            Where(table.type == "id")
        }
        XCTAssertEqual(try database.makeRequest(with: uuidQuery).fetchOne()?.value, uuid)
    }

    func testDocumentationCustomTypeRoundTrips() throws {
        let dialect = XLSQLiteDialect()
        let registry = try XLValueCodecRegistry()
            .registering(decimalDateCodec)
            .registering(integerDateCodec)
        let codingConfiguration = try XLValueCodingConfiguration(
            registry: registry,
            defaultCodecKeys: [decimalDateCodecKey]
        )
        let date = Date(timeIntervalSince1970: 86_400)
        let parameterContext = XLValueCodingContext(
            site: .parameter,
            path: XLValueCodingPath("invoice.dueDate")
        )
        let resultContext = XLValueCodingContext(
            site: .result,
            path: XLValueCodingPath("invoice.dueDate")
        )

        XCTAssertEqual(
            try codingConfiguration.encode(
                date,
                using: dialect,
                context: parameterContext
            ),
            .text("86400.0")
        )
        let resolvedDateCodec = try codingConfiguration.resolvedCodec(
            for: Date.self,
            using: dialect,
            context: parameterContext,
            selection: XLValueCodecSelection(
                explicitCodecKey: integerDateCodecKey,
                queryCodecKey: decimalDateCodecKey
            )
        )
        XCTAssertEqual(try resolvedDateCodec.encode(date), .integer(86_400))
        XCTAssertEqual(
            try codingConfiguration.decode(
                Date.self,
                from: .integer(86_400),
                using: dialect,
                context: resultContext,
                selection: XLValueCodecSelection(
                    explicitCodecKey: integerDateCodecKey
                )
            ),
            date
        )
        XCTAssertEqual(
            try codingConfiguration.encodeOptional(
                Optional<Date>.none,
                using: dialect,
                context: parameterContext
            ),
            .null
        )
        let decodedNull: Date? = try codingConfiguration.decodeOptional(
            Date.self,
            from: .null,
            using: dialect,
            context: resultContext
        )
        XCTAssertNil(decodedNull)

        let contextualDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftql-contextual-docs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: contextualDirectory,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: contextualDirectory) }

        let codecDatabase = try GRDBDatabase(
            url: contextualDirectory.appendingPathComponent("fixture.sqlite"),
            codingConfiguration: codingConfiguration,
            logger: nil
        )
        let cutoffDate = try codecDatabase.contextualBinding(
            Date.self,
            expressedAs: String.self,
            named: "cutoffDate"
        )
        let cutoffQuery = sql { _ in
            Select(cutoffDate)
        }
        let cutoffRequest = codecDatabase.makeRequest(with: cutoffQuery)
        let cutoffBindings = try XLInvocationBindings<XLSQLiteValue>(
            layout: cutoffRequest.parameterLayout,
            bindings: [
                try cutoffDate.encode(date, in: cutoffRequest.parameterLayout)
            ]
        ).validatingComplete()
        let storedCutoff = try cutoffRequest.fetchOne(bindings: cutoffBindings)
        XCTAssertEqual(storedCutoff, "86400.0")

        let optionalDate = try codecDatabase.contextualBinding(
            Date.self,
            expressedAs: Optional<String>.self,
            named: "optionalDate",
            nullability: .nullable
        )
        let nullQuery = sql { _ in Select(optionalDate.isNull()) }
        let nullRequest = codecDatabase.makeRequest(with: nullQuery)
        let nullBindings = try XLInvocationBindings<XLSQLiteValue>(
            layout: nullRequest.parameterLayout,
            bindings: [
                try optionalDate.encodeOptional(
                    nil,
                    in: nullRequest.parameterLayout
                )
            ]
        ).validatingComplete()
        XCTAssertEqual(
            try nullRequest.fetchOne(bindings: nullBindings),
            true
        )
        XCTAssertThrowsError(
            try XLInvocationBindings<XLSQLiteValue>(
                layout: nullRequest.parameterLayout
            ).validatingComplete()
        )

        try testExample_Date()
        try testExample_DateConstant()
        try testExample_DateParameter()

        let employee = CustomTypeEmployee(
            id: MyUUID(UUID(uuidString: "536d0033-65a0-4142-8c21-99b6b891c4e8")!),
            name: "Ada"
        )
        try database.makeRequest(with: sqlCreate(CustomTypeEmployee.self)).execute()
        try database.makeRequest(with: sqlInsert(employee)).execute()

        let employeeQuery = sql { schema in
            let employee = schema.table(CustomTypeEmployee.self)
            Select(employee)
            From(employee)
        }
        XCTAssertEqual(
            try database.makeRequest(with: employeeQuery).fetchOne(),
            employee
        )

        let invoice = CustomTypeInvoice(
            id: "invoice-1",
            dueDate: SQLDate(Date(timeIntervalSince1970: 86_400))
        )
        try database.makeRequest(with: sqlCreate(CustomTypeInvoice.self)).execute()
        try database.makeRequest(with: sqlInsert(invoice)).execute()

        let dateParameter = XLNamedBindingReference<SQLDate>(name: "date")
        let invoiceQuery = sqlQuery { schema in
            let invoice = schema.table(CustomTypeInvoice.self)
            return select(invoice)
                .from(invoice)
                .where(invoice.dueDate > dateParameter)
        }
        var invoiceRequest = database.makeRequest(with: invoiceQuery)
        invoiceRequest.set(dateParameter, SQLDate(Date(timeIntervalSince1970: 0)))
        XCTAssertEqual(try invoiceRequest.fetchOne(), invoice)

        let legacyKey = XLValueCodecKey(
            id: "com.example.my-uuid.v1-literal",
            version: 1
        )
        let legacyAdapter = XLV1LiteralCodec<MyUUID>(
            key: legacyKey,
            valueTypeIdentifier: XLValueTypeIdentifier(
                rawValue: "com.example.my-uuid"
            ),
            storageClass: .text
        )
        let legacyConfiguration = try XLValueCodingConfiguration(
            registry: XLValueCodecRegistry().registering(legacyAdapter.codec)
        )
        let legacySelection = XLValueCodecSelection(legacyCodecKey: legacyKey)
        let encodedEmployeeID = try legacyConfiguration.encode(
            employee.id,
            using: dialect,
            context: parameterContext,
            selection: legacySelection
        )
        XCTAssertEqual(
            encodedEmployeeID,
            .text(employee.id.wrappedValue.uuidString)
        )
        XCTAssertEqual(
            try legacyConfiguration.decode(
                MyUUID.self,
                from: encodedEmployeeID,
                using: dialect,
                context: resultContext,
                selection: legacySelection
            ),
            employee.id
        )

        let _: (XLExecutionTests) -> () throws -> Void = XLExecutionTests.testStringToDataRoundTrip
    }

    func testDocumentationStaticQueries() throws {
        let staticQueryDialect = XLSQLiteDialect()
        let staticDateCoding = try XLValueCodingConfiguration(
            registry: try XLValueCodecRegistry().registering(decimalDateCodec),
            defaultCodecKeys: [decimalDateCodecKey]
        )
        let cutoffContext = XLValueCodingContext(
            site: .parameter,
            path: XLValueCodingPath("invoice.cutoffDate")
        )
        let cutoffCodec = try staticDateCoding.resolvedCodec(
            for: Date.self,
            using: staticQueryDialect,
            context: cutoffContext
        )
        let cutoffParameterIdentity = try XLQuerySlotIdentity(
            path: ["invoice", "parameter", "cutoffDate"]
        )
        let cutoffParameter = try staticDateCoding.queryCapture(
            Date.self,
            expressedAs: String.self,
            identifiedBy: cutoffParameterIdentity,
            using: staticQueryDialect,
            context: cutoffContext
        )

        let cutoffEncoding = try XLiteEncoder(dialect: staticQueryDialect)
            .makeValidatedSQL(sql { _ in Select(cutoffParameter) })
        let cutoffStatement = try XLStaticStatementDefinition(
            validating: cutoffEncoding
        )
        let selectedDateIdentity = try XLQuerySlotIdentity(
            path: ["invoice", "result", "cutoffDate"]
        )
        let cutoffMetadata = try cutoffParameter.staticQueryParameter(
            in: cutoffEncoding
        )
        let selectedDate = XLStaticQueryResultSlot(
            index: XLLogicalResultIndex(0),
            identity: selectedDateIdentity,
            valueTypeIdentifier: cutoffCodec.identity.valueTypeIdentifier,
            valueTypeName: String(reflecting: Date.self),
            nullability: .required,
            codecIdentity: cutoffCodec.identity,
            storageIdentifier: cutoffCodec.identity.storageIdentifier,
            codingContext: XLValueCodingContext(
                site: .result,
                path: XLValueCodingPath("invoice.cutoffDate")
            )
        )
        let cutoffDescriptor = try XLStaticQueryDescriptor(
            definitionIdentity: XLQueryDefinitionIdentity(
                path: ["invoice", "selected-after-cutoff"],
                version: 1
            ),
            statement: cutoffStatement,
            parameters: [cutoffMetadata],
            results: try XLStaticQueryResultMetadata(slots: [selectedDate]),
            cardinality: .exactlyOne
        )

        guard case .named(let cutoffBindingName) = cutoffParameter.declaration.key else {
            return XCTFail("Query captures must use stable named keys")
        }
        XCTAssertEqual(cutoffDescriptor.sql, "SELECT :\(cutoffBindingName)")
        XCTAssertEqual(cutoffDescriptor.parameters, [cutoffMetadata])
        XCTAssertEqual(cutoffDescriptor.results.slots, [selectedDate])
        let staticQueryRegistry = [
            cutoffDescriptor.identity: cutoffDescriptor,
        ]
        let registeredDescriptor = try XCTUnwrap(
            staticQueryRegistry[cutoffDescriptor.identity]
        )
        try registeredDescriptor.identity.validateDefinitionCompatibility(
            with: cutoffDescriptor.identity
        )

        let staticDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftql-static-query-docs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: staticDirectory,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: staticDirectory) }
        let databaseURL = staticDirectory.appendingPathComponent("fixture.sqlite")
        let staticDatabase = try GRDBDatabase(
            url: databaseURL,
            codingConfiguration: staticDateCoding,
            logger: nil
        )
        defer { try? staticDatabase.databasePool.close() }
        let preparedCutoff = try staticDatabase.prepareInvocation(
            with: cutoffDescriptor
        )
        let preparedCutoffParameter = try preparedCutoff.preparedParameter(
            Date.self,
            identifiedBy: cutoffParameterIdentity
        )
        let expectedDate = Date(timeIntervalSince1970: 86_400)
        let cutoffBindings = try XLInvocationBindings<XLSQLiteValue>(
            layout: preparedCutoff.parameterLayout,
            bindings: [
                try preparedCutoffParameter.encode(expectedDate)
            ]
        ).validatingComplete()
        let cutoffRow = try preparedCutoff.fetchExactlyOneValues(
            bindings: cutoffBindings
        )
        let cutoffResultCodec = try preparedCutoff.resultCodec(
            Date.self,
            identifiedBy: selectedDateIdentity
        )
        let decodedCutoff = try cutoffResultCodec.decode(cutoffRow[0])
        XCTAssertEqual(decodedCutoff, expectedDate)
        let capturedCutoffBindings = try preparedCutoff.makeInvocationBindings {
            try $0.bind(expectedDate, to: cutoffParameter)
        }
        XCTAssertEqual(capturedCutoffBindings.bindings, cutoffBindings.bindings)

        let intrinsicParameter = XLNamedBindingReference<Int>(name: "value")
        let intrinsicEncoding = try XLiteEncoder(dialect: staticQueryDialect)
            .makeValidatedSQL(sql { _ in Select(intrinsicParameter) })
        let intrinsicStatement = try XLStaticStatementDefinition(
            validating: intrinsicEncoding
        )
        let intrinsicSlot = try XCTUnwrap(
            intrinsicStatement.parameterLayout.slot(for: .named("value"))
        )
        let intrinsicParameterIdentity = try XLQuerySlotIdentity(
            path: ["intrinsic", "parameter", "value"]
        )
        let intrinsicResultIdentity = try XLQuerySlotIdentity(
            path: ["intrinsic", "result", "value"]
        )
        let integerStorage = XLValueStorageIdentifier(
            rawValue: XLSQLiteStorageClass.integer.rawValue
        )
        let intrinsicDescriptor = try XLStaticQueryDescriptor(
            definitionIdentity: XLQueryDefinitionIdentity(
                path: ["documentation", "intrinsic-value"],
                version: 1
            ),
            statement: intrinsicStatement,
            parameters: [
                XLStaticQueryParameterMetadata(
                    identity: intrinsicParameterIdentity,
                    slot: intrinsicSlot,
                    storageIdentifier: integerStorage
                )
            ],
            results: try XLStaticQueryResultMetadata(slots: [
                XLStaticQueryResultSlot(
                    index: XLLogicalResultIndex(0),
                    identity: intrinsicResultIdentity,
                    valueTypeIdentifier: XLValueTypeIdentifier(
                        rawValue: "swift.int"
                    ),
                    valueTypeName: String(reflecting: Int.self),
                    nullability: .required,
                    codecIdentity: nil,
                    storageIdentifier: integerStorage,
                    codingContext: XLValueCodingContext(
                        site: .result,
                        path: XLValueCodingPath("intrinsic.value")
                    )
                )
            ]),
            cardinality: .exactlyOne
        )
        let preparedIntrinsic = try staticDatabase.prepareInvocation(
            with: intrinsicDescriptor
        )
        let intrinsicBindings = try XLInvocationBindings<XLSQLiteValue>(
            layout: preparedIntrinsic.parameterLayout,
            bindings: [
                try XLInvocationBinding(
                    slot: intrinsicSlot,
                    value: .integer(7)
                )
            ]
        ).validatingComplete()
        XCTAssertEqual(
            try preparedIntrinsic.fetchExactlyOneValues(
                bindings: intrinsicBindings
            ),
            [.integer(7)]
        )
    }

    func testDocumentationCustomFunctionRegistrationAndExecution() throws {
        try testExample_CustomFunction()
    }

    func testDocumentationConditionalAndScalarFunctions() throws {
        try testExample_Iif()
        try testExample_SwitchCaseWhenThen()
        try testExample_SwitchCaseWhenThenElse()
        try testExample_IfCaseWhenThen()
        try testExample_IfCaseWhenThenElse()
    }

    func testDocumentationQueriesJoinsAggregatesPaginationSubqueriesCompoundsAndCTEs() throws {
        try testExample_LeftJoin_Statement_NullRows()
        try testExample_Subquery()

        let _: (XLExecutionTests) -> () throws -> Void = XLExecutionTests.testGroupConcatVariants
        let _: (XLExecutionTests) -> () throws -> Void = XLExecutionTests.testQueryBuilderLimitAndOffsetExecution
        let _: (XLExecutionTests) -> () throws -> Void = XLExecutionTests.testUnion
        let _: (XLExecutionTests) -> () throws -> Void = XLExecutionTests.testScalarRecursiveCommonTableExpression
        let _: (XLExecutionTests) -> () throws -> Void = XLExecutionTests.testRecursiveCommonTableExpressionUsingCommonTableExpression
    }

    func testDocumentationLiveQueryPublishers() throws {
        let idParameter = XLNamedBindingReference<String>(name: "id")
        let personByID = sql { schema in
            let person = schema.table(Person.self)
            Select(person)
            From(person)
            Where(person.id == idParameter)
        }
        let request = database.makeRequest(with: personByID)
        let layout = request.parameterLayout
        let expectedPerson = johnDoe
        let idBindings = try XLInvocationBindings<XLSQLiteValue>(
            layout: layout,
            bindings: [
                try XLInvocationBinding(
                    slot: try XCTUnwrap(
                        layout.slot(for: .named("id"))
                    ),
                    value: .text(expectedPerson.id)
                )
            ]
        ).validatingComplete()

        let initialValue = expectation(
            description: "packet-backed publisher emits the selected person"
        )
        let refreshedValue = expectation(
            description: "packet-backed publisher reuses the packet on refresh"
        )
        initialValue.assertForOverFulfill = false
        refreshedValue.assertForOverFulfill = false

        let cancellable = request.publish(bindings: idBindings).sink(
            receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    XCTFail("Packet-backed observation failed: \(error)")
                }
            },
            receiveValue: { rows in
                if rows == [expectedPerson] {
                    initialValue.fulfill()
                }
                else if rows.isEmpty {
                    refreshedValue.fulfill()
                }
                else {
                    XCTFail("Unexpected packet-backed rows: \(rows)")
                }
            }
        )
        defer { cancellable.cancel() }

        wait(for: [initialValue], timeout: 2)
        try databasePool.write { database in
            try database.execute(
                sql: "DELETE FROM Person WHERE id = ?",
                arguments: [expectedPerson.id]
            )
        }
        wait(for: [refreshedValue], timeout: 2)

        let _: (XLPublisherTests) -> () throws -> Void = XLPublisherTests.testPublishExistingEntities
        let _: (XLPublisherTests) -> () throws -> Void = XLPublisherTests.testPublishOneObservesDirectWrites
        let _: (XLPublisherTests) -> () throws -> Void = XLPublisherTests.testCancellationStopsObservationFetchesAndValues
        let _: (XLGRDBLiveQueryRetryTests) -> () throws -> Void =
            XLGRDBLiveQueryRetryTests
                .testRealGRDBObservationRecoversFromInjectedBusyAndKeepsObserving
    }
}
