import Foundation
import SwiftQL

func rejectNonComparableBetweenExpression() {
    let data = XLNamedBindingReference<Data>(name: "data")
    _ = data.isBetween(Data(), Data()) // expected-error
}
