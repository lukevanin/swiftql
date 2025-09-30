//
//  Date.swift
//  
//
//  Created by Luke Van In on 2023/08/04.
//

import Foundation


#warning("TODO: Support time intervals (eg relative time offsets")

#warning("TODO: Support custom date formats")

#warning("TODO: Support floating point date")

#warning("TODO: Date operators: !=, >=, <, <=, -")

#warning("TODO: Support date components")


#warning("TODO: Use property wrapper to specify date formatting")

//@propertyWrapper public struct XLDate {
//    
//    public enum Format {
//        case iso8601
//    }
//    
//    public var wrappedValue: Date
//    
//    public init(format: Format, wrappedValue: Date) {
//        self.wrappedValue = wrappedValue
//    }
//}


#warning("TODO: Make XLISO8601Date a property wrapper")
//public struct XLISO8601Date: XLExpression, XLLiteral, XLEquatable, XLComparable {
//    
//    private static let dateFormatter: ISO8601DateFormatter = {
//        let formatter = ISO8601DateFormatter()
//        formatter.formatOptions = [
//            .withDashSeparatorInDate,
//            .withColonSeparatorInTime,
//            .withFullDate,
//            .withFullTime,
//            .withFractionalSeconds
//        ]
//        return formatter
//    }()
//    
//    public typealias T = Self
//    
//    let date: Date
//    
//    public init(_ date: Date) {
//        self.date = date
//    }
//    
//    public init(reader: XLColumnReader, at index: Int) {
//        let rawValue = reader.readText(at: index)
//        #warning("TODO: Throw error")
//        self.date = Self.dateFormatter.date(from: rawValue)!
//    }
//    
//    public func makeSQL(context: inout XLBuilder) {
//        context.simpleFunction(name: "unixepoch") { context in
//            context.listItem { context in
//                context.text(Self.dateFormatter.string(from: date))
//            }
//            context.listItem { context in
//                context.text("subsec")
//            }
//        }
//    }
//    
//    public static func sqlDefault() -> XLISO8601Date {
//        XLISO8601Date(.distantPast)
//    }
//}


//extension XLExpression {
//    
//    public func toTimeInterval() -> some XLExpression<XLTimeInterval> where T == XLISO8601Date {
//        XLTypeCastExpression<XLTimeInterval> { context in
//            makeSQL(context: &context)
//        }
//    }
//}


//public struct XLTimeInterval: XLLiteral, XLExpression, XLEquatable, XLComparable {
//    
//    public typealias T = Self
//    
//    private let timeInterval: TimeInterval
//    
//    public init(_ date: Date) {
//        self.init(date.timeIntervalSince1970)
//    }
//    
//    public init(_ timeInterval: TimeInterval) {
//        self.timeInterval = timeInterval
//    }
//    
//    public init(reader: XLColumnReader, at index: Int) {
//        self.timeInterval = reader.readReal(at: index)
//    }
//    
//    public func makeSQL(context: inout XLBuilder) {
//        context.real(timeInterval)
//    }
//    
//    public static func sqlDefault() -> XLTimeInterval {
//        XLTimeInterval(0)
//    }
//}


//extension XLExpression {
//    
//    public func toISO8601Date() -> some XLExpression<XLISO8601Date> where T == XLTimeInterval {
//        XLTypeCastExpression<XLISO8601Date> { context in
//            makeSQL(context: &context)
//        }
//    }
//}
