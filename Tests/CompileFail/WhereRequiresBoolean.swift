import SwiftQL

func rejectNonBooleanWherePredicate(
    query: XLQueryTableStatement<Int, XLSQLiteDialect>,
    value: XLNamedBindingReference<Int>
) {
    _ = query.where(value) // expected-error
}
