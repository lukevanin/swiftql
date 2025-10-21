//
//  Intrinsic.swift
//  
//
//  Created by Luke Van In on 2023/08/04.
//

import Foundation


///
/// Adds support for `Bool` types to be used as SwiftQL columns.
///
/// The boolean type is emulated in SQLite using an `Int` storage. A  literal zero represents a `false`
/// value, and any other value represents `true`.
///
extension Bool: XLExpression, XLLiteral, XLEquatable, XLComparable {
    
    public typealias T = Self
    
    public init(reader: XLColumnReader, at index: Int) {
        self = reader.readInteger(at: index) != 0
    }
    
    public func bind(context: inout XLBindingContext) {
        context.bindInteger(value: self ? 1 : 0)
    }

    public static func sqlDefault() -> Bool {
        false
    }
    
    public func makeSQL(context: inout XLBuilder) {
        context.integer(self ? 1 : 0)
    }
}


///
/// Adds support for `Int` types to be used as SwiftQL columns.
///
extension Int: XLExpression, XLLiteral, XLEquatable, XLComparable {
    
    public typealias T = Self
    
    public init(reader: XLColumnReader, at index: Int) {
        self = reader.readInteger(at: index)
    }
    
    public func bind(context: inout XLBindingContext) {
        context.bindInteger(value: self)
    }
    
    public static func sqlDefault() -> Int {
        0
    }
    
    public func makeSQL(context: inout XLBuilder) {
        context.integer(self)
    }
}


///
/// Adds support for `Double` types to be used as SwiftQL columns.
///
extension Double: XLExpression, XLLiteral, XLEquatable, XLComparable {
    
    public typealias T = Self
    
    public init(reader: XLColumnReader, at index: Int) {
        self = reader.readReal(at: index)
    }
    
    public func bind(context: inout XLBindingContext) {
        context.bindReal(value: self)
    }

    public static func sqlDefault() -> Double {
        0.0
    }
    
    public func makeSQL(context: inout XLBuilder) {
        context.real(self)
    }
    
    public func relatedEntities() -> Set<String> {
        []
    }
}


///
/// Adds support for `String` types to be used as SwiftQL columns.
///
extension String: XLExpression, XLLiteral, XLEquatable, XLComparable {
    
    public typealias T = Self
    
    public init(reader: XLColumnReader, at index: Int) {
        self = reader.readText(at: index)
    }
    
    public func bind(context: inout XLBindingContext) {
        context.bindText(value: self)
    }

    public static func sqlDefault() -> String {
        ""
    }
    
    public func makeSQL(context: inout XLBuilder) {
        context.text(self)
    }
}


///
/// Adds support for `Data` types to be used as SwiftQL columns.
///
extension Data: XLExpression, XLLiteral, XLEquatable {
    
    public typealias T = Self
    
    public init(reader: XLColumnReader, at index: Int) {
        self = reader.readBlob(at: index)
    }
    
    public func bind(context: inout XLBindingContext) {
        context.bindBlob(value: self)
    }

    public static func sqlDefault() -> Data {
        Data()
    }
    
    public func makeSQL(context: inout XLBuilder) {
        context.blob(self)
    }
}
