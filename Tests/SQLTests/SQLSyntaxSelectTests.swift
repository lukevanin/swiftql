//
//  SQLSyntaxSelectTests.swift
//
//  Rendering of SELECT, including its clauses and factored (WITH) form.
//
//  Split from SQLSyntaxTests.swift (issue #567).
//

import XCTest
import SwiftQL


final class XLSyntaxSelectTests: XLSyntaxTestCase {

    // MARK: - Select
    
    func testSelect() {
        let expression = sqlQuery { schema in
            let test = schema.table(TestTable.self)
            return select(test).from(test)
        }
        assertRenders(expression, as: "SELECT t0.id AS id, t0.value AS value FROM Test AS t0")
    }
    
    func testSelectWhere() {
        let expression = sqlQuery { schema in
            let t = schema.table(TestTable.self)
            return select(t).from(t).where(t.value > 0)
        }
        assertRenders(expression, as: "SELECT t0.id AS id, t0.value AS value FROM Test AS t0 WHERE (t0.value > 0)")
    }
    
    func testSelectWhereAnd() {
        let expression = sqlQuery { schema in
            let t = schema.table(TestTable.self)
            return select(t).from(t).where(t.value > 0 && t.value < 1)
        }
        assertRenders(expression, as: "SELECT t0.id AS id, t0.value AS value FROM Test AS t0 WHERE ((t0.value > 0) AND (t0.value < 1))")
    }
    
    func testSelectWhereNotInArrayOfText() {
        let expression = sqlQuery { s in
            let t = s.table(TestTable.self)
            return select(t).from(t).where(t.id.notIn(["foo", "bar"]))
        }
        assertRenders(expression, as: "SELECT t0.id AS id, t0.value AS value FROM Test AS t0 WHERE (t0.id NOT IN ('foo', 'bar'))")
    }

    func testSelectWhereInArrayContainingNull() {
        let expression = sqlQuery { s in
            let t = s.table(TestNullablesTable.self)
            return select(t).from(t).where(
                t.value.in([1, Optional<Int>.none])
            )
        }
        assertRenders(expression, as: "SELECT t0.id AS id, t0.value AS value FROM TestNullables AS t0 WHERE (t0.value IN (1, NULL))")
    }

    func testSelectWhereNotInArrayContainingNull() {
        let expression = sqlQuery { s in
            let t = s.table(TestNullablesTable.self)
            return select(t).from(t).where(
                t.value.notIn([1, Optional<Int>.none])
            )
        }
        assertRenders(expression, as: "SELECT t0.id AS id, t0.value AS value FROM TestNullables AS t0 WHERE (t0.value NOT IN (1, NULL))")
    }

    func testSelectWhereNotInEmptyArray() {
        let expression = sqlQuery { s in
            let t = s.table(TestTable.self)
            return select(t).from(t).where(t.id.notIn([]))
        }
        assertRenders(expression, as: "SELECT t0.id AS id, t0.value AS value FROM Test AS t0 WHERE (t0.id NOT IN ())")
    }

    func testScalarSelectWhereNotInSubquery() {
        let schema = XLSchema()
        let t = schema.table(TestTable.self)
        let expression = select(t)
            .from(t)
            .where(
                t.id.notIn {
                    select(t.id).from(t)
                }
            )
        assertRenders(expression, as: "SELECT t0.id AS id, t0.value AS value FROM Test AS t0 WHERE (t0.id NOT IN (SELECT t0.id FROM Test AS t0))")
    }

    /// The negation belongs to the IN operator itself, not to a wrapping NOT,
    /// so it must not migrate outwards when the predicate is combined.
    func testSelectWhereNotInComposesWithoutMovingTheNegation() {
        let expression = sqlQuery { s in
            let t = s.table(TestTable.self)
            return select(t).from(t).where(
                t.id.notIn(["foo"]) && t.id.in(["bar"])
            )
        }
        assertRenders(expression, as: "SELECT t0.id AS id, t0.value AS value FROM Test AS t0 WHERE ((t0.id NOT IN ('foo')) AND (t0.id IN ('bar')))")
    }

    func testSelectWhereRegexp() {
        let expression = sqlQuery { s in
            let t = s.table(TestTable.self)
            return select(t).from(t).where(t.id.regexp("^a.*z$"))
        }
        assertRenders(expression, as: "SELECT t0.id AS id, t0.value AS value FROM Test AS t0 WHERE (t0.id REGEXP '^a.*z$')")
    }

    /// REGEXP is an ordinary binary operator, so it composes and parenthesises
    /// the same way LIKE and GLOB do.
    func testSelectWhereRegexpComposesWithOtherPredicates() {
        let expression = sqlQuery { s in
            let t = s.table(TestTable.self)
            return select(t).from(t).where(
                t.id.regexp("^a") && t.id.glob("*z")
            )
        }
        assertRenders(expression, as: "SELECT t0.id AS id, t0.value AS value FROM Test AS t0 WHERE ((t0.id REGEXP '^a') AND (t0.id GLOB '*z'))")
    }

    func testSelectWhereLikeWithEscape() {
        let expression = sqlQuery { s in
            let t = s.table(TestTable.self)
            return select(t).from(t).where(t.id.like("100\\%", escape: "\\"))
        }
        assertRenders(expression, as: "SELECT t0.id AS id, t0.value AS value FROM Test AS t0 WHERE (t0.id LIKE '100\\%' ESCAPE '\\')")
    }

    /// ESCAPE belongs to its own LIKE, so a second LIKE in the same predicate
    /// must not absorb it.
    func testSelectWhereLikeWithEscapeBindsToItsOwnLike() {
        let expression = sqlQuery { s in
            let t = s.table(TestTable.self)
            return select(t).from(t).where(
                t.id.like("100\\%", escape: "\\") && t.id.like("b%")
            )
        }
        assertRenders(expression, as: "SELECT t0.id AS id, t0.value AS value FROM Test AS t0 WHERE ((t0.id LIKE '100\\%' ESCAPE '\\') AND (t0.id LIKE 'b%'))")
    }

    func testSelectWhereInArrayOfText() {
        let expression = sqlQuery { s in
            let t = s.table(TestTable.self)
            return select(t).from(t).where(t.id.in(["foo", "bar"]))
        }
        assertRenders(expression, as: "SELECT t0.id AS id, t0.value AS value FROM Test AS t0 WHERE (t0.id IN ('foo', 'bar'))")
    }
    
    func testSelectWhereInArrayOfInteger() {
        let expression = sqlQuery { s in
            let t = s.table(TestTable.self)
            return select(t).from(t).where(t.value.in([9000, 42]))
        }
        assertRenders(expression, as: "SELECT t0.id AS id, t0.value AS value FROM Test AS t0 WHERE (t0.value IN (9000, 42))")
    }
    
    //    func testSelectColumns() {
    //        let expression = sqlQuery {
    //            let t = from(TestTable.self)
    //            let columns = result {
    //                TestColumns(
    //                    id: $0.column(t.id + t.id),
    //                    value: $0.column(t.value + t.value)
    //                )
    //            }
    //            return select(columns)
    //        }
    //        XCTAssertEqual(encoder.makeSQL(expression), "SELECT t0.id || t0.id AS c0, (t0.value + t0.value) AS c1 FROM Test AS t0")
    //    }
    
    func testSelectJoin() {
        let expression = sqlQuery { s in
            let t0 = s.table(TestTable.self)
            let t1 = s.table(TestTable.self)
            return select(t1).from(t0).innerJoin(t1, on: t1.id == t0.id)
        }
        assertRenders(expression, as: "SELECT t1.id AS id, t1.value AS value FROM Test AS t0 INNER JOIN Test AS t1 ON (t1.id == t0.id)")
    }


    func testSelectJoinSkipsExplicitAliases() {
        let expression = sqlQuery { schema in
            let explicit0 = schema.table(TestTable.self, as: "T0")
            let explicit1 = schema.table(TestTable.self, as: "t1")
            let automatic = schema.table(TestTable.self)
            return select(automatic)
                .from(automatic)
                .innerJoin(explicit0, on: automatic.id == explicit0.id)
                .innerJoin(explicit1, on: automatic.id == explicit1.id)
        }
        assertRenders(expression, as: "SELECT t2.id AS id, t2.value AS value FROM Test AS t2 INNER JOIN Test AS T0 ON (t2.id == T0.id) INNER JOIN Test AS t1 ON (t2.id == t1.id)")
    }
    
    func testSelectJoinWhere() {
        let expression = sqlQuery { s in
            let t0 = s.table(TestTable.self)
            let t1 = s.table(TestTable.self)
            return select(t1).from(t0).innerJoin(t1, on: t1.id == t0.id).where(t0.id == "foo")
        }
        assertRenders(expression, as: "SELECT t1.id AS id, t1.value AS value FROM Test AS t0 INNER JOIN Test AS t1 ON (t1.id == t0.id) WHERE (t0.id == 'foo')")
    }
    
    func testSelectJoinJoinWhere() {
        let expression = sqlQuery { s in
            let t0 = s.table(TestTable.self)
            let t1 = s.table(TestTable.self)
            let t2 = s.table(TestTable.self)
            return select(t2).from(t0).innerJoin(t1, on: t1.id == t0.id ).innerJoin(t2, on: t2.id == t1.id ).where(t0.id == "foo")
        }
        assertRenders(expression, as: "SELECT t2.id AS id, t2.value AS value FROM Test AS t0 INNER JOIN Test AS t1 ON (t1.id == t0.id) INNER JOIN Test AS t2 ON (t2.id == t1.id) WHERE (t0.id == 'foo')")
    }
    
    func testSelectOrder() {
        let expression = sqlQuery { s in
            let t = s.table(TestTable.self)
            return select(t).from(t).orderBy(t.id.ascending())
        }
        assertRenders(expression, as: "SELECT t0.id AS id, t0.value AS value FROM Test AS t0 ORDER BY t0.id ASC")
    }
    
    func testSelectJoinOrder() {
        let expression = sqlQuery { s in
            let t0 = s.table(TestTable.self)
            let t1 = s.table(TestTable.self)
            return select(t1).from(t0).innerJoin(t1, on: t1.id == t0.id).orderBy(t0.id.ascending())
        }
        assertRenders(expression, as: "SELECT t1.id AS id, t1.value AS value FROM Test AS t0 INNER JOIN Test AS t1 ON (t1.id == t0.id) ORDER BY t0.id ASC")
    }
    
    func testSelectWhereOrder() {
        let expression = sqlQuery { s in
            let t = s.table(TestTable.self)
            return select(t).from(t).where(t.id == "foo").orderBy(t.id.ascending())
        }
        assertRenders(expression, as: "SELECT t0.id AS id, t0.value AS value FROM Test AS t0 WHERE (t0.id == 'foo') ORDER BY t0.id ASC")
    }
    
    func testSelectJoinWhereOrder() {
        let expression = sqlQuery { s in
            let t0 = s.table(TestTable.self)
            let t1 = s.table(TestTable.self)
            return select(t1).from(t0).innerJoin(t1, on: t1.id == t0.id).where(t0.id == "foo").orderBy(t0.id.ascending())
        }
        assertRenders(expression, as: "SELECT t1.id AS id, t1.value AS value FROM Test AS t0 INNER JOIN Test AS t1 ON (t1.id == t0.id) WHERE (t0.id == 'foo') ORDER BY t0.id ASC")
    }
    
    func testSelectLimit() {
        let expression = sqlQuery { s in
            let t = s.table(TestTable.self)
            return select(t).from(t).limit(10)
        }
        assertRenders(expression, as: "SELECT t0.id AS id, t0.value AS value FROM Test AS t0 LIMIT 10")
    }
    
    func testSelectLimitOffset() {
        let expression = sqlQuery { s in
            let t = s.table(TestTable.self)
            return select(t).from(t).limit(10).offset(5)
        }
        assertRenders(expression, as: "SELECT t0.id AS id, t0.value AS value FROM Test AS t0 LIMIT 10 OFFSET 5")
    }
    
    //    func testSelectGroupBy() {
    //        let expression = sqlQuery {
    //            let t = from(TestTable.self)
    //            let result = result {
    //                TestColumns(
    //                    id: $0.column(t.id),
    //                    value: $0.column(t.value.sum())
    //                )
    //            }
    //            return select(result).groupBy(t.id)
    //        }
    //        XCTAssertEqual(encoder.makeSQL(expression), "SELECT t0.id AS c0, SUM(t0.value) AS c1 FROM Test AS t0 GROUP BY t0.id")
    //    }

    
    // MARK: Factored select (ie WITH common table expression)
    
    
    func testFactoredSelect() {
        let s = XLSchema()
        let foo = s.commonTable { s in
            let t = s.table(TestTable.self)
            return select(t).from(t)
        }
        let t = s.table(foo)
        let expression = with(foo).select(t).from(t)
        assertRenders(expression, as: "WITH cte0 AS (SELECT t0.id AS id, t0.value AS value FROM Test AS t0) SELECT t0.id AS id, t0.value AS value FROM cte0 AS t0")
    }
    
    
    func testNestedFactoredSelect() {
        let s = XLSchema()
        let bar = s.commonTable { s in
            let foo = s.commonTable { s in
                let test = s.table(TestTable.self)
                return select(test).from(test)
            }
            let test = s.table(foo)
            return with(foo).select(test).from(test)
        }
        let t = s.table(bar)
        let expression = with(bar).select(t).from(t)
        assertRenders(expression, as: "WITH cte0 AS (WITH cte0 AS (SELECT t0.id AS id, t0.value AS value FROM Test AS t0) SELECT t0.id AS id, t0.value AS value FROM cte0 AS t0) SELECT t0.id AS id, t0.value AS value FROM cte0 AS t0")
    }
    
    
    func testScalarCommonTableExpression() {
        let s = XLSchema()
        let cte = s.commonTable { schema in
            let r = SQLScalarResult<Int>.columns(scalarValue: 1)
            return select(r)
        }
        let t = s.table(cte)
        let expression = with(cte)
            .select(t)
            .from(t)
        assertRenders(expression, as: "WITH cte0 AS (SELECT 1 AS scalarValue) SELECT t0.scalarValue AS scalarValue FROM cte0 AS t0")
    }
    
    
    func testScalarResultCommonTableExpression() {
        let s = XLSchema()
        let cte = s.commonTable { schema in
            let r = SQLScalarResult<Int>.columns(scalarValue: 1)
            return select(r)
        }
        let t = s.table(cte)
        let r = TestTable.columns(id: "foo", value: t.scalarValue)
        let expression = with(cte)
            .select(r)
            .from(t)
        assertRenders(expression, as: "WITH cte0 AS (SELECT 1 AS scalarValue) SELECT 'foo' AS id, t0.scalarValue AS value FROM cte0 AS t0")
    }
}
