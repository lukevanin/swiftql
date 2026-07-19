import SwiftQL

func rejectWhereAfterOrderBy(
    query: XLQueryTableStatement<Int>,
    value: XLNamedBindingReference<Int>,
    predicate: XLNamedBindingReference<Bool>
) {
    _ = query.orderBy(value.ascending()).where(predicate) // expected-error
}
