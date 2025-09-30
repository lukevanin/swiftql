//
//  File.swift
//  
//
//  Created by Luke Van In on 2024/10/28.
//

import XCTest

@testable import SwiftQL


final class XLQueryExpressionBuilderTests: XCTestCase {
    
    var encoder: XLiteEncoder!
    
    override func setUp() {
        let formatter = XLiteFormatter(
            identifierFormattingOptions: .noEscape
        )
        encoder = XLiteEncoder(formatter: formatter)
    }
    
    override func tearDown() {
        encoder = nil
    }
    
    
    // MARK: SELECT ... FROM
    
    func testSelectFrom() throws {
        let expression = sql { schema in
            let t = schema.table(TestTable.self)
            Select(t)
            From(t)
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "SELECT t0.id AS id, t0.value AS value FROM Test AS t0")
    }
    
    func testSelectWhere() {
        let expression = sql { schema in
            let t = schema.table(TestTable.self)
            Select(t)
            From(t)
            Where(t.value > 0)
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "SELECT t0.id AS id, t0.value AS value FROM Test AS t0 WHERE (t0.value > 0)")
    }
    
    func testSelectJoin() {
        let expression = sql { s in
            let t0 = s.table(TestTable.self)
            let t1 = s.table(TestTable.self)
            Select(t1)
            From(t0)
            Join.Inner(t1, on: t1.id == t0.id)
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "SELECT t1.id AS id, t1.value AS value FROM Test AS t0 INNER JOIN Test AS t1 ON (t1.id == t0.id)")
    }
    
    func testSelectJoinWhere() {
        let expression = sql { s in
            let t0 = s.table(TestTable.self)
            let t1 = s.table(TestTable.self)
            Select(t1)
            From(t0)
            Join.Inner(t1, on: t1.id == t0.id)
            Where(t0.id == "foo")
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "SELECT t1.id AS id, t1.value AS value FROM Test AS t0 INNER JOIN Test AS t1 ON (t1.id == t0.id) WHERE (t0.id == 'foo')")
    }
    
    func testSelectJoinJoinWhere() {
        let expression = sql { s in
            let t0 = s.table(TestTable.self)
            let t1 = s.table(TestTable.self)
            let t2 = s.table(TestTable.self)
            Select(t2)
            From(t0)
            Join.Inner(t1, on: t1.id == t0.id)
            Join.Inner(t2, on: t2.id == t1.id)
            Where(t0.id == "foo")
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "SELECT t2.id AS id, t2.value AS value FROM Test AS t0 INNER JOIN Test AS t1 ON (t1.id == t0.id) INNER JOIN Test AS t2 ON (t2.id == t1.id) WHERE (t0.id == 'foo')")
    }
    
    func testSelectOrder() {
        let expression = sql { s in
            let t = s.table(TestTable.self)
            Select(t)
            From(t)
            OrderBy(t.id.ascending())
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "SELECT t0.id AS id, t0.value AS value FROM Test AS t0 ORDER BY t0.id ASC")
    }
    
    func testSelectJoinOrder() {
        let expression = sql { s in
            let t0 = s.table(TestTable.self)
            let t1 = s.table(TestTable.self)
            Select(t1)
            From(t0)
            Join.Inner(t1, on: t1.id == t0.id)
            OrderBy(t0.id.ascending())
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "SELECT t1.id AS id, t1.value AS value FROM Test AS t0 INNER JOIN Test AS t1 ON (t1.id == t0.id) ORDER BY t0.id ASC")
    }
    
    func testSelectWhereOrder() {
        let expression = sql { s in
            let t = s.table(TestTable.self)
            Select(t)
            From(t)
            Where(t.id == "foo")
            OrderBy(t.id.ascending())
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "SELECT t0.id AS id, t0.value AS value FROM Test AS t0 WHERE (t0.id == 'foo') ORDER BY t0.id ASC")
    }
    
    func testSelectJoinWhereOrder() {
        let expression = sql { s in
            let t0 = s.table(TestTable.self)
            let t1 = s.table(TestTable.self)
            Select(t1)
            From(t0)
            Join.Inner(t1, on: t1.id == t0.id)
            Where(t0.id == "foo")
            OrderBy(t0.id.ascending())
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "SELECT t1.id AS id, t1.value AS value FROM Test AS t0 INNER JOIN Test AS t1 ON (t1.id == t0.id) WHERE (t0.id == 'foo') ORDER BY t0.id ASC")
    }
    
    func testSelectLimit() {
        let expression = sql { s in
            let t = s.table(TestTable.self)
            Select(t)
            From(t)
            Limit(10)
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "SELECT t0.id AS id, t0.value AS value FROM Test AS t0 LIMIT 10")
    }
    
    func testSelectLimitOffset() {
        let expression = sql { s in
            let t = s.table(TestTable.self)
            Select(t)
            From(t)
            Limit(10)
            Offset(5)
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "SELECT t0.id AS id, t0.value AS value FROM Test AS t0 LIMIT 10 OFFSET 5")
    }
    
    
    // MARK: - Factored Select (Common Table Expression)
    
    
    func testFactoredSelect() {
        let expression = sql { schema in
            let foo = schema.commonTableExpression { schema in
                let t = schema.table(TestTable.self)
                Select(t)
                From(t)
            }
            let t = schema.table(foo)
            With(foo)
            Select(t)
            From(t)
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "WITH cte0 AS (SELECT t0.id AS id, t0.value AS value FROM Test AS t0) SELECT t0.id AS id, t0.value AS value FROM cte0 AS t0")
    }
    
    
    func testNestedFactoredSelect() {
        let expression = sql { schema in
            let bar = schema.commonTableExpression { schema in
                let foo = schema.commonTableExpression { schema in
                    let test = schema.table(TestTable.self)
                    Select(test)
                    From(test)
                }
                let test = schema.table(foo)
                With(foo)
                Select(test)
                From(test)
            }
            let t = schema.table(bar)
            With(bar)
            Select(t)
            From(t)
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "WITH cte0 AS (WITH cte0 AS (SELECT t0.id AS id, t0.value AS value FROM Test AS t0) SELECT t0.id AS id, t0.value AS value FROM cte0 AS t0) SELECT t0.id AS id, t0.value AS value FROM cte0 AS t0")
    }
    
    
    // MARK: - Recursive Common Table Expressions
    
    
    func testRecursiveCommonTableExpression() {
        typealias Scalar = SQLScalarResult<String?>
        let expression = sql { schema in
            let cte = schema.recursiveCommonTableExpression(Scalar.self) { schema, cte in
                let org = schema.table(Org.self)
                
                let initialResult = result {
                    Scalar.SQLReader(scalarValue: "Alice".toNullable())
                }
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
        let finalResult = encoder.makeSQL(expression)
        XCTAssertEqual(finalResult.sql, "WITH cte0 AS (SELECT 'Alice' AS scalarValue UNION SELECT t0.name AS scalarValue FROM Org AS t0 CROSS JOIN cte0 AS t0 WHERE (t0.boss IS t0.scalarValue)) SELECT t1.name FROM Org AS t1 WHERE (t1.name IN cte0)")
    }
    
    
    func testRecursiveCommonTableExpressionUsingCommonTableExpression() {

        typealias Scalar = SQLScalarResult<String?>
        let expression = sql { schema in
            
            let parentOfCommonTable = schema.commonTableExpression { schema in
                let family = schema.table(Family.self)
                let momRow = result {
                    FamilyMemberParent.SQLReader(name: family.name, parent: family.mom)
                }
                let dadRow = result {
                    FamilyMemberParent.SQLReader(name: family.name, parent: family.dad)
                }
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
        
        let finalResult = encoder.makeSQL(expression)
        XCTAssertEqual(finalResult.sql, "WITH cte0 AS (SELECT t0.name AS name, t0.mom AS parent FROM Family AS t0 UNION SELECT t0.name AS name, t0.dad AS parent FROM Family AS t0), cte1 AS (SELECT t0.parent AS scalarValue FROM cte0 AS t0 WHERE (t0.name IS 'Alice') UNION ALL SELECT t0.parent AS scalarValue FROM cte0 AS t0 INNER JOIN cte1 AS t0 ON (t0.scalarValue IS t0.name)) SELECT t2.name FROM cte1 AS t1 CROSS JOIN Family AS t2 WHERE ((t1.scalarValue IS t2.name) AND (julianday(t2.died) ISNULL)) ORDER BY julianday(t2.born) ASC")
    }
    
    
    // MARK: - Union
    
    
    func testUnion() throws {
        let expression = sql { schema in
            let familyMom = schema.table(Family.self)
            let familyDad = schema.table(Family.self)
            let momRow = result {
                FamilyMemberParent.SQLReader(name: familyMom.name, parent: familyMom.mom)
            }
            let dadRow = result {
                FamilyMemberParent.SQLReader(name: familyDad.name, parent: familyDad.dad)
            }
            Select(momRow)
            From(familyMom)
            Union()
            Select(dadRow)
            From(familyDad)
        }
        let finalResult = encoder.makeSQL(expression)
        XCTAssertEqual(finalResult.sql, "SELECT t0.name AS name, t0.mom AS parent FROM Family AS t0 UNION SELECT t1.name AS name, t1.dad AS parent FROM Family AS t1")
    }
    
    
    func testUnionAll() throws {
        let expression = sql { schema in
            let familyMom = schema.table(Family.self)
            let familyDad = schema.table(Family.self)
            let momRow = FamilyMemberParent.columns(name: familyMom.name, parent: familyMom.mom)
            let dadRow = FamilyMemberParent.columns(name: familyDad.name, parent: familyDad.dad)
            Select(momRow)
            From(familyMom)
            UnionAll()
            Select(dadRow)
            From(familyDad)
        }
        let finalResult = encoder.makeSQL(expression)
        XCTAssertEqual(finalResult.sql, "SELECT t0.name AS name, t0.mom AS parent FROM Family AS t0 UNION ALL SELECT t1.name AS name, t1.dad AS parent FROM Family AS t1")
    }
    
    
    func testIntersect() throws {
        let expression = sql { schema in
            let familyMom = schema.table(Family.self)
            let familyDad = schema.table(Family.self)
            let momRow = result {
                FamilyMemberParent.SQLReader(name: familyMom.name, parent: familyMom.mom)
            }
            let dadRow = result {
                FamilyMemberParent.SQLReader(name: familyDad.name, parent: familyDad.dad)
            }
            Select(momRow)
            From(familyMom)
            Intersect()
            Select(dadRow)
            From(familyDad)
        }
        let finalResult = encoder.makeSQL(expression)
        XCTAssertEqual(finalResult.sql, "SELECT t0.name AS name, t0.mom AS parent FROM Family AS t0 INTERSECT SELECT t1.name AS name, t1.dad AS parent FROM Family AS t1")
    }
    
    
    func testExcept() throws {
        let expression = sql { schema in
            let familyMom = schema.table(Family.self)
            let familyDad = schema.table(Family.self)
            let momRow = result {
                FamilyMemberParent.SQLReader(name: familyMom.name, parent: familyMom.mom)
            }
            let dadRow = result {
                FamilyMemberParent.SQLReader(name: familyDad.name, parent: familyDad.dad)
            }
            Select(momRow)
            From(familyMom)
            Except()
            Select(dadRow)
            From(familyDad)
        }
        let finalResult = encoder.makeSQL(expression)
        XCTAssertEqual(finalResult.sql, "SELECT t0.name AS name, t0.mom AS parent FROM Family AS t0 EXCEPT SELECT t1.name AS name, t1.dad AS parent FROM Family AS t1")
    }
    
    
    func testUnionOrderBy() throws {
        let expression = sql { schema in
            let familyMom = schema.table(Family.self)
            let familyDad = schema.table(Family.self)
            let momRow = result {
                FamilyMemberParent.SQLReader(name: familyMom.name, parent: familyMom.mom)
            }
            let dadRow = result {
                FamilyMemberParent.SQLReader(name: familyDad.name, parent: familyDad.dad)
            }
            Select(momRow)
            From(familyMom)
            Union()
            Select(dadRow)
            From(familyDad)
            OrderBy(momRow.name.ascending())
        }
        let finalResult = encoder.makeSQL(expression)
        XCTAssertEqual(finalResult.sql, "SELECT t0.name AS name, t0.mom AS parent FROM Family AS t0 UNION SELECT t1.name AS name, t1.dad AS parent FROM Family AS t1 ORDER BY name ASC")
    }
    
    
    func testUnionWithCommonTableExpression() throws {
        let expression = sql { schema in
            let cte = schema.commonTableExpression { schema in
                let family = schema.table(Family.self)
                Select(family)
                From(family)
            }
                
            let familyMom = schema.table(cte)
            let familyDad = schema.table(cte)
            let momRow = result {
                FamilyMemberParent.SQLReader(name: familyMom.name, parent: familyMom.mom)
            }
            let dadRow = result {
                FamilyMemberParent.SQLReader(name: familyDad.name, parent: familyDad.dad)
            }
            
            With(cte)
            Select(momRow)
            From(familyMom)
            Union()
            Select(dadRow)
            From(familyDad)
        }
        let finalResult = encoder.makeSQL(expression)
        
        XCTAssertEqual(finalResult.sql, "WITH cte0 AS (SELECT t0.name AS name, t0.mom AS mom, t0.dad AS dad, julianday(t0.born) AS born, julianday(t0.died) AS died FROM Family AS t0) SELECT t0.name AS name, t0.mom AS parent FROM cte0 AS t0 UNION SELECT t1.name AS name, t1.dad AS parent FROM cte0 AS t1")
    }
    
    
    // MARK: - Subquery
    
    func testInlineSubquery() {
        let expression = sql { schema in
            let t = schema.table(TestTable.self)
            Select(t)
            From(
                subqueryExpression { _ in
                    Select(t)
                    From(t)
                    Where(t.value > 10)
                }
            )
            Where(t.value < 10)
        }
        XCTAssertEqual(
            encoder.makeSQL(expression).sql,
            "SELECT t0.id AS id, t0.value AS value FROM (SELECT t0.id AS id, t0.value AS value FROM Test AS t0 WHERE (t0.value > 10)) AS t0 WHERE (t0.value < 10)"
        )
    }
    
    
    // MARK: - Scalar select
    
    func testScalarSelect() {
        let expression = sql { schema in
            let t = schema.table(TestTable.self)
            Select(t.id)
            From(t)
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "SELECT t0.id FROM Test AS t0")
    }
    
    func testSelectSubqueryAggregate() {
        let expression = sql { schema in
            let t = schema.table(TestTable.self)
            let r = result {
                TestColumns.SQLReader(
                    id: t.id,
                    value: subqueryExpression { schema in
                        let t = schema.table(TestTable.self)
                        Select(t.value.sum())
                        From(t)
                    }
                )
            }
            Select(r)
            From(t)
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "SELECT t0.id AS id, (SELECT SUM(t0.value) FROM Test AS t0) AS value FROM Test AS t0")
    }
    
    func testScalarSelectWhereIn() {
        let expression = sql { schema in
            let t = schema.table(TestTable.self)
            Select(t)
            From(t)
            Where(t.id.in { _ in
                Select(t.id)
                From(t)
            })
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "SELECT t0.id AS id, t0.value AS value FROM Test AS t0 WHERE (t0.id IN (SELECT t0.id FROM Test AS t0))")
    }
    
    
    // MARK: - Select Variable Parameter Binding
    
    func testVariableBinding() {
        let idParameter = XLNamedBindingReference<String>(name: "id")
        let expression = sql { schema in
            let t = schema.table(TestTable.self)
            Select(t)
            From(t)
            Where(t.id == idParameter)
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "SELECT t0.id AS id, t0.value AS value FROM Test AS t0 WHERE (t0.id == :id)")
    }
}
