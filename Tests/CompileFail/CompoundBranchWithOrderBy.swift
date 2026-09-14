import SwiftQL

// Issue #657: SQLite applies ORDER BY, LIMIT, and OFFSET to a whole compound
// select, so a right-hand branch that ends with one of them must not compile.
func rejectCompoundBranchWithOrderBy(
    query: XLQueryTableStatement<Int>,
    branch: XLQueryTableStatement<Int>,
    value: XLNamedBindingReference<Int>
) {
    _ = query.union { branch.orderBy(value.ascending()) } // expected-error
}
