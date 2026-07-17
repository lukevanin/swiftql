//
//  SQLExecutionTests.swift
//  
//
//  Created by Luke Van In on 2023/07/31.
//

import Foundation
import XCTest
import GRDB
import SwiftQL

@SQLResult
struct ColumnsResultShadowingProjection: Equatable {
    let id: String
    let result: Int
}

final class XLExecutionTests: XCTestCase {
    
    var encoder: XLiteEncoder!
    var databasePool: DatabasePool!
    var database: GRDBDatabase!
    
    override func setUp() {
        let formatter = XLiteFormatter(
            identifierFormattingOptions: .mysqlCompatible
        )
        let directory = FileManager.default.temporaryDirectory
        let filename = UUID().uuidString
        let fileURL = directory.appending(path: filename, directoryHint: .notDirectory).appendingPathExtension("sqlite")
        print("Connecting to database \(fileURL.path)")
        encoder = XLiteEncoder(formatter: formatter)
        databasePool = try! DatabasePool(path: fileURL.path)
        database = try! GRDBDatabase(databasePool: databasePool, formatter: formatter, logger: nil)
    }
    
    override func tearDown() {
        encoder = nil
        databasePool = nil
        database = nil
    }
    
    
    // MARK: - Query functions

    func testGeneratedColumnsSupportsAResultNamedPropertyAndBinding() throws {
        try createTestTable()
        try insertTest(TestTable(id: "bar", value: 42))

        let id = XLNamedBindingReference<String>(name: "id")
        let statement = sql { schema in
            let table = schema.table(TestTable.self)
            Select(
                ColumnsResultShadowingProjection.columns(
                    id: table.id,
                    result: table.value
                )
            )
            From(table)
            Where(table.id == id)
        }
        var request = database.makeRequest(with: statement)
        request.set(id, "bar")

        XCTAssertEqual(
            try request.fetchOne(),
            ColumnsResultShadowingProjection(id: "bar", result: 42)
        )
    }

    func testNestedUnaryOperatorExecution() throws {
        let x = XLNamedBindingReference<Int>(name: "x")
        let doubleNegation = sql { _ in
            Select(-(-x))
        }
        var doubleNegationRequest = database.makeRequest(with: doubleNegation)
        doubleNegationRequest.set(x, 7)
        XCTAssertEqual(try doubleNegationRequest.fetchOne(), 7)

        let a = XLNamedBindingReference<Int>(name: "a")
        let b = XLNamedBindingReference<Int>(name: "b")
        let compoundNegation = sql { _ in
            Select(-(a + b))
        }
        var compoundNegationRequest = database.makeRequest(with: compoundNegation)
        compoundNegationRequest.set(a, 7)
        compoundNegationRequest.set(b, 5)
        XCTAssertEqual(try compoundNegationRequest.fetchOne(), -12)
    }

    func testBitwiseNotExecutesForIntegerLiteralsColumnsAndComposedExpressions() throws {
        let literal: any XLExpression<Int> = 12
        let literalStatement = sql { _ in
            Select(~literal)
        }
        XCTAssertEqual(
            try database.makeRequest(with: literalStatement).fetchOne(),
            -13
        )

        try createTestTable()
        try insertTest(TestTable(id: "bitwise", value: 42))

        let columnStatement = sql { schema in
            let table = schema.table(TestTable.self)
            Select(~table.value)
            From(table)
            Where(table.id == "bitwise")
        }
        XCTAssertEqual(
            try database.makeRequest(with: columnStatement).fetchOne(),
            -43
        )

        let composedStatement = sql { schema in
            let table = schema.table(TestTable.self)
            Select(~(table.value + 5))
            From(table)
            Where(table.id == "bitwise")
        }
        XCTAssertEqual(
            try database.makeRequest(with: composedStatement).fetchOne(),
            -48
        )
    }

    func testBuiltInCollationExecution() throws {
        let lhs = XLNamedBindingReference<String>(name: "lhs")
        let rhs = XLNamedBindingReference<String>(name: "rhs")

        func compare(
            _ collation: XLCollation,
            lhs lhsValue: String,
            rhs rhsValue: String
        ) throws -> Bool? {
            let statement = sql { _ in
                Select(lhs.collate(collation) == rhs)
            }
            var request = database.makeRequest(with: statement)
            request.set(lhs, lhsValue)
            request.set(rhs, rhsValue)
            return try request.fetchOne()
        }

        XCTAssertEqual(
            try compare(.binary, lhs: "alpha", rhs: "ALPHA"),
            false
        )
        XCTAssertEqual(
            try compare(.nocase, lhs: "alpha", rhs: "ALPHA"),
            true
        )
        XCTAssertEqual(
            try compare(.rtrim, lhs: "alpha ", rhs: "alpha"),
            true
        )
    }

    func testConcatenationCollationExecution() throws {
        let lhs = XLNamedBindingReference<String>(name: "lhs")
        let rhs = XLNamedBindingReference<String>(name: "rhs")

        let collatedOperand = sql { _ in
            Select((lhs.collate(.rtrim) + rhs) == "a")
        }
        var collatedOperandRequest = database.makeRequest(with: collatedOperand)
        collatedOperandRequest.set(lhs, "a ")
        collatedOperandRequest.set(rhs, "")
        XCTAssertEqual(try collatedOperandRequest.fetchOne(), true)

        let collatedResult = sql { _ in
            Select(
                (lhs.collate(.rtrim) + rhs)
                    .collate(.nocase) == "a"
            )
        }
        var collatedResultRequest = database.makeRequest(with: collatedResult)
        collatedResultRequest.set(lhs, "a ")
        collatedResultRequest.set(rhs, "")
        // The outer NOCASE collation must override the nested RTRIM collation;
        // unlike RTRIM, NOCASE does not ignore the trailing space.
        XCTAssertEqual(try collatedResultRequest.fetchOne(), false)
    }

    func testGroupConcatVariants() throws {
        try database.makeRequest(with: sqlCreate(CompanyTable.self)).execute()
        for company in [
            CompanyTable(id: "beta-1", name: "Beta"),
            CompanyTable(id: "alpha", name: "Alpha"),
            CompanyTable(id: "beta-2", name: "Beta"),
        ] {
            try database.makeRequest(with: sqlInsert(company)).execute()
        }

        let defaultStatement = sql { schema in
            let company = schema.table(CompanyTable.self)
            Select(company.name.groupConcatOrNull())
            From(company)
        }
        let defaultResult = try XCTUnwrap(try database.makeRequest(with: defaultStatement).fetchOne() ?? nil)
        XCTAssertEqual(defaultResult.split(separator: ",").map(String.init).sorted(), ["Alpha", "Beta", "Beta"])

        let distinctStatement = sql { schema in
            let company = schema.table(CompanyTable.self)
            Select(company.name.groupConcatOrNull(distinct: true))
            From(company)
        }
        let distinctResult = try XCTUnwrap(try database.makeRequest(with: distinctStatement).fetchOne() ?? nil)
        XCTAssertEqual(distinctResult.split(separator: ",").map(String.init).sorted(), ["Alpha", "Beta"])

        let separatorStatement = sql { schema in
            let company = schema.table(CompanyTable.self)
            Select(company.name.groupConcatOrNull(separator: "|"))
            From(company)
        }
        let separatorResult = try XCTUnwrap(try database.makeRequest(with: separatorStatement).fetchOne() ?? nil)
        XCTAssertEqual(separatorResult.split(separator: "|").map(String.init).sorted(), ["Alpha", "Beta", "Beta"])
    }


    func testQueryBuilderLimitAndOffsetExecution() throws {
        try createTestTable()
        let rows = [
            TestTable(id: "one", value: 10),
            TestTable(id: "two", value: 20),
            TestTable(id: "three", value: 30),
            TestTable(id: "four", value: 40),
        ]
        for row in rows {
            try insertTest(row)
        }

        let literalSchema = XLSchema()
        let literalTable = literalSchema.table(TestTable.self)
        let literalStatement = try QueryBuilder(select: literalTable)
            .from(literalTable)
            .orderBy(literalTable.value.ascending())
            .limit(2)
            .build()
        let literalResult = try database.makeRequest(with: literalStatement).fetchAll()
        XCTAssertEqual(literalResult, Array(rows[0 ..< 2]))

        let numericSchema = XLSchema()
        let numericTable = numericSchema.table(TestTable.self)
        let numericStatement = try QueryBuilder(select: numericTable)
            .from(numericTable)
            .orderBy(numericTable.value.ascending())
            .limit(2.0)
            .offset(1.0)
            .build()
        let numericResult = try database.makeRequest(with: numericStatement).fetchAll()
        XCTAssertEqual(numericResult, Array(rows[1 ... 2]))

        let unboundedSchema = XLSchema()
        let unboundedTable = unboundedSchema.table(TestTable.self)
        let unboundedStatement = try QueryBuilder(select: unboundedTable)
            .from(unboundedTable)
            .orderBy(unboundedTable.value.ascending())
            .limit(-1)
            .offset(2)
            .build()
        let unboundedResult = try database.makeRequest(with: unboundedStatement).fetchAll()
        XCTAssertEqual(unboundedResult, Array(rows[2...]))

        let limit = XLNamedBindingReference<Int>(name: "limit")
        let offset = XLNamedBindingReference<Int>(name: "offset")
        let boundSchema = XLSchema()
        let boundTable = boundSchema.table(TestTable.self)
        let boundStatement = try QueryBuilder(select: boundTable)
            .from(boundTable)
            .orderBy(boundTable.value.ascending())
            .limit(limit)
            .offset(offset)
            .build()
        var boundRequest = database.makeRequest(with: boundStatement)
        boundRequest.set(limit, 2)
        boundRequest.set(offset, 1)
        let boundResult = try boundRequest.fetchAll()
        XCTAssertEqual(boundResult, Array(rows[1 ... 2]))
    }
    
    func testSelect() throws {
        try createTestTable()
        try insertTest(TestTable(id: "foo", value: 9000))
        try insertTest(TestTable(id: "bar", value: 42))
        try insertTest(TestTable(id: "baz", value: 100))
        
        let statement = sql { s in
            let t = s.table(TestTable.self)
            Select(t)
            From(t)
        }
        let results = try database.makeRequest(with: statement).fetchAll()
        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results[0], TestTable(id: "foo", value: 9000))
        XCTAssertEqual(results[1], TestTable(id: "bar", value: 42))
        XCTAssertEqual(results[2], TestTable(id: "baz", value: 100))
    }
    
    
    func testSelectWhere() throws {
        try createTestTable()
        try insertTest(TestTable(id: "foo", value: 9000))
        try insertTest(TestTable(id: "bar", value: 42))
        try insertTest(TestTable(id: "baz", value: 100))
        
        let statement = sql { s in
            let t = s.table(TestTable.self)
            Select(t)
            From(t)
            Where(t.id == "bar")
        }
        let request = database.makeRequest(with: statement)
        let results = try request.fetchAll()
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0], TestTable(id: "bar", value: 42))
    }


    func testSelectWhereLargeIntegerLiteral() throws {
        try createTestTable()
        try insertTest(TestTable(id: "max", value: Int(Int64.max)))
        try insertTest(TestTable(id: "min", value: Int(Int64.min)))
        try insertTest(TestTable(id: "timestamp", value: 1_752_000_000_000))

        let statement = sql { s in
            let t = s.table(TestTable.self)
            Select(t)
            From(t)
            Where(t.value == 1_752_000_000_000)
        }
        let results = try database.makeRequest(with: statement).fetchAll()
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0], TestTable(id: "timestamp", value: 1_752_000_000_000))

        let maxStatement = sql { s in
            let t = s.table(TestTable.self)
            Select(t)
            From(t)
            Where(t.value == Int(Int64.max))
        }
        let maxResults = try database.makeRequest(with: maxStatement).fetchAll()
        XCTAssertEqual(maxResults.count, 1)
        XCTAssertEqual(maxResults[0], TestTable(id: "max", value: Int(Int64.max)))

        let minStatement = sql { s in
            let t = s.table(TestTable.self)
            Select(t)
            From(t)
            Where(t.value == Int(Int64.min))
        }
        let minResults = try database.makeRequest(with: minStatement).fetchAll()
        XCTAssertEqual(minResults.count, 1)
        XCTAssertEqual(minResults[0], TestTable(id: "min", value: Int(Int64.min)))
    }


    func testSelectWhereStringContainingQuote() throws {
        try createTestTable()
        try insertTest(TestTable(id: "O'Brien", value: 1))
        try insertTest(TestTable(id: "plain", value: 2))

        let statement = sql { s in
            let t = s.table(TestTable.self)
            Select(t)
            From(t)
            Where(t.id == "O'Brien")
        }
        let results = try database.makeRequest(with: statement).fetchAll()
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0], TestTable(id: "O'Brien", value: 1))
    }


    func testSelectWhereInjectionAttemptMatchesNothing() throws {
        try createTestTable()
        try insertTest(TestTable(id: "foo", value: 1))
        try insertTest(TestTable(id: "bar", value: 2))

        let statement = sql { s in
            let t = s.table(TestTable.self)
            Select(t)
            From(t)
            Where(t.id == "x' OR '1'='1")
        }
        let results = try database.makeRequest(with: statement).fetchAll()
        XCTAssertEqual(results.count, 0)
    }


    func testSelectWhereLike() throws {
        try createTestTable()
        try insertTest(TestTable(id: "foo", value: 9000))
        try insertTest(TestTable(id: "bar", value: 42))
        try insertTest(TestTable(id: "baz", value: 100))
        
        let statement = sql { s in
            let t = s.table(TestTable.self)
            Select(t)
            From(t)
            Where(t.id.like("b%"))
        }
        let request = database.makeRequest(with: statement)
        let results = try request.fetchAll()
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0], TestTable(id: "bar", value: 42))
        XCTAssertEqual(results[1], TestTable(id: "baz", value: 100))
    }
    
    
    func testSelectWhereVariable() throws {
        try createTestTable()
        try insertTest(TestTable(id: "foo", value: 9000))
        try insertTest(TestTable(id: "bar", value: 42))
        try insertTest(TestTable(id: "baz", value: 100))
        
        let idParameter = XLNamedBindingReference<String>(name: "id")
        let statement = sql { s in
            let t = s.table(TestTable.self)
            Select(t)
            From(t)
            Where(t.id == idParameter)
        }
        
        var request0 = database.makeRequest(with: statement)
        request0.set(parameter: idParameter, value: "baz")
        
        var request1 = database.makeRequest(with: statement)
        request1.set(parameter: idParameter, value: "foo")
        
        let results0 = try request0.fetchAll()
        let results1 = try request1.fetchAll()
        
        XCTAssertEqual(results0.count, 1)
        XCTAssertEqual(results0[0], TestTable(id: "baz", value: 100))
        XCTAssertEqual(results1.count, 1)
        XCTAssertEqual(results1[0], TestTable(id: "foo", value: 9000))
    }
    

    func testSelectWhereIn() throws {
        try createTestTable()
        try insertTest(TestTable(id: "foo", value: 9000))
        try insertTest(TestTable(id: "bar", value: 42))
        try insertTest(TestTable(id: "baz", value: 100))
        
        let statement = sql { s in
            let t = s.table(TestTable.self)
            Select(t)
            From(t)
            Where(t.value.in([9000, 100]))
        }
        let request = database.makeRequest(with: statement)
        let results = try request.fetchAll()
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0], TestTable(id: "foo", value: 9000))
        XCTAssertEqual(results[1], TestTable(id: "baz", value: 100))
    }
    
    
    func testSelectWhereInParameter() throws {
        try createTestTable()
        try insertTest(TestTable(id: "foo", value: 9000))
        try insertTest(TestTable(id: "bar", value: 42))
        try insertTest(TestTable(id: "baz", value: 100))
        
        let parameter = XLNamedBindingReference<String>(name: "p")
        
        let statement = sql { s in
            let t = s.table(TestTable.self)
            Select(t)
            From(t)
            Where(t.id.in(["goo", parameter]))
        }
        
        var request = database.makeRequest(with: statement)
        request.set(parameter: parameter, value: "foo")

        let results = try request.fetchAll()
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0], TestTable(id: "foo", value: 9000))
    }
    
    
    func testSelectWhereEqualToNullOptionalParameter() throws {
        try createEmployeeTable()
        try insertEmployee(EmployeeTable(id: "emp01", name: "Boss", companyId: nil, managerEmployeeId: nil))
        try insertEmployee(EmployeeTable(id: "emp02", name: "Whip", companyId: nil, managerEmployeeId: "emp01"))
        try insertEmployee(EmployeeTable(id: "emp03", name: "Slave", companyId: nil, managerEmployeeId: "emp01"))

        let parameter = XLNamedBindingReference<Optional<String>>(name: "p")
        
        let statement = sql { s in
            let t = s.table(EmployeeTable.self)
            Select(t)
            From(t)
            Where(t.managerEmployeeId == parameter)
        }
        
        var request = database.makeRequest(with: statement)
        request.set(parameter: parameter, value: nil)
        
        let results = try request.fetchAll()
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0], EmployeeTable(id: "emp01", name: "Boss", companyId: nil, managerEmployeeId: nil))
    }
    
    
    func testSelectWhereEqualToOptionalParameter() throws {
        try createEmployeeTable()
        try insertEmployee(EmployeeTable(id: "emp01", name: "Boss", companyId: nil, managerEmployeeId: nil))
        try insertEmployee(EmployeeTable(id: "emp02", name: "Whip", companyId: nil, managerEmployeeId: "emp01"))
        try insertEmployee(EmployeeTable(id: "emp03", name: "Slave", companyId: nil, managerEmployeeId: "emp01"))

        let parameter = XLNamedBindingReference<Optional<String>>(name: "p")
        
        let statement = sql { s in
            let t = s.table(EmployeeTable.self)
            Select(t)
            From(t)
            Where(t.managerEmployeeId == parameter)
        }
        
        var request = database.makeRequest(with: statement)
        request.set(parameter: parameter, value: nil)
        
        let results = try request.fetchAll()
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0], EmployeeTable(id: "emp01", name: "Boss", companyId: nil, managerEmployeeId: nil))
    }
    
    
    func testSelectWhereOptionalIsNotNull() throws {
        try createEmployeeTable()
        try insertEmployee(EmployeeTable(id: "emp01", name: "Boss", companyId: nil, managerEmployeeId: nil))
        try insertEmployee(EmployeeTable(id: "emp02", name: "Whip", companyId: nil, managerEmployeeId: "emp01"))
        try insertEmployee(EmployeeTable(id: "emp03", name: "Slave", companyId: nil, managerEmployeeId: "emp01"))
        
        let statement = sql { s in
            let t = s.table(EmployeeTable.self)
            Select(t)
            From(t)
            Where(t.managerEmployeeId.notNull())
        }
        
        let request = database.makeRequest(with: statement)
        
        let results = try request.fetchAll()
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0], EmployeeTable(id: "emp02", name: "Whip", companyId: nil, managerEmployeeId: "emp01"))
        XCTAssertEqual(results[1], EmployeeTable(id: "emp03", name: "Slave", companyId: nil, managerEmployeeId: "emp01"))
    }
    
    
    func testSelectWhereOptionalIsNull() throws {
        try createEmployeeTable()
        try insertEmployee(EmployeeTable(id: "emp01", name: "Boss", companyId: nil, managerEmployeeId: nil))
        try insertEmployee(EmployeeTable(id: "emp02", name: "Whip", companyId: nil, managerEmployeeId: "emp01"))
        try insertEmployee(EmployeeTable(id: "emp03", name: "Slave", companyId: nil, managerEmployeeId: "emp01"))
        
        let statement = sql { s in
            let t = s.table(EmployeeTable.self)
            Select(t)
            From(t)
            Where(t.managerEmployeeId.isNull())
        }
        
        let request = database.makeRequest(with: statement)
        
        let results = try request.fetchAll()
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0], EmployeeTable(id: "emp01", name: "Boss", companyId: nil, managerEmployeeId: nil))
    }
    
    
//    func testSelectWhereInSubquery() throws {
//        try createEmployeeTable()
//        try insertEmployee(EmployeeTable(id: "bos01", name: "Big Boss", managerEmployeeId: nil))
//        try insertEmployee(EmployeeTable(id: "bos02", name: "Little Boss", managerEmployeeId: nil))
//        try insertEmployee(EmployeeTable(id: "emp02", name: "Whip", managerEmployeeId: "bos01"))
//        try insertEmployee(EmployeeTable(id: "emp03", name: "Slave", managerEmployeeId: "bos02"))
//        
//        let statement = sqlQuery {
//            let t = $0.table(EmployeeTable.self, as: "t")
//            Select(t)
//            From(t)
//            Where {
//                t.managerEmployeeId.in {
//                    let t = $0.table(EmployeeTable.self, as: "t")
//                    Select { t.id }
//                    From(t)
//                    Where { t.managerEmployeeId.isNull() }
//                }
//            }
//        }
//        
//        let request = database.makeRequest(with: statement)
//        
//        let results = try request.fetchAll()
//        XCTAssertEqual(results.count, 2)
//        XCTAssertEqual(results[0], EmployeeTable(id: "emp02", name: "Whip", managerEmployeeId: "bos01"))
//        XCTAssertEqual(results[1], EmployeeTable(id: "emp03", name: "Slave", managerEmployeeId: "bos02"))
//    }
    
    
    // MARK: Scalar SELECT
    
    func testScalarSelect() throws {
        
        try createTestTable()
        try insertTest(TestTable(id: "foo", value: 9000))
        try insertTest(TestTable(id: "bar", value: 42))
        try insertTest(TestTable(id: "baz", value: 100))
        
        let statement = sql { schema in
            let t = schema.table(TestTable.self)
            Select(t.value)
            From(t)
        }
        let results = try database.makeRequest(with: statement).fetchAll()
        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results[0], 9000)
        XCTAssertEqual(results[1], 42)
        XCTAssertEqual(results[2], 100)
    }


    // MARK: - Type cast

    func testStringToDataTypeofIsBlob() throws {
        let castSQL = encoder.makeSQL("abc".toData()).sql
        let typeName = try databasePool.read { db in
            try String.fetchOne(db, sql: "SELECT typeof(\(castSQL))")
        }
        XCTAssertEqual(typeName, "blob")
    }


    func testStringToDataRoundTrip() throws {
        try createTestTable()
        try insertTest(TestTable(id: "foo", value: 1))

        typealias Scalar = SQLScalarResult<Data>
        let statement = sql { schema in
            let t = schema.table(TestTable.self)
            Select(Scalar.columns(scalarValue: t.id.toData()))
            From(t)
        }
        let results = try database.makeRequest(with: statement).fetchAll()
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].scalarValue, Data("foo".utf8))
    }


    // MARK: - Recursive Common Table Expression
    
    func testScalarRecursiveCommonTableExpression() throws {

        // Create table.
        try database.makeRequest(with: sqlCreate(Org.self)).execute()
        
        // Insert org structure.
        let values = [
            Org(name: "Alice", boss: nil),
            Org(name: "Jane", boss: "Alice"),
            Org(name: "Rachel", boss: "Alice"),
            Org(name: "Cindy", boss: "Jane"),
            Org(name: "Candace", boss: "Jane"),
            Org(name: "Dick", boss: nil),
            Org(name: "Bob", boss: "Dick"),
        ]
        for value in values {
            try database.makeRequest(with: sqlInsert(value)).execute()
        }
        
        // Fetch all members in the org from Alice and below.
        typealias Scalar = SQLScalarResult<String?>
        let expression = sql { schema in
            let cte = schema.recursiveCommonTableExpression(Scalar.self) { schema, cte in
                let org = schema.table(Org.self)
                
                let initialResult = Scalar.columns(scalarValue: "Alice".toNullable())
                Select(initialResult)
                Union()
                Select(Scalar.columns(scalarValue: org.name))
                From(org)
                Join.Cross(cte)
                Where(org.boss == cte.scalarValue)
            }
            let org = schema.table(Org.self)
            With(cte)
            Select(org.name)
            From(org)
            Where(org.name.in(cte))
        }
        
        let finalResult = try database.makeRequest(with: expression).fetchAll()
        XCTAssertEqual(finalResult.count, 5)
        XCTAssertTrue(finalResult.contains("Alice"))
        XCTAssertTrue(finalResult.contains("Jane"))
        XCTAssertTrue(finalResult.contains("Rachel"))
        XCTAssertTrue(finalResult.contains("Cindy"))
        XCTAssertTrue(finalResult.contains("Candace"))
        XCTAssertFalse(finalResult.contains("Dick"))
        XCTAssertFalse(finalResult.contains("Bob"))
    }


    func testRecursiveCommonTableUsesDistinctAliasesForMatchingColumnNames() throws {
        try database.makeRequest(with: sqlCreate(Org.self)).execute()
        for value in [
            Org(name: "Alice", boss: nil),
            Org(name: "Jane", boss: "Alice"),
            Org(name: "Cindy", boss: "Jane"),
            Org(name: "Dick", boss: nil),
        ] {
            try database.makeRequest(with: sqlInsert(value)).execute()
        }

        let statement = sql { schema in
            let cte = schema.recursiveCommonTableExpression(Org.self) { schema, cte in
                let org = schema.table(Org.self)
                Select(Org.columns(name: "Alice".toNullable(), boss: Optional<String>.none))
                UnionAll()
                Select(Org.columns(name: org.name, boss: org.boss))
                From(org)
                Join.Inner(cte, on: org.boss == cte.name)
            }
            let names = schema.table(cte)
            With(cte)
            Select(names)
            From(names)
        }

        let result = try database.makeRequest(with: statement).fetchAll()
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(Set(result.compactMap(\.name)), Set(["Alice", "Jane", "Cindy"]))
    }
    
    
    func testRecursiveCommonTableExpressionUsingCommonTableExpression() throws {
        
        // Create the table
        try database.makeRequest(with: sqlCreate(Family.self)).execute()
        
        // Insert family tree.
        let familyMembers = [
            Family(name: "David", mom: nil, dad: nil, born: Date(string: "1930-03-13 11:00"), died: Date(string: "2010-11-27 21:00")),
            Family(name: "Mary", mom: nil, dad: "David", born: Date(string: "1960-10-17 23:00"), died: nil),
            Family(name: "Joe", mom: nil, dad: nil, born: Date(string: "1955-01-12 10:00"), died: nil),
            Family(name: "John", mom: "Mary", dad: "Joe", born: Date(string: "1980-09-15 09:00"), died: nil),
            Family(name: "Daniel", mom: "Mary", dad: "Joe", born: Date(string: "1982-03-03 13:00"), died: nil),
            Family(name: "Elisha", mom: "Mary", dad: "Joe", born: Date(string: "1985-07-22 18:00"), died: Date(string: "1987-11-27 03:00")),
            Family(name: "Kate", mom: nil, dad: nil, born: Date(string: "1965-12-03 22:00"), died: nil),
            Family(name: "Alice", mom: "Kate", dad: "John", born: Date(string: "2010-02-24 23:00"), died: nil),
            Family(name: "Candace", mom: "Kate", dad: "John", born: Date(string: "2015-04-19 15:00"), died: nil),
        ]
        for familyMember in familyMembers {
            print("Inserting family member", familyMember)
            try database.makeRequest(with: sqlInsert(familyMember)).execute()
        }

        // Fetch all of the living ancestors of Alice.
        typealias Scalar = SQLScalarResult<String?>
        let selectStatement = sql { schema in
            
            let parentOfCommonTable = schema.commonTableExpression { schema in
                let family = schema.table(Family.self)
                let momRow = FamilyMemberParent.columns(name: family.name, parent: family.mom)
                let dadRow = FamilyMemberParent.columns(name: family.name, parent: family.dad)
                Select(momRow)
                From(family)
                Union()
                Select(dadRow)
                From(family)
            }
            
            let ancestorOfAliceCommonTable = schema.recursiveCommonTableExpression(Scalar.self) { schema, this in
                let parentOf = schema.table(parentOfCommonTable)
                Select(Scalar.columns(scalarValue: parentOf.parent))
                From(parentOf)
                Where(parentOf.name == "Alice".toNullable())
                UnionAll()
                Select(Scalar.columns(scalarValue: parentOf.parent))
                From(parentOf)
                Join.Inner(this, on: this.scalarValue == parentOf.name)
            }
            
            let ancestorOfAlice = schema.table(ancestorOfAliceCommonTable)
            let family = schema.table(Family.self)
            With(parentOfCommonTable, ancestorOfAliceCommonTable)
            Select(family.name)
            From(ancestorOfAlice)
            Join.Cross(family)
            Where((ancestorOfAlice.scalarValue == family.name) && family.died.isNull())
            OrderBy(family.born.ascending())
        }
        
        let finalResult = try database.makeRequest(with: selectStatement).fetchAll()
        print("Living ancestors of alice", finalResult)
        XCTAssertEqual(finalResult.count, 4)
        XCTAssertTrue(finalResult.contains("Joe")) // Joe is John's father (Alice's grandfather).
        XCTAssertTrue(finalResult.contains("Mary")) // Mary is John's mother (Alice's grandmother.
        XCTAssertTrue(finalResult.contains("John")) // John is Alice's father.
        XCTAssertTrue(finalResult.contains("Kate")) // Kate is Alice's mother.
        XCTAssertFalse(finalResult.contains("David")) // David is Joe's deceased father (Alice's great-grandfather).
        XCTAssertFalse(finalResult.contains("Daniel")) // Daniel is John's brother (Alice's uncle).
        XCTAssertFalse(finalResult.contains("Elisha")) // Elisha is John's deceased sister (Alice's aunt).
        XCTAssertFalse(finalResult.contains("Candace")) // Candace is Alice's sister.
     }
    
    
    // MARK: - Union
    
    func testUnion() throws {
        
        let createStatement = sqlCreate(Family.self)
        try database.makeRequest(with: createStatement).execute()
        
        try database.makeRequest(with: sqlInsert(Family(name: "john", mom: "mary", dad: "joe", born: nil, died: nil))).execute()
        try database.makeRequest(with: sqlInsert(Family(name: "jane", mom: "alice", dad: "bob", born: nil, died: nil))).execute()

        let selectExpression = sql { schema in
            let familyMom = schema.table(Family.self)
            let familyDad = schema.table(Family.self)
            let momRow = FamilyMemberParent.columns(name: familyMom.name, parent: familyMom.mom)
            let dadRow = FamilyMemberParent.columns(name: familyDad.name, parent: familyDad.dad)
            Select(momRow)
            From(familyMom)
            Union()
            Select(dadRow)
            From(familyDad)
        }
        let finalResult = try database.makeRequest(with: selectExpression).fetchAll()
        XCTAssertEqual(finalResult.count, 4)
        XCTAssertTrue(finalResult.contains(FamilyMemberParent(name: "john", parent: "mary")))
        XCTAssertTrue(finalResult.contains(FamilyMemberParent(name: "john", parent: "joe")))
        XCTAssertTrue(finalResult.contains(FamilyMemberParent(name: "jane", parent: "alice")))
        XCTAssertTrue(finalResult.contains(FamilyMemberParent(name: "jane", parent: "bob")))
    }
    
    
    func testUnionOrderBy() throws {
        
        let createStatement = sqlCreate(Family.self)
        try database.makeRequest(with: createStatement).execute()
        
        try database.makeRequest(with: sqlInsert(Family(name: "john", mom: "mary", dad: "joe", born: nil, died: nil))).execute()
        try database.makeRequest(with: sqlInsert(Family(name: "jane", mom: "alice", dad: "bob", born: nil, died: nil))).execute()

        let selectExpression: any XLQueryStatement<FamilyMemberParent> = sql { schema in
            let familyMom = schema.table(Family.self)
            let familyDad = schema.table(Family.self)
            let momRow = FamilyMemberParent.columns(name: familyMom.name, parent: familyMom.mom)
            let dadRow = FamilyMemberParent.columns(name: familyDad.name, parent: familyDad.dad)
            Select(momRow)
            From(familyMom)
            Union()
            Select(dadRow)
            From(familyDad)
            OrderBy(momRow.name.ascending(), momRow.parent.ascending())
            Limit(1)
        }
        let finalResult = try database.makeRequest(with: selectExpression).fetchAll()
        XCTAssertEqual(finalResult.count, 1)
        XCTAssertEqual(try finalResult.element(at: 0), FamilyMemberParent(name: "jane", parent: "alice"))
    }
    
    
    // MARK: - CREATE TABLE
    
    func testCreateTable() throws {
        let createStatement = sqlCreate(TestTable.self)
        try database.makeRequest(with: createStatement).execute()
        
        let insertStatement = sqlInsert(TestTable(id: "foo", value: 69))
        try database.makeRequest(with: insertStatement).execute()
        
        let selectStatement = sql { schema in
            let table = schema.table(TestTable.self)
            Select(table)
            From(table)
        }
        let finalResult = try database.makeRequest(with: selectStatement).fetchOne()
        XCTAssertNotNil(finalResult)
    }
    
    func testCreateNullablesTable() throws {
        let createStatement = sqlCreate(TestNullablesTable.self)
        try database.makeRequest(with: createStatement).execute()
        
        let insertStatement = sqlInsert(TestNullablesTable(id: "foo", value: nil))
        try database.makeRequest(with: insertStatement).execute()
        
        let selectStatement = sql { schema in
            let table = schema.table(TestNullablesTable.self)
            Select(table)
            From(table)
        }
        let finalResult = try database.makeRequest(with: selectStatement).fetchOne()
        XCTAssertNotNil(finalResult)
    }
    
    func testCreateGenericTableWithStringValue() throws {
        let createStatement = sqlCreate(GenericTable<String>.self)
        try database.makeRequest(with: createStatement).execute()
        
        let insertStatement = sqlInsert(GenericTable(id: "foo", type: "name", value: "Foo"))
        try database.makeRequest(with: insertStatement).execute()
        
        let selectStatement = sql { schema in
            let table = schema.table(GenericTable<String>.self)
            Select(table)
            From(table)
            Where(table.type == "name")
        }
        let finalResult = try database.makeRequest(with: selectStatement).fetchOne()
        XCTAssertNotNil(finalResult)
    }
    
    func testCreateGenericTableWithObjectValue() throws {
        let testValue = UUID()
        
        let createStatement = sqlCreate(GenericTable<MyUUID>.self)
        try database.makeRequest(with: createStatement).execute()
        
        let insertStatement = sqlInsert(GenericTable(id: "foo", type: "id", value: MyUUID(testValue)))
        try database.makeRequest(with: insertStatement).execute()

        let selectStatement = sql { schema in
            let table = schema.table(GenericTable<MyUUID>.self)
            Select(table)
            From(table)
            Where(table.type == "id")
        }
        let finalResult = try database.makeRequest(with: selectStatement).fetchOne()
        XCTAssertNotNil(finalResult)
        XCTAssertEqual(finalResult?.value, MyUUID(testValue))
    }
    
    
    // MARK: - CREATE TABLE ... AS SELECT
    
    func testCreateTableAsSelect() throws {
        
        try database.makeRequest(with: sqlCreate(EmployeeTable.self)).execute()
        
        let employeeInsertStatement = sqlInsert(EmployeeTable(id: "fred", name: "Fred", companyId: "acme", managerEmployeeId: nil))
        try database.makeRequest(with: employeeInsertStatement).execute()
        
        let tempCreateStatement = sql { schema in
            let t = schema.create(Temp.self)
            Create(t)
            As { schema in
                let employee = schema.table(EmployeeTable.self)
                let result = Temp.columns(
                    id: employee.id,
                    value: employee.name
                )
                Select(result)
                From(employee)
            }
        }
        try database.makeRequest(with: tempCreateStatement).execute()
        
        let selectStatement = sql { schema in
            let table = schema.table(Temp.self)
            Select(table)
            From(table)
        }
        let finalResult = try database.makeRequest(with: selectStatement).fetchOne()
        XCTAssertNotNil(finalResult)
        XCTAssertEqual(finalResult?.id, "fred")
        XCTAssertEqual(finalResult?.value, "Fred")
    }
    
    func testCreateTableAsSelectWithCommonTable() throws {
        
        try database.makeRequest(with: sqlCreate(EmployeeTable.self)).execute()
        
        let employeeInsertStatement = sqlInsert(EmployeeTable(id: "fred", name: "Fred", companyId: "acme", managerEmployeeId: nil))
        try database.makeRequest(with: employeeInsertStatement).execute()
        
        let tempCreateStatement = sql { schema in
            let t = schema.create(Temp.self)
            Create(t)
            As { schema in
                
                let cte = schema.commonTableExpression { schema in
                    let t = schema.table(EmployeeTable.self)
                    Select(t)
                    From(t)
                }
                
                let t = schema.table(cte)
                let r = Temp.columns(
                    id: t.id,
                    value: t.name
                )
                With(cte)
                Select(r)
                From(t)
            }
        }
        try database.makeRequest(with: tempCreateStatement).execute()
        
        let selectStatement = sql { schema in
            let table = schema.table(Temp.self)
            Select(table)
            From(table)
        }
        let finalResult = try database.makeRequest(with: selectStatement).fetchOne()
        XCTAssertNotNil(finalResult)
        XCTAssertEqual(finalResult?.id, "fred")
        XCTAssertEqual(finalResult?.value, "Fred")
    }
    
    
    // MARK: Insert
    
    func testInsertSelect() throws {
        
        let createCompanyTableStatement = sqlCreate(CompanyTable.self)
        try database.makeRequest(with: createCompanyTableStatement).execute()
        try database.makeRequest(with: sqlInsert(CompanyTable(id: "aapl", name: "Apple"))).execute()
        try database.makeRequest(with: sqlInsert(CompanyTable(id: "goog", name: "Google"))).execute()
        try database.makeRequest(with: sqlInsert(CompanyTable(id: "msft", name: "Microsoft"))).execute()

        let createTempTableExpression = sqlCreate(Temp.self)
        try database.makeRequest(with: createTempTableExpression).execute()
        
        let insertStatement = sql { schema in
            let temp = schema.table(Temp.self)
            let company = schema.table(CompanyTable.self)
            let row = Temp.columns(
                id: company.id,
                value: company.name + " Test"
            )
            Insert(temp)
            Select(row)
            From(company)
        }
        try database.makeRequest(with: insertStatement).execute()
        
        let selectStatement = sql { schema in
            let temp = schema.table(Temp.self)
            Select(temp)
            From(temp)
            OrderBy(temp.value.ascending())
        }
        let finalResult = try database.makeRequest(with: selectStatement).fetchAll()
        XCTAssertEqual(finalResult.count, 3)
        XCTAssertEqual(try finalResult.element(at: 0).value, "Apple Test")
        XCTAssertEqual(try finalResult.element(at: 1).value, "Google Test")
        XCTAssertEqual(try finalResult.element(at: 2).value, "Microsoft Test")
    }
    
    
    // MARK: Update
    
    func testUpdate() throws {
        
        let createStatement = sqlCreate(TestTable.self)
        try database.makeRequest(with: createStatement).execute()
        
        try database.makeRequest(with: sqlInsert(TestTable(id: "foo", value: 69))).execute()
        try database.makeRequest(with: sqlInsert(TestTable(id: "bar", value: 420))).execute()

        let selectStatement = sql { schema in
            let table = schema.table(TestTable.self)
            Select(table)
            From(table)
            OrderBy(table.value.ascending())
        }
        
        let initialResult = try database.makeRequest(with: selectStatement).fetchAll()
        XCTAssertEqual(initialResult.count, 2)
        XCTAssertEqual(try initialResult.element(at: 0).value, 69)
        XCTAssertEqual(try initialResult.element(at: 1).value, 420)

        let updateStatement = sql { schema in
            let t = schema.into(TestTable.self)
            Update(t)
            Setting<TestTable> { row in
                row.value = t.value * 10
            }
            Where(t.value == 69)
        }
        try database.makeRequest(with: updateStatement).execute()
        
        let finalResult = try database.makeRequest(with: selectStatement).fetchAll()
        XCTAssertEqual(finalResult.count, 2)
        XCTAssertEqual(try finalResult.element(at: 0).value, 420)
        XCTAssertEqual(try finalResult.element(at: 1).value, 690)

    }
    
    
    // MARK: Delete
    
    
    func testDelete() throws {
        
        let createStatement = sqlCreate(TestTable.self)
        try database.makeRequest(with: createStatement).execute()
        
        try database.makeRequest(with: sqlInsert(TestTable(id: "foo", value: 69))).execute()
        try database.makeRequest(with: sqlInsert(TestTable(id: "bar", value: 420))).execute()

        let selectStatement = sql { schema in
            let table = schema.table(TestTable.self)
            Select(table)
            From(table)
            OrderBy(table.value.ascending())
        }
        
        let initialResult = try database.makeRequest(with: selectStatement).fetchAll()
        XCTAssertEqual(initialResult.count, 2)
        XCTAssertEqual(try initialResult.element(at: 0).value, 69)
        XCTAssertEqual(try initialResult.element(at: 1).value, 420)

        let deleteStatement = sql { schema in
            let t = schema.into(TestTable.self)
            Delete(t)
            Where(t.value == 69)
        }
        try database.makeRequest(with: deleteStatement).execute()
        
        let finalResult = try database.makeRequest(with: selectStatement).fetchAll()
        XCTAssertEqual(finalResult.count, 1)
        XCTAssertEqual(try finalResult.element(at: 0).value, 420)

    }
    
    
    // MARK: Assymetric encoding and decoding using unwrap
    
    
    func testInsertUnwrappedProperty() throws {
        
        let createTableStatement = sqlCreate(DateTest.self)
        try database.makeRequest(with: createTableStatement).execute()
        
        let date = Date(string: "2024-10-24T10:05:30.007", format: "yyyy-MM-dd'T'HH:mm:ss.SSS")
        let originalEntity = DateTest(id: 69420, date: date)
        
        let insertStatement = sql {
            let table = $0.table(DateTest.self)
            Insert(table)
            Values(DateTest(id: originalEntity.id, date: originalEntity.date))
        }
        try database.makeRequest(with: insertStatement).execute()
        
        let finalResult = try getDateTestEntities(database: database)
        XCTAssertEqual(finalResult.count, 1)
        XCTAssertEqual(finalResult[0]["id"], "69420")
        XCTAssertEqual(finalResult[0]["date"], "2024-10-24T10:05:30.007")
    }
    
    
    func testInsertUnwrappedPropertyParameter() throws {
        
        let createTableStatement = sqlCreate(DateTest.self)
        try database.makeRequest(with: createTableStatement).execute()
        
        let date = Date(string: "2024-10-24T10:05:30.007", format: "yyyy-MM-dd'T'HH:mm:ss.SSS")
        let originalEntity = DateTest(id: 69420, date: date)
        
        let dateParameter = XLNamedBindingReference<Date>(name: "date")
        let insertStatement = sql {
            let table = $0.table(DateTest.self)
            Insert(table)
            Values(
                DateTest.MetaInsert(
                    id: originalEntity.id,
                    date: dateParameter
                )
            )
        }
        var request = database.makeRequest(with: insertStatement)
        request.set(dateParameter, date)
        try request.execute()
        
        let finalResult = try getDateTestEntities(database: database)
        XCTAssertEqual(finalResult.count, 1)
        XCTAssertEqual(finalResult[0]["id"], "69420")
        XCTAssertEqual(finalResult[0]["date"], "2024-10-24T10:05:30.007")
    }
    
    
    func testSelectUnwrappedProperty() throws {
        
        let createTableStatement = sqlCreate(DateTest.self)
        try database.makeRequest(with: createTableStatement).execute()
        
        let date = Date(string: "2024-10-24T10:05:30.007", format: "yyyy-MM-dd'T'HH:mm:ss.SSS")
        let originalEntity = DateTest(id: 69420, date: date)
        
        let insertStatement = sql {
            let table = $0.table(DateTest.self)
            Insert(table)
            Values(DateTest(id: originalEntity.id, date: originalEntity.date))
        }
        try database.makeRequest(with: insertStatement).execute()
        
        let queryStatement = sql {
            let table = $0.table(DateTest.self)
            Select(table)
            From(table)
            Where(
                table.date == date
            )
        }
        let finalResult = try database.makeRequest(with: queryStatement).fetchAll()
        
        XCTAssertEqual(finalResult.count, 1)
        XCTAssertEqual(finalResult[0].id, 69420)
        XCTAssertEqual(finalResult[0].date, date)
    }
    
    
    func testSelectUnwrappedPropertyParameter() throws {
        
        let createTableStatement = sqlCreate(DateTest.self)
        try database.makeRequest(with: createTableStatement).execute()
        
        let date = Date(string: "2024-10-24T10:05:30.007", format: "yyyy-MM-dd'T'HH:mm:ss.SSS")
        let originalEntity = DateTest(id: 69420, date: date)
        
        let insertStatement = sqlInsert {
            let table = $0.table(DateTest.self)
            return insert(table).values(DateTest.MetaInsert(id: originalEntity.id, date: originalEntity.date))
        }
        try database.makeRequest(with: insertStatement).execute()
        
        let dateParameter = XLNamedBindingReference<Date>(name: "date")
        let queryStatement = sql {
            let table = $0.table(DateTest.self)
            Select(table)
            From(table)
            Where(table.date == dateParameter)
        }
        var request = database.makeRequest(with: queryStatement)
        request.set(dateParameter, date)
        let entities = try request.fetchAll()
        
        XCTAssertEqual(entities.count, 1)
        XCTAssertEqual(entities.first?.id, originalEntity.id)
        XCTAssertEqual(entities.first?.date, originalEntity.date)
    }
    
    
    func testInsertOptionalUnwrappedProperty() throws {
        
        let createTableStatement = sqlCreate(OptionalDateTest.self)
        try database.makeRequest(with: createTableStatement).execute()
        
        let date = Date(string: "2024-10-24T10:05:30.007", format: "yyyy-MM-dd'T'HH:mm:ss.SSS")
        let originalEntity = OptionalDateTest(id: 69420, date: date)
        
        let insertStatement = sql {
            let table = $0.table(OptionalDateTest.self)
            Insert(table)
            Values(OptionalDateTest(id: originalEntity.id, date: originalEntity.date))
        }
        try database.makeRequest(with: insertStatement).execute()
        
        let finalResult = try getDateTestEntities(database: database)
        XCTAssertEqual(finalResult.count, 1)
        XCTAssertEqual(finalResult[0]["id"], "69420")
        XCTAssertEqual(finalResult[0]["date"], "2024-10-24T10:05:30.007")
    }
    
    
    func textInsertOptionalUnwrappedPropertyParameter() throws {
        
        let createTableStatement = sqlCreate(OptionalDateTest.self)
        try database.makeRequest(with: createTableStatement).execute()
        
        let date = Date(string: "2024-10-24T10:05:30.007", format: "yyyy-MM-dd'T'HH:mm:ss.SSS")
        let originalEntity = OptionalDateTest(id: 69420, date: date)
        
        let dateParameter = XLNamedBindingReference<Optional<Date>>(name: "date")
        let insertStatement = sql {
            let table = $0.table(OptionalDateTest.self)
            Insert(table)
            Values(
                OptionalDateTest.MetaInsert(
                    id: originalEntity.id,
                    date: dateParameter
                )
            )
        }
        var request = database.makeRequest(with: insertStatement)
        request.set(dateParameter, date)
        try request.execute()
        
        let finalResult = try getDateTestEntities(database: database)
        XCTAssertEqual(finalResult.count, 1)
        XCTAssertEqual(finalResult[0]["id"], "69420")
        XCTAssertEqual(finalResult[0]["date"], "2024-10-24T10:05:30.007")
    }
    
    
    func testSelectOptionalUnwrappedPropertyParameter() throws {
        
        let createTableStatement = sqlCreate(OptionalDateTest.self)
        try database.makeRequest(with: createTableStatement).execute()
        
        let date = Date(string: "2024-10-24T10:05:30.007", format: "yyyy-MM-dd'T'HH:mm:ss.SSS")
        let originalEntity = OptionalDateTest(id: 69420, date: date)
        
        let insertStatement = sql {
            let table = $0.table(OptionalDateTest.self)
            Insert(table)
            Values(OptionalDateTest(id: originalEntity.id, date: originalEntity.date))
        }
        try database.makeRequest(with: insertStatement).execute()
        
        let queryStatement = sql {
            let table = $0.table(OptionalDateTest.self)
            Select(table)
            From(table)
            Where(
                table.date == date
            )
        }
        let finalResult = try database.makeRequest(with: queryStatement).fetchAll()
        
        XCTAssertEqual(finalResult.count, 1)
        XCTAssertEqual(finalResult[0].id, 69420)
        XCTAssertEqual(finalResult[0].date, date)
    }
    
    
    func testSelectOptionalUnrwappedPropertyParameter() throws {
        
        let createTableStatement = sqlCreate(OptionalDateTest.self)
        try database.makeRequest(with: createTableStatement).execute()
        
        let entityId = 69420
        let date = Date(string: "2024-10-24T10:05:30.007", format: "yyyy-MM-dd'T'HH:mm:ss.SSS")
        
        let insertStatement = sql {
            let table = $0.table(OptionalDateTest.self)
            Insert(table)
            Values(
                OptionalDateTest(
                    id: entityId,
                    date: date
                )
            )
        }
        try database.makeRequest(with: insertStatement).execute()
        
        let dateParameter = XLNamedBindingReference<Date>(name: "date")
        let queryStatement = sql {
            let table = $0.table(OptionalDateTest.self)
            Select(table)
            From(table)
            Where(table.date == dateParameter)
        }
        var request = database.makeRequest(with: queryStatement)
        request.set(dateParameter, date)
        let entities = try request.fetchAll()
        
        XCTAssertEqual(entities.count, 1)
        XCTAssertEqual(entities.first?.id, entityId)
        XCTAssertEqual(entities.first?.date, date)
    }
    
    
    func testUpdateUnwrappedProperty() throws {
        
        let createTableStatement = sqlCreate(DateTest.self)
        try database.makeRequest(with: createTableStatement).execute()
        
        let entityId = 69420
        let oldDate = Date(string: "2020-01-01T00:00:00.001", format: "yyyy-MM-dd'T'HH:mm:ss.SSS")
        let newDate = Date(string: "2030-01-01T00:00:00.001", format: "yyyy-MM-dd'T'HH:mm:ss.SSS")

        let insertStatement = sql {
            let table = $0.table(DateTest.self)
            Insert(table)
            Values(
                DateTest(
                    id: entityId,
                    date: oldDate
                )
            )
        }
        try database.makeRequest(with: insertStatement).execute()
        
        let updateStatement = sql {
            let table = $0.into(DateTest.self)
            Update(table)
            Setting<DateTest> { row in
                row.date = newDate
            }
            Where(
                table.id == entityId
            )
        }
        try database.makeRequest(with: updateStatement).execute()

        let finalResult = try getDateTestEntities(database: database)
        XCTAssertEqual(finalResult.count, 1)
        XCTAssertEqual(finalResult[0]["id"], "69420")
        XCTAssertEqual(finalResult[0]["date"], "2030-01-01T00:00:00.001")
    }
    
    
    func testUpdateUnwrappedPropertyParameter() throws {
        
        let createTableStatement = sqlCreate(DateTest.self)
        try database.makeRequest(with: createTableStatement).execute()
        
        let entityId = 69420
        let oldDate = Date(string: "2020-01-01T00:00:00.001", format: "yyyy-MM-dd'T'HH:mm:ss.SSS")
        let newDate = Date(string: "2030-01-01T00:00:00.001", format: "yyyy-MM-dd'T'HH:mm:ss.SSS")
        let dateParameter = XLNamedBindingReference<Date>(name: "date")
        
        let insertStatement = sql {
            let table = $0.table(DateTest.self)
            Insert(table)
            Values(
                DateTest(
                    id: entityId,
                    date: oldDate
                )
            )
        }
        try database.makeRequest(with: insertStatement).execute()

        let updateStatement = sql {
            let table = $0.into(DateTest.self)
            Update(table)
            Setting<DateTest> { row in
                row.date = dateParameter
            }
            Where(
                table.id == entityId
            )
        }
        var request = database.makeRequest(with: updateStatement)
        request.set(dateParameter, newDate)
        try request.execute()
        
        let finalResult = try getDateTestEntities(database: database)
        XCTAssertEqual(finalResult.count, 1)
        XCTAssertEqual(finalResult[0]["id"], "69420")
        XCTAssertEqual(finalResult[0]["date"], "2030-01-01T00:00:00.001")
    }
    
    
    func testUpdateOptionalUnwrappedPropertyParameter() throws {
        
        let createTableStatement = sqlCreate(OptionalDateTest.self)
        try database.makeRequest(with: createTableStatement).execute()
        
        let entityId = 69420
        let oldDate = Date(string: "2020-01-01T00:00:00.001", format: "yyyy-MM-dd'T'HH:mm:ss.SSS")
        let newDate = Date(string: "2030-01-01T00:00:00.001", format: "yyyy-MM-dd'T'HH:mm:ss.SSS")
        let dateParameter = XLNamedBindingReference<Optional<Date>>(name: "date")
        
        let insertStatement = sql {
            let table = $0.table(OptionalDateTest.self)
            Insert(table)
            Values(
                OptionalDateTest(
                    id: entityId,
                    date: oldDate
                )
            )
        }
        try database.makeRequest(with: insertStatement).execute()

        let updateStatement = sql {
            let table = $0.into(OptionalDateTest.self)
            Update(table)
            Setting<OptionalDateTest> { row in
                row.date = dateParameter
            }
            Where(
                table.id == entityId
            )
        }
        var request = database.makeRequest(with: updateStatement)
        request.set(dateParameter, newDate)
        try request.execute()
        
        let finalResult = try getDateTestEntities(database: database)
        XCTAssertEqual(finalResult.count, 1)
        XCTAssertEqual(finalResult[0]["id"], "69420")
        XCTAssertEqual(finalResult[0]["date"], "2030-01-01T00:00:00.001")
    }
    
    
    // MARK: - Helpers
    
    private func createTestTable() throws {
        let createStatement = sqlCreate(TestTable.self)
        try database.makeRequest(with: createStatement).execute()
    }
    
    
    private func createEmployeeTable() throws {
        let createStatement = sqlCreate(EmployeeTable.self)
        try database.makeRequest(with: createStatement).execute()
    }

    
    private func insertTest(_ test: TestTable) throws {
        let insertStatement = sqlInsert(test)
        try database.makeRequest(with: insertStatement).execute()
    }

    
    private func insertEmployee(_ employee: EmployeeTable) throws {
        let insertStatement = sqlInsert(employee)
        try database.makeRequest(with: insertStatement).execute()
    }
    
    private func getDateTestEntities(database: GRDBDatabase) throws -> [[String: String]] {
        try database.databasePool.read { database in
            var output: [[String: String]] = []
            let statement = try database.makeStatement(sql: "SELECT * FROM DateTest")
            let rows = try Row.fetchCursor(statement)
            while let row = try rows.next() {
                let id: String = row["id"]
                let date: String = row["date"]
                let entity = [
                    "id": id,
                    "date": date
                ]
                output.append(entity)
            }
            return output
        }

    }
}
