//
//  Intrinsic.swift
//  
//
//  Created by Luke Van In on 2023/08/04.
//

import Foundation


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
