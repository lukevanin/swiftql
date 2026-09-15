//
//  GRDBDatabase+InsertBatch.swift
//  SwiftQL
//
//  Inserting many rows of one table through one rendered statement (issue
//  #668).
//
//  `sqlInsert(_:)` renders each row's values into the SQL text as literals, so
//  a loop of `makeRequest(with: sqlInsert(row)).execute()` renders one
//  statement per row, and every distinct row is a distinct SQL string that
//  SQLite prepares again. `insert(contentsOf:)` renders the insert once with a
//  placeholder where each literal was, and binds every row's values through an
//  invocation packet.
//

import Foundation
import GRDB


extension GRDBDatabase {

    ///
    /// Inserts every row in `rows` through one rendered insert statement.
    ///
    /// The statement is the one `sqlInsert(_:)` renders for the first row, with
    /// a bound parameter in place of each literal value. It is rendered once
    /// per call, and each row binds its values to it through an immutable
    /// invocation packet. Because the SQL text is the same for every row,
    /// GRDB's per-connection statement cache prepares it once per connection
    /// and reuses it for every later row.
    ///
    /// All rows run on one connection, in sequence order, and the call is one
    /// unit: when a row fails, no row of this call stays written.
    ///
    /// - On a transaction scope -- the value ``withTransaction(_:)`` passes to
    ///   its body -- the rows are written inside a savepoint in that
    ///   transaction. When a row fails, the savepoint rolls back every row of
    ///   this call and is released before the error is thrown. Writes the body
    ///   made before or after the call are not affected, so a body that catches
    ///   the error and returns normally commits without any row of the batch.
    ///   On success the savepoint is released, and the rows commit or roll back
    ///   with the enclosing transaction.
    /// - On any other database, the call opens one write transaction for all
    ///   rows. Either every row commits or none does.
    ///
    /// `rows` is read inside the connection access, one element at a time, and
    /// only after the database or scope has been checked. A lazily produced
    /// element must not use a database itself: the root database is rejected
    /// from inside the access, as it is from inside a transaction body.
    ///
    /// SwiftQL keeps only the rendered SQL and its parameter layout between
    /// rows. The prepared statement stays owned by the connection that
    /// prepared it and is never kept past the connection access of this call.
    ///
    /// A row whose values cannot be bound to the shared statement is rendered
    /// and executed exactly as `sqlInsert(_:)` would, inside the same
    /// transaction. That covers a value that renders as more than one literal
    /// or as SQL other than a literal, such as a custom literal type that wraps
    /// its value in a function call, and a value that fails to render, such as
    /// a non-finite `Double`. Such a row therefore fails with the same error
    /// the single-row path reports.
    ///
    /// An empty sequence renders and writes nothing. It still checks the
    /// database or scope, so an escaped scope throws
    /// ``XLTransactionScopeError/scopeEscaped`` for an empty sequence too.
    ///
    /// - Parameter rows: The rows to insert.
    /// - Throws: The first error a row's rendering, binding, or execution
    ///   raises, after every row written by this call is rolled back;
    ///   ``XLTransactionScopeError/scopeEscaped`` when called on a transaction
    ///   scope after its body returned; or
    ///   ``XLTransactionScopeError/nestedTransactionUnsupported`` when called on
    ///   the root database from inside an active transaction body.
    ///
    public func insert<Rows>(contentsOf rows: Rows) throws
    where
        Rows: Sequence,
        Rows.Element: XLTable,
        Rows.Element.MetaNamedResult.Row == Rows.Element,
        Rows.Element.MetaInsert.Row == Rows.Element
    {
        var driver = driver
        // A pool-backed call owns its whole transaction, which already rolls
        // back every row on failure. A scope's transaction belongs to the
        // body, so the batch takes its own savepoint to stay one unit.
        let usesSavepoint = driver.isPinned
        try driver.withTransaction { connection in
            var iterator = rows.makeIterator()
            guard let firstRow = iterator.next() else {
                return
            }
            let batch = GRDBInsertBatch<Rows.Element>(
                database: self,
                templateRow: firstRow
            )
            if usesSavepoint {
                try connection.withSavepoint { connection in
                    try batch.insertRows(
                        first: firstRow,
                        rest: &iterator,
                        in: &connection
                    )
                }
            }
            else {
                try batch.insertRows(
                    first: firstRow,
                    rest: &iterator,
                    in: &connection
                )
            }
        }
    }
}


///
/// One rendered insert statement shared by the rows of one
/// `insert(contentsOf:)` call (issue #668).
///
/// Holds the logical statement only: SQL text, parameter layout, and the
/// recorded shape of the values clause. A physical statement is looked up on
/// the connection for each row and is never stored here.
///
struct GRDBInsertBatch<Row>
where
    Row: XLTable,
    Row.MetaNamedResult.Row == Row,
    Row.MetaInsert.Row == Row
{

    private struct Template {

        let executor: GRDBInvocationExecutor

        /// The recorded shape of the template row's values clause. A later
        /// row binds to the template only when its values clause records the
        /// same shape.
        let shape: [XLInsertValueCaptureToken]

        /// The parameter slot for each captured value, in capture order.
        let slots: [XLParameterSlot]
    }

    private let database: GRDBDatabase

    /// `nil` when the template row's values cannot be expressed as bound
    /// parameters. Every row then renders as `sqlInsert(_:)` does.
    private let template: Template?

    init(database: GRDBDatabase, templateRow: Row) {
        self.database = database
        self.template = Self.makeTemplate(database: database, row: templateRow)
    }

    private static func makeTemplate(
        database: GRDBDatabase,
        row: Row
    ) -> Template? {
        let recorder = XLInsertValueCaptureRecorder(expectedShape: nil)
        let schema = XLSchema()
        let table = schema.table(Row.self)
        // The same statement `sqlInsert(_:)` builds, except that the values
        // clause renders a parameter in place of each literal.
        let statement = XLInsertTableValuesStatement<Row>(
            components: SwiftQL.insert(table).components.appending(
                XLInsertValueParameterization(
                    values: Row.MetaInsert(row),
                    recorder: recorder
                )
            )
        )
        let encoding = database.encoder.makeSQL(statement)
        guard
            recorder.isParameterizable,
            encoding.valueEncodingError == nil,
            encoding.parameterLayoutError == nil,
            encoding.customFunctions.isEmpty,
            encoding.parameterLayout.count == recorder.values.count
        else {
            return nil
        }
        var slots: [XLParameterSlot] = []
        slots.reserveCapacity(recorder.values.count)
        for index in recorder.values.indices {
            guard
                let slot = encoding.parameterLayout.slot(
                    for: XLInsertValueCaptureRecorder.key(forValueAt: index)
                )
            else {
                return nil
            }
            slots.append(slot)
        }
        return Template(
            executor: GRDBInvocationExecutor(
                driver: database.driver,
                logicalStatement: database.logicalStatement(for: encoding),
                parameterLayoutError: database.preparedParameterLayoutError(
                    for: encoding
                ),
                valueEncodingError: encoding.valueEncodingError,
                customFunctions: encoding.customFunctions
            ),
            shape: recorder.shape,
            slots: slots
        )
    }

    /// Inserts `first`, then every row `rest` still produces, on `connection`.
    func insertRows<Rest>(
        first: Row,
        rest: inout Rest,
        in connection: inout GRDBDatabaseDriverConnection
    ) throws where Rest: IteratorProtocol, Rest.Element == Row {
        try insert(first, in: &connection)
        while let row = rest.next() {
            try insert(row, in: &connection)
        }
    }

    /// Inserts `row` on `connection`, which the caller holds for the whole
    /// batch.
    func insert(
        _ row: Row,
        in connection: inout GRDBDatabaseDriverConnection
    ) throws {
        if let template {
            let recorder = XLInsertValueCaptureRecorder(
                expectedShape: template.shape
            )
            var capture: XLBuilder = XLInsertValueCaptureBuilder(
                base: nil,
                recorder: recorder
            )
            Row.MetaInsert(row).makeSQL(context: &capture)
            if recorder.matchesExpectedShape {
                var bindings: [XLInvocationBinding<XLSQLiteValue>] = []
                bindings.reserveCapacity(template.slots.count)
                for (slot, value) in zip(template.slots, recorder.values) {
                    bindings.append(
                        try XLInvocationBinding(slot: slot, value: value)
                    )
                }
                try execute(
                    XLInvocationBindings(
                        layout: template.executor.parameterLayout,
                        bindings: bindings
                    ),
                    executor: template.executor,
                    in: &connection
                )
                return
            }
        }
        try insertRendered(row, in: &connection)
    }

    /// Renders and executes `row` exactly as
    /// `makeRequest(with: sqlInsert(row)).execute()` does, but on the
    /// connection this batch already holds.
    private func insertRendered(
        _ row: Row,
        in connection: inout GRDBDatabaseDriverConnection
    ) throws {
        let encoding = database.encoder.makeSQL(sqlInsert(row))
        let executor = GRDBInvocationExecutor(
            driver: database.driver,
            logicalStatement: database.logicalStatement(for: encoding),
            parameterLayoutError: database.preparedParameterLayoutError(
                for: encoding
            ),
            valueEncodingError: encoding.valueEncodingError,
            customFunctions: encoding.customFunctions
        )
        // `GRDBWriteRequest.execute()` reports a layout error from its binding
        // accumulator before the executor checks the packet.
        if let error = executor.parameterLayoutError {
            throw error
        }
        try execute(
            XLInvocationBindings<XLSQLiteValue>(layout: executor.parameterLayout),
            executor: executor,
            in: &connection
        )
    }

    private func execute(
        _ bindings: XLInvocationBindings<XLSQLiteValue>,
        executor: GRDBInvocationExecutor,
        in connection: inout GRDBDatabaseDriverConnection
    ) throws {
        let packet = try executor.sqlitePacket(bindings)
        database.logger?.debug(
            "execute: <<<\(executor.logicalStatement.sql)>>> parameters: <<<\(packet.bindings)>>>"
        )
        try executor.execute(packet: packet, in: &connection)
    }
}


// MARK: - Values capture


///
/// One builder call recorded while a generated `MetaInsert` renders its column
/// list and values clause.
///
/// The sequence is the values clause's shape. Two rows of one table with the
/// same shape render the same SQL once each literal is a parameter, so the
/// second row can bind to the statement rendered for the first.
///
enum XLInsertValueCaptureToken: Equatable {
    case value
    case name(XLName)
    case listBegin(separator: String)
    case listItemBegin
    case listItemEnd
    case listEnd
    case blockBegin(prefix: String, suffix: String, separator: XLSeparator)
    case blockEnd
    case unaryPrefixBegin(String)
    case unaryPrefixEnd
}


///
/// Shared state of one values-clause capture: the literal values in render
/// order, the recorded shape, and whether the clause can be bound.
///
final class XLInsertValueCaptureRecorder {

    /// The captured literal values, in render order.
    private(set) var values: [XLSQLiteValue] = []

    /// The recorded shape. Empty when an expected shape was given.
    private(set) var shape: [XLInsertValueCaptureToken] = []

    /// `false` once the clause rendered something other than the literal
    /// values, names, lists, blocks, and prefixes a generated `MetaInsert`
    /// renders, or a literal that fails to render.
    private(set) var isParameterizable = true

    private let expectedShape: [XLInsertValueCaptureToken]?

    private var position = 0

    init(expectedShape: [XLInsertValueCaptureToken]?) {
        self.expectedShape = expectedShape
        if let expectedShape {
            values.reserveCapacity(expectedShape.count)
        }
    }

    /// Whether a capture against an expected shape matched all of it.
    var matchesExpectedShape: Bool {
        guard let expectedShape else {
            return false
        }
        return isParameterizable && position == expectedShape.count
    }

    /// The parameter key for the value at `index` in render order.
    static func key(forValueAt index: Int) -> XLBindingKey {
        .named("swiftql_insert_\(index)")
    }

    func record(_ token: XLInsertValueCaptureToken) {
        guard isParameterizable else {
            return
        }
        guard let expectedShape else {
            shape.append(token)
            return
        }
        guard position < expectedShape.count, expectedShape[position] == token else {
            isParameterizable = false
            return
        }
        position += 1
    }

    /// Records a literal value and returns the declaration of the parameter
    /// that takes its place.
    func recordValue(_ value: XLSQLiteValue) -> XLParameterDeclaration {
        record(.value)
        let key = Self.key(forValueAt: values.count)
        values.append(value)
        return XLParameterDeclaration(
            key: key,
            valueTypeIdentifier: XLValueTypeIdentifier(
                rawValue: "swiftql.insert-batch.sqlite-value"
            ),
            valueTypeName: String(reflecting: XLSQLiteValue.self),
            nullability: .nullable,
            codecIdentity: nil,
            codingContext: XLValueCodingContext(
                site: .parameter,
                path: XLValueCodingPath(key.contextPathComponent)
            )
        )
    }

    func reject() {
        isParameterizable = false
    }
}


///
/// Renders a generated `MetaInsert` through a builder that records its values
/// clause and puts a parameter in place of each literal.
///
struct XLInsertValueParameterization: XLEncodable {

    let values: any XLEncodable

    let recorder: XLInsertValueCaptureRecorder

    func makeSQL(context: inout XLBuilder) {
        XLInsertValueCaptureBuilder.forward(
            &context,
            recorder: recorder,
            body: values.makeSQL
        )
    }
}


///
/// A builder that records the calls a generated `MetaInsert` makes and
/// forwards them to `base`, with a parameter in place of each literal value.
///
/// With no `base`, it only records. That is how a later row's values are
/// captured without rendering any SQL.
///
/// Every call a generated `MetaInsert` does not make marks the capture as not
/// parameterizable and is forwarded unchanged, so the rendered text stays well
/// formed and the caller renders that row as `sqlInsert(_:)` does.
///
struct XLInsertValueCaptureBuilder: XLBuilder {

    private(set) var base: XLBuilder?

    let recorder: XLInsertValueCaptureRecorder

    init(base: XLBuilder?, recorder: XLInsertValueCaptureRecorder) {
        self.base = base
        self.recorder = recorder
    }

    /// Runs `body` with a capturing builder over `builder`, then writes the
    /// forwarded state back into `builder`.
    static func forward(
        _ builder: inout XLBuilder,
        recorder: XLInsertValueCaptureRecorder,
        body: (inout XLBuilder) -> Void
    ) {
        var capture: XLBuilder = XLInsertValueCaptureBuilder(
            base: builder,
            recorder: recorder
        )
        body(&capture)
        guard
            let captured = capture as? XLInsertValueCaptureBuilder,
            let base = captured.base
        else {
            recorder.reject()
            return
        }
        builder = base
    }

    /// Runs `body` against a nested builder: a capturing builder over
    /// `nested` when forwarding, or a recording-only builder otherwise.
    private func nested(
        _ nested: inout XLBuilder,
        _ body: (inout XLBuilder) -> Void
    ) {
        Self.forward(&nested, recorder: recorder, body: body)
    }

    private func recordOnly(_ body: (inout XLBuilder) -> Void) {
        var capture: XLBuilder = XLInsertValueCaptureBuilder(
            base: nil,
            recorder: recorder
        )
        body(&capture)
    }

    // MARK: Recorded calls

    func build() -> String {
        base?.build() ?? ""
    }

    func entities() -> Set<String> {
        base?.entities() ?? []
    }

    mutating func null() {
        value(.null)
    }

    mutating func integer(_ value: Int) {
        self.value(.integer(Int64(value)))
    }

    mutating func real(_ value: Double) {
        guard value.isFinite else {
            // The literal path reports a non-finite value as a rendering
            // error, where a bound parameter would store it. Keep the literal
            // path's behavior by rendering this row as a literal.
            recorder.reject()
            base?.real(value)
            return
        }
        self.value(.real(value))
    }

    mutating func text(_ value: String) {
        guard !value.utf8.contains(0) else {
            recorder.reject()
            base?.text(value)
            return
        }
        self.value(.text(value))
    }

    mutating func blob(_ value: Data) {
        self.value(.blob(value))
    }

    private mutating func value(_ value: XLSQLiteValue) {
        let declaration = recorder.recordValue(value)
        base?.parameter(declaration)
    }

    mutating func name(_ value: XLName) {
        recorder.record(.name(value))
        base?.name(value)
    }

    mutating func list(separator: String, items: ListBuilder) {
        recorder.record(.listBegin(separator: separator))
        let recorder = recorder
        if base != nil {
            base!.list(separator: separator) { listBuilder in
                var capture: XLListBuilder = XLInsertValueCaptureListBuilder(
                    base: listBuilder,
                    recorder: recorder
                )
                items(&capture)
                guard
                    let captured = capture as? XLInsertValueCaptureListBuilder,
                    let base = captured.base
                else {
                    recorder.reject()
                    return
                }
                listBuilder = base
            }
        }
        else {
            var capture: XLListBuilder = XLInsertValueCaptureListBuilder(
                base: nil,
                recorder: recorder
            )
            items(&capture)
        }
        recorder.record(.listEnd)
    }

    mutating func block(
        beginsWith prefix: String,
        endsWith suffix: String,
        separator: XLSeparator,
        contents: Builder
    ) {
        recorder.record(
            .blockBegin(prefix: prefix, suffix: suffix, separator: separator)
        )
        if base != nil {
            let capture = self
            base!.block(
                beginsWith: prefix,
                endsWith: suffix,
                separator: separator
            ) { nested in
                capture.nested(&nested, contents)
            }
        }
        else {
            recordOnly(contents)
        }
        recorder.record(.blockEnd)
    }

    mutating func unaryPrefix(_ operator: String, expression: Builder) {
        recorder.record(.unaryPrefixBegin(`operator`))
        if base != nil {
            let capture = self
            base!.unaryPrefix(`operator`) { nested in
                capture.nested(&nested, expression)
            }
        }
        else {
            recordOnly(expression)
        }
        recorder.record(.unaryPrefixEnd)
    }

    // MARK: Calls a generated MetaInsert does not make

    mutating func entity(_ name: String) {
        recorder.reject()
        base?.entity(name)
    }

    mutating func customFunction(_ registration: XLCustomFunctionRegistration) {
        recorder.reject()
        base?.customFunction(registration)
    }

    mutating func valueEncodingFailed(_ error: XLSQLValueEncodingError) {
        recorder.reject()
        base?.valueEncodingFailed(error)
    }

    mutating func qualifiedName(_ value: XLQualifiedName) {
        recorder.reject()
        base?.qualifiedName(value)
    }

    mutating func namedBinding(_ name: XLName) {
        recorder.reject()
        base?.namedBinding(name)
    }

    mutating func indexedBinding(_ index: Int) {
        recorder.reject()
        base?.indexedBinding(index)
    }

    mutating func parameter(_ slot: XLParameterSlot) {
        recorder.reject()
        base?.parameter(slot)
    }

    mutating func parameter(_ declaration: XLParameterDeclaration) {
        recorder.reject()
        base?.parameter(declaration)
    }

    mutating func unarySuffix(_ operator: String, expression: Builder) {
        recorder.reject()
        base?.unarySuffix(`operator`, expression: expression)
    }

    mutating func unaryOperator(_ operator: String, expression: Builder) {
        recorder.reject()
        base?.unaryOperator(`operator`, expression: expression)
    }

    mutating func binaryOperator(_ operator: String, left: Builder, right: Builder) {
        recorder.reject()
        base?.binaryOperator(`operator`, left: left, right: right)
    }

    mutating func between(term: Builder, minimum: Builder, maximum: Builder) {
        recorder.reject()
        base?.between(term: term, minimum: minimum, maximum: maximum)
    }

    mutating func cast(type: String, expression: Builder) {
        recorder.reject()
        base?.cast(type: type, expression: expression)
    }

    mutating func simpleFunction(name: String, parameters: ListBuilder) {
        recorder.reject()
        base?.simpleFunction(name: name, parameters: parameters)
    }

    mutating func aggregateFunction(name: String, distinct: Bool, parameters: ListBuilder) {
        recorder.reject()
        base?.aggregateFunction(name: name, distinct: distinct, parameters: parameters)
    }

    mutating func alias(_ name: XLName, expression: Builder) {
        recorder.reject()
        base?.alias(name, expression: expression)
    }

    mutating func commonTables(builder: CommonTablesBuilder) {
        recorder.reject()
        base?.commonTables(builder: builder)
    }

    mutating func createTable(_ name: XLQualifiedName) {
        recorder.reject()
        base?.createTable(name)
    }

    mutating func createTable(_ name: XLQualifiedName, builder: ColumnsBuilder) {
        recorder.reject()
        base?.createTable(name, builder: builder)
    }
}


///
/// The list builder counterpart of ``XLInsertValueCaptureBuilder``.
///
struct XLInsertValueCaptureListBuilder: XLListBuilder {

    private(set) var base: XLListBuilder?

    let recorder: XLInsertValueCaptureRecorder

    init(base: XLListBuilder?, recorder: XLInsertValueCaptureRecorder) {
        self.base = base
        self.recorder = recorder
    }

    func build() -> String {
        base?.build() ?? ""
    }

    func entities() -> Set<String> {
        base?.entities() ?? []
    }

    mutating func listItem(expression: Builder) {
        recorder.record(.listItemBegin)
        let recorder = recorder
        if base != nil {
            base!.listItem { nested in
                XLInsertValueCaptureBuilder.forward(
                    &nested,
                    recorder: recorder,
                    body: expression
                )
            }
        }
        else {
            var capture: XLBuilder = XLInsertValueCaptureBuilder(
                base: nil,
                recorder: recorder
            )
            expression(&capture)
        }
        recorder.record(.listItemEnd)
    }
}
