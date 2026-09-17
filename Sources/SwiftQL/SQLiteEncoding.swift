//
//  SQLiteEncoding.swift
//
//
//  Created by Luke Van In on 2023/07/21.
//

import Foundation


///
/// Encodes SwiftQL statements into SQL for one dialect.
///
/// The dialect supplies both halves of the rendering seam: the formatter that
/// spells literals, identifiers, and placeholders, and the vocabulary that
/// spells the keywords which differ between dialects. A second dialect is
/// therefore rendered by this same encoder rather than by a parallel one.
///
/// The dialect also decides how a logical binding key is spelled and numbered,
/// so a dialect with no named placeholders renders a query written with named
/// parameters as positional ones.
///
public struct XLDialectEncoder<Dialect>: XLEncoder where Dialect: XLSQLDialect {

    ///
    /// The dialect this encoder renders for.
    ///
    public let dialect: Dialect

    ///
    /// The formatter vended by ``dialect``.
    ///
    public var formatter: Dialect.Formatter {
        dialect.makeFormatter()
    }

    ///
    /// Creates an encoder for an explicit dialect configuration.
    ///
    public init(dialect: Dialect) {
        self.dialect = dialect
    }

    public func makeSQL(_ expression: XLEncodable) -> XLEncoding {
        let requirementRecorder = XLiteDialectRequirementRecorder(
            placeholderAssigner: dialect.makePlaceholderAssigner()
        )
        let recordingFormatter = XLiteRequirementRecordingFormatter(
            base: formatter,
            recorder: requirementRecorder
        )
        let customFunctionRegistry = XLiteCustomFunctionRegistry()
        var builder: XLBuilder = XLiteBuilder(
            formatter: recordingFormatter,
            vocabulary: dialect.makeVocabulary(),
            customFunctionRegistry: customFunctionRegistry
        )
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
            valueEncodingError: requirementRecorder.valueEncodingError,
            customFunctions: customFunctionRegistry.registrations
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


///
/// Encodes SwiftQL statements into SQL that can be executed by SQLite.
///
/// The SQLite conformance of ``XLDialectEncoder``.
///
public typealias XLiteEncoder = XLDialectEncoder<XLSQLiteDialect>


extension XLDialectEncoder where Dialect == XLSQLiteDialect {

    ///
    /// Creates a SQLite encoder from a formatter.
    ///
    /// The formatter carries the identifier quoting, which is the only part of
    /// the dialect it can express; everything else takes its default.
    ///
    public init(formatter: XLiteFormatter) {
        self.init(
            dialect: XLSQLiteDialect(
                identifierFormattingOptions: formatter.identifierFormattingOptions
            )
        )
    }
}


private final class XLiteDialectRequirementRecorder {

    var capabilities: XLDialectCapabilities = []

    private(set) var parameterLayout: XLParameterLayout = .empty

    private(set) var parameterLayoutError: XLInvocationBindingError?

    private(set) var valueEncodingError: XLSQLValueEncodingError?

    /// Assigns the rendered placeholder and physical position for each key.
    /// The dialect owns this rule, so a positional-only dialect numbers a
    /// named key rather than failing to render it.
    private var placeholderAssigner: any XLPlaceholderAssigner

    private var slotByPhysicalIndex: [Int: XLParameterSlot] = [:]

    /// Every textual appearance, in render order.
    private var occurrences: [XLParameterOccurrence] = []

    private var bindingOriginByKey: [XLBindingKey: XLBindingOrigin] = [:]

    init(placeholderAssigner: any XLPlaceholderAssigner) {
        self.placeholderAssigner = placeholderAssigner
    }

    /// Rejects two automatically named binding references from different
    /// namespaces that resolve to the same key. Without this check the
    /// recorder reuses the first slot, and both references share one value.
    ///
    /// The collision is reported as
    /// ``XLInvocationBindingError/conflictingParameterKey(key:existing:incoming:)``
    /// so that the public error enum keeps its cases. Both slots are the slot
    /// that the first reference recorded, because the two declarations are
    /// identical and only their origins differ.
    func recordBindingOrigin(_ origin: XLBindingOrigin, key: XLBindingKey) {
        guard let existingOrigin = bindingOriginByKey[key] else {
            bindingOriginByKey[key] = origin
            return
        }
        guard existingOrigin != origin,
              parameterLayoutError == nil,
              let slot = parameterLayout.slot(for: key) else {
            return
        }
        parameterLayoutError = .conflictingParameterKey(
            key: key,
            existing: slot,
            incoming: slot
        )
    }

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
                slots: parameterLayout.slots + [slot],
                occurrences: occurrences
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
        let assignment = placeholderAssigner.assignment(for: slot.key)
        let physicalIndex = assignment.physicalIndex

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

    /// Assigns the placeholder for `key` and records this textual appearance.
    ///
    /// The layout coalesces repeated appearances of a named parameter into a
    /// single slot, because it is bound once. This keeps the appearances too,
    /// in render order, for a dialect that must act on each of them.
    ///
    /// Called once per rendered reference, after the slot for `key` has been
    /// recorded.
    func renderPlaceholder(for key: XLBindingKey) -> XLBindingPlaceholder {
        let assignment = placeholderAssigner.assignment(for: key)
        if let slot = parameterLayout.slot(for: key) {
            occurrences.append(
                XLParameterOccurrence(
                    index: slot.index,
                    key: key,
                    placeholder: assignment.placeholder,
                    physicalIndex: assignment.physicalIndex
                )
            )
            rebuildLayoutOccurrences()
        }
        return assignment.placeholder
    }

    private func rebuildLayoutOccurrences() {
        do {
            parameterLayout = try XLParameterLayout(
                slots: parameterLayout.slots,
                occurrences: occurrences
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

    private func nextLogicalIndex() -> XLLogicalParameterIndex {
        var rawValue = 0
        while parameterLayout.slot(at: XLLogicalParameterIndex(rawValue)) != nil {
            rawValue += 1
        }
        return XLLogicalParameterIndex(rawValue)
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

    func recordBindingOrigin(_ origin: XLBindingOrigin, key: XLBindingKey)
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
        recorder.recordLegacyParameter(key: .named(named))
        return renderPlaceholder(for: .named(named))
    }

    func indexedBinding(_ index: Int) -> String {
        recorder.recordLegacyParameter(key: .indexed(index))
        return renderPlaceholder(for: .indexed(index))
    }

    func formatParameter(_ slot: XLParameterSlot) -> String {
        recorder.recordParameter(slot)
        return renderPlaceholder(for: slot.key)
    }

    ///
    /// Renders one parameter reference through the dialect's placeholder rule.
    ///
    /// The capability recorded is the one the rendered placeholder needs, not
    /// the one the logical key would suggest. A dialect that spells every key
    /// positionally therefore requires only `.indexedBindings`, whatever the
    /// Swift code named.
    ///
    private func renderPlaceholder(for key: XLBindingKey) -> String {
        switch recorder.renderPlaceholder(for: key) {
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
        return renderPlaceholder(for: declaration.key)
    }

    func recordValueEncodingError(_ error: XLSQLValueEncodingError) {
        recorder.recordValueEncodingError(error)
    }

    func recordBindingOrigin(_ origin: XLBindingOrigin, key: XLBindingKey) {
        recorder.recordBindingOrigin(origin, key: key)
    }
}


///
/// Formats SwiftQL literals into SQL sub-expressions for use with SQLite.


///
/// Reference-type collector for custom-function registrations discovered while rendering one
/// statement.
///
/// `XLiteBuilder` and its nested sub-builders are value types created afresh at every nesting
/// boundary (see `entities()` and the `_entities.formUnion(...)` calls throughout this file).
/// Sharing one instance of this collector across every nested builder lets a custom-function call
/// at any nesting depth record itself directly, without threading a second `Set`-returning
/// accessor and union step through every nesting method that already exists for `entities()`.
///
final class XLiteCustomFunctionRegistry {

    private(set) var registrations: [XLCustomFunctionDefinition: XLCustomFunctionRegistration] = [:]

    /// Records `registration`, keeping what earlier registrations of the same
    /// signature retain.
    ///
    /// The latest registration still decides which registration the statement
    /// carries, as before. Registrations that share a signature are
    /// interchangeable, and the driver installs a signature once per
    /// connection, so this choice does not pick the implementation a
    /// connection runs. Its retained values are merged rather than replaced, so a
    /// statement that matches two ``XLRegexPattern`` values keeps both alive,
    /// not only the last one rendered.
    func insert(_ registration: XLCustomFunctionRegistration) {
        guard let existing = registrations[registration.definition] else {
            registrations[registration.definition] = registration
            return
        }
        registrations[registration.definition] = registration.retaining(
            existing.retainedValues
        )
    }
}


///
/// Constructs an SQL expression that can be executed by SQLite.
///
public struct XLiteBuilder: XLBuilder {

    private var formatter: XLFormatter

    ///
    /// Spells the keywords whose text differs between dialects.
    ///
    /// This builder renders for SQLite, so it carries SQLite's vocabulary.
    ///
    public let vocabulary: any XLSQLVocabulary

    private var _tokens: [String] = []

    private var _entities: Set<String> = []

    private let customFunctionRegistry: XLiteCustomFunctionRegistry

    public init(formatter: XLFormatter, vocabulary: any XLSQLVocabulary = XLiteVocabulary()) {
        self.init(
            formatter: formatter,
            vocabulary: vocabulary,
            customFunctionRegistry: XLiteCustomFunctionRegistry()
        )
    }

    init(
        formatter: XLFormatter,
        vocabulary: any XLSQLVocabulary = XLiteVocabulary(),
        customFunctionRegistry: XLiteCustomFunctionRegistry
    ) {
        self.formatter = formatter
        self.vocabulary = vocabulary
        self.customFunctionRegistry = customFunctionRegistry
    }

    // A single already-rendered token per call. Every caller passes exactly one
    // string, so this avoids the variadic array box and the `filter` copy that
    // the previous `String...` signature allocated on every builder node.
    private mutating func append(_ token: String) {
        if !token.isEmpty {
            _tokens.append(token)
        }
    }

    public func build() -> String {
        // A single already-rendered token is by far the common case for leaf and
        // wrapper builders; return it directly instead of allocating a new joined
        // string. The separator is irrelevant for one element, so output is
        // identical.
        if _tokens.count == 1 {
            return _tokens[0]
        }
        return _tokens.joined(separator: XLSeparator.tuple.rawValue)
    }

    public func entities() -> Set<String> {
        _entities
    }

    public mutating func entity(_ name: String) {
        _entities.insert(name)
    }

    public mutating func customFunction(_ registration: XLCustomFunctionRegistration) {
        customFunctionRegistry.insert(registration)
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
        // SQLite reads a text literal only up to the first NUL, so a value
        // that contains U+0000 cannot render faithfully (issue #657). Report
        // it without an invalid token, as `real(_:)` does for NaN.
        if value.utf8.contains(0) {
            valueEncodingFailed(
                .nulCharacterInText(
                    valueType: String(reflecting: String.self),
                    context: nil
                )
            )
            return
        }
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
        var listBuilder: XLListBuilder = XLiteListBuilder(
            formatter: formatter,
            separator: separator,
            customFunctionRegistry: customFunctionRegistry
        )
        items(&listBuilder)
        append(listBuilder.build())
        _entities.formUnion(listBuilder.entities())
    }

    public mutating func block(beginsWith prefix: String, endsWith suffix: String, separator: XLSeparator, contents: (inout XLBuilder) -> Void) {
        var blockBuilder: XLBuilder = XLiteBuilder(formatter: formatter, vocabulary: vocabulary, customFunctionRegistry: customFunctionRegistry)
        contents(&blockBuilder)
        append(prefix + separator.rawValue + blockBuilder.build() + separator.rawValue + suffix)
        _entities.formUnion(blockBuilder.entities())
    }

    public mutating func unaryPrefix(_ operator: String, expression: (inout XLBuilder) -> Void) {
        var expressionBuilder: XLBuilder = XLiteBuilder(formatter: formatter, vocabulary: vocabulary, customFunctionRegistry: customFunctionRegistry)
        expression(&expressionBuilder)
        append(`operator` + " " + expressionBuilder.build())
        _entities.formUnion(expressionBuilder.entities())
    }

    public mutating func unarySuffix(_ operator: String, expression: (inout XLBuilder) -> Void) {
        var expressionBuilder: XLBuilder = XLiteBuilder(formatter: formatter, vocabulary: vocabulary, customFunctionRegistry: customFunctionRegistry)
        expression(&expressionBuilder)
        append(expressionBuilder.build() + " " + `operator`)
        _entities.formUnion(expressionBuilder.entities())
    }

    public mutating func unaryOperator(_ operator: String, expression: (inout XLBuilder) -> Void) {
        var expressionBuilder: XLBuilder = XLiteBuilder(formatter: formatter, vocabulary: vocabulary, customFunctionRegistry: customFunctionRegistry)
        expression(&expressionBuilder)
        append(`operator` + expressionBuilder.build())
        _entities.formUnion(expressionBuilder.entities())
    }

    public mutating func binaryOperator(_ operator: String, left: (inout XLBuilder) -> Void, right: (inout XLBuilder) -> Void) {
        var lhsExpressionBuilder: XLBuilder = XLiteBuilder(formatter: formatter, vocabulary: vocabulary, customFunctionRegistry: customFunctionRegistry)
        var rhsExpressionBuilder: XLBuilder = XLiteBuilder(formatter: formatter, vocabulary: vocabulary, customFunctionRegistry: customFunctionRegistry)
        left(&lhsExpressionBuilder)
        right(&rhsExpressionBuilder)
        append(lhsExpressionBuilder.build() + " " + `operator` + " " + rhsExpressionBuilder.build())
        _entities.formUnion(lhsExpressionBuilder.entities())
        _entities.formUnion(rhsExpressionBuilder.entities())
    }

    public mutating func cast(type: String, expression: (inout XLBuilder) -> Void) {
        var expressionBuilder: XLBuilder = XLiteBuilder(formatter: formatter, vocabulary: vocabulary, customFunctionRegistry: customFunctionRegistry)
        expression(&expressionBuilder)
        append("CAST(" + expressionBuilder.build() + " AS " + type + ")")
        _entities.formUnion(expressionBuilder.entities())
    }

    public mutating func simpleFunction(name: String, parameters: (inout XLListBuilder) -> Void) {
        var listBuilder: XLListBuilder = XLiteListBuilder(
            formatter: formatter,
            separator: .list,
            customFunctionRegistry: customFunctionRegistry
        )
        parameters(&listBuilder)
        append(name + "(" + listBuilder.build() + ")")
        _entities.formUnion(listBuilder.entities())
    }

    public mutating func aggregateFunction(name: String, distinct: Bool, parameters: (inout XLListBuilder) -> Void) {
        var listBuilder: XLListBuilder = XLiteListBuilder(
            formatter: formatter,
            separator: .list,
            customFunctionRegistry: customFunctionRegistry
        )
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
        var expressionBuilder: XLBuilder = XLiteBuilder(formatter: formatter, vocabulary: vocabulary, customFunctionRegistry: customFunctionRegistry)
        expression(&expressionBuilder)
        append(expressionBuilder.build() + " AS " + formatter.name(name.rawValue))
        _entities.formUnion(expressionBuilder.entities())
    }

    public mutating func commonTables(builder: (inout XLCommonTablesBuilder) -> Void) {
        var commonTablesBuilder: XLCommonTablesBuilder = XLiteCommonTablesBuilder(
            formatter: formatter,
            customFunctionRegistry: customFunctionRegistry
        )
        builder(&commonTablesBuilder)
        append(vocabulary.spelling(for: .with) + " " + commonTablesBuilder.build())
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


extension XLiteBuilder: XLBindingOriginRecording {

    func recordBindingOrigin(_ origin: XLBindingOrigin, key: XLBindingKey) {
        guard let recordingFormatter =
                formatter as? any XLiteParameterRecordingFormatter else {
            return
        }
        recordingFormatter.recordBindingOrigin(origin, key: key)
    }
}


///
/// Used by `XLiteBuilder` to construct a list of sub-expressions.
///
public struct XLiteListBuilder: XLListBuilder {

    private var formatter: XLFormatter

    /// Carried so that nested builders render with the same dialect's keywords.
    let vocabulary: any XLSQLVocabulary

    private var separator: String

    private var _tokens: [String] = []

    private var _entities: Set<String> = []

    private let customFunctionRegistry: XLiteCustomFunctionRegistry

    init(
        formatter: XLFormatter,
        separator: String,
        vocabulary: any XLSQLVocabulary = XLiteVocabulary(),
        customFunctionRegistry: XLiteCustomFunctionRegistry
    ) {
        self.vocabulary = vocabulary
        self.separator = separator
        self.formatter = formatter
        self.customFunctionRegistry = customFunctionRegistry
    }

    init(
        formatter: XLFormatter,
        separator: XLSeparator,
        vocabulary: any XLSQLVocabulary = XLiteVocabulary(),
        customFunctionRegistry: XLiteCustomFunctionRegistry
    ) {
        self.init(
            formatter: formatter,
            separator: separator.rawValue,
            vocabulary: vocabulary,
            customFunctionRegistry: customFunctionRegistry
        )
    }

    public func build() -> String {
        if _tokens.count == 1 {
            return _tokens[0]
        }
        return _tokens.joined(separator: separator)
    }

    public func entities() -> Set<String> {
        _entities
    }

    public mutating func listItem(expression: (inout XLBuilder) -> Void) {
        var builder: XLBuilder = XLiteBuilder(formatter: formatter, vocabulary: vocabulary, customFunctionRegistry: customFunctionRegistry)
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

    /// Carried so that nested builders render with the same dialect's keywords.
    let vocabulary: any XLSQLVocabulary

    private var _tokens: [String] = []

    private var _entities: Set<String> = []

    private let customFunctionRegistry: XLiteCustomFunctionRegistry

    init(
        formatter: XLFormatter,
        vocabulary: any XLSQLVocabulary = XLiteVocabulary(),
        customFunctionRegistry: XLiteCustomFunctionRegistry
    ) {
        self.formatter = formatter
        self.vocabulary = vocabulary
        self.customFunctionRegistry = customFunctionRegistry
    }

    public func build() -> String {
        if _tokens.count == 1 {
            return _tokens[0]
        }
        return _tokens.joined(separator: XLSeparator.list.rawValue)
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
        var builder: XLBuilder = XLiteBuilder(formatter: formatter, vocabulary: vocabulary, customFunctionRegistry: customFunctionRegistry)
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
        if _tokens.count == 1 {
            return _tokens[0]
        }
        return _tokens.joined(separator: XLSeparator.list.rawValue)
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
