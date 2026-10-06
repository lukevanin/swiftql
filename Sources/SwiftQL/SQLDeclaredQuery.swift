//
//  SQLDeclaredQuery.swift
//  SwiftQL
//
//  Issue #659: the data a `@SQLQuery` or `@SQLQueries` declaration emits about
//  itself, and the generic runtime that assembles that data into an
//  `XLStaticQueryDescriptor`.
//
//  The macro has no type information. It knows the specification's name, its
//  parameter names and spelled types, its row type, its cardinality, and the
//  value-free statement builder. Everything that needs a type -- the rendered
//  SQL, the parameter layout, the value type and storage class of every
//  parameter and result -- is derived here, at run time, from the statement
//  the generated executor renders, with the encoder of the database the query
//  was read from.
//

import Foundation


///
/// One named parameter of a declared query, as its declaration spells it.
///
/// The generated code passes the parameter's Swift type, so the runtime can
/// derive the parameter's storage class. The rendered statement's parameter
/// layout remains the authority for everything else.
///
public struct XLDeclaredQueryParameter {

    /// The SQL placeholder name, without a leading colon.
    public let name: String

    let valueType: Any.Type

    public init<Value>(name: String, valueType: Value.Type) where Value: XLLiteral {
        self.name = name
        self.valueType = valueType
    }
}


///
/// A declared query, lowered from its declaration to the data a static
/// descriptor needs.
///
/// Every value is read from a database instance, so it renders with that
/// database's encoder:
///
/// - `@SQLQueries` generates a `declaredQueries` property on the extended
///   type and on its `Context`, with one value per specification in the
///   container.
/// - `@SQLQuery` generates a `<name>DeclaredQuery()` method beside each
///   declaration.
///
/// Call ``makeDescriptor()`` to assemble the static descriptor. A statement
/// that is not a declaration can be described the same way, by calling an
/// initializer directly.
///
public struct XLDeclaredQuery {

    /// The name of the database type the query is declared on, qualified by
    /// its enclosing types and without its module.
    public let databaseTypeName: String

    /// The specification function's base name.
    public let name: String

    /// The number of rows the query's declared return type promises.
    public let cardinality: XLQueryCardinality

    /// The parameters in declaration order.
    public let parameters: [XLDeclaredQueryParameter]

    private let encoder: (any XLEncoder)?

    private let render: (any XLEncoder) throws -> RenderedStatement

    ///
    /// Describes one declared query read from `database`.
    ///
    /// The query renders with the database's own encoder, so its descriptor
    /// carries the SQL that database runs. A `GRDBDatabase` supplies its
    /// encoder. For another database type, use
    /// ``init(databaseType:encoder:name:cardinality:parameters:rowType:statement:)``.
    ///
    /// - Parameters:
    ///   - database: The database the query is declared on.
    ///   - name: The specification function's base name.
    ///   - cardinality: The cardinality the declared return type selects.
    ///   - parameters: Every named parameter the statement binds.
    ///   - rowType: The row type the executor decodes.
    ///   - statement: Returns the value-free statement the executor renders.
    ///
    public init<Database, Row>(
        database: Database,
        name: String,
        cardinality: XLQueryCardinality,
        parameters: [XLDeclaredQueryParameter],
        rowType: Row.Type,
        statement: @escaping () -> any XLQueryStatement<Row>
    ) {
        self.init(
            databaseTypeName: Self.qualifiedTypeName(of: Database.self),
            optionalEncoder: (database as? GRDBDatabase)?.encoder,
            name: name,
            cardinality: cardinality,
            parameters: parameters,
            statement: statement
        )
    }

    ///
    /// Describes one declared query for a database type that renders with
    /// `encoder`.
    ///
    public init<Database, Row>(
        databaseType: Database.Type,
        encoder: any XLEncoder,
        name: String,
        cardinality: XLQueryCardinality,
        parameters: [XLDeclaredQueryParameter],
        rowType: Row.Type,
        statement: @escaping () -> any XLQueryStatement<Row>
    ) {
        self.init(
            databaseTypeName: Self.qualifiedTypeName(of: databaseType),
            optionalEncoder: encoder,
            name: name,
            cardinality: cardinality,
            parameters: parameters,
            statement: statement
        )
    }

    private init<Row>(
        databaseTypeName: String,
        optionalEncoder: (any XLEncoder)?,
        name: String,
        cardinality: XLQueryCardinality,
        parameters: [XLDeclaredQueryParameter],
        statement: @escaping () -> any XLQueryStatement<Row>
    ) {
        self.databaseTypeName = databaseTypeName
        self.name = name
        self.cardinality = cardinality
        self.parameters = parameters
        self.encoder = optionalEncoder
        self.render = { encoder in
            let value = statement()
            let encoding = encoder.makeSQL(value)
            if let select = value.components.reader as? Select<Row>,
               let layout = select.staticLayout {
                return RenderedStatement(encoding: encoding, results: .staticLayout(layout.metadata))
            }
            let recorder = XLDeclaredQueryResultRecorder()
            _ = try value.readRow(reader: recorder)
            return RenderedStatement(encoding: encoding, results: .recorded(recorder.columns))
        }
    }

    ///
    /// The query's stable identifier: the database type name and the
    /// specification name, joined by a period.
    ///
    public var id: String {
        "\(databaseTypeName).\(name)"
    }

    ///
    /// The definition identity: a path of the database type name and the
    /// specification name, at version 1.
    ///
    /// Neither component depends on the build, so the identity is the same
    /// in every build of an unchanged declaration.
    ///
    public func definitionIdentity() throws -> XLQueryDefinitionIdentity {
        try XLQueryDefinitionIdentity(path: [databaseTypeName, name], version: 1)
    }

    ///
    /// Assembles the static descriptor for this query.
    ///
    /// The statement is rendered with the encoder of the database the query
    /// was read from, so the descriptor's SQL is the SQL that database runs.
    ///
    /// A row selected through a static row layout takes its result slots from
    /// the layout's metadata, codecs included. Any other row is replayed
    /// against a reader that notes each column's alias and Swift type. That
    /// replay calls `sqlDefault()` on each result type, exactly as rendering
    /// a legacy `Select` projection already does.
    ///
    /// - Throws: ``XLDeclaredQueryError`` when the declaration and the
    ///   rendered statement disagree, or any error the statement, the row
    ///   reader, or the descriptor raises while it is validated.
    ///
    public func makeDescriptor() throws -> XLLoweredDeclaredQuery {
        guard let encoder else {
            throw XLDeclaredQueryError.encoderUnavailable(
                query: id,
                databaseType: databaseTypeName
            )
        }
        let rendered = try render(encoder)
        let definition = try XLStaticStatementDefinition(validating: rendered.encoding)
        let parameterMetadata = try makeParameterMetadata(
            layout: definition.parameterLayout
        )

        let results: XLStaticQueryResultMetadata
        let aliases: [String]
        switch rendered.results {
        case .staticLayout(let metadata):
            results = metadata.results
            aliases = metadata.fields.map(\.alias)
        case .recorded(let columns):
            results = try makeRecordedResults(columns)
            aliases = columns.map(\.alias)
        }

        let descriptor = try XLStaticQueryDescriptor(
            definitionIdentity: try definitionIdentity(),
            statement: definition,
            parameters: parameterMetadata,
            results: results,
            cardinality: cardinality
        )
        return XLLoweredDeclaredQuery(
            id: id,
            descriptor: descriptor,
            resultAliases: aliases
        )
    }

    private func makeRecordedResults(
        _ columns: [XLDeclaredQueryResultRecorder.Column]
    ) throws -> XLStaticQueryResultMetadata {
        var slots: [XLStaticQueryResultSlot] = []
        for (offset, column) in columns.enumerated() {
            let metadata = legacyValueMetadata(for: column.valueType)
            guard let storage = Self.storageClass(for: column.valueType) else {
                throw XLDeclaredQueryError.unknownStorageClass(
                    query: id,
                    slot: "result/\(column.alias)",
                    valueType: metadata.typeName
                )
            }
            slots.append(XLStaticQueryResultSlot(
                index: XLLogicalResultIndex(offset),
                identity: try XLQuerySlotIdentity(path: ["result", column.alias]),
                valueTypeIdentifier: metadata.identifier,
                valueTypeName: metadata.typeName,
                nullability: metadata.isOptional ? .nullable : .required,
                codecIdentity: nil,
                storageIdentifier: XLValueStorageIdentifier(rawValue: storage.rawValue),
                codingContext: XLValueCodingContext(
                    site: .result,
                    path: XLValueCodingPath(column.alias)
                )
            ))
        }
        return try XLStaticQueryResultMetadata(slots: slots)
    }

    private func makeParameterMetadata(
        layout: XLParameterLayout
    ) throws -> [XLStaticQueryParameterMetadata] {
        var declaredByName: [String: XLDeclaredQueryParameter] = [:]
        for parameter in parameters where declaredByName[parameter.name] == nil {
            declaredByName[parameter.name] = parameter
        }

        var renderedNames: Set<String> = []
        var metadata: [XLStaticQueryParameterMetadata] = []
        for slot in layout.slots {
            guard case .named(let name) = slot.key else {
                throw XLDeclaredQueryError.positionalParameter(
                    query: id,
                    key: slot.key.contextPathComponent
                )
            }
            renderedNames.insert(name)
            guard let declared = declaredByName[name] else {
                throw XLDeclaredQueryError.undeclaredParameter(query: id, name: name)
            }
            let expected = legacyValueMetadata(for: declared.valueType)
            let expectedNullability: XLParameterNullability = expected.isOptional
                ? .nullable
                : .required
            guard expected.identifier == slot.valueTypeIdentifier,
                  expectedNullability == slot.nullability else {
                throw XLDeclaredQueryError.parameterTypeMismatch(
                    query: id,
                    name: name,
                    declared: expected.typeName,
                    rendered: slot.valueTypeName
                )
            }
            let storageIdentifier: XLValueStorageIdentifier
            if let codecIdentity = slot.codecIdentity {
                storageIdentifier = codecIdentity.storageIdentifier
            }
            else if let storage = Self.storageClass(for: declared.valueType) {
                storageIdentifier = XLValueStorageIdentifier(rawValue: storage.rawValue)
            }
            else {
                throw XLDeclaredQueryError.unknownStorageClass(
                    query: id,
                    slot: "parameter/\(name)",
                    valueType: expected.typeName
                )
            }
            metadata.append(XLStaticQueryParameterMetadata(
                identity: try XLQuerySlotIdentity(path: ["parameter", name]),
                slot: slot,
                storageIdentifier: storageIdentifier
            ))
        }

        for parameter in parameters where !renderedNames.contains(parameter.name) {
            throw XLDeclaredQueryError.parameterNotRendered(
                query: id,
                name: parameter.name
            )
        }
        return metadata
    }

    ///
    /// A type's name qualified by its enclosing types, without its module.
    ///
    /// `String(describing:)` drops the enclosing types, so `A.Database` and
    /// `B.Database` would share one identity. `String(reflecting:)` keeps
    /// them, and its first component is the module, which is dropped so the
    /// name does not change when the declarations move to another module. A
    /// type declared in a private scope reflects an `(unknown context at …)`
    /// component whose address changes between builds, so that component is
    /// dropped too.
    ///
    static func qualifiedTypeName(of type: Any.Type) -> String {
        let reflected = String(reflecting: type)
        var components: [String] = []
        var current = ""
        var depth = 0
        for character in reflected {
            switch character {
            case "<", "(", "[":
                depth += 1
                current.append(character)
            case ">", ")", "]":
                depth -= 1
                current.append(character)
            case "." where depth == 0:
                components.append(current)
                current = ""
            default:
                current.append(character)
            }
        }
        components.append(current)
        if components.count > 1 {
            components.removeFirst()
        }
        components.removeAll { $0.hasPrefix("(") }
        guard !components.isEmpty else {
            return String(describing: type)
        }
        return components.joined(separator: ".")
    }

    ///
    /// The SQLite storage class a value of `type` binds as.
    ///
    /// Optionals are unwrapped, intrinsic types are known, and an `XLEnum`
    /// binds as its raw value. Any other literal is asked by binding its
    /// `sqlDefault()` placeholder and observing which storage class it wrote.
    ///
    static func storageClass(for type: Any.Type) -> XLSQLiteStorageClass? {
        if let optional = type as? any _XLOptionalLiteralType.Type {
            return storageClass(for: optional.wrappedType)
        }
        if let intrinsic = sqliteStorageClass(for: type) {
            return intrinsic
        }
        if let enumType = type as? any XLEnum.Type {
            return rawValueStorageClass(of: enumType)
        }
        if let literalType = type as? any XLLiteral.Type {
            return placeholderStorageClass(of: literalType)
        }
        return nil
    }

    private static func rawValueStorageClass<Value>(
        of type: Value.Type
    ) -> XLSQLiteStorageClass? where Value: XLEnum {
        storageClass(for: Value.RawValue.self)
    }

    private static func placeholderStorageClass<Value>(
        of type: Value.Type
    ) -> XLSQLiteStorageClass? where Value: XLLiteral {
        let value = _xlCapturedSQLiteValue(of: String(reflecting: Value.self)) { context in
            Value.sqlDefault().bind(context: &context)
        }
        switch value {
        case .null:
            return nil
        case .integer:
            return .integer
        case .real:
            return .real
        case .text:
            return .text
        case .blob:
            return .blob
        }
    }
}


/// A rendered declared-query statement and where its result slots come from.
private struct RenderedStatement {

    enum Results {
        case staticLayout(XLStaticRowMetadata)
        case recorded([XLDeclaredQueryResultRecorder.Column])
    }

    let encoding: XLEncoding

    let results: Results
}


///
/// A declared query's static descriptor, with the result aliases the
/// descriptor itself does not carry.
///
public struct XLLoweredDeclaredQuery {

    /// The declared query's stable identifier. See ``XLDeclaredQuery/id``.
    public let id: String

    /// The assembled static descriptor.
    public let descriptor: XLStaticQueryDescriptor

    /// The `AS` alias of every result column, in result order.
    public let resultAliases: [String]
}


///
/// A reason a declared query cannot be assembled into a static descriptor.
///
public enum XLDeclaredQueryError: Error, Equatable, LocalizedError {

    /// The statement renders a positional parameter. A declaration binds
    /// only named parameters.
    case positionalParameter(query: String, key: String)

    /// The statement renders a named parameter the declaration does not list.
    case undeclaredParameter(query: String, name: String)

    /// The declaration lists a parameter the statement does not render.
    case parameterNotRendered(query: String, name: String)

    /// The declared parameter type and the rendered slot disagree about the
    /// value type or its nullability.
    case parameterTypeMismatch(query: String, name: String, declared: String, rendered: String)

    /// No SQLite storage class can be derived for a slot's Swift type.
    case unknownStorageClass(query: String, slot: String, valueType: String)

    /// The query was read from a database whose encoder SwiftQL cannot
    /// reach. Describe it with an explicit encoder instead.
    case encoderUnavailable(query: String, databaseType: String)

    /// A generated declared-query registry was given no instance of a
    /// database type that declares queries, so those queries would be
    /// silently left out.
    case missingDatabaseInstance(typeName: String)

    public var errorDescription: String? {
        switch self {
        case .positionalParameter(let query, let key):
            return "Declared query '\(query)' renders positional parameter \(key). A declared query binds named parameters only."
        case .undeclaredParameter(let query, let name):
            return "Declared query '\(query)' renders parameter ':\(name)', but its declaration does not list it."
        case .parameterNotRendered(let query, let name):
            return "Declared query '\(query)' lists parameter '\(name)', but its statement does not render ':\(name)'."
        case .parameterTypeMismatch(let query, let name, let declared, let rendered):
            return "Declared query '\(query)' declares parameter '\(name)' as \(declared), but its statement renders it as \(rendered)."
        case .unknownStorageClass(let query, let slot, let valueType):
            return "Declared query '\(query)' has slot '\(slot)' of type \(valueType), and no SQLite storage class can be derived for it. Its sqlDefault() placeholder must bind a non-NULL value."
        case .encoderUnavailable(let query, let databaseType):
            return "Declared query '\(query)' was read from a \(databaseType), whose encoder SwiftQL cannot reach. Describe the query with XLDeclaredQuery(databaseType:encoder:name:cardinality:parameters:rowType:statement:)."
        case .missingDatabaseInstance(let typeName):
            return "The declared-query registry has queries declared on \(typeName), but no instance of \(typeName) was passed. Pass one, or those queries are not validated."
        }
    }
}


///
/// Records the alias and Swift type of every column a row reader reads.
///
/// Returns each type's `sqlDefault()` placeholder so the reader can run to
/// completion without a database row. A row that reads raw dialect values
/// fails with the default ``XLRowReader`` diagnostic rather than producing a
/// partial result layout.
///
final class XLDeclaredQueryResultRecorder: XLRowReader {

    struct Column {
        let alias: String
        let valueType: Any.Type
    }

    private(set) var columns: [Column] = []

    func column<T>(
        _ expression: any XLExpression<T>,
        alias: XLName
    ) throws -> T where T: XLLiteral {
        columns.append(Column(alias: alias.rawValue, valueType: T.self))
        return T.sqlDefault()
    }
}
