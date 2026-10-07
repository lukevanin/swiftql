import SwiftQL

func rejectOffsetWithoutLimit(query: XLQueryTableStatement<Int, XLSQLiteDialect>) {
    _ = query.offset(2) // expected-error
}
