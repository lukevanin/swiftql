import SwiftQL

func typeCheckValidQueryClauseOrdering(
    query: XLQueryTableStatement<Int>,
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
}
