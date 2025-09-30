//
//  File.swift
//  
//
//  Created by Luke Van In on 2023/08/22.
//

import XCTest
import GRDB
import SwiftQL


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


@SQLTable struct PersonOccupation: Equatable {

    let person: String
    
    let occupation: String
}


@SQLTable struct OccupationColor: Equatable {

    let occupation: String
    
    let color: String
}


@SQLTable struct OccupationOptionalColor: Equatable {

    let occupation: String
    
    let color: String?
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


extension Date: XLCustomType, XLEquatable, XLComparable {
    
    // Define a formatter to use to encode and decode the date.
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        formatter.timeZone = .gmt
        return formatter
    }()
    
    public typealias T = Self
    
    // Decode the date from an XL result.
    public init(reader: XLColumnReader, at index: Int) {
        let rawValue = reader.readReal(at: index)
        self = Date(julianDay: rawValue)!
    }
    
    // Bind the date to an XL expression.
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
    
    // Define the function signature. XLite uses the name and number of parameters to differentiate functions.
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
    
    // Define how the function is formatted into an XL expression.
    public func makeSQL(context: inout XLBuilder) {
        context.simpleFunction(name: Self.definition.name) { context in
            context.listItem(expression: fromLatitude.makeSQL)
            context.listItem(expression: fromLongitude.makeSQL)
            context.listItem(expression: toLatitude.makeSQL)
            context.listItem(expression: toLongitude.makeSQL)
        }
    }
    
    // Define the implementation details for how the function works. This is called at runtime from XL, and the results
    // are returned to XL.
    public static func execute(reader: XLColumnReader) throws -> Double {
        let latA = radians(degrees: reader.readReal(at: 0))
        let lonA = radians(degrees: reader.readReal(at: 1))
        let latB = radians(degrees: reader.readReal(at: 2))
        let lonB = radians(degrees: reader.readReal(at: 3))
        return acos(sin(latA) * sin(latB) + cos(latA) * cos(latB) * cos(lonB - lonA)) * 6371
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
        var config = Configuration()
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
            let result = result {
                OccupationCount.SQLReader(
                    occupation: occupation.name,
                    numberOfPeople: subquery {
                        select(person.id.count()).from(person).where(person.occupationId == occupation.id)
                    }
                )
            }
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
    
    func testExample_Iif() throws {
        let statement = sqlQuery { schema in
            let person = schema.table(Person.self)
            let occupation = schema.nullableTable(Occupation.self)
            let result = result {
                PersonOccupation.SQLReader(
                    person: person.name,
                    occupation: iif(occupation.name.isNull(), then: "Unemployed", else: "Employed")
                )
            }
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
            let result = result {
                PersonOccupation.SQLReader(
                    person: person.name,
                    occupation: occupation.name.coalesce("No occupation")
                )
            }
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
            let result = result {
                OccupationOptionalColor.SQLReader(
                    occupation: occupation.name,
                    color: switchCase(occupation.name)
                        .when("Engineer", then: "Red")
                        .when("Scientist", then: "Blue")
                )
            }
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
            let result = result {
                OccupationColor.SQLReader(
                    occupation: occupation.name,
                    color: switchCase(occupation.name)
                        .when("Engineer", then: "Red")
                        .when("Scientist", then: "Blue")
                        .else("Green")
                )
            }
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
            let result = result {
                OccupationOptionalColor.SQLReader(
                    occupation: occupation.name,
                    color: when(occupation.name == "Artist", then: "Cyan")
                )
            }
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
            let result = result {
                OccupationColor.SQLReader(
                    occupation: occupation.name,
                    color: when(occupation.name == "Artist", then: "Cyan").else("Magenta")
                )
            }
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
            let result = result {
                NearbyRestaurant.SQLReader(
                    name: restaurant.name,
                    distance: HaversineDistance(
                        fromLatitude: myLatitude,
                        fromLongitude: myLongitude,
                        toLatitude: restaurant.latitude,
                        toLongitude: restaurant.longitude
                    ).rounded(to: 2)
                )
            }
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
            let result = result {
                EventDuration.SQLReader(
                    name: event.name,
                    startDate: event.startDate,
                    endDate: event.endDate,
                    duration: (event.endDate - event.startDate)
                )
            }
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
