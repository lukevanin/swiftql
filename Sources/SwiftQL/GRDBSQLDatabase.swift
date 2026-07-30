//
//  GRDBSQLDatabase.swift
//  
//
//  Created by Luke Van In on 2023/07/31.
//

import Foundation
import GRDB
#if canImport(Combine)
import Combine
#else
import OpenCombine
#endif


struct GRDBRowAdapter: XLColumnReader {

    private let reader: XLSQLiteValueReader

    init(row: GRDB.Row) {
        self.reader = XLSQLiteValueReader(
            values: row.databaseValues.map(\.sqliteDialectValue)
        )
    }
    
    func isNull(at index: Int) throws -> Bool {
        try reader.isNull(at: index)
    }
    
    func readInteger(at index: Int) throws -> Int {
        try reader.readInteger(at: index)
    }
    
    func readReal(at index: Int) throws -> Double {
        try reader.readReal(at: index)
    }
    
    func readText(at index: Int) throws -> String {
        try reader.readText(at: index)
    }
    
    func readBlob(at index: Int) throws -> Data {
        try reader.readBlob(at: index)
    }
}


struct GRDBValuesAdapter: XLColumnReader {

    private let reader: XLSQLiteValueReader

    init(values: [GRDB.DatabaseValue]) {
        self.reader = XLSQLiteValueReader(
            values: values.map(\.sqliteDialectValue)
        )
    }
    
    func isNull(at index: Int) throws -> Bool {
        try reader.isNull(at: index)
    }
    
    func readInteger(at index: Int) throws -> Int {
        try reader.readInteger(at: index)
    }
    
    func readReal(at index: Int) throws -> Double {
        try reader.readReal(at: index)
    }
    
    func readText(at index: Int) throws -> String {
        try reader.readText(at: index)
    }
    
    func readBlob(at index: Int) throws -> Data {
        try reader.readBlob(at: index)
    }
}


/// Package-scoped decoding seam shared by the GRDB adapter and performance harness.
///
/// Keeping the adapter and sequential column reader behind this type lets benchmarks exercise the
/// production decoding path without exposing GRDB implementation details as public SwiftQL API.
package struct GRDBRowDecoder<Output> {

    private let reader: any XLRowReadable<Output>

    package init(reader: any XLRowReadable<Output>) {
        self.reader = reader
    }

    package func decode(_ row: GRDB.Row) throws -> Output {
        try decode(values: row.databaseValues.map(\.sqliteDialectValue))
    }

    func decode(values: [XLSQLiteValue]) throws -> Output {
        try XLColumnValuesRowReader<Output>.withReader(
            XLSQLiteValueReader(values: values)
        ) { columnReader in
            try reader.readRow(reader: columnReader)
        }
    }
}


fileprivate struct BindingContext: XLBindingContext {

    var value: XLSQLiteValue = .null
    
    mutating func bindNull() {
        self.value = .null
    }
    
    mutating func bindInteger(value: Int) {
        self.value = .integer(Int64(value))
    }
    
    mutating func bindReal(value: Double) {
        self.value = .real(value)
    }
    
    mutating func bindText(value: String) {
        self.value = .text(value)
    }
    
    mutating func bindBlob(value: Data) {
        self.value = .blob(value)
    }
}


struct GRDBRequest<Row>: XLRequest {

    private let executor: GRDBInvocationExecutor

    /// Immutable value-coding policy captured when this request is created.
    let codingConfiguration: XLValueCodingConfiguration
    
    private let logger: XLLogger?
    
    private let reader: any XLRowReadable<Row>

    /// A `RETURNING` statement writes as it reads, so its rows must be decoded
    /// on a write connection inside a transaction; a plain query reads on a
    /// read-only connection. Observation is unsupported in the write mode
    /// because re-running a data-changing statement on every database change is
    /// never the intended behavior.
    private let requiresWriteConnection: Bool

    private let liveQueryRetryPolicy: GRDBLiveQueryRetryPolicy

    private let liveQueryRetryScheduler: GRDBLiveQueryRetryScheduler

    private var compatibilityBindings: XLInvocationBindings<XLSQLiteValue>

    private var compatibilityBindingError: XLInvocationBindingError?

    init(
        driver: GRDBDatabaseDriver,
        codingConfiguration: XLValueCodingConfiguration,
        logger: XLLogger?,
        reader: any XLRowReadable<Row>,
        logicalStatement: XLLogicalPreparedStatement,
        parameterLayoutError: XLInvocationBindingError? = nil,
        valueEncodingError: XLSQLValueEncodingError? = nil,
        requiresWriteConnection: Bool = false,
        customFunctions: [XLCustomFunctionDefinition: XLCustomFunctionRegistration] = [:],
        liveQueryRetryPolicy: GRDBLiveQueryRetryPolicy,
        liveQueryRetryScheduler: GRDBLiveQueryRetryScheduler
    ) {
        self.requiresWriteConnection = requiresWriteConnection
        self.executor = GRDBInvocationExecutor(
            driver: driver,
            logicalStatement: logicalStatement,
            parameterLayoutError: parameterLayoutError,
            valueEncodingError: valueEncodingError,
            customFunctions: customFunctions
        )
        self.codingConfiguration = codingConfiguration
        self.logger = logger
        self.reader = reader
        self.liveQueryRetryPolicy = liveQueryRetryPolicy
        self.liveQueryRetryScheduler = liveQueryRetryScheduler
        self.compatibilityBindings = XLInvocationBindings(
            layout: logicalStatement.parameterLayout
        )
        self.compatibilityBindingError = parameterLayoutError
    }

    var parameterLayout: XLParameterLayout {
        executor.parameterLayout
    }
    
    public mutating func set<T>(parameter reference: XLNamedBindingReference<Optional<T>>, value: T?) where T: XLBindable {
        bindValue(
            declaration: _xlLegacyParameterDeclaration(
                for: Optional<T>.self,
                key: .named(reference.name.rawValue)
            )
        ) { context in
            if let value {
                value.bind(context: &context)
            }
            else {
                context.bindNull()
            }
        }
    }

    public mutating func set<T>(parameter reference: XLNamedBindingReference<T>, value: T) where T: XLBindable {
        bindValue(
            declaration: _xlLegacyParameterDeclaration(
                for: T.self,
                key: .named(reference.name.rawValue)
            )
        ) { context in
            value.bind(context: &context)
        }
    }
    
    private mutating func bindValue(
        declaration: XLParameterDeclaration,
        bind: (inout XLBindingContext) -> Void
    ) {
        guard let slot = parameterLayout.slot(for: declaration.key) else {
            if compatibilityBindingError == nil {
                compatibilityBindingError = .parameterDeclarationNotInLayout(
                    declaration: declaration
                )
            }
            return
        }
        guard slot.acceptsLegacySet(declaration) else {
            if compatibilityBindingError == nil {
                compatibilityBindingError = .parameterMetadataMismatch(
                    expected: slot,
                    actual: declaration.slot(at: slot.index)
                )
            }
            return
        }
        var context: any XLBindingContext = BindingContext()
        bind(&context)
        let value = (context as! BindingContext).value
        do {
            compatibilityBindings = try replacingBinding(
                value,
                at: slot,
                in: compatibilityBindings
            )
        }
        catch let error as XLInvocationBindingError {
            if compatibilityBindingError == nil {
                compatibilityBindingError = error
            }
        }
        catch {
            preconditionFailure("Unexpected invocation binding error: \(error)")
        }
    }
    
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

    private func decodeRows(
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

    private func decodeRows(
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

    private func decodeRows(
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

    private func decodeRows(
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

    func withResultSet<Result>(
        _ operation: (XLResultSet<Row>) throws -> Result
    ) throws -> Result {
        try withResultSet(bindings: try compatibilityPacket(), operation)
    }

    ///
    /// True-streaming override of the ``XLRequest`` default: lends an
    /// `XLResultSet` backed directly by `GRDBInvocationExecutor`'s
    /// value-level cursor stepper, so `next()` performs one real SQLite step
    /// and one real typed decode -- nothing is prefetched, and nothing is
    /// buffered beyond the one row currently being decoded.
    ///
    /// A `RETURNING` request (`requiresWriteConnection`) is the one
    /// exception: `RETURNING` rows are produced as SQLite steps through the
    /// data-changing statement itself, so stepping only part of the cursor
    /// would commit a write that only partially ran. Decoding lazily could
    /// silently apply an incomplete `UPDATE`/`DELETE`/`INSERT` if the caller
    /// stopped calling `next()` early. To keep that impossible, a
    /// `RETURNING` request decodes every row eagerly inside its transaction
    /// -- exactly like `fetchAll(bindings:)` -- before handing the
    /// already-decoded rows to the caller through the same lazy `next()`
    /// surface. Non-`RETURNING` requests are unaffected and stream lazily.
    ///
    func withResultSet<Result>(
        bindings: any XLInvocationBindingPacket,
        _ operation: (XLResultSet<Row>) throws -> Result
    ) throws -> Result {
        let packet = try executor.sqlitePacket(bindings)
        logger?.debug(
            "withResultSet: <<<\(executor.logicalStatement.sql)>>> parameters: <<<\(packet.bindings)>>>")

        if requiresWriteConnection {
            var driver = executor.driver
            var items: [Row] = []
            try driver.withTransaction { connection in
                items = try decodeRows(packet: packet, in: &connection)
            }
            return try withEagerResultSet(items, operation)
        }

        let rowDecoder = GRDBRowDecoder(reader: reader)
        return try executor.withValuesStepper(
            packet: packet,
            requiresWriteConnection: false
        ) { valuesStepper in
            let resultSet = XLResultSet<Row>(stepper: {
                guard let values = try valuesStepper() else {
                    return nil
                }
                return try rowDecoder.decode(values: values)
            })
            defer { resultSet.close() }
            return try operation(resultSet)
        }
    }

    /// Mirrors `XLRequest`'s eager compatibility fallback (see
    /// `SQLDatabase.swift`), used only for the `RETURNING` path above where
    /// rows must already be fully decoded before `operation` runs.
    private func withEagerResultSet<Result>(
        _ rows: [Row],
        _ operation: (XLResultSet<Row>) throws -> Result
    ) throws -> Result {
        var iterator = rows.makeIterator()
        let resultSet = XLResultSet<Row>(stepper: { iterator.next() })
        defer { resultSet.close() }
        return try operation(resultSet)
    }

    // `publish()`/`publish(bindings:)`/`publishOne()`/`publishOne(bindings:)` are Combine convenience
    // adapters over `stream()`/`streamOne()` (issue #309): they never call `ValueObservation
    // .publisher(in:)` or own a Combine-side retry pipeline. Observation, immutable-packet capture,
    // retry, decoding, and buffering all come from the async stream; `xlLiveQueryPublisher(makeStream:)`
    // only adapts Combine subscription/demand/cancellation and applies the documented main-queue
    // delivery default.
    //
    // Two guard checks below stay eager (a synchronous `Fail`) instead of folding into the lazy stream
    // adapter: `requiresWriteConnection` (a `RETURNING` statement is never observable) and a `nil`
    // `databasePool` (a transaction-scoped driver, issue #284, has no pool to track). Both are pure,
    // already-computed structural checks -- not observation, retry, or decoding logic -- and keeping
    // them synchronous preserves a real regression contract: `SQLTransactionScopeTests
    // .testPublishInsideATransactionFailsPredictablyInsteadOfObservingAnInvalidatedConnection` calls
    // `.publish()` and synchronously waits on the *same* thread `withTransaction(_:)`'s body is running
    // on. `databasePool.write(_:)` blocks the calling thread for that body's duration, so if this fast-
    // fail error were instead delivered lazily through a `Task` plus `.receive(on: DispatchQueue.main)`
    // (as `stream()`/`streamOne()` do), it could never be delivered while that same thread is the one
    // blocked waiting for it -- a deadlock. `Fail` needs no dispatch queue and delivers synchronously,
    // exactly like the pre-#309 implementation did for these two cases.
    func publish() -> AnyPublisher<[Row], Error> {
        if requiresWriteConnection {
            return Fail(error: XLReturningRequestError.observationUnsupported)
                .eraseToAnyPublisher()
        }
        do {
            return publish(bindings: try compatibilityPacket())
        }
        catch {
            return Fail(error: error).eraseToAnyPublisher()
        }
    }

    func publish(
        bindings: any XLInvocationBindingPacket
    ) -> AnyPublisher<[Row], Error> {
        if requiresWriteConnection {
            return Fail(error: XLReturningRequestError.observationUnsupported)
                .eraseToAnyPublisher()
        }
        guard executor.driver.databasePool != nil else {
            return Fail(error: XLTransactionScopeError.liveQueriesUnsupportedInTransaction)
                .eraseToAnyPublisher()
        }
        return xlLiveQueryPublisher(makeStream: { self.stream(bindings: bindings) })
    }

    func publishOne() -> AnyPublisher<Row?, Error> {
        if requiresWriteConnection {
            return Fail(error: XLReturningRequestError.observationUnsupported)
                .eraseToAnyPublisher()
        }
        do {
            return publishOne(bindings: try compatibilityPacket())
        }
        catch {
            return Fail(error: error).eraseToAnyPublisher()
        }
    }

    func publishOne(
        bindings: any XLInvocationBindingPacket
    ) -> AnyPublisher<Row?, Error> {
        if requiresWriteConnection {
            return Fail(error: XLReturningRequestError.observationUnsupported)
                .eraseToAnyPublisher()
        }
        guard executor.driver.databasePool != nil else {
            return Fail(error: XLTransactionScopeError.liveQueriesUnsupportedInTransaction)
                .eraseToAnyPublisher()
        }
        return xlLiveQueryPublisher(makeStream: { self.streamOne(bindings: bindings) })
    }
    
    func stream() -> AsyncThrowingStream<[Row], Error> {
        do {
            return try stream(bindings: compatibilityPacket())
        }
        catch {
            return xlFailingAsyncThrowingStream(error)
        }
    }

    func stream(
        bindings: any XLInvocationBindingPacket
    ) -> AsyncThrowingStream<[Row], Error> {
        if requiresWriteConnection {
            return xlFailingAsyncThrowingStream(XLReturningRequestError.observationUnsupported)
        }
        do {
            let packet = try executor.sqlitePacket(bindings)
            guard let bridge = liveQueryStreamBridge(fetch: { database -> [Row] in
                logger?.debug(
                    "stream: <<<\(executor.logicalStatement.sql)>>> parameters: <<<\(packet.bindings)>>>")
                var connection = executor.driver.makeConnection(database)
                return try decodeRows(packet: packet, in: &connection)
            }) else {
                return xlFailingAsyncThrowingStream(XLTransactionScopeError.liveQueriesUnsupportedInTransaction)
            }
            return bridge.stream()
        }
        catch {
            return xlFailingAsyncThrowingStream(error)
        }
    }

    func streamOne() -> AsyncThrowingStream<Row?, Error> {
        do {
            return try streamOne(bindings: compatibilityPacket())
        }
        catch {
            return xlFailingAsyncThrowingStream(error)
        }
    }

    func streamOne(
        bindings: any XLInvocationBindingPacket
    ) -> AsyncThrowingStream<Row?, Error> {
        if requiresWriteConnection {
            return xlFailingAsyncThrowingStream(XLReturningRequestError.observationUnsupported)
        }
        do {
            let packet = try executor.sqlitePacket(bindings)
            guard let bridge = liveQueryStreamBridge(fetch: { database -> Row? in
                logger?.debug(
                    "streamOne: <<<\(executor.logicalStatement.sql)>>> parameters: <<<\(packet.bindings)>>>")
                var connection = executor.driver.makeConnection(database)
                guard let values = try executor.fetchOne(packet: packet, in: &connection) else {
                    return nil
                }
                return try GRDBRowDecoder(reader: reader).decode(values: values)
            }) else {
                return xlFailingAsyncThrowingStream(XLTransactionScopeError.liveQueriesUnsupportedInTransaction)
            }
            return bridge.stream()
        }
        catch {
            return xlFailingAsyncThrowingStream(error)
        }
    }

    /// Builds the async-native GRDB observation bridge shared by `stream()`/`streamOne()`. Returns `nil`
    /// for a transaction-scoped driver (issue #284), which has no pool to track — the same guard
    /// `publish(bindings:)`/`publishOne(bindings:)` check eagerly for the Combine path (issue #309).
    private func liveQueryStreamBridge<Value>(
        fetch: @escaping (Database) throws -> Value
    ) -> GRDBLiveQueryAsyncBridge<Value>? {
        guard let databasePool = executor.driver.databasePool else {
            return nil
        }
        return GRDBLiveQueryAsyncBridge(
            policy: liveQueryRetryPolicy,
            scheduler: liveQueryRetryScheduler,
            makeSource: { onError, onChange in
                ValueObservation
                    .tracking(fetch)
                    .start(in: databasePool, onError: onError, onChange: onChange)
            }
        )
    }

    private func compatibilityPacket() throws -> XLInvocationBindings<XLSQLiteValue> {
        if let compatibilityBindingError {
            throw compatibilityBindingError
        }
        return compatibilityBindings
    }
}


struct GRDBWriteRequest: XLWriteRequest {

    private let executor: GRDBInvocationExecutor

    /// Immutable value-coding policy captured when this request is created.
    let codingConfiguration: XLValueCodingConfiguration
    
    private let logger: XLLogger?
    
    private var compatibilityBindings: XLInvocationBindings<XLSQLiteValue>

    private var compatibilityBindingError: XLInvocationBindingError?
    
    init(
        driver: GRDBDatabaseDriver,
        codingConfiguration: XLValueCodingConfiguration,
        logger: XLLogger?,
        logicalStatement: XLLogicalPreparedStatement,
        parameterLayoutError: XLInvocationBindingError? = nil,
        valueEncodingError: XLSQLValueEncodingError? = nil,
        customFunctions: [XLCustomFunctionDefinition: XLCustomFunctionRegistration] = [:]
    ) {
        self.executor = GRDBInvocationExecutor(
            driver: driver,
            logicalStatement: logicalStatement,
            parameterLayoutError: parameterLayoutError,
            valueEncodingError: valueEncodingError,
            customFunctions: customFunctions
        )
        self.codingConfiguration = codingConfiguration
        self.logger = logger
        self.compatibilityBindings = XLInvocationBindings(
            layout: logicalStatement.parameterLayout
        )
        self.compatibilityBindingError = parameterLayoutError
    }

    var parameterLayout: XLParameterLayout {
        executor.parameterLayout
    }
    
    public mutating func set<T>(parameter reference: XLNamedBindingReference<Optional<T>>, value: T?) where T: XLBindable {
        bindValue(
            declaration: _xlLegacyParameterDeclaration(
                for: Optional<T>.self,
                key: .named(reference.name.rawValue)
            )
        ) { context in
            if let value {
                value.bind(context: &context)
            }
            else {
                context.bindNull()
            }
        }
    }

    public mutating func set<T>(parameter reference: XLNamedBindingReference<T>, value: T) where T: XLBindable {
        bindValue(
            declaration: _xlLegacyParameterDeclaration(
                for: T.self,
                key: .named(reference.name.rawValue)
            )
        ) { context in
            value.bind(context: &context)
        }
    }
    
    private mutating func bindValue(
        declaration: XLParameterDeclaration,
        bind: (inout XLBindingContext) -> Void
    ) {
        guard let slot = parameterLayout.slot(for: declaration.key) else {
            if compatibilityBindingError == nil {
                compatibilityBindingError = .parameterDeclarationNotInLayout(
                    declaration: declaration
                )
            }
            return
        }
        guard slot.acceptsLegacySet(declaration) else {
            if compatibilityBindingError == nil {
                compatibilityBindingError = .parameterMetadataMismatch(
                    expected: slot,
                    actual: declaration.slot(at: slot.index)
                )
            }
            return
        }
        var context: any XLBindingContext = BindingContext()
        bind(&context)
        let value = (context as! BindingContext).value
        do {
            compatibilityBindings = try replacingBinding(
                value,
                at: slot,
                in: compatibilityBindings
            )
        }
        catch let error as XLInvocationBindingError {
            if compatibilityBindingError == nil {
                compatibilityBindingError = error
            }
        }
        catch {
            preconditionFailure("Unexpected invocation binding error: \(error)")
        }
    }
    
    func execute() throws {
        if let compatibilityBindingError {
            throw compatibilityBindingError
        }
        try execute(bindings: compatibilityBindings)
    }

    func execute(
        bindings: any XLInvocationBindingPacket
    ) throws {
        let packet = try executor.sqlitePacket(bindings)
        logger?.debug(
            "execute: <<<\(executor.logicalStatement.sql)>>> parameters: <<<\(packet.bindings)>>>")
        try executor.execute(bindings: packet)
    }
}


private extension XLParameterSlot {

    func acceptsLegacySet(_ declaration: XLParameterDeclaration) -> Bool {
        self.declaration == declaration || isRendererLegacyBindingWildcard
    }

    /// `XLBuilder.namedBinding` and `indexedBinding` predate typed parameter
    /// declarations. The renderer records this exact sentinel so the v1
    /// mutating `set` facade can still normalize a value for custom expressions
    /// that emit placeholders directly. Typed and contextual slots never take
    /// this path and continue to require an exact declaration match.
    private var isRendererLegacyBindingWildcard: Bool {
        valueTypeIdentifier == XLValueTypeIdentifier(
            rawValue: "swiftql.legacy-binding-value"
        )
            && valueTypeName == "SwiftQL.XLBindable"
            && nullability == .nullable
            && codecIdentity == nil
    }
}


private func replacingBinding(
    _ value: XLSQLiteValue,
    at slot: XLParameterSlot,
    in packet: XLInvocationBindings<XLSQLiteValue>
) throws -> XLInvocationBindings<XLSQLiteValue> {
    if value == .null, slot.nullability == .required {
        throw XLInvocationBindingError.nullForRequiredParameter(slot: slot)
    }
    return try XLInvocationBindings(
        layout: packet.layout,
        bindings: packet.bindings.filter { $0.slot.index != slot.index } + [
            XLInvocationBinding(slot: slot, value: value)
        ]
    )
}


/// Configures a GRDB-backed SwiftQL database before its connection pool is created.
public struct GRDBDatabaseBuilder {
    
    private let url: URL

    private var configuration: GRDB.Configuration

    private let codingConfiguration: XLValueCodingConfiguration

    private let formatter: XLiteFormatter
    
    private let logger: XLLogger?

    private let liveQueryRetryPolicy: GRDBLiveQueryRetryPolicy
    
    /// Creates a database builder.
    ///
    /// - Parameters:
    ///   - url: The SQLite database file URL.
    ///   - configuration: The GRDB connection configuration to extend.
    ///   - formatter: The formatter used when SwiftQL renders SQL.
    ///   - logger: An optional logger for executed statements.
    ///   - liveQueryRetryPolicy: Recovery policy for live-query failures. The
    ///     default is ``GRDBLiveQueryRetryPolicy/terminal``.
    public init(
        url: URL,
        configuration: GRDB.Configuration,
        formatter: XLiteFormatter = XLiteFormatter(),
        logger: XLLogger?,
        liveQueryRetryPolicy: GRDBLiveQueryRetryPolicy = .terminal
    ) throws {
        try self.init(
            url: url,
            codingConfiguration: XLValueCodingConfiguration(),
            configuration: configuration,
            formatter: formatter,
            logger: logger,
            liveQueryRetryPolicy: liveQueryRetryPolicy
        )
    }

    /// Creates a database builder with an immutable value-coding snapshot.
    ///
    /// - Parameters:
    ///   - url: The SQLite database file URL.
    ///   - codingConfiguration: Contextual codecs and defaults captured by the
    ///     database and requests built from it.
    ///   - configuration: The GRDB connection configuration to extend.
    ///   - formatter: The formatter used when SwiftQL renders SQL.
    ///   - logger: An optional logger for executed statements.
    ///   - liveQueryRetryPolicy: Recovery policy for live-query failures.
    public init(
        url: URL,
        codingConfiguration: XLValueCodingConfiguration,
        configuration: GRDB.Configuration,
        formatter: XLiteFormatter = XLiteFormatter(),
        logger: XLLogger?,
        liveQueryRetryPolicy: GRDBLiveQueryRetryPolicy = .terminal
    ) throws {
        self.url = url
        self.configuration = configuration
        self.codingConfiguration = codingConfiguration
        self.formatter = formatter
        self.logger = logger
        self.liveQueryRetryPolicy = liveQueryRetryPolicy
    }
    
    /// Registers a custom scalar function on every database connection created by the builder.
    ///
    /// - Parameter function: The custom function type to register.
    public mutating func addFunction<F>(_ function: F.Type) where F: XLCustomFunction, F.T: DatabaseValueConvertible {
        configuration.prepareDatabase { database in
            database.add(
                function: DatabaseFunction(
                    function.definition.name,
                    argumentCount: Int(function.definition.numberOfArguments),
                    function: { values in
                        let reader = GRDBValuesAdapter(values: values)
                        return try F.execute(reader: reader)
                    }
                )
            )
        }
    }

    /// Registers a custom collating sequence on every database connection
    /// created by the builder.
    ///
    /// Name the same sequence in a query with `XLCollation(rawValue:)`. SQLite
    /// resolves collations at preparation, so an unregistered name fails with
    /// `no such collation sequence` rather than silently comparing differently.
    ///
    /// - Parameter name: Collation name, matched case-insensitively by SQLite.
    /// - Parameter compare: Ordering between two strings.
    public mutating func addCollation(
        _ name: String,
        compare: @escaping @Sendable (String, String) -> ComparisonResult
    ) {
        configuration.prepareDatabase { database in
            database.add(collation: DatabaseCollation(name, function: compare))
        }
    }

    /// Creates the configured database and its connection pool.
    public func build() throws -> GRDBDatabase {
        try GRDBDatabase(
            databasePool: try DatabasePool(
                path: url.path,
                configuration: configuration
            ),
            codingConfiguration: codingConfiguration,
            formatter: formatter,
            logger: logger,
            liveQueryRetryPolicy: liveQueryRetryPolicy
        )
    }
}


/// A SwiftQL database adapter backed by a GRDB `DatabasePool`.
public struct GRDBDatabase: XLDatabase {
    
    /// The GRDB connection pool used to execute requests.
    public let databasePool: DatabasePool
    
    /// The encoder used to render SwiftQL statements.
    public let encoder: XLEncoder

    /// Explicit SQLite syntax and value contract used by this adapter.
    public let dialect: XLSQLiteDialect

    /// Immutable contextual value-coding policy captured by this database.
    public let codingConfiguration: XLValueCodingConfiguration

    /// Stable identity of the database transport used by this adapter.
    public let driverIdentifier: XLDriverIdentifier

    private let driver: GRDBDatabaseDriver
    
    private let logger: XLLogger?

    private let liveQueryRetryPolicy: GRDBLiveQueryRetryPolicy

    private let liveQueryRetryScheduler: GRDBLiveQueryRetryScheduler
    
    /// Opens a GRDB-backed SQLite database.
    ///
    /// - Parameters:
    ///   - url: The SQLite database file URL.
    ///   - configuration: The GRDB connection configuration.
    ///   - formatter: The formatter used when SwiftQL renders SQL.
    ///   - logger: An optional logger for executed statements.
    ///   - liveQueryRetryPolicy: Recovery policy for live-query failures. The
    ///     default is ``GRDBLiveQueryRetryPolicy/terminal``.
    public init(
        url: URL,
        configuration: GRDB.Configuration = GRDB.Configuration(),
        formatter: XLiteFormatter = XLiteFormatter(),
        logger: XLLogger?,
        liveQueryRetryPolicy: GRDBLiveQueryRetryPolicy = .terminal
    ) throws {
        try self.init(
            url: url,
            codingConfiguration: XLValueCodingConfiguration(),
            configuration: configuration,
            formatter: formatter,
            logger: logger,
            liveQueryRetryPolicy: liveQueryRetryPolicy
        )
    }

    /// Opens a GRDB-backed SQLite database with a value-coding snapshot.
    ///
    /// - Parameters:
    ///   - url: The SQLite database file URL.
    ///   - codingConfiguration: Contextual codecs and defaults captured by the
    ///     database and every request it creates.
    ///   - configuration: The GRDB connection configuration.
    ///   - formatter: The formatter used when SwiftQL renders SQL.
    ///   - logger: An optional logger for executed statements.
    ///   - liveQueryRetryPolicy: Recovery policy for live-query failures.
    public init(
        url: URL,
        codingConfiguration: XLValueCodingConfiguration,
        configuration: GRDB.Configuration = GRDB.Configuration(),
        formatter: XLiteFormatter = XLiteFormatter(),
        logger: XLLogger?,
        liveQueryRetryPolicy: GRDBLiveQueryRetryPolicy = .terminal
    ) throws {
        try self.init(
            databasePool: try DatabasePool(
                path: url.path,
                configuration: configuration
            ),
            codingConfiguration: codingConfiguration,
            formatter: formatter,
            logger: logger,
            liveQueryRetryPolicy: liveQueryRetryPolicy
        )
    }
    
    /// Wraps an existing GRDB database pool.
    ///
    /// - Parameters:
    ///   - databasePool: The pool used to execute requests.
    ///   - formatter: The formatter used when SwiftQL renders SQL.
    ///   - logger: An optional logger for executed statements.
    ///   - liveQueryRetryPolicy: Recovery policy for live-query failures. The
    ///     default is ``GRDBLiveQueryRetryPolicy/terminal``.
    public init(
        databasePool: DatabasePool,
        formatter: XLiteFormatter,
        logger: XLLogger?,
        liveQueryRetryPolicy: GRDBLiveQueryRetryPolicy = .terminal
    ) throws {
        try self.init(
            databasePool: databasePool,
            codingConfiguration: XLValueCodingConfiguration(),
            formatter: formatter,
            logger: logger,
            liveQueryRetryPolicy: liveQueryRetryPolicy
        )
    }

    /// Wraps an existing GRDB pool with a value-coding snapshot.
    ///
    /// - Parameters:
    ///   - databasePool: The pool used to execute requests.
    ///   - codingConfiguration: Contextual codecs and defaults captured by the
    ///     database and every request it creates.
    ///   - formatter: The formatter used when SwiftQL renders SQL.
    ///   - logger: An optional logger for executed statements.
    ///   - liveQueryRetryPolicy: Recovery policy for live-query failures.
    public init(
        databasePool: DatabasePool,
        codingConfiguration: XLValueCodingConfiguration,
        formatter: XLiteFormatter,
        logger: XLLogger?,
        liveQueryRetryPolicy: GRDBLiveQueryRetryPolicy = .terminal
    ) throws {
        try self.init(
            databasePool: databasePool,
            codingConfiguration: codingConfiguration,
            formatter: formatter,
            logger: logger,
            liveQueryRetryPolicy: liveQueryRetryPolicy,
            liveQueryRetryScheduler: .mainQueue
        )
    }

    init(
        databasePool: DatabasePool,
        formatter: XLiteFormatter,
        logger: XLLogger?,
        liveQueryRetryPolicy: GRDBLiveQueryRetryPolicy,
        liveQueryRetryScheduler: GRDBLiveQueryRetryScheduler
    ) throws {
        try self.init(
            databasePool: databasePool,
            codingConfiguration: XLValueCodingConfiguration(),
            formatter: formatter,
            logger: logger,
            liveQueryRetryPolicy: liveQueryRetryPolicy,
            liveQueryRetryScheduler: liveQueryRetryScheduler
        )
    }

    init(
        databasePool: DatabasePool,
        codingConfiguration: XLValueCodingConfiguration,
        formatter: XLiteFormatter,
        logger: XLLogger?,
        liveQueryRetryPolicy: GRDBLiveQueryRetryPolicy,
        liveQueryRetryScheduler: GRDBLiveQueryRetryScheduler
    ) throws {
        let dialect = XLSQLiteDialect(
            identifierFormattingOptions: formatter.identifierFormattingOptions
        )
        let driver = GRDBDatabaseDriver(
            databasePool: databasePool,
            dialect: dialect
        )
        self.dialect = dialect
        self.codingConfiguration = codingConfiguration
        self.encoder = XLiteEncoder(dialect: dialect)
        self.databasePool = databasePool
        self.driverIdentifier = driver.driverIdentifier
        self.driver = driver
        self.logger = logger
        self.liveQueryRetryPolicy = liveQueryRetryPolicy
        self.liveQueryRetryScheduler = liveQueryRetryScheduler
    }

    /// Constructs a transaction-scoped copy of this database (issue #284),
    /// pinned to `pinnedDriver`'s connection. Every other field is copied
    /// unchanged, so a pinned scope renders through the same encoder,
    /// dialect, coding snapshot, logger, and live-query retry policy as the
    /// database ``withTransaction(_:)`` was called on.
    private init(pinnedDriver: GRDBDatabaseDriver, pinnedFrom other: GRDBDatabase) {
        self.dialect = other.dialect
        self.encoder = other.encoder
        self.codingConfiguration = other.codingConfiguration
        self.databasePool = other.databasePool
        self.driverIdentifier = other.driverIdentifier
        self.driver = pinnedDriver
        self.logger = other.logger
        self.liveQueryRetryPolicy = other.liveQueryRetryPolicy
        self.liveQueryRetryScheduler = other.liveQueryRetryScheduler
    }

    /// Scopes render-once cache entries (issues #18/#26) to this database and
    /// dialect. Rendering depends only on the dialect; the database identifier
    /// keeps a per-declaration `static` cache from binding one database's
    /// request to another. The driver assigns a fresh identifier per init, so
    /// the scope is per `GRDBDatabase` instance rather than per `DatabasePool`
    /// (see ``XLPreparedQueryCacheKey``).
    public var preparedQueryCacheKey: XLPreparedQueryCacheKey? {
        XLPreparedQueryCacheKey(
            databaseIdentifier: driver.databaseIdentifier,
            dialectIdentifier: dialect.descriptor.identity
        )
    }

    public func makeRequest<Row>(with statement: any XLQueryStatement<Row>) -> any XLRequest<Row> {
        let encoding = encoder.makeSQL(statement)
        return GRDBRequest(
            driver: driver,
            codingConfiguration: codingConfiguration,
            logger: logger,
            reader: statement,
            logicalStatement: logicalStatement(for: encoding),
            parameterLayoutError: preparedParameterLayoutError(for: encoding),
            valueEncodingError: encoding.valueEncodingError,
            customFunctions: encoding.customFunctions,
            liveQueryRetryPolicy: liveQueryRetryPolicy,
            liveQueryRetryScheduler: liveQueryRetryScheduler
        )
    }

    /// Prepares an immutable raw-value runtime handle for concurrent
    /// invocations of one rendered statement.
    ///
    /// The handle intentionally does not retain the typed v1 row-reader graph.
    /// Callers that need typed decoding can use `makeRequest(with:)`; static
    /// typed descriptors build on this raw execution seam separately.
    public func prepareInvocation(
        with statement: any XLEncodable
    ) -> GRDBPreparedInvocation {
        let encoding = encoder.makeSQL(statement)
        return GRDBPreparedInvocation(
            executor: GRDBInvocationExecutor(
                driver: driver,
                logicalStatement: logicalStatement(for: encoding),
                parameterLayoutError: preparedParameterLayoutError(for: encoding),
                valueEncodingError: encoding.valueEncodingError,
                customFunctions: encoding.customFunctions
            )
        )
    }

    /// Prepares a database-independent static query descriptor against this
    /// database's dialect and immutable coding snapshot.
    ///
    /// Validation happens before a runtime handle is returned. Physical SQLite
    /// statements remain connection-owned and are created only while executing
    /// through the GRDB driver.
    public func prepareInvocation(
        with descriptor: XLStaticQueryDescriptor
    ) throws -> GRDBPreparedStaticQuery {
        try descriptor.statement.dialectRequirement.validate(
            dialect.descriptor
        )
        try validateStaticQueryStorage(descriptor)
        try validateStaticQueryCodecs(descriptor)

        let statement = XLLogicalPreparedStatement(
            databaseIdentifier: driver.databaseIdentifier,
            dialectRequirement: descriptor.statement.dialectRequirement,
            sql: descriptor.statement.sql,
            entities: descriptor.statement.entities,
            parameterLayout: descriptor.statement.parameterLayout
        )
        let invocation = GRDBPreparedInvocation(
            executor: GRDBInvocationExecutor(
                driver: driver,
                logicalStatement: statement
            )
        )
        return GRDBPreparedStaticQuery(
            descriptor: descriptor,
            invocation: invocation,
            codingConfiguration: codingConfiguration,
            dialect: dialect
        )
    }
    
    public func makeRequest<Row>(with statement: any XLReturningStatement<Row>) -> any XLRequest<Row> {
        let encoding = encoder.makeSQL(statement)
        return GRDBRequest(
            driver: driver,
            codingConfiguration: codingConfiguration,
            logger: logger,
            reader: statement,
            logicalStatement: logicalStatement(for: encoding),
            parameterLayoutError: preparedParameterLayoutError(for: encoding),
            valueEncodingError: encoding.valueEncodingError,
            requiresWriteConnection: true,
            liveQueryRetryPolicy: liveQueryRetryPolicy,
            liveQueryRetryScheduler: liveQueryRetryScheduler
        )
    }

    public func makeRequest(with statement: any XLUpdateStatement) -> XLWriteRequest {
        makeWriteRequest(with: statement)
    }
    
    public func makeRequest(with statement: any XLInsertStatement) -> XLWriteRequest {
        makeWriteRequest(with: statement)
    }
    
    public func makeRequest(with statement: any XLCreateStatement) -> XLWriteRequest {
        makeWriteRequest(with: statement)
    }
    
    public func makeRequest(with statement: any XLDeleteStatement) -> XLWriteRequest {
        makeWriteRequest(with: statement)
    }

    private func makeWriteRequest(with statement: any XLEncodable) -> XLWriteRequest {
        let encoding = encoder.makeSQL(statement)
        return GRDBWriteRequest(
            driver: driver,
            codingConfiguration: codingConfiguration,
            logger: logger,
            logicalStatement: logicalStatement(for: encoding),
            parameterLayoutError: preparedParameterLayoutError(for: encoding),
            valueEncodingError: encoding.valueEncodingError,
            customFunctions: encoding.customFunctions
        )
    }

    /// Confirms that every contextual parameter retained by the rendered
    /// statement belongs to this database's immutable coding snapshot. A
    /// reference resolved by another database is accepted only when the same
    /// durable codec identity is registered for the same dialect.
    private func preparedParameterLayoutError(
        for encoding: XLEncoding
    ) -> XLInvocationBindingError? {
        if let parameterLayoutError = encoding.parameterLayoutError {
            return parameterLayoutError
        }

        for slot in encoding.parameterLayout.slots {
            guard let expected = slot.codecIdentity else {
                continue
            }
            guard expected.dialectIdentifier == dialect.descriptor.identity else {
                return .preparedCodecDialectMismatch(
                    slot: slot,
                    codecIdentity: expected,
                    expectedDialectIdentifier: dialect.descriptor.identity
                )
            }
            guard let actual = codingConfiguration.registry.identity(
                for: expected.key
            ) else {
                return .preparedCodecUnavailable(
                    slot: slot,
                    codecIdentity: expected
                )
            }
            guard actual == expected else {
                return .preparedCodecIdentityMismatch(
                    slot: slot,
                    expected: expected,
                    actual: actual
                )
            }
        }
        return nil
    }

    private func validateStaticQueryCodecs(
        _ descriptor: XLStaticQueryDescriptor
    ) throws {
        for metadata in descriptor.parameters {
            let slot = metadata.slot
            guard let expected = slot.codecIdentity else {
                continue
            }
            guard expected.dialectIdentifier == dialect.descriptor.identity else {
                throw XLInvocationBindingError.preparedCodecDialectMismatch(
                    slot: slot,
                    codecIdentity: expected,
                    expectedDialectIdentifier: dialect.descriptor.identity
                )
            }
            guard let actual = codingConfiguration.registry.identity(
                for: expected.key
            ) else {
                throw XLInvocationBindingError.preparedCodecUnavailable(
                    slot: slot,
                    codecIdentity: expected
                )
            }
            guard actual == expected else {
                throw XLInvocationBindingError.preparedCodecIdentityMismatch(
                    slot: slot,
                    expected: expected,
                    actual: actual
                )
            }
        }

        for slot in descriptor.results.slots {
            guard let expected = slot.codecIdentity else {
                continue
            }
            guard expected.dialectIdentifier == dialect.descriptor.identity else {
                throw GRDBStaticQueryError.resultCodecDialectMismatch(
                    identity: descriptor.identity,
                    slot: slot,
                    codecIdentity: expected,
                    expectedDialectIdentifier: dialect.descriptor.identity
                )
            }
            guard let actual = codingConfiguration.registry.identity(
                for: expected.key
            ) else {
                throw GRDBStaticQueryError.resultCodecUnavailable(
                    identity: descriptor.identity,
                    slot: slot,
                    codecIdentity: expected
                )
            }
            guard actual == expected else {
                throw GRDBStaticQueryError.resultCodecIdentityMismatch(
                    identity: descriptor.identity,
                    slot: slot,
                    expected: expected,
                    actual: actual
                )
            }
        }
    }

    private func validateStaticQueryStorage(
        _ descriptor: XLStaticQueryDescriptor
    ) throws {
        for parameter in descriptor.parameters {
            guard XLSQLiteStorageClass(
                rawValue: parameter.storageIdentifier.rawValue
            ) != nil else {
                throw GRDBStaticQueryError.unsupportedParameterStorage(
                    identity: descriptor.identity,
                    parameter: parameter
                )
            }
        }

        for slot in descriptor.results.slots {
            guard XLSQLiteStorageClass(
                rawValue: slot.storageIdentifier.rawValue
            ) != nil else {
                throw GRDBStaticQueryError.unsupportedResultStorage(
                    identity: descriptor.identity,
                    slot: slot
                )
            }
        }
    }

    private func logicalStatement(for encoding: XLEncoding) -> XLLogicalPreparedStatement {
        XLLogicalPreparedStatement(
            databaseIdentifier: driver.databaseIdentifier,
            dialectRequirement: encoding.dialectRequirement,
            sql: encoding.sql,
            entities: encoding.entities,
            parameterLayout: encoding.parameterLayout
        )
    }
}


/// `@unchecked Sendable` because sharing one value across threads and connections is this type's
/// whole purpose: `databasePool` hands any given call to whichever of several pooled physical
/// connections is idle, so every stored property is designed to be read concurrently from
/// multiple threads. The strict-concurrency checker cannot see that GRDB's own pool
/// synchronization already makes this safe.
extension GRDBDatabase: @unchecked Sendable {}


extension GRDBDatabase: XLTransactionalDatabase {

    /// Runs `body` against one pinned `DatabasePool` connection inside one
    /// real GRDB transaction (issue #284): `databasePool.write(_:)` opens the
    /// transaction, hands `body` a `GRDBDatabase` pinned to that connection,
    /// commits when `body` returns normally, and rolls back — preserving the
    /// original error — when `body` throws. See ``XLTransactionalDatabase``
    /// for the full ordering, atomicity, and lifetime contract.
    ///
    /// Rejects two cases before any transaction work happens:
    /// - calling `withTransaction(_:)` again from inside an already-active
    ///   body on this database throws
    ///   ``XLTransactionScopeError/nestedTransactionUnsupported`` without
    ///   touching the pool;
    /// - a task that is already cancelled when this is called throws
    ///   `CancellationError` before opening the transaction. The body itself
    ///   runs synchronously to completion once started, so there is no later
    ///   cooperative cancellation point.
    public func withTransaction<Result>(
        _ body: (GRDBDatabase) throws -> Result
    ) throws -> Result {
        // Rejects reentry on the pinned scope itself (fast, value-level,
        // thread-independent) and reentry through the original, unpinned
        // database captured from inside an active body (thread-scoped; see
        // `GRDBTransactionScopeTracker`). Both checks run before touching
        // `databasePool.write`, because GRDB's own reentrant-write guard is
        // an uncatchable `fatalError`.
        guard !driver.isPinned else {
            throw XLTransactionScopeError.nestedTransactionUnsupported
        }
        guard !GRDBTransactionScopeTracker.shared.isActive(driver.databaseIdentifier) else {
            throw XLTransactionScopeError.nestedTransactionUnsupported
        }
        if Task.isCancelled {
            throw CancellationError()
        }
        // `withActive` must be entered *inside* `databasePool.write`'s
        // closure, not around it: GRDB runs that closure on its own writer
        // thread, not necessarily the caller's thread, and the tracker marks
        // a thread active via `Thread.current.threadDictionary`. A reentrant
        // call from inside `body` runs on this same writer thread (it is
        // still on the same call stack), so marking active here is what
        // `preconditionNotRootReentrant()` actually observes.
        return try databasePool.write { database in
            try GRDBTransactionScopeTracker.shared.withActive(driver.databaseIdentifier) {
                let box = GRDBPinnedConnectionBox(database)
                defer { box.invalidate() }
                let scope = GRDBDatabase(
                    pinnedDriver: driver.pinned(to: box),
                    pinnedFrom: self
                )
                return try body(scope)
            }
        }
    }
}
