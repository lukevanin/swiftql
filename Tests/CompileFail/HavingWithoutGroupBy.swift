import SwiftQL

func rejectHavingWithoutGroupBy(
    query: XLQueryTableStatement<Int>,
    predicate: XLNamedBindingReference<Bool>
) {
    _ = query.having(predicate) // expected-error
}
