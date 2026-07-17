import SwiftQL

func rejectDoubleBitwiseNotExpression() {
    let realExpression = XLNamedBindingReference<Double>(name: "real")
    _ = ~realExpression // expected-error
}
