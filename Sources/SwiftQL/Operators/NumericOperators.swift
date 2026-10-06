//
//  NumericOperators.swift
//  
//
//  Created by Luke Van In on 2023/08/07.
//

import Foundation


// MARK: - Standard library numeric operands


// `Int` and `Double` are expressions of every dialect, so a plain `Int` or
// `Double` operand also matches each dialect's generic prefix operators,
// which scripts/dialect-surface generates from
// Templates/NumericOperators.swift.template and
// Templates/IntegerOperators.swift.template (issue #789). Swift 5.9 and Swift 6.4
// still pick the standard library operator for such an operand, but Swift 6.3
// picks SwiftQL's, and `let x = -someInt` stops compiling in every file that
// imports SwiftQL (issue #771). These exact-match overloads restore `Int` and
// `Double` on every compiler.
//
// `Double` gets a `+` overload only. For `-someDouble`, Swift 6.3 already picks
// the standard library operator, and an exact-match `-` overload for `Double`
// makes `-someDouble` ambiguous.

public prefix func +(operand: Int) -> Int {
    operand
}

public prefix func -(operand: Int) -> Int {
    0 - operand
}

public prefix func +(operand: Double) -> Double {
    operand
}

// Keeps `~someInt` typed as `Int` on Swift 6.3. The comment above explains
// why the exact-match overload is needed (issue #771).

public prefix func ~(operand: Int) -> Int {
    operand ^ -1
}
