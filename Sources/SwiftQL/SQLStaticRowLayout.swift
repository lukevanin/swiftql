//
//  SQLStaticRowLayout.swift
//  SwiftQL
//
//  A row's complete decoding plan: the ordered fields it is made of, and how
//  a reader walks them.
//
//  Reduced to the layout itself by issue #559 -- its errors, its fields, and
//  the configuration that builds them are in the three files beside it.
//

import Foundation


struct _XLStaticOffsetRowReader: XLRowReader {
    let base: XLRowReader
    let offset: Int

    func column<Value>(
        _ expression: any XLExpression<Value>,
        alias: XLName
    ) throws -> Value where Value: XLLiteral {
        try base.column(expression, alias: alias)
    }

    func dialectValue<RequestedDialect>(
        at index: Int,
        using dialect: RequestedDialect
    ) throws -> RequestedDialect.Value where RequestedDialect: XLValueCodingDialect {
        try base.dialectValue(at: offset + index, using: dialect)
    }
}


/// A row reader whose projection is available structurally without executing
/// its decoding closure.
public protocol XLStaticRowReadable<Row>: XLRowReadable, XLEncodable {
    associatedtype Row
    var metadata: XLStaticRowMetadata { get }
}


/// An operational typed row layout paired with driver-neutral structural
/// metadata.
///
/// Construction validates only immutable field metadata. The model
/// initializer in `decode` runs exclusively when a database row is decoded;
/// it is never called while building a `Select` or static query descriptor.
public struct XLStaticRowLayout<Row, Dialect>:
    XLStaticRowReadable
where Dialect: XLValueCodingDialect {

    public let metadata: XLStaticRowMetadata

    let fields: [XLAnyStaticSelectField<Dialect>]
    let decodeRow: (XLRowReader) throws -> Row
    let encodeRow: (Row) throws -> [Dialect.Value]

    public init(
        fields: [XLAnyStaticSelectField<Dialect>],
        decode: @escaping (XLRowReader) throws -> Row,
        encode: @escaping (Row) throws -> [Dialect.Value]
    ) throws {
        self.metadata = try XLStaticRowMetadata(
            fields: fields.map(\.metadata)
        )
        self.fields = fields
        self.decodeRow = decode
        self.encodeRow = encode
    }

    public func makeSQL(context: inout XLBuilder) {
        context.list(separator: .list) { list in
            for field in fields {
                list.listItem { builder in
                    builder.alias(
                        XLName(field.metadata.alias),
                        expression: { expressionBuilder in
                            if field.expression is any XLQueryStatement {
                                expressionBuilder.parenthesis(
                                    contents: field.expression.makeSQL
                                )
                            }
                            else {
                                field.expression.makeSQL(
                                    context: &expressionBuilder
                                )
                            }
                        }
                    )
                }
            }
        }
    }

    public func readRow(reader: XLRowReader) throws -> Row {
        try decodeRow(reader)
    }

    /// Decodes one complete ordered row of dialect values.
    public func decode(_ values: [Dialect.Value]) throws -> Row {
        guard values.count == metadata.fields.count else {
            throw XLStaticRowLayoutError.valueCountMismatch(
                expected: metadata.fields.count,
                actual: values.count
            )
        }
        try validate(values)
        let reader = _XLStaticDialectValuesRowReader(
            values: values,
            dialect: Dialect.self
        )
        return try decodeRow(reader)
    }

    /// Encodes every property in declaration order using the exact codecs
    /// retained by this layout.
    public func encode(_ row: Row) throws -> [Dialect.Value] {
        let values = try encodeRow(row)
        guard values.count == metadata.fields.count else {
            throw XLStaticRowLayoutError.valueCountMismatch(
                expected: metadata.fields.count,
                actual: values.count
            )
        }
        try validate(values)
        return values
    }

    func validate(_ values: [Dialect.Value]) throws {
        for (field, value) in zip(fields, values) {
            try field.validateValue(value)
        }
    }
}


extension XLStaticRowLayout: XLStaticRowFieldSource {
    public typealias FieldValue = Row
    public typealias FieldDialect = Dialect

    /// The nested composite contribution: every one of this layout's own
    /// flattened slots, continuing at `index` and re-aliased with `alias`.
    /// Reading recurses through this layout's own `readRow(reader:)` against
    /// an index-offsetting view of the enclosing row, so none of its fields
    /// need to be rebuilt; encoding reuses `encode(_:)` directly, since its
    /// flat, ordered output already matches the position where the group's
    /// `fields` are spliced into the enclosing layout.
    public func grouped(
        at index: Int,
        alias: String
    ) throws -> XLStaticFieldGroup<Row, Dialect> {
        let offsetFields = fields.map {
            $0._swiftQLNested(atOffset: index, aliasPrefix: alias)
        }
        return XLStaticFieldGroup(
            fields: offsetFields,
            decode: { reader in
                try self.readRow(
                    reader: _XLStaticOffsetRowReader(base: reader, offset: index)
                )
            },
            encode: { value in try self.encode(value) }
        )
    }
}


/// A typed static descriptor whose operational row layout is proven to match
/// the structural result contract used by stable query identity.
///
/// This API is database-driver independent and contains no GRDB types.
public struct XLTypedStaticQueryDescriptor<Row, Dialect>
where Dialect: XLValueCodingDialect {
    public let descriptor: XLStaticQueryDescriptor
    public let layout: XLStaticRowLayout<Row, Dialect>

    public init(
        descriptor: XLStaticQueryDescriptor,
        layout: XLStaticRowLayout<Row, Dialect>
    ) throws {
        guard descriptor.results == layout.metadata.results else {
            throw XLStaticRowLayoutError.descriptorResultsMismatch(
                expected: descriptor.results,
                actual: layout.metadata.results
            )
        }
        self.descriptor = descriptor
        self.layout = layout
    }
}
