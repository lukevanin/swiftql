//
//  SQLSyntaxCompoundSelectTests.swift
//
//  Rendering of the compound operators, recursive common tables, subqueries,
//  and variable parameter bindings.
//
//  Split from SQLSyntaxTests.swift (issue #567).
//

import XCTest
import SwiftQL


final class XLSyntaxCompoundSelectTests: XLSyntaxTestCase {

    // MARK: Union
    
    func testUnion() {
        let schema = XLSchema()
        let familyMom = schema.table(Family.self)
        let familyDad = schema.table(Family.self)
        let momRow = FamilyMemberParent.columns(name: familyMom.name, parent: familyMom.mom)
        let dadRow = FamilyMemberParent.columns(name: familyDad.name, parent: familyDad.dad)
        let expression = select(momRow).from(familyMom).union {
            select(dadRow).from(familyDad)
        }
        let result = encoder.makeSQL(expression)
        XCTAssertEqual(result.sql, "SELECT t0.name AS name, t0.mom AS parent FROM Family AS t0 UNION SELECT t1.name AS name, t1.dad AS parent FROM Family AS t1")
    }
    
    func testUnionAll() {
        let schema = XLSchema()
        let familyMom = schema.table(Family.self)
        let familyDad = schema.table(Family.self)
        let momRow = FamilyMemberParent.columns(name: familyMom.name, parent: familyMom.mom)
        let dadRow = FamilyMemberParent.columns(name: familyDad.name, parent: familyDad.dad)
        let expression = select(momRow).from(familyMom).unionAll {
            select(dadRow).from(familyDad)
        }
        let result = encoder.makeSQL(expression)
        XCTAssertEqual(result.sql, "SELECT t0.name AS name, t0.mom AS parent FROM Family AS t0 UNION ALL SELECT t1.name AS name, t1.dad AS parent FROM Family AS t1")
    }
    
    func testIntersect() {
        let schema = XLSchema()
        let familyMom = schema.table(Family.self)
        let familyDad = schema.table(Family.self)
        let momRow = FamilyMemberParent.columns(name: familyMom.name, parent: familyMom.mom)
        let dadRow = FamilyMemberParent.columns(name: familyDad.name, parent: familyDad.dad)
        let expression = select(momRow).from(familyMom).intersect {
            select(dadRow).from(familyDad)
        }
        let result = encoder.makeSQL(expression)
        XCTAssertEqual(result.sql, "SELECT t0.name AS name, t0.mom AS parent FROM Family AS t0 INTERSECT SELECT t1.name AS name, t1.dad AS parent FROM Family AS t1")
    }
    
    func testExcept() {
        let schema = XLSchema()
        let familyMom = schema.table(Family.self)
        let familyDad = schema.table(Family.self)
        let momRow = FamilyMemberParent.columns(name: familyMom.name, parent: familyMom.mom)
        let dadRow = FamilyMemberParent.columns(name: familyDad.name, parent: familyDad.dad)
        let expression = select(momRow).from(familyMom).except {
            select(dadRow).from(familyDad)
        }
        let result = encoder.makeSQL(expression)
        XCTAssertEqual(result.sql, "SELECT t0.name AS name, t0.mom AS parent FROM Family AS t0 EXCEPT SELECT t1.name AS name, t1.dad AS parent FROM Family AS t1")
    }
    
    
    // MARK: Recursion
    
    func testScalarRecursiveCommonTableExpression() {
        
        //WITH RECURSIVE
        //  works_for_alice(n) AS (
        //    VALUES('Alice')
        //    UNION
        //    SELECT name FROM org JOIN works_for_alice
        //     WHERE org.boss=works_for_alice.n
        //  )
        //SELECT name FROM org
        // WHERE org.name IN works_for_alice;
        typealias Scalar = SQLScalarResult<String?>
        let schema = XLSchema()
        let cte = schema.recursiveCommonTable(Scalar.self) { schema, this in
            let org = schema.table(Org.self)
            
            let initialResult = Scalar.columns(scalarValue: "Alice".toNullable())
            return select(initialResult).union {
                select(Scalar.columns(scalarValue: org.name))
                    .from(org)
                    .crossJoin(this)
                    .where(org.boss == this.scalarValue)
            }
        }
        
        let org = schema.table(Org.self)
        let expression = with(cte)
            .select(org.name)
            .from(org)
            .where(
                org.name.in(cte)
            )
        let finalResult = encoder.makeSQL(expression)
        XCTAssertEqual(finalResult.sql, "WITH cte0 AS (SELECT 'Alice' AS scalarValue UNION SELECT t1.name AS scalarValue FROM Org AS t1 CROSS JOIN cte0 AS t0 WHERE (t1.boss IS t0.scalarValue)) SELECT t0.name FROM Org AS t0 WHERE (t0.name IN cte0)")
    }
    
    
    func testRecursiveCommonTableExpression() {

        //WITH RECURSIVE
        //  parent_of(name, parent) AS
        //    (SELECT name, mom FROM family UNION SELECT name, dad FROM family),
        //  ancestor_of_alice(name) AS
        //    (SELECT parent FROM parent_of WHERE name='Alice'
        //     UNION ALL
        //     SELECT parent FROM parent_of JOIN ancestor_of_alice USING(name))
        //SELECT family.name FROM ancestor_of_alice, family
        // WHERE ancestor_of_alice.name=family.name
        //   AND died IS NULL
        // ORDER BY born;
        typealias Scalar = SQLScalarResult<String?>
        let schema = XLSchema()
        
        let parentOfCommonTable = schema.commonTable { schema in
            let family = schema.table(Family.self)
            let momRow = FamilyMemberParent.columns(name: family.name, parent: family.mom)
            let dadRow = FamilyMemberParent.columns(name: family.name, parent: family.dad)
            return select(momRow).from(family).union {
                select(dadRow).from(family)
            }
        }
        
        let ancestorOfAliceCommonTable = schema.recursiveCommonTable(Scalar.self) { schema, this in
            let parentOf = schema.table(parentOfCommonTable)
            return select(Scalar.columns(scalarValue: parentOf.parent))
                .from(parentOf)
                .where(parentOf.name == "Alice".toNullable())
                .unionAll {
                    select(Scalar.columns(scalarValue: parentOf.parent))
                        .from(parentOf)
                        .innerJoin(this, on: this.scalarValue == parentOf.name)
                }
        }
        
        let ancestorOfAlice = schema.table(ancestorOfAliceCommonTable)
        let family = schema.table(Family.self)
        let expression = with(parentOfCommonTable, ancestorOfAliceCommonTable)
            .select(family.name)
            .from(ancestorOfAlice)
            .crossJoin(family)
            .where(ancestorOfAlice.scalarValue == family.name && family.died.isNull())
            .orderBy(family.born.ascending())
        
        let finalResult = encoder.makeSQL(expression)
        XCTAssertEqual(finalResult.sql, "WITH cte0 AS (SELECT t0.name AS name, t0.mom AS parent FROM Family AS t0 UNION SELECT t0.name AS name, t0.dad AS parent FROM Family AS t0), cte1 AS (SELECT t1.parent AS scalarValue FROM cte0 AS t1 WHERE (t1.name IS 'Alice') UNION ALL SELECT t1.parent AS scalarValue FROM cte0 AS t1 INNER JOIN cte1 AS t0 ON (t0.scalarValue IS t1.name)) SELECT t1.name FROM cte1 AS t0 CROSS JOIN Family AS t1 WHERE ((t0.scalarValue IS t1.name) AND (julianday(t1.died) ISNULL)) ORDER BY julianday(t1.born) ASC")
    }
    
    
    // MARK: Subquery
    
    
    func testSubquery() {
        let t = subquery { s in
            let t = s.table(TestTable.self)
            return select(t).from(t).where(t.value > 10)
        }
        let expression = select(t).from(t).where(t.value < 10)
        assertRenders(
            expression,
            as: "SELECT t0.id AS id, t0.value AS value FROM (SELECT t0.id AS id, t0.value AS value FROM Test AS t0 WHERE (t0.value > 10)) AS t0 WHERE (t0.value < 10)"
        )
    }
    
    
    // MARK: - Scalar subquery
    
    func testScalarSelectConstant() {
        let expression = select(1)
        assertRenders(expression, as: "SELECT 1")
    }
    
    func testScalarSelect() {
        let schema = XLSchema()
        let t = schema.table(TestTable.self)
        let expression = select(t.id).from(t)
        assertRenders(expression, as: "SELECT t0.id FROM Test AS t0")
    }
    
    /// A subquery on the nullable side of a LEFT JOIN. Before #70 this was not
    /// expressible: `subquery(alias:)` returns a non-nullable result, and the
    /// nullable overload could never be selected because no `select` function
    /// produces a statement over a generated `Nullable` row type.
    func testNullableSubqueryOnLeftJoin() {
        let schema = XLSchema()
        let company = schema.table(CompanyTable.self)
        let employees = nullableSubquery(alias: "staff") { inner in
            let e = inner.table(EmployeeTable.self)
            return select(e).from(e)
        }
        let expression = select(company)
            .from(company)
            .leftJoin(employees, on: employees.companyId == company.id)
        // The subquery opens its own namespace, so its inner alias restarts at
        // t0 rather than continuing the outer numbering. The two t0 scopes do
        // not collide because the inner one is only visible inside the
        // parentheses.
        assertRenders(
            expression,
            as: "SELECT t0.id AS id, t0.name AS name FROM Company AS t0 LEFT JOIN (SELECT t0.id AS id, t0.name AS name, t0.companyId AS companyId, t0.managerEmployeeId AS managerEmployeeId FROM Employee AS t0) AS staff ON (staff.companyId IS t0.id)"
        )
    }

    func testSelectSubqueryAggregate() {
        let s = XLSchema()
        let t = s.table(TestTable.self)
        let r = TestColumns.columns(
            id: t.id,
            // No XLTypeAffinityExpression wrapper: the scalar subquery now
            // yields Int? directly instead of Int??.
            value: subquery {
                let t = s.table(TestTable.self)
                return select(t.value.sumOrNull()).from(t)
            }
        )
        let expression = select(r).from(t)
        assertRenders(expression, as: "SELECT t0.id AS id, (SELECT SUM(t1.value) FROM Test AS t1) AS value FROM Test AS t0")
    }

    /// The schema-parameter closure shape of the same flattening overload
    /// exercised by `testSelectSubqueryAggregate` (issue #162): a scalar
    /// subquery over an already-optional expression yields `Int?`, not
    /// `Int??`, with no `XLTypeAffinityExpression` wrapper required.
    func testSelectSubqueryAggregateWithSchemaParameter() {
        let s = XLSchema()
        let t = s.table(TestTable.self)
        let r = TestColumns.columns(
            id: t.id,
            value: subquery { schema in
                let t = schema.table(TestTable.self)
                return select(t.value.sumOrNull()).from(t)
            }
        )
        let expression = select(r).from(t)
        assertRenders(expression, as: "SELECT t0.id AS id, (SELECT SUM(t0.value) FROM Test AS t0) AS value FROM Test AS t0")
    }

    func testScalarSelectWhereIn() {
        let schema = XLSchema()
        let t = schema.table(TestTable.self)
        let expression = select(t)
            .from(t)
            .where(
                t.id.in {
                    select(t.id).from(t)
                }
            )
        assertRenders(expression, as: "SELECT t0.id AS id, t0.value AS value FROM Test AS t0 WHERE (t0.id IN (SELECT t0.id FROM Test AS t0))")
    }
    
    
    // MARK: - Variable parameter bindings
    
    
    func testVariableBinding() {
        let idParameter = XLNamedBindingReference<String>(name: "id")
        let schema = XLSchema()
        let t = schema.table(TestTable.self)
        let expression = select(t).from(t).where(t.id == idParameter)
        assertRenders(expression, as: "SELECT t0.id AS id, t0.value AS value FROM Test AS t0 WHERE (t0.id == :id)")
    }
    
    
    //    func testScalarSelectWhere() {
    //        let expression = sqlQuery { db in
    //            let t = db.from(Test.self, as: "t")
    //            Where { t.value > 0 }
    //            SelectColumn(t.id)
    //        }
    //        XCTAssertEqual(encoder.makeSQL(expression), "SELECT t.id AS c0 FROM Test AS t WHERE (t.value > 0)")
    //    }
    
    //    func testScalarSelectWhere_ReferenceSelect() {
    //        let expression = sqlQuery { db in
    //            let t = db.from(Test.self, as: "t")
    //            Where { t.id == "foo" }
    //            SelectColumn(column)
    //        }
    //        XCTAssertEqual(encoder.makeSQL(expression), "SELECT t.id AS c0 FROM Test AS t WHERE (c0 == 'foo')")
    //    }
    
    
    //    func testSelectColumnExpressionWhere() {
    //        let expression = sqlQuery { db in
    //            let test = db.from(Test.self, as: "test")
    //            let columns = db.columns { row in
    //                Result(
    //                    id: row { test.id },
    //                    value: row { test.value * 2 }
    //                )
    //            }
    //            Select(columns)
    //            Where { columns.value > 2 }
    //        }
    //        XCTAssertEqual(encoder.makeSQL(expression), "SELECT test.id AS c0, (test.value * 2) AS c1 FROM Test AS test")
    //    }
    
    //    func testSelectAverage() {
    //        let expression = sqlQuery { db in
    //            let t = db.from(Test.self, as: "t")
    //            #warning("TODO: Error or warning when using aggregate without group by")
    ////            Group(by: t.id)
    //            Select { columns in
    //                TestResult(
    //                    id: columns { t.id },
    //                    total: columns { Sum(t.value) }
    //                )
    //            }
    //        }
    //        XCTAssertEqual(encoder.makeSQL(expression), "SELECT t.id AS c0, SUM(t.value) AS c1 FROM Test AS t")
    //    }
}
