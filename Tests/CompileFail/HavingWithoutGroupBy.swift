import SwiftQL

func rejectHavingWithoutGroupBy(
    query: XLQueryTableStatement<Int, XLSQLiteDialect>,
    predicate: XLNamedBindingReference<Bool>
) {
    _ = query.having(predicate) // expected-error
}
