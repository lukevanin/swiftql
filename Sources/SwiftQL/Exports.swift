//
//  Exports.swift
//
//  SwiftQL re-exports SwiftQLSQLite, and through it the query surface, the
//  runtime, and SwiftQLCore, so `import SwiftQL` keeps working as the one import
//  a v1 file wrote (issue #790, decision D13). SwiftQLCore is re-exported
//  directly too, as it always has been.
//

@_exported import SwiftQLSQLite
@_exported import SwiftQLCore
