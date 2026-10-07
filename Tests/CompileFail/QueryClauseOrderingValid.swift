import SwiftQL

func typeCheckValidQueryClauseOrdering(
    query: XLQueryTableStatement<Int, XLSQLiteDialect>,
    value: XLNamedBindingReference<Int>,
    predicate: XLNamedBindingReference<Bool>
) {
    _ = query
        .where(predicate)
        .orderBy(value.ascending())
        .limit(10)
        .offset(2)

    _ = query
        .groupBy(value)
        .having(predicate)
        .orderBy(value.ascending())
        .limit(10)
        .offset(2)

    // Issue #657: a plain branch still compiles, and ORDER BY, LIMIT, and
    // OFFSET apply to the whole compound after its last branch.
    _ = query
        .union { query.where(predicate) }
        .orderBy(value.ascending())
        .limit(10)
        .offset(2)

    // A branch known only as a statement of the query's dialect still
    // compiles. Its clauses are checked when the compound renders.
    let erased: any XLDialectQueryStatement<Int, XLSQLiteDialect> = query
    _ = query.unionAll { erased }
}
