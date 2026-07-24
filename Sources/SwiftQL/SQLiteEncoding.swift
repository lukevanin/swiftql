//
//  SQLiteEncoding.swift
//
//
//  Created by Luke Van In on 2023/07/21.
//

import Foundation


///
/// Encodes SwiftQL statements into SQL that can be executed by SQLite.
///
public struct XLiteEncoder: XLEncoder {

    public var formatter: XLiteFormatter

    private var dialectDescriptor: XLDialectDescriptor

    public init(formatter: XLiteFormatter) {
        self.formatter = formatter
        self.dialectDescriptor = XLSQLiteDialect().descriptor
    }

    /// Creates an encoder from an explicit SQLite dialect configuration.
    public init(dialect: XLSQLiteDialect) {
        self.formatter = XLiteFormatter(
            identifierFormattingOptions: dialect.identifierFormattingOptions
        )
        self.dialectDescriptor = dialect.descriptor
    }

    public var dialect: XLSQLiteDialect {
        XLSQLiteDialect(
            identifierFormattingOptions: formatter.identifierFormattingOptions,
            version: dialectDescriptor.version,
            capabilities: dialectDescriptor.capabilities
        )
    }

    public func makeSQL(_ expression: XLEncodable) -> XLEncoding {
        let requirementRecorder = XLiteDialectRequirementRecorder()
        let recordingFormatter = XLiteRequirementRecordingFormatter(
            base: formatter,
            recorder: requirementRecorder
        )
        var builder: XLBuilder = XLiteBuilder(formatter: recordingFormatter)
        expression.makeSQL(context: &builder)
        return XLEncoding(
            sql: builder.build(),
            entities: builder.entities(),
            dialectRequirement: XLDialectRequirement(
                identity: dialect.descriptor.identity,
                capabilities: requirementRecorder.capabilities
            ),
            parameterLayout: requirementRecorder.parameterLayout,
            parameterLayoutError: requirementRecorder.parameterLayoutError,
            valueEncodingError: requirementRecorder.valueEncodingError
        )
    }

    /// Renders SQL and rejects conflicting or invalid static parameter
    /// declarations before a prepared handle is created.
    public func makeValidatedSQL(_ expression: XLEncodable) throws -> XLEncoding {
        let encoding = makeSQL(expression)
        if let error = encoding.valueEncodingError {
            throw error
        }
        if let error = encoding.parameterLayoutError {
            throw error
        }
        return encoding
    }
}


private final class XLiteDialectRequirementRecorder {

    var capabilities: XLDialectCapabilities = []

    private(set) var parameterLayout: XLParameterLayout = .empty

    private(set) var parameterLayoutError: XLInvocationBindingError?

    private(set) var valueEncodingError: XLSQLValueEncodingError?

    private var physicalIndexByKey: [XLBindingKey: Int] = [:]

    private var slotByPhysicalIndex: [Int: XLParameterSlot] = [:]

    private var largestPhysicalIndex = 0

    func recordValueEncodingError(_ error: XLSQLValueEncodingError) {
        if valueEncodingError == nil {
            valueEncodingError = error
        }
    }

    func recordLegacyParameter(key: XLBindingKey) {
        let existing = parameterLayout.slot(for: key)
        let slot = XLParameterSlot(
            index: existing?.index ?? nextLogicalIndex(),
            key: key,
            valueTypeIdentifier: XLValueTypeIdentifier(
                rawValue: "swiftql.legacy-binding-value"
            ),
            valueTypeName: "SwiftQL.XLBindable",
            nullability: .nullable,
            codecIdentity: nil,
            codingContext: XLValueCodingContext(
                site: .parameter,
                path: XLValueCodingPath(key.parameterPathComponent)
            )
        )

        if let existing {
            guard existing.declaration == slot.declaration else {
                if parameterLayoutError == nil {
                    parameterLayoutError = .conflictingParameterKey(
                        key: key,
                        existing: existing,
                        incoming: slot
                    )
                }
                return
            }
            return
        }
        recordParameter(slot)
    }

    func recordParameter(_ slot: XLParameterSlot) {
        recordPhysicalParameter(slot)
        do {
            parameterLayout = try XLParameterLayout(
                slots: parameterLayout.slots + [slot]
            )
        }
        catch let error as XLInvocationBindingError {
            if parameterLayoutError == nil {
                parameterLayoutError = error
            }
        }
        catch {
            preconditionFailure("XLParameterLayout produced an unexpected error: \(error)")
        }
    }

    func recordParameter(_ declaration: XLParameterDeclaration) {
        let existing = parameterLayout.slot(for: declaration.key)
        if let existing,
           existing.isRendererLegacyBindingWildcard,
           existing.declaration != declaration {
            if parameterLayoutError == nil {
                parameterLayoutError = .conflictingParameterKey(
                    key: declaration.key,
                    existing: existing,
                    incoming: declaration.slot(at: existing.index)
                )
            }
            return
        }
        let index = existing?.index ?? nextLogicalIndex()
        recordParameter(declaration.slot(at: index))
    }

    /// SQLite assigns named parameters the next physical index, while `?NNN`
    /// uses `NNN` directly. A named parameter followed by an explicit index can
    /// therefore alias the same physical slot even though SwiftQL has two
    /// distinct logical keys. Reject that shape during rendering.
    private func recordPhysicalParameter(_ slot: XLParameterSlot) {
        let physicalIndex: Int
        if let recorded = physicalIndexByKey[slot.key] {
            physicalIndex = recorded
        }
        else {
            switch slot.key {
            case .named:
                physicalIndex = largestPhysicalIndex + 1
            case .indexed(let zeroBasedIndex):
                physicalIndex = zeroBasedIndex + 1
            }
            physicalIndexByKey[slot.key] = physicalIndex
            largestPhysicalIndex = max(largestPhysicalIndex, physicalIndex)
        }

        if let existing = slotByPhysicalIndex[physicalIndex],
           existing.key != slot.key {
            if parameterLayoutError == nil {
                parameterLayoutError = .conflictingPhysicalParameterIndex(
                    index: physicalIndex,
                    existing: existing,
                    incoming: slot
                )
            }
            return
        }
        slotByPhysicalIndex[physicalIndex] = slot
    }

    private func nextLogicalIndex() -> XLLogicalParameterIndex {
        var rawValue = 0
        while parameterLayout.slot(at: XLLogicalParameterIndex(rawValue)) != nil {
            rawValue += 1
        }
        return XLLogicalParameterIndex(rawValue)
    }
}


private extension XLParameterSlot {

    var isRendererLegacyBindingWildcard: Bool {
        valueTypeIdentifier == XLValueTypeIdentifier(
            rawValue: "swiftql.legacy-binding-value"
        )
            && valueTypeName == "SwiftQL.XLBindable"
            && nullability == .nullable
            && codecIdentity == nil
    }
}


private extension XLBindingKey {

    var parameterPathComponent: String {
        switch self {
        case .named(let name):
            return name
        case .indexed(let index):
            return String(index)
        }
    }
}


private protocol XLiteParameterRecordingFormatter: XLFormatter {

    func formatParameter(_ slot: XLParameterSlot) -> String

    func formatParameter(_ declaration: XLParameterDeclaration) -> String

    func recordValueEncodingError(_ error: XLSQLValueEncodingError)
}


private struct XLiteRequirementRecordingFormatter: XLiteParameterRecordingFormatter {

    let base: XLFormatter

    let recorder: XLiteDialectRequirementRecorder

    func null() -> String {
        base.null()
    }

    func integer(_ value: Int) -> String {
        base.integer(value)
    }

    func real(_ value: Double) -> String {
        base.real(value)
    }

    func text(_ value: String) -> String {
        base.text(value)
    }

    func blob(_ value: Data) -> String {
        base.blob(value)
    }

    func name(_ value: String) -> String {
        base.name(value)
    }

    func scopedName(_ values: [String]) -> String {
        base.scopedName(values)
    }

    func namedBinding(_ named: String) -> String {
        recorder.capabilities.insert(.namedBindings)
        recorder.recordLegacyParameter(key: .named(named))
        return base.namedBinding(named)
    }

    func indexedBinding(_ index: Int) -> String {
        recorder.capabilities.insert(.indexedBindings)
        recorder.recordLegacyParameter(key: .indexed(index))
        return base.indexedBinding(index)
    }

    func formatParameter(_ slot: XLParameterSlot) -> String {
        recorder.recordParameter(slot)
        switch slot.key {
        case .named(let name):
            recorder.capabilities.insert(.namedBindings)
            return base.namedBinding(name)
        case .indexed(let index):
            recorder.capabilities.insert(.indexedBindings)
            return base.indexedBinding(index)
        }
    }

    func formatParameter(_ declaration: XLParameterDeclaration) -> String {
        recorder.recordParameter(declaration)
        switch declaration.key {
        case .named(let name):
            recorder.capabilities.insert(.namedBindings)
            return base.namedBinding(name)
        case .indexed(let index):
            recorder.capabilities.insert(.indexedBindings)
            return base.indexedBinding(index)
        }
    }

    func recordValueEncodingError(_ error: XLSQLValueEncodingError) {
        recorder.recordValueEncodingError(error)
    }
}


///
/// Formats SwiftQL literals into SQL sub-expressions for use with SQLite.
///
public struct XLiteFormatter: XLFormatter {

    ///
    /// Defines the escape sequence used to encode identifiers.
    ///
    /// SQLite provides compatibility for different conventions for escaping names of identifiers. SwiftQL
    /// uses SQLite's canonical double-quoted identifier syntax by default.
    ///
    public typealias IdentifierFormattingOptions = XLSQLiteIdentifierFormattingOptions

    public var identifierFormattingOptions: IdentifierFormattingOptions

    public init(identifierFormattingOptions: IdentifierFormattingOptions = .sqlite) {
        self.identifierFormattingOptions = identifierFormattingOptions
    }

    public func null() -> String {
        "NULL"
    }

    public func integer(_ value: Int) -> String {
        String(value)
    }

    public func real(_ value: Double) -> String {
        guard value.isFinite else {
            return ""
        }
        return String(value)
    }

    public func text(_ text: String) -> String {
        // Embedded single quotes must be doubled per the SQL standard, otherwise
        // the value breaks out of the literal (broken SQL at best, injection at worst).
        guard text.contains("'") else {
            return "'\(text)'"
        }
        return "'\(text.replacingOccurrences(of: "'", with: "''"))'"
    }

    public func text(_ text: StaticString) -> String {
        self.text(text.description)
    }

    public func blob(_ data: Data) -> String {
        "x'\(data.hex())'"
    }

    public func name(_ value: String) -> String {
        XLSQLiteDialect(
            identifierFormattingOptions: identifierFormattingOptions
        ).formatIdentifier(value)
    }

    public func scopedName(_ values: [String]) -> String {
        values.map(name).joined(separator: ".")
    }

    public func namedBinding(_ named: String) -> String {
        ":\(named)"
    }

    public func indexedBinding(_ index: Int) -> String {
        "?\(index + 1)"
    }
}


///
/// Constructs an SQL expression that can be executed by SQLite.
///
public struct XLiteBuilder: XLBuilder {

    private var formatter: XLFormatter

    private var _tokens: [String] = []

    private var _entities: Set<String> = []

    public init(formatter: XLFormatter) {
        self.formatter = formatter
    }

    private mutating func append(_ tokens: String...) {
        _tokens.append(contentsOf: tokens.filter({ !$0.isEmpty }))
    }

    public func build() -> String {
        _tokens.joined(separator: XLSeparator.tuple.rawValue)
    }

    public func entities() -> Set<String> {
        _entities
    }

    public mutating func entity(_ name: String) {
        _entities.insert(name)
    }

    public mutating func null() {
        append(formatter.null())
    }

    public mutating func integer(_ value: Int) {
        append(formatter.integer(value))
    }

    public mutating func real(_ value: Double) {
        if let classified = XLNonFiniteRealValue(value) {
            valueEncodingFailed(
                .nonFiniteRealLiteral(
                    value: classified,
                    expressionType: String(reflecting: Double.self)
                )
            )
            return
        }
        append(formatter.real(value))
    }

    public mutating func valueEncodingFailed(
        _ error: XLSQLValueEncodingError
    ) {
        guard let recordingFormatter =
                formatter as? any XLiteParameterRecordingFormatter else {
            return
        }
        recordingFormatter.recordValueEncodingError(error)
    }

    public mutating func text(_ value: String) {
        append(formatter.text(value))
    }

    public mutating func blob(_ value: Data) {
        append(formatter.blob(value))
    }

    public mutating func name(_ value: XLName) {
        append(formatter.name(value.rawValue))
    }

    public mutating func qualifiedName(_ value: XLQualifiedName) {
        append(formatter.scopedName(value.components.map { $0.rawValue }))
    }

    public mutating func namedBinding(_ name: XLName) {
        append(formatter.namedBinding(name.rawValue))
    }

    public mutating func indexedBinding(_ index: Int) {
        append(formatter.indexedBinding(index))
    }

    public mutating func parameter(_ slot: XLParameterSlot) {
        if let recordingFormatter = formatter as? any XLiteParameterRecordingFormatter {
            append(recordingFormatter.formatParameter(slot))
            return
        }

        switch slot.key {
        case .named(let name):
            append(formatter.namedBinding(name))
        case .indexed(let index):
            append(formatter.indexedBinding(index))
        }
    }

    public mutating func parameter(_ declaration: XLParameterDeclaration) {
        if let recordingFormatter = formatter as? any XLiteParameterRecordingFormatter {
            append(recordingFormatter.formatParameter(declaration))
            return
        }

        switch declaration.key {
        case .named(let name):
            append(formatter.namedBinding(name))
        case .indexed(let index):
            append(formatter.indexedBinding(index))
        }
    }

    public mutating func list(separator: String, items: (inout XLListBuilder) -> Void) {
        var listBuilder: XLListBuilder = XLiteListBuilder(formatter: formatter, separator: separator)
        items(&listBuilder)
        append(listBuilder.build())
        _entities.formUnion(listBuilder.entities())
    }

    public mutating func block(beginsWith prefix: String, endsWith suffix: String, separator: XLSeparator, contents: (inout XLBuilder) -> Void) {
        var blockBuilder: XLBuilder = XLiteBuilder(formatter: formatter)
        contents(&blockBuilder)
        append(prefix + separator.rawValue + blockBuilder.build() + separator.rawValue + suffix)
        _entities.formUnion(blockBuilder.entities())
    }

    public mutating func unaryPrefix(_ operator: String, expression: (inout XLBuilder) -> Void) {
        var expressionBuilder: XLBuilder = XLiteBuilder(formatter: formatter)
        expression(&expressionBuilder)
        append(`operator` + " " + expressionBuilder.build())
        _entities.formUnion(expressionBuilder.entities())
    }

    public mutating func unarySuffix(_ operator: String, expression: (inout XLBuilder) -> Void) {
        var expressionBuilder: XLBuilder = XLiteBuilder(formatter: formatter)
        expression(&expressionBuilder)
        append(expressionBuilder.build() + " " + `operator`)
        _entities.formUnion(expressionBuilder.entities())
    }

    public mutating func unaryOperator(_ operator: String, expression: (inout XLBuilder) -> Void) {
        var expressionBuilder: XLBuilder = XLiteBuilder(formatter: formatter)
        expression(&expressionBuilder)
        append(`operator` + expressionBuilder.build())
        _entities.formUnion(expressionBuilder.entities())
    }

    public mutating func binaryOperator(_ operator: String, left: (inout XLBuilder) -> Void, right: (inout XLBuilder) -> Void) {
        var lhsExpressionBuilder: XLBuilder = XLiteBuilder(formatter: formatter)
        var rhsExpressionBuilder: XLBuilder = XLiteBuilder(formatter: formatter)
        left(&lhsExpressionBuilder)
        right(&rhsExpressionBuilder)
        append(lhsExpressionBuilder.build() + " " + `operator` + " " + rhsExpressionBuilder.build())
        _entities.formUnion(lhsExpressionBuilder.entities())
        _entities.formUnion(rhsExpressionBuilder.entities())
    }

    public mutating func cast(type: String, expression: (inout XLBuilder) -> Void) {
        var expressionBuilder: XLBuilder = XLiteBuilder(formatter: formatter)
        expression(&expressionBuilder)
        append("CAST(" + expressionBuilder.build() + " AS " + type + ")")
        _entities.formUnion(expressionBuilder.entities())
    }

    public mutating func simpleFunction(name: String, parameters: (inout XLListBuilder) -> Void) {
        var listBuilder: XLListBuilder = XLiteListBuilder(formatter: formatter, separator: .list)
        parameters(&listBuilder)
        append(name + "(" + listBuilder.build() + ")")
        _entities.formUnion(listBuilder.entities())
    }

    public mutating func aggregateFunction(name: String, distinct: Bool, parameters: (inout XLListBuilder) -> Void) {
        var listBuilder: XLListBuilder = XLiteListBuilder(formatter: formatter, separator: .list)
        parameters(&listBuilder)
        if distinct {
            append(name + "(DISTINCT " + listBuilder.build() + ")")
        }
        else {
            append(name + "(" + listBuilder.build() + ")")
        }
        _entities.formUnion(listBuilder.entities())
    }

    public mutating func alias(_ name: XLName, expression: (inout XLBuilder) -> Void) {
        var expressionBuilder: XLBuilder = XLiteBuilder(formatter: formatter)
        expression(&expressionBuilder)
        append(expressionBuilder.build() + " AS " + formatter.name(name.rawValue))
        _entities.formUnion(expressionBuilder.entities())
    }

    public mutating func commonTables(builder: (inout XLCommonTablesBuilder) -> Void) {
        var commonTablesBuilder: XLCommonTablesBuilder = XLiteCommonTablesBuilder(formatter: formatter)
        builder(&commonTablesBuilder)
        append("WITH " + commonTablesBuilder.build())
        _entities.formUnion(commonTablesBuilder.entities())
    }

    public mutating func createTable(_ name: XLQualifiedName) {
        let tableName = formatter.scopedName(name.components.map { $0.rawValue })
        append("CREATE TABLE IF NOT EXISTS " + tableName + " AS")
    }

    public mutating func createTable(_ name: XLQualifiedName, builder: (inout XLColumnDefinitionsBuilder) -> Void) {
        var columnsBuilder: XLColumnDefinitionsBuilder = XLiteColumnDefinitionsBuilder(formatter: formatter)
        builder(&columnsBuilder)
        let tableName = formatter.scopedName(name.components.map { $0.rawValue })
        append("CREATE TABLE IF NOT EXISTS " + tableName + " (" + columnsBuilder.build() + ")")
    }
}


///
/// Used by `XLiteBuilder` to construct a list of sub-expressions.
///
public struct XLiteListBuilder: XLListBuilder {

    private var formatter: XLFormatter

    private var separator: String

    private var _tokens: [String] = []

    private var _entities: Set<String> = []

    init(formatter: XLFormatter, separator: String) {
        self.separator = separator
        self.formatter = formatter
    }

    init(formatter: XLFormatter, separator: XLSeparator) {
        self.init(formatter: formatter, separator: separator.rawValue)
    }

    public func build() -> String {
        _tokens.joined(separator: separator)
    }

    public func entities() -> Set<String> {
        _entities
    }

    public mutating func listItem(expression: (inout XLBuilder) -> Void) {
        var builder: XLBuilder = XLiteBuilder(formatter: formatter)
        expression(&builder)
        _tokens.append(builder.build())
        _entities.formUnion(builder.entities())
    }
}


///
/// Used by `XLiteBuilder` to construct common table expressions.
///
public struct XLiteCommonTablesBuilder: XLCommonTablesBuilder {

    private var formatter: XLFormatter

    private var _tokens: [String] = []

    private var _entities: Set<String> = []

    init(formatter: XLFormatter) {
        self.formatter = formatter
    }

    public func build() -> String {
        _tokens.joined(separator: XLSeparator.list.rawValue)
    }

    public func entities() -> Set<String> {
        _entities
    }

    public mutating func commonTable(alias: XLName, expression: (inout XLBuilder) -> Void) {
        commonTable(alias: alias, materialization: .unspecified, columns: [], expression: expression)
    }

    public mutating func commonTable(
        alias: XLName,
        materialization: XLCommonTableMaterialization,
        columns: [XLName],
        expression: (inout XLBuilder) -> Void
    ) {
        var builder: XLBuilder = XLiteBuilder(formatter: formatter)
        expression(&builder)
        let hint = materialization.keyword.map { " " + $0 } ?? ""
        let columnList = columns.isEmpty
            ? ""
            : "(" + columns.map { formatter.name($0.rawValue) }.joined(separator: XLSeparator.list.rawValue) + ")"
        _tokens.append(formatter.name(alias.rawValue) + columnList + " AS" + hint + " (" + builder.build() + ")")
        _entities.formUnion(builder.entities())
    }
}


///
/// Used by `XLiteBuilder` to construct a set of columns.
///
public struct XLiteColumnDefinitionsBuilder: XLColumnDefinitionsBuilder {

    private var formatter: XLFormatter

    private var _tokens: [String] = []

    init(formatter: XLFormatter) {
        self.formatter = formatter
    }

    public func build() -> String {
        _tokens.joined(separator: XLSeparator.list.rawValue)
    }

    ///
    /// Append a column to a table CREATE statement.
    /// SwiftQL does not emit a declared SQLite type for the column. Values are
    /// encoded and decoded using the column's Swift literal type.
    ///
    public mutating func column(name: XLName, nullable: Bool) {

        var components: [String] = []
        components.append(formatter.name(name.rawValue))
        if !nullable {
            components.append("NOT NULL")
        }
        _tokens.append(components.joined(separator: XLSeparator.tuple.rawValue))
    }
}
