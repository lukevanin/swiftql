import SwiftQL

func rejectOffsetWithoutLimit(query: XLQueryTableStatement<Int>) {
    _ = query.offset(2) // expected-error
}
