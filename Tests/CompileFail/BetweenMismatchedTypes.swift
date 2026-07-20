import SwiftQL

func rejectMismatchedBetweenBounds() {
    let integer = XLNamedBindingReference<Int>(name: "integer")
    let minimum = XLNamedBindingReference<String>(name: "minimum")
    _ = integer.isBetween(minimum, "z") // expected-error
}
