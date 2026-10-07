import SwiftQL

func typeCheckIntegerBitwiseNotExpressions() {
    let integerLiteral: any XLSQLiteExpression<Int> = 12
    let integerReference = XLNamedBindingReference<Int>(name: "integer")
    let composedIntegerExpression = integerReference + 5

    _ = ~integerLiteral
    _ = ~integerReference
    _ = ~composedIntegerExpression
}
