//
//  UUID.swift
//  
//
//  Created by Luke Van In on 2023/08/07.
//

import Foundation

/*
 #warning("TODO: Install UUID function if XLite was compiled without UUID extension")
 ///
 /// Assumes XLite was compiled with the UUID extension: https://sqlite.org/src/file/ext/misc/uuid.c
 ///
 public struct XLUUIDString: XLLiteral, XLExpression, XLEquatable, XLComparable {
 
 public typealias T = Self
 
 private let value: String
 
 public init(_ value: String) {
 self.init(UUID(uuidString: value)!)
 }
 
 public init(_ uuid: UUID) {
 self.value = uuid.uuidString
 }
 
 public init(reader: XLColumnReader, at index: Int) {
 self.value = reader.readText(at: index)
 }
 
 public func bind(context: inout XLBindingContext) {
 context.bindText(value: value)
 }
 
 public static func sqlDefault() -> XLUUIDString {
 XLUUIDString("00000000-0000-0000-0000-000000000000")
 }
 
 public func makeSQL(context: inout XLBuilder) {
 context.text(value)
 //        context.simpleFunction(name: "uuid_blob") { context in
 //            context.listItem { context in
 //                context.text(value)
 //            }
 //        }
 }
 
 //    public static func wrapSQL(context: inout XLBuilder, expression: (inout XLBuilder) -> Void) {
 //        context.simpleFunction(name: "uuid_blob") { context in
 //            context.listItem { context in
 //                expression(&context)
 //            }
 //        }
 //    }
 }
 
 
 extension XLExpression {
 
 public func toUUID() -> some XLExpression<XLUUID> where T == XLUUIDString {
 XLTypeCastExpression<XLUUID> { context in
 context.simpleFunction(name: "uuid_blob") { context in
 context.listItem { context in
 self.makeSQL(context: &context)
 }
 }
 }
 }
 }
 
 
 public struct XLUUID: XLLiteral, XLExpression, XLEquatable, XLComparable {
 
 public typealias T = Self
 
 private let value: Data
 
 public init(_ data: Data) {
 self.init(UUID(data: data))
 }
 
 public init(_ uuid: UUID) {
 self.value = uuid.data()
 }
 
 public init(reader: XLColumnReader, at index: Int) {
 self.value = reader.readBlob(at: index)
 }
 
 public func bind(context: inout XLBindingContext) {
 value.bind(context: &context)
 }
 
 public static func sqlDefault() -> XLUUID {
 XLUUID(Data(repeating: 0, count: 16))
 }
 
 public func makeSQL(context: inout XLBuilder) {
 context.blob(value)
 }
 }
 
 
 extension XLExpression {
 
 public func toUUIDString() -> some XLExpression<XLUUIDString> where T == XLUUID {
 XLTypeCastExpression<XLUUIDString> { context in
 context.simpleFunction(name: "uuid_str") { context in
 context.listItem { context in
 self.makeSQL(context: &context)
 }
 }
 }
 }
 }
 */
