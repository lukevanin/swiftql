import SwiftQL

func typeCheckBetweenExpressions() {
    let value = XLNamedBindingReference<Int>(name: "value")
    let optionalValue = XLNamedBindingReference<Optional<Int>>(name: "optionalValue")
    let minimum = XLNamedBindingReference<Int>(name: "minimum")
    let maximum = XLNamedBindingReference<Int>(name: "maximum")

    let literalBounds: any XLExpression<Bool> = value.isBetween(5, 10)
    let bindingBounds: any XLExpression<Bool> = value.isNotBetween(minimum, maximum)
    let nullableResult: any XLExpression<Optional<Bool>> = optionalValue.isBetween(5, 10)

    _ = literalBounds
    _ = bindingBounds
    _ = nullableResult
}
