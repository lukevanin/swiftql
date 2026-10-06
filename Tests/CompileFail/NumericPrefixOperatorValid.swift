import SwiftQL

// Issue #771. `Int` and `Double` conform to `XLExpression`, so a plain number
// also matches SwiftQL's generic prefix operators. A client file must still get
// the standard library operator for such an operand, and the SwiftQL operator
// for an expression operand.

func takesInteger(_ value: Int) {}

func takesReal(_ value: Double) {}

func typeCheckNumberPrefixOperators(integer: Int, real: Double) {
    let negatedInteger = -integer
    let positiveInteger = +integer
    let invertedInteger = ~integer
    let negatedReal = -real
    let positiveReal = +real

    takesInteger(negatedInteger)
    takesInteger(positiveInteger)
    takesInteger(invertedInteger)
    takesReal(negatedReal)
    takesReal(positiveReal)
}

func typeCheckExpressionPrefixOperators() {
    let integerReference = XLNamedBindingReference<Int>(name: "integer")
    let realReference = XLNamedBindingReference<Double>(name: "real")
    let optionalReference = XLNamedBindingReference<Optional<Int>>(
        name: "optionalInteger"
    )

    let _: any XLExpression<Int> = -integerReference
    let _: any XLExpression<Int> = +integerReference
    let _: any XLExpression<Int> = ~integerReference
    let _: any XLExpression<Int> = -(-integerReference)
    let _: any XLExpression<Double> = -realReference
    let _: any XLExpression<Double> = +realReference
    let _: any XLExpression<Optional<Int>> = -optionalReference
    let _: any XLExpression<Optional<Int>> = ~optionalReference
}
