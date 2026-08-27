//
//  GRDBRequest+Fetch.swift
//  SwiftQL
//
//  Eager fetching: run the statement, decode every row, return an array.
//
//  Split out of GRDBSQLDatabase.swift (issue #560).
//

import Foundation
import GRDB
#if canImport(Combine)
import Combine
#else
import OpenCombine
#endif


extension GRDBRequest {

    func fetchAll() throws -> [Row] {
        try fetchAll(bindings: compatibilityPacket())
    }

    func fetchAll(
        bindings: any XLInvocationBindingPacket
    ) throws -> [Row] {
        let packet = try executor.sqlitePacket(bindings)
        logger?.debug(
            "fetchAll: <<<\(executor.logicalStatement.sql)>>> parameters: <<<\(packet.bindings)>>>")
        return try decodeRows(packet: packet)
    }

    func decodeRows(
        packet: XLInvocationBindings<XLSQLiteValue>
    ) throws -> [Row] {
        var driver = executor.driver
        // Both branches accumulate into an outer array and return Void from
        // the closure, instead of returning [Row] directly from
        // withTransaction<Result>/withReadConnection<Result>. On the pinned
        // Swift 5.9.2 compatibility cell, instantiating that specific generic
        // reabstraction boundary with a 2+ generic-parameter Row type (e.g.
        // #row's SQLRow2...6) crashes swift-frontend in IRGen
        // (NativeConventionSchema::mapIntoNative) — and, because this is a
        // compiler memory-safety bug rather than a clean type error, a single
        // unpatched crossing point elsewhere in the same module can corrupt
        // shared frontend state and surface as an unrelated-looking crash
        // (e.g. ConformanceLookupTable::updateLookupTable,
        // llvm::FoldingSetBase::FindNodeOrInsertPos) at a completely
        // different file later in the same compilation. This shape has no
        // cost on any other Row type, and it protects both of this file's
        // fetchAll() boundaries from that crash — it is not a blanket fix for
        // the bug class: the publish()/publishOne() paths below independently
        // hit the same crash through their own generic publisher/witness-
        // method return types, which is why #row's 2+-column shapes stay
        // gated to Swift 6.1+ (SQLRowMacro.swift) rather than being unlocked
        // by this change.
        var items: [Row] = []
        if requiresWriteConnection {
            try driver.withTransaction { connection in
                items = try decodeRows(packet: packet, in: &connection)
            }
        }
        else {
            try driver.withReadConnection { connection in
                items = try decodeRows(packet: packet, in: &connection)
            }
        }
        return items
    }

    func decodeRows(
        packet: XLInvocationBindings<XLSQLiteValue>,
        in connection: inout GRDBDatabaseDriverConnection
    ) throws -> [Row] {
        let rowDecoder = GRDBRowDecoder(reader: reader)
        var items: [Row] = []

        try executor.forEachRow(packet: packet, in: &connection) { values in
            do {
                let item = try rowDecoder.decode(values: values)
                items.append(item)
                return .advance
            }
            catch {
                logger?.error("fetchAll : Cannot decode entity: \(error)")
                throw error
            }
        }
        return items
    }
    
    func fetchAtMost(
        _ limit: Int,
        bindings: any XLInvocationBindingPacket
    ) throws -> [Row] {
        let packet = try executor.sqlitePacket(bindings)
        logger?.debug(
            "fetchAtMost(\(limit)): <<<\(executor.logicalStatement.sql)>>> parameters: <<<\(packet.bindings)>>>")
        return try decodeRows(packet: packet, limit: limit)
    }

    func decodeRows(
        packet: XLInvocationBindings<XLSQLiteValue>,
        limit: Int
    ) throws -> [Row] {
        var driver = executor.driver
        // Same accumulator/Void-return shape as the two decodeRows(packet:)
        // overloads above, and for the same reason: this is
        // fetchAtMost(_:bindings:)'s decode boundary (used by @SQLQuery's
        // `.exactlyOne` cardinality) — an unpatched crossing point of the
        // same IRGen crash class.
        var items: [Row] = []
        try driver.withReadConnection { connection in
            items = try decodeRows(packet: packet, limit: limit, in: &connection)
        }
        return items
    }

    func decodeRows(
        packet: XLInvocationBindings<XLSQLiteValue>,
        limit: Int,
        in connection: inout GRDBDatabaseDriverConnection
    ) throws -> [Row] {
        precondition(limit >= 0, "fetchAtMost(_:bindings:) requires limit >= 0, got \(limit).")
        guard limit > 0 else {
            return []
        }
        let rowDecoder = GRDBRowDecoder(reader: reader)
        var items: [Row] = []

        try executor.forEachRow(packet: packet, in: &connection) { values in
            do {
                let item = try rowDecoder.decode(values: values)
                items.append(item)
                return items.count < limit ? .advance : .stop
            }
            catch {
                logger?.error("fetchAtMost(\(limit)): Cannot decode entity: \(error)")
                throw error
            }
        }
        return items
    }

    func fetchOne() throws -> Row? {
        try fetchOne(bindings: compatibilityPacket())
    }

    func fetchOne(
        bindings: any XLInvocationBindingPacket
    ) throws -> Row? {
        let packet = try executor.sqlitePacket(bindings)
        logger?.debug(
            "fetchOne: <<<\(executor.logicalStatement.sql)>>> parameters: <<<\(packet.bindings)>>>")
        let values: [XLSQLiteValue]?
        if requiresWriteConnection {
            var driver = executor.driver
            values = try driver.withTransaction { connection in
                try executor.fetchOne(packet: packet, in: &connection)
            }
        }
        else {
            values = try executor.fetchOne(bindings: packet)
        }
        guard let values else {
            return nil
        }

        return try GRDBRowDecoder(reader: reader).decode(values: values)
    }
}
