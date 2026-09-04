//
//  SQLSyntaxWriteStatementTests.swift
//
//  Rendering of the statements that change the database: INSERT, UPDATE,
//  CREATE, and DELETE.
//
//  Split from SQLSyntaxTests.swift (issue #567).
//

import XCTest
import SwiftQL


final class XLSyntaxWriteStatementTests: XLSyntaxTestCase {

    // MARK: - Insert
    
    func testInsertDiscreteParameters() {
        let idParameter = XLNamedBindingReference<String>(name: "id")
        let valueParameter = XLNamedBindingReference<Int>(name: "value")
        let schema = XLSchema()
        let t = schema.table(TestTable.self)
        let expression = insert(t).values(
            TestTable.MetaInsert(
                id: idParameter,
                value: valueParameter
            )
        )
        let result = encoder.makeSQL(expression)
        XCTAssertEqual(result.sql, "INSERT INTO Test AS t0 (id,value) VALUES (:id,:value)")
        XCTAssertTrue(result.entities.contains("Test"))
    }
    
    func testInsertInstanceParameter() {
        let instance = TestTable(id: "foo", value: 42)
        let schema = XLSchema()
        let t = schema.table(TestTable.self)
        let expression = insert(t).values(TestTable.MetaInsert(instance))
        let result = encoder.makeSQL(expression)
        XCTAssertEqual(result.sql, "INSERT INTO Test AS t0 (id,value) VALUES ('foo',42)")
        XCTAssertTrue(result.entities.contains("Test"))
    }
    
    func testInsertImplicitInstanceParameter() {
        let instance = TestTable(id: "foo", value: 42)
        let schema = XLSchema()
        let t = schema.table(TestTable.self)
        let expression = insert(t).values(instance)
        let result = encoder.makeSQL(expression)
        XCTAssertEqual(result.sql, "INSERT INTO Test AS t0 (id,value) VALUES ('foo',42)")
        XCTAssertTrue(result.entities.contains("Test"))
    }
    
    func testInsertSelect() {
        let schema = XLSchema()
        let t = schema.table(Temp.self)
        let e = schema.table(EmployeeTable.self)
        let r = Temp.columns(id: e.id, value: e.name)
        let expression = insert(t).select(r).from(e)
        let finalResult = encoder.makeSQL(expression)
        XCTAssertEqual(finalResult.sql, "INSERT INTO Temp AS t0 SELECT t1.id AS id, t1.name AS value FROM Employee AS t1")
        XCTAssertTrue(finalResult.entities.contains("Temp"))
    }
    
    func testInsertSelectWithCommonTableExpression() {
        let schema = XLSchema()
        let cte = schema.commonTable { schema in
            let t = schema.table(CompanyTable.self)
            return select(t).from(t)
        }
        let t = schema.table(Temp.self)
        let e = schema.table(cte)
        let r = Temp.columns(id: e.id, value: e.name)
        let expression = with(cte).insert(t).select(r).from(e)
        let finalResult = encoder.makeSQL(expression)
        XCTAssertEqual(finalResult.sql, "WITH cte0 AS (SELECT t0.id AS id, t0.name AS name FROM Company AS t0) INSERT INTO Temp AS t0 SELECT t1.id AS id, t1.name AS value FROM cte0 AS t1")
        XCTAssertTrue(finalResult.entities.contains("Temp"))
    }

    func testInsertSelectFluentRemainingTransitions() {
        let schema = XLSchema()
        let temp = schema.table(Temp.self)
        let company = schema.table(CompanyTable.self)
        let employeeTable = schema.table(EmployeeTable.self)
        // Insert-select joins accept unnamed result metadata. Reuse the named
        // table dependency so every join keeps the deterministic t2 alias.
        let employee = EmployeeTable.makeSQLTable(
            namespace: employeeTable._namespace,
            dependency: employeeTable._dependency
        )
        let nullableEmployee = EmployeeTable.makeSQLNullableResult(
            namespace: employeeTable._namespace,
            dependency: employeeTable._dependency
        )
        let row = Temp.columns(id: company.id, value: company.name)
        let from = insert(temp).select(row).from(company)
        let filtered = from.where(company.name != "skip")
        let grouped = from.groupBy(company.id, company.name)
        let having = grouped.having(company.id.count() >= 1)
        let baseSQL = "INSERT INTO Temp AS t0 SELECT t1.id AS id, t1.name AS value FROM Company AS t1"
        let cases: [(String, any XLEncodable, String)] = [
            (
                "FROM to bare INNER JOIN",
                from.innerJoin(employee),
                " INNER JOIN Employee AS t2"
            ),
            (
                "FROM to CROSS JOIN",
                from.crossJoin(employee),
                " CROSS JOIN Employee AS t2"
            ),
            (
                "FROM to nullable LEFT JOIN",
                from.leftJoin(
                    nullableEmployee,
                    on: nullableEmployee.companyId == company.id
                ),
                " LEFT JOIN Employee AS t2 ON (t2.companyId IS t1.id)"
            ),
            (
                "FROM to GROUP BY",
                from.groupBy(company.id, company.name),
                " GROUP BY t1.id, t1.name"
            ),
            (
                "FROM to ORDER BY",
                from.orderBy(company.name.ascending()),
                " ORDER BY t1.name ASC"
            ),
            (
                "FROM to LIMIT",
                from.limit(1),
                " LIMIT 1"
            ),
            (
                "WHERE to ORDER BY",
                filtered.orderBy(company.name.ascending()),
                " WHERE (t1.name != 'skip') ORDER BY t1.name ASC"
            ),
            (
                "WHERE to LIMIT",
                filtered.limit(1),
                " WHERE (t1.name != 'skip') LIMIT 1"
            ),
            (
                "GROUP BY to ORDER BY",
                grouped.orderBy(company.name.ascending()),
                " GROUP BY t1.id, t1.name ORDER BY t1.name ASC"
            ),
            (
                "GROUP BY to LIMIT",
                grouped.limit(1),
                " GROUP BY t1.id, t1.name LIMIT 1"
            ),
            (
                "HAVING to LIMIT",
                having.limit(1),
                " GROUP BY t1.id, t1.name HAVING (COUNT(t1.id) >= 1) LIMIT 1"
            ),
        ]

        for (transition, statement, suffix) in cases {
            XCTAssertEqual(
                encoder.makeSQL(statement).sql,
                baseSQL + suffix,
                transition
            )
        }
    }
    
    
    // MARK: - Update
    
    func testUpdate() {
        let schema = XLSchema()
        let t = schema.into(TestTable.self)
        let expression = update(t, set: TestTable.MetaUpdate(
            value: t.value + 1
        ))
        let result = encoder.makeSQL(expression)
        XCTAssertEqual(result.sql, "UPDATE Test AS t0 SET value = (t0.value + 1)")
        XCTAssertTrue(result.entities.contains("Test"))
    }
    
    func testUpdateDecimal() {
        let schema = XLSchema()
        let t = schema.into(DoubleTest.self)
        let expression = update(t, set: DoubleTest.MetaUpdate(
            value: 1234.56
        ))
        let result = encoder.makeSQL(expression)
        XCTAssertEqual(result.sql, "UPDATE DoubleTest AS t0 SET value = 1234.56")
        XCTAssertTrue(result.entities.contains("DoubleTest"))
    }
    
    func testUpdateFractional() {
        let schema = XLSchema()
        let t = schema.into(DoubleTest.self)
        let expression = update(t, set: DoubleTest.MetaUpdate(
            value: 0.56
        ))
        let result = encoder.makeSQL(expression)
        XCTAssertEqual(result.sql, "UPDATE DoubleTest AS t0 SET value = 0.56")
        XCTAssertTrue(result.entities.contains("DoubleTest"))
    }
    
    func testUpdateWhere() {
        let schema = XLSchema()
        let t = schema.into(TestTable.self)
        let expression = update(t) 
            .set { row in
                row.value = t.value + 1
            }
            .where(t.id == "foo")
        let result = encoder.makeSQL(expression)
        XCTAssertEqual(result.sql, "UPDATE Test AS t0 SET value = (t0.value + 1) WHERE (t0.id == 'foo')")
        XCTAssertTrue(result.entities.contains("Test"))
    }
    
    func testUpdateFrom() {
        let schema = XLSchema()
        let t = schema.into(Temp.self)
        let s = schema.from { schema in
            let t = schema.table(CompanyTable.self)
            return select(t).from(t)
        }
        let expression = update(t)
            .set { row in
                row.value = t.value + " " + s.name
            }
            .from(s)
            .where(t.id == s.id)
        let result = encoder.makeSQL(expression)
        XCTAssertEqual(result.sql, "UPDATE Temp AS t0 SET value = ((t0.value || ' ') || t1.name) FROM (SELECT t0.id AS id, t0.name AS name FROM Company AS t0) AS t1 WHERE (t0.id == t1.id)")
        XCTAssertTrue(result.entities.contains("Temp"))
    }
    
    
    // MARK: - Create
    
    func testCreateTable() {
        let schema = XLSchema()
        let t = schema.create(TestTable.self)
        let expression = create(t)
        assertRenders(expression, as: "CREATE TABLE IF NOT EXISTS Test (id NOT NULL, value NOT NULL)")
    }
    
    func testCreateNullablesTable() {
        let schema = XLSchema()
        let t = schema.create(TestNullablesTable.self)
        let expression = create(t)
        assertRenders(expression, as: "CREATE TABLE IF NOT EXISTS TestNullables (id NOT NULL, value)")
    }
    
    func testCreateGenericValueTable() {
        let schema = XLSchema()
        let t = schema.create(GenericTable<String>.self)
        let expression = create(t)
        assertRenders(expression, as: "CREATE TABLE IF NOT EXISTS Generic (id NOT NULL, type NOT NULL, value NOT NULL)")
    }
    
    
    // MARK: Create ... Select
    
    func testCreateTableUsingSelect() {
        
        let schema = XLSchema()
        let t = schema.create(Temp.self)
        let expression = create(t).as { schema in
            let t = schema.table(EmployeeTable.self)
            let r = Temp.columns(id: t.id, value: t.name)
            return select(r).from(t)
        }
        assertRenders(expression, as: "CREATE TABLE IF NOT EXISTS Temp AS SELECT t0.id AS id, t0.name AS value FROM Employee AS t0")
    }
    
    func testCreateTableUsingSelectWithCommonTable() {
        
        let schema = XLSchema()
        let t = schema.create(Temp.self)
        let expression = create(t).as { schema in
            
            let cte = schema.commonTable { schema in
                let t = schema.table(EmployeeTable.self)
                return select(t).from(t)
            }
            
            let t = schema.table(cte)
            let r = Temp.columns(id: t.id, value: t.name)
            return with(cte).select(r).from(t)
        }
        assertRenders(expression, as: "CREATE TABLE IF NOT EXISTS Temp AS WITH cte0 AS (SELECT t0.id AS id, t0.name AS name, t0.companyId AS companyId, t0.managerEmployeeId AS managerEmployeeId FROM Employee AS t0) SELECT t0.id AS id, t0.name AS value FROM cte0 AS t0")
    }
    
    
    // MARK: - Delete
    
    func testDelete() {
        let schema = XLSchema()
        let t = schema.into(TestTable.self)
        let expression = delete(t)
        let result = encoder.makeSQL(expression)
        XCTAssertEqual(result.sql, "DELETE FROM Test AS t0")
        XCTAssertTrue(result.entities.contains("Test"))
    }
    
    func testDeleteWhere() {
        let schema = XLSchema()
        let t = schema.into(TestTable.self)
        let expression = delete(t).where(t.value == 42)
        let result = encoder.makeSQL(expression)
        XCTAssertEqual(result.sql, "DELETE FROM Test AS t0 WHERE (t0.value == 42)")
        XCTAssertTrue(result.entities.contains("Test"))
    }
    
    func testDeleteWithCommonTableExpression() {
        let schema = XLSchema()
        let cte = schema.commonTable { schema in
            let t = schema.table(TestTable.self)
            return select(t).from(t)
        }
        let t0 = schema.table(cte)
        let t1 = schema.into(TestTable.self)
        let expression = with(cte)
            .delete(t1)
            .where(
                t1.id.in {
                    select(t0.id).from(t0)
                }
            )
        let result = encoder.makeSQL(expression)
        XCTAssertEqual(result.sql, "WITH cte0 AS (SELECT t0.id AS id, t0.value AS value FROM Test AS t0) DELETE FROM Test AS t1 WHERE (t1.id IN (SELECT t0.id FROM cte0 AS t0))")
        XCTAssertTrue(result.entities.contains("Test"))
    }
    
    func testDeleteWithSubquery() {
        let schema = XLSchema()
        let t0 = schema.into(TestTable.self)
        let expression = delete(t0)
            .where(
                t0.id.in {
                    let t1 = schema.table(TestTable.self)
                    return select(t1.id).from(t1)
                }
            )
        let result = encoder.makeSQL(expression)
        XCTAssertEqual(result.sql, "DELETE FROM Test AS t0 WHERE (t0.id IN (SELECT t1.id FROM Test AS t1))")
        XCTAssertTrue(result.entities.contains("Test"))
    }


    // Compile-only: the deprecated context verifies both retained v1 result helpers without adding
    // deprecation warnings to the warning-clean test build.
    @available(*, deprecated, message: "Exercises the source-compatible SwiftQL 1.x result helpers.")
    private func assertLegacyResultHelpersRemainSourceCompatible() {
        let _: SQLScalarResult<Int>.MetaResult = result {
            SQLScalarResult<Int>.SQLReader(scalarValue: 1)
        }
        let _: SQLScalarResult<Int>.MetaResult = result { reader in
            let scalarValue: Int = (try? reader.column(1, alias: "scalarValue")) ?? 0
            return SQLScalarResult(
                scalarValue: scalarValue
            )
        }
    }
}
