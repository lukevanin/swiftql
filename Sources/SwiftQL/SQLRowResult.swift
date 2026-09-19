//
//  SQLRowResult.swift
//
//
//  Ad hoc row projections used by the `#row` macro (see SQLRowMacro.swift).
//
//  Gated to Swift 6.1+: on both the pinned Swift 5.9.2 and Swift 6.0
//  compatibility cells, decoding a 2+ generic-parameter result type
//  (SQLRow2...6) through fetchAll()/publish() crashes swift-frontend in
//  IRGen. See #408 and COMPATIBILITY.md.
//

#if compiler(>=6.1)
import Foundation

///
/// A two-column ad hoc row projection.
///
/// `SQLRow2` and its siblings (`SQLRow3`...`SQLRow6`) exist so `#row(...)` can build a result
/// column set without requiring the caller to declare a named `@SQLResult` type first. Fields are
/// exposed positionally as `_0`, `_1`, ... because the columns have no caller-chosen name; declare
/// an `@SQLResult` type instead when the projection is reused or the columns deserve real names.
///
@SQLResult
public struct SQLRow2<C0, C1> where C0: XLLiteral & XLExpression, C1: XLLiteral & XLExpression {

    public var _0: C0
    public var _1: C1
}

extension SQLRow2: Equatable where C0: Equatable, C1: Equatable {

}

extension SQLRow2: Hashable where C0: Hashable, C1: Hashable {

}

///
/// The row crosses an isolation boundary on every observation path, so
/// ``XLRequest`` requires a `Sendable` row. A generic model cannot get this
/// conformance from `@SQLResult`: an extension macro cannot write a `where`
/// clause over its own type's generic signature. The macro documents this
/// exact spelling as the remedy. See `SQLMacro.swift` and issue #685.
///
extension SQLRow2: Sendable where C0: Sendable, C1: Sendable {

}


///
/// A three-column ad hoc row projection. See ``SQLRow2``.
///
@SQLResult
public struct SQLRow3<C0, C1, C2> where C0: XLLiteral & XLExpression, C1: XLLiteral & XLExpression, C2: XLLiteral & XLExpression {

    public var _0: C0
    public var _1: C1
    public var _2: C2
}

extension SQLRow3: Equatable where C0: Equatable, C1: Equatable, C2: Equatable {

}

extension SQLRow3: Hashable where C0: Hashable, C1: Hashable, C2: Hashable {

}

/// The `Sendable` conformance ``SQLRow2`` explains.
extension SQLRow3: Sendable where C0: Sendable, C1: Sendable, C2: Sendable {

}


///
/// A four-column ad hoc row projection. See ``SQLRow2``.
///
@SQLResult
public struct SQLRow4<C0, C1, C2, C3> where C0: XLLiteral & XLExpression, C1: XLLiteral & XLExpression, C2: XLLiteral & XLExpression, C3: XLLiteral & XLExpression {

    public var _0: C0
    public var _1: C1
    public var _2: C2
    public var _3: C3
}

extension SQLRow4: Equatable where C0: Equatable, C1: Equatable, C2: Equatable, C3: Equatable {

}

extension SQLRow4: Hashable where C0: Hashable, C1: Hashable, C2: Hashable, C3: Hashable {

}

/// The `Sendable` conformance ``SQLRow2`` explains.
extension SQLRow4: Sendable where C0: Sendable, C1: Sendable, C2: Sendable, C3: Sendable {

}


///
/// A five-column ad hoc row projection. See ``SQLRow2``.
///
@SQLResult
public struct SQLRow5<C0, C1, C2, C3, C4> where C0: XLLiteral & XLExpression, C1: XLLiteral & XLExpression, C2: XLLiteral & XLExpression, C3: XLLiteral & XLExpression, C4: XLLiteral & XLExpression {

    public var _0: C0
    public var _1: C1
    public var _2: C2
    public var _3: C3
    public var _4: C4
}

extension SQLRow5: Equatable where C0: Equatable, C1: Equatable, C2: Equatable, C3: Equatable, C4: Equatable {

}

extension SQLRow5: Hashable where C0: Hashable, C1: Hashable, C2: Hashable, C3: Hashable, C4: Hashable {

}

/// The `Sendable` conformance ``SQLRow2`` explains.
extension SQLRow5: Sendable where C0: Sendable, C1: Sendable, C2: Sendable, C3: Sendable, C4: Sendable {

}


///
/// A six-column ad hoc row projection. See ``SQLRow2``.
///
@SQLResult
public struct SQLRow6<C0, C1, C2, C3, C4, C5> where C0: XLLiteral & XLExpression, C1: XLLiteral & XLExpression, C2: XLLiteral & XLExpression, C3: XLLiteral & XLExpression, C4: XLLiteral & XLExpression, C5: XLLiteral & XLExpression {

    public var _0: C0
    public var _1: C1
    public var _2: C2
    public var _3: C3
    public var _4: C4
    public var _5: C5
}

extension SQLRow6: Equatable where C0: Equatable, C1: Equatable, C2: Equatable, C3: Equatable, C4: Equatable, C5: Equatable {

}

extension SQLRow6: Hashable where C0: Hashable, C1: Hashable, C2: Hashable, C3: Hashable, C4: Hashable, C5: Hashable {

}

/// The `Sendable` conformance ``SQLRow2`` explains.
extension SQLRow6: Sendable where C0: Sendable, C1: Sendable, C2: Sendable, C3: Sendable, C4: Sendable, C5: Sendable {

}
#endif
