//
//  File.swift
//  
//
//  Created by Luke Van In on 2023/09/01.
//

import Foundation


// MARK: - Bool


extension XLExpression {
    
    public func toInt() -> some XLExpression<Int> where T == Bool {
        XLTypeAffinityExpression<Int>(expression: self)
    }
}


// MARK: - Optional Bool


extension XLExpression {
    
    public func toInt() -> some XLExpression<Optional<Int>> where T == Optional<Bool> {
        XLTypeAffinityExpression<Optional<Int>>(expression: self)
    }
}


// MARK: - Int

extension XLExpression {
    
    public func toDouble() -> some XLExpression<Double> where T == Int {
        XLTypeCastExpression(type: "REAL", expression: self)
    }

    public func toString() -> some XLExpression<String> where T == Int {
        XLTypeCastExpression(type: "TEXT", expression: self)
    }
}


// MARK: - Optional Int

extension XLExpression {
    
    public func toDouble() -> some XLExpression<Optional<Double>> where T == Optional<Int> {
        XLTypeCastExpression(type: "REAL", expression: self)
    }

    public func toString() -> some XLExpression<Optional<String>> where T == Optional<Int> {
        XLTypeCastExpression(type: "TEXT", expression: self)
    }
}


// MARK: - Double

extension XLExpression {
    
    public func toInt() -> some XLExpression<Int> where T == Double {
        XLTypeCastExpression(type: "INTEGER", expression: self)
    }

    public func toString() -> some XLExpression<String> where T == Double {
        XLTypeCastExpression(type: "TEXT", expression: self)
    }
}


// MARK: - Optional Double


extension XLExpression {
    
    public func toInt() -> some XLExpression<Optional<Int>> where T == Optional<Double> {
        XLTypeCastExpression(type: "INTEGER", expression: self)
    }

    public func toString() -> some XLExpression<Optional<String>> where T == Optional<Double> {
        XLTypeCastExpression(type: "TEXT", expression: self)
    }
}


// MARK: - String


extension XLExpression {
    
    public func toInt() -> some XLExpression<Int> where T == String {
        XLTypeCastExpression(type: "INTEGER", expression: self)
    }
    
    public func toDouble() -> some XLExpression<Double> where T == String {
        XLTypeCastExpression(type: "REAL", expression: self)
    }
    
    public func toData() -> some XLExpression<Data> where T == String {
        XLTypeCastExpression(type: "NONE", expression: self)
    }
}


// MARK: - Optional String


extension XLExpression {
    
    public func toInt() -> some XLExpression<Optional<Int>> where T == Optional<String> {
        XLTypeCastExpression(type: "INTEGER", expression: self)
    }
    
    public func toDouble() -> some XLExpression<Optional<Double>> where T == Optional<String> {
        XLTypeCastExpression(type: "REAL", expression: self)
    }
    
    public func toData() -> some XLExpression<Optional<Data>> where T == Optional<String> {
        XLTypeCastExpression(type: "NONE", expression: self)
    }
}


// MARK: - Data


extension XLExpression {
    
    public func toString() -> some XLExpression<String> where T == Data {
        XLTypeCastExpression(type: "TEXT", expression: self)
    }
}


// MARK: - Optional Data


extension XLExpression {
    
    public func toString() -> some XLExpression<Optional<String>> where T == Optional<Data> {
        XLTypeCastExpression(type: "TEXT", expression: self)
    }
}
