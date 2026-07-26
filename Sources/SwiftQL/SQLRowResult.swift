//
//  SQLRowResult.swift
//
//
//  Ad hoc row projections used by the `#row` macro (see SQLRowMacro.swift).
//
//  Gated to Swift 6.0+: on the pinned Swift 5.9.2 compatibility cell,
//  decoding a 2+ generic-parameter result type (SQLRow2...6) through
//  fetchAll()/publish() crashes swift-frontend in IRGen
//  (NativeConventionSchema::mapIntoNative). See #408 and COMPATIBILITY.md.
//

#if compiler(>=6.0)
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
#endif
