import SwiftQL

func rejectNonBooleanWherePredicate(
    query: XLQueryTableStatement<Int>,
    value: XLNamedBindingReference<Int>
) {
    _ = query.where(value) // expected-error
}
