import Foundation


/// Adapts a SwiftQL v1 literal to the contextual SQLite value-codec contract.
///
/// The adapter preserves the existing `XLLiteral` binding and reading behavior
/// while making its durable identity and SQLite storage representation explicit.
/// Its value must be `Sendable` because the resulting codec can be shared in a
/// concurrent immutable configuration; the original v1 path remains unchanged.
/// This is a compatibility bridge; new domain values can define
/// `XLValueCodec` instances directly without conforming to `XLLiteral`.
public struct XLV1LiteralCodec<Value>: Sendable where Value: XLLiteral & Sendable {

    /// The contextual codec backed by the v1 literal implementation.
    public let codec: XLValueCodec<Value, XLSQLiteDialect>

    /// Creates a contextual codec for an existing v1 literal.
    ///
    /// - Parameters:
    ///   - key: The stable name and version of the persisted representation.
    ///   - valueTypeIdentifier: The stable identity of the Swift value's
    ///     persisted meaning.
    ///   - storageClass: The SQLite storage class produced and consumed by the
    ///     literal. Values that do not match it fail at the codec boundary.
    public init(
        key: XLValueCodecKey,
        valueTypeIdentifier: XLValueTypeIdentifier,
        storageClass: XLSQLiteStorageClass
    ) {
        self.codec = XLValueCodec(
            key: key,
            valueTypeIdentifier: valueTypeIdentifier,
            dialectIdentifier: XLSQLiteDialect.identity,
            storageIdentifier: XLValueStorageIdentifier(
                rawValue: storageClass.rawValue
            ),
            encode: { value, _, _ in
                var context: any XLBindingContext = _XLV1LiteralBindingContext()
                value.bind(context: &context)
                return (context as! _XLV1LiteralBindingContext).value
            },
            decode: { value, _, _ in
                try Value(
                    reader: XLSQLiteValueReader(values: [value]),
                    at: 0
                )
            }
        )
    }
}


private struct _XLV1LiteralBindingContext: XLBindingContext {

    var value: XLSQLiteValue = .null

    mutating func bindNull() {
        value = .null
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
