import SwiftQL

func typeCheckIntegerBitwiseNotExpressions() {
    let integerLiteral: any XLExpression<Int> = 12
    let integerReference = XLNamedBindingReference<Int>(name: "integer")
    let composedIntegerExpression = integerReference + 5

    _ = ~integerLiteral
    _ = ~integerReference
    _ = ~composedIntegerExpression
}
