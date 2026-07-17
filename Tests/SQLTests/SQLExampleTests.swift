//
//  SQLExampleTests.swift
//  
//
//  Created by Luke Van In on 2023/08/22.
//

import Foundation
import XCTest
import GRDB
import SwiftQL


struct MyUUID: XLCustomType, XLComparable, Equatable {

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

    public init(reader: XLColumnReader, at index: Int) throws {
        let rawValue = try reader.readText(at: index)
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
        formatter.timeZone = .gmt
        return formatter
    }()

    public init(reader: XLColumnReader, at index: Int) throws {
        let rawValue = try reader.readReal(at: index)
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
        formatter.timeZone = .gmt
        return formatter
    }()
    
    public typealias T = Self
    
    // Decode the date from a SwiftQL result.
    public init(reader: XLColumnReader, at index: Int) throws {
        let rawValue = try reader.readReal(at: index)
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
        let fileURL = directory.appending(path: filename, directoryHint: .notDirectory).appendingPathExtension("sqlite")
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
        var request = database.makeRequest(with: statement)
        request.set(myLatitude, -33.877873677687894)
        request.set(myLongitude, 18.488075015723)
        let rows = try request.fetchAll()
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

    func testDocumentationREADME() {
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
    }

    func testDocumentationQuickStart() throws {
        testDocumentationREADME()
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
        var fredRequest = peopleByNameRequest
        fredRequest.set(nameParameter, "Fred")
        XCTAssertEqual(try fredRequest.fetchAll(), [fredPerson])

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
        var fredAgeRequest = database.makeRequest(with: updateAgeStatement)
        fredAgeRequest.set(personIDParameter, "fred")
        fredAgeRequest.set(ageParameter, 42)
        try fredAgeRequest.execute()

        var updatedFredRequest = peopleByNameRequest
        updatedFredRequest.set(nameParameter, "Fred")
        XCTAssertEqual(
            try updatedFredRequest.fetchOne(),
            Person(id: "fred", occupationId: nil, name: "Fred", age: 42)
        )

        let deleteIDParameter = XLNamedBindingReference<String>(name: "id")
        let deletePersonStatement = sql { schema in
            let person = schema.into(Person.self)
            Delete(person)
            Where(person.id == deleteIDParameter)
        }
        var deleteFredRequest = database.makeRequest(with: deletePersonStatement)
        deleteFredRequest.set(deleteIDParameter, "fred")
        try deleteFredRequest.execute()

        var deletedFredRequest = peopleByNameRequest
        deletedFredRequest.set(nameParameter, "Fred")
        XCTAssertNil(try deletedFredRequest.fetchOne())
    }

    func testDocumentationExpressions() throws {
        try testExample_Coalesce()
        try testExample_IfCaseWhenThenElse()

        let _: (XLExecutionTests) -> () throws -> Void = XLExecutionTests.testSelectWhereLike
        let _: (XLExecutionTests) -> () throws -> Void = XLExecutionTests.testSelectWhereIn
        let _: (XLSyntaxTests) -> () -> Void = XLSyntaxTests.test_TextBinding_In_Subquery
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
        var request = database.makeRequest(with: runningJobs)
        request.set(stateParameter, .running)

        XCTAssertEqual(
            try request.fetchAll(),
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
        try testExample_Variable_ExplicitAlias()
        try testExample_LeftJoin_Functional_NullRows()

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

        let _: (XLExecutionTests) -> () throws -> Void = XLExecutionTests.testStringToDataRoundTrip
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

    func testDocumentationLiveQueryPublishers() {
        let _: (XLPublisherTests) -> () throws -> Void = XLPublisherTests.testPublishExistingEntities
        let _: (XLPublisherTests) -> () throws -> Void = XLPublisherTests.testPublishOneObservesDirectWrites
        let _: (XLPublisherTests) -> () throws -> Void = XLPublisherTests.testCancellationStopsObservationFetchesAndValues
        let _: (XLGRDBLiveQueryRetryTests) -> () throws -> Void =
            XLGRDBLiveQueryRetryTests
                .testRealGRDBObservationRecoversFromInjectedBusyAndKeepsObserving
    }
}
