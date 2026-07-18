import XCTest
import SwiftQL


final class XLMetaDependencyTests: XCTestCase {

    private let encoder = XLiteEncoder(
        formatter: XLiteFormatter(identifierFormattingOptions: .mysqlCompatible)
    )

    func testFromTableDependencyRendersQualifiedNameAndRecordsBaseEntity() {
        let dependency = XLFromTableDependency(
            qualifiedName: XLQualifiedTableName(name: "base_table"),
            alias: "t"
        )

        let encoding = encoder.makeSQL(dependency)

        XCTAssertEqual(encoding.sql, "`base_table` AS `t`")
        XCTAssertEqual(encoding.entities, ["base_table"])
        XCTAssertEqual(
            encoder.makeSQL(dependency.qualifiedName(forColumn: "value")).sql,
            "`t`.`value`"
        )
    }

    func testFromTableDependencyRendersOnlyCommonTableAlias() {
        let statement = ProbeStatement()
        let commonTable = XLCommonTableDependency(
            alias: "cte",
            statement: statement
        )
        let dependency = XLFromTableDependency(
            commonTable: commonTable,
            alias: "t"
        )

        let encoding = encoder.makeSQL(dependency)

        XCTAssertEqual(encoding.sql, "`cte` AS `t`")
        XCTAssertEqual(encoding.entities, [])
        XCTAssertEqual(statement.renderCount, 0)
    }

    func testFromTableDependencySnapshotsCommonTableAlias() {
        var commonTable = XLCommonTableDependency(
            alias: "cte",
            statement: ProbeStatement()
        )
        let dependency = XLFromTableDependency(
            commonTable: commonTable,
            alias: "t"
        )

        commonTable.alias = "changed"

        XCTAssertEqual(encoder.makeSQL(dependency).sql, "`cte` AS `t`")
    }

    func testFromTableDependencyCopiesAliasWithValueSemantics() {
        let original = XLFromTableDependency(
            qualifiedName: XLQualifiedTableName(name: "base_table"),
            alias: "t"
        )
        var copy = original

        copy.alias = "copy"

        XCTAssertEqual(encoder.makeSQL(original).sql, "`base_table` AS `t`")
        XCTAssertEqual(encoder.makeSQL(copy).sql, "`base_table` AS `copy`")
    }

    func testFromTableDependencyDoesNotRetainCommonTableStatement() {
        var dependency: XLFromTableDependency?
        weak var weakStatement: ProbeStatement?

        do {
            let statement = ProbeStatement()
            weakStatement = statement
            let commonTable = XLCommonTableDependency(
                alias: "cte",
                statement: statement
            )
            dependency = XLFromTableDependency(
                commonTable: commonTable,
                alias: "t"
            )
        }

        XCTAssertNil(weakStatement)
        XCTAssertEqual(encoder.makeSQL(dependency!).sql, "`cte` AS `t`")
    }

    @available(*, deprecated)
    func testDeprecatedFromCommonTableDependencyNameStillRenders() {
        let commonTable = XLCommonTableDependency(
            alias: "cte",
            statement: ProbeStatement()
        )
        let dependency = XLFromCommonTableDependency(
            commonTable: commonTable,
            alias: "t"
        )

        XCTAssertEqual(encoder.makeSQL(dependency).sql, "`cte` AS `t`")
    }
}


private final class ProbeStatement: XLEncodable {

    private(set) var renderCount = 0

    func makeSQL(context: inout XLBuilder) {
        renderCount += 1
        context.name("definition_body")
        context.entity("definition_body")
    }
}
