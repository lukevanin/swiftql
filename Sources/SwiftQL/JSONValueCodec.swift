import Foundation


/// SQLite storage representation produced by a JSON `Codable` codec.
///
/// `TEXT` and `BLOB` are not interchangeable. They are distinct SQLite
/// storage classes with distinct stable ``XLValueCodecIdentity`` values, so a
/// codec built for one storage never silently accepts or reinterprets bytes
/// produced for the other; a mismatch fails with
/// `XLValueCodecError.storageMismatch`.
public enum XLJSONValueCodecStorage: String, Hashable, Sendable {

    /// UTF-8 encoded JSON text, stored as SQLite `TEXT`.
    case text

    /// Raw JSON bytes, stored as SQLite `BLOB`.
    case blob

    var storageClass: XLSQLiteStorageClass {
        switch self {
        case .text:
            return .text
        case .blob:
            return .blob
        }
    }
}


/// An immutable, `Sendable` snapshot of the `JSONEncoder`/`JSONDecoder`
/// strategies used by ``XLJSONValueCodec`` factories.
///
/// Only strategies that have a stable `Sendable` value-type representation
/// are exposed. A live `JSONEncoder`/`JSONDecoder` instance is never
/// captured or shared across calls: every encode and decode builds a fresh
/// encoder or decoder from this snapshot, so there is no process-global or
/// shared mutable JSON configuration. A mapping that needs a closure-based
/// strategy (for example a custom date formatter) is out of scope for this
/// factory; construct an `XLValueCodec` directly for that case.
public struct XLJSONCodecConfiguration: Hashable, Sendable {

    /// Mirrors the `Sendable`-safe cases of `JSONEncoder.KeyEncodingStrategy`.
    public enum KeyEncodingStrategy: Hashable, Sendable {
        case useDefaultKeys
        case convertToSnakeCase
    }

    /// Mirrors the `Sendable`-safe cases of `JSONDecoder.KeyDecodingStrategy`.
    public enum KeyDecodingStrategy: Hashable, Sendable {
        case useDefaultKeys
        case convertFromSnakeCase
    }

    /// Mirrors the `Sendable`-safe cases of `JSONEncoder.DateEncodingStrategy`.
    public enum DateEncodingStrategy: Hashable, Sendable {
        case deferredToDate
        case secondsSince1970
        case millisecondsSince1970
        case iso8601
    }

    /// Mirrors the `Sendable`-safe cases of `JSONDecoder.DateDecodingStrategy`.
    public enum DateDecodingStrategy: Hashable, Sendable {
        case deferredToDate
        case secondsSince1970
        case millisecondsSince1970
        case iso8601
    }

    /// Mirrors the `Sendable`-safe cases of `JSONEncoder.DataEncodingStrategy`.
    public enum DataEncodingStrategy: Hashable, Sendable {
        case base64
        case deferredToData
    }

    /// Mirrors the `Sendable`-safe cases of `JSONDecoder.DataDecodingStrategy`.
    public enum DataDecodingStrategy: Hashable, Sendable {
        case base64
        case deferredToData
    }

    public let keyEncodingStrategy: KeyEncodingStrategy

    public let keyDecodingStrategy: KeyDecodingStrategy

    public let dateEncodingStrategy: DateEncodingStrategy

    public let dateDecodingStrategy: DateDecodingStrategy

    public let dataEncodingStrategy: DataEncodingStrategy

    public let dataDecodingStrategy: DataDecodingStrategy

    /// Sorts object keys while encoding so two calls that encode equal
    /// values produce byte-identical JSON.
    ///
    /// This is a canonicalization aid for stable storage and comparison, not
    /// a schema guarantee: it only orders keys that `Value`'s `Encodable`
    /// implementation already writes. Defaults to `true`.
    public let sortsKeys: Bool

    public init(
        keyEncodingStrategy: KeyEncodingStrategy = .useDefaultKeys,
        keyDecodingStrategy: KeyDecodingStrategy = .useDefaultKeys,
        dateEncodingStrategy: DateEncodingStrategy = .deferredToDate,
        dateDecodingStrategy: DateDecodingStrategy = .deferredToDate,
        dataEncodingStrategy: DataEncodingStrategy = .base64,
        dataDecodingStrategy: DataDecodingStrategy = .base64,
        sortsKeys: Bool = true
    ) {
        self.keyEncodingStrategy = keyEncodingStrategy
        self.keyDecodingStrategy = keyDecodingStrategy
        self.dateEncodingStrategy = dateEncodingStrategy
        self.dateDecodingStrategy = dateDecodingStrategy
        self.dataEncodingStrategy = dataEncodingStrategy
        self.dataDecodingStrategy = dataDecodingStrategy
        self.sortsKeys = sortsKeys
    }

    func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        switch keyEncodingStrategy {
        case .useDefaultKeys:
            encoder.keyEncodingStrategy = .useDefaultKeys
        case .convertToSnakeCase:
            encoder.keyEncodingStrategy = .convertToSnakeCase
        }
        switch dateEncodingStrategy {
        case .deferredToDate:
            encoder.dateEncodingStrategy = .deferredToDate
        case .secondsSince1970:
            encoder.dateEncodingStrategy = .secondsSince1970
        case .millisecondsSince1970:
            encoder.dateEncodingStrategy = .millisecondsSince1970
        case .iso8601:
            encoder.dateEncodingStrategy = .iso8601
        }
        switch dataEncodingStrategy {
        case .base64:
            encoder.dataEncodingStrategy = .base64
        case .deferredToData:
            encoder.dataEncodingStrategy = .deferredToData
        }
        if sortsKeys {
            encoder.outputFormatting.insert(.sortedKeys)
        }
        return encoder
    }

    func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        switch keyDecodingStrategy {
        case .useDefaultKeys:
            decoder.keyDecodingStrategy = .useDefaultKeys
        case .convertFromSnakeCase:
            decoder.keyDecodingStrategy = .convertFromSnakeCase
        }
        switch dateDecodingStrategy {
        case .deferredToDate:
            decoder.dateDecodingStrategy = .deferredToDate
        case .secondsSince1970:
            decoder.dateDecodingStrategy = .secondsSince1970
        case .millisecondsSince1970:
            decoder.dateDecodingStrategy = .millisecondsSince1970
        case .iso8601:
            decoder.dateDecodingStrategy = .iso8601
        }
        switch dataDecodingStrategy {
        case .base64:
            decoder.dataDecodingStrategy = .base64
        case .deferredToData:
            decoder.dataDecodingStrategy = .deferredToData
        }
        return decoder
    }
}


/// Structured failures raised while transcoding a JSON `Codable` value.
///
/// These are thrown from inside a codec's encode/decode closures. The
/// contextual codec boundary in `SwiftQLCore` (`XLValueCodec.encode(_:using:context:)`
/// and `.decode(_:using:context:)`) catches them and wraps them, together
/// with the active codec key and `XLValueCodingContext`, into
/// `XLValueCodecError.encodingFailed` or `.decodingFailed`. Conforming to
/// `CustomStringConvertible` keeps the underlying `EncodingError`/
/// `DecodingError` text inside that wrapped message instead of losing it to
/// the default `Error` description.
public enum XLJSONValueCodecError: Error, CustomStringConvertible, Sendable {

    /// `JSONEncoder` failed to encode the application value, or the
    /// `Codable` implementation itself threw while encoding.
    case encodingFailed(valueType: String, underlying: String)

    /// `JSONDecoder` failed to decode the application value, or the
    /// `Codable` implementation itself threw while decoding.
    case decodingFailed(valueType: String, underlying: String)

    public var description: String {
        switch self {
        case .encodingFailed(let valueType, let underlying):
            return "JSON encoding of \(valueType) failed: \(underlying)"
        case .decodingFailed(let valueType, let underlying):
            return "JSON decoding of \(valueType) failed: \(underlying)"
        }
    }
}


/// Factory for contextual SQLite JSON `Codable` codecs.
///
/// SwiftQL has no built-in JSON column type. SQLite itself stores JSON as
/// `TEXT` or `BLOB` bytes; SwiftQL does not validate JSON, drive SQLite's
/// `json1` functions, or create generated/indexed columns on the caller's
/// behalf. `XLJSONValueCodec` builds an `XLValueCodec` that converts an
/// application `Codable` value to and from one of those two storage
/// representations using a snapshotted ``XLJSONCodecConfiguration``. Register
/// the result with `XLValueCodecRegistry.registering(_:)` like any other
/// contextual codec; optionality composes the same way it does for every
/// other codec, through `encodeOptional`/`decodeOptional` on the resolved
/// codec or coding configuration, never inside these closures.
///
/// This factory is deliberately SQLite-specific. PostgreSQL's native `JSONB`
/// representation is different and out of scope here (tracked separately as
/// issue #137). The private `Value <-> Data` transcoding used by both
/// `text(key:valueTypeIdentifier:configuration:)` and
/// `blob(key:valueTypeIdentifier:configuration:)` below is isolated from
/// `XLSQLiteValue`/`XLSQLiteStorageClass`, so a future PostgreSQL dialect
/// could reuse the same `Codable` transcoding behind a JSONB-native lowering
/// without changing this SQLite mapping.
public enum XLJSONValueCodec {

    /// Creates a codec that stores `Value` as SQLite `TEXT` containing UTF-8 JSON.
    ///
    /// - Parameters:
    ///   - key: The stable name and version of the persisted representation.
    ///     Treat a change to `key.id`, `key.version`, `valueTypeIdentifier`,
    ///     or the chosen storage (`.text` here, `.blob` below) as a data
    ///     migration: these are the stable components schema and query
    ///     fingerprints use.
    ///   - valueTypeIdentifier: The stable identity of the Swift value's
    ///     persisted meaning.
    ///   - configuration: The immutable `JSONEncoder`/`JSONDecoder` strategy
    ///     snapshot used for every encode and decode made through this codec.
    public static func text<Value: Codable>(
        key: XLValueCodecKey,
        valueTypeIdentifier: XLValueTypeIdentifier,
        configuration: XLJSONCodecConfiguration = XLJSONCodecConfiguration()
    ) -> XLValueCodec<Value, XLSQLiteDialect> {
        XLValueCodec(
            key: key,
            valueTypeIdentifier: valueTypeIdentifier,
            dialectIdentifier: XLSQLiteDialect.identity,
            storageIdentifier: XLValueStorageIdentifier(
                rawValue: XLSQLiteStorageClass.text.rawValue
            ),
            encode: { value, _, _ in
                let data = try _XLJSONTranscoder.encode(value, using: configuration)
                // `JSONEncoder` always produces UTF-8 bytes, so this
                // conversion cannot fail; `String(decoding:as:)` reflects
                // that instead of introducing an unreachable throw.
                return .text(String(decoding: data, as: UTF8.self))
            },
            decode: { dialectValue, _, _ in
                // `XLValueCodec.decode` validates the incoming storage class
                // against `identity.storageIdentifier` before this closure
                // runs, so `dialectValue` is always `.text` here.
                guard case .text(let text) = dialectValue else {
                    preconditionFailure(
                        "XLValueCodec validated TEXT storage before invoking this closure."
                    )
                }
                return try _XLJSONTranscoder.decode(
                    from: Data(text.utf8),
                    using: configuration
                )
            }
        )
    }

    /// Creates a codec that stores `Value` as SQLite `BLOB` JSON bytes.
    ///
    /// - Parameters:
    ///   - key: The stable name and version of the persisted representation.
    ///     Treat a change to `key.id`, `key.version`, `valueTypeIdentifier`,
    ///     or the chosen storage (`.blob` here, `.text` above) as a data
    ///     migration: these are the stable components schema and query
    ///     fingerprints use.
    ///   - valueTypeIdentifier: The stable identity of the Swift value's
    ///     persisted meaning.
    ///   - configuration: The immutable `JSONEncoder`/`JSONDecoder` strategy
    ///     snapshot used for every encode and decode made through this codec.
    public static func blob<Value: Codable>(
        key: XLValueCodecKey,
        valueTypeIdentifier: XLValueTypeIdentifier,
        configuration: XLJSONCodecConfiguration = XLJSONCodecConfiguration()
    ) -> XLValueCodec<Value, XLSQLiteDialect> {
        XLValueCodec(
            key: key,
            valueTypeIdentifier: valueTypeIdentifier,
            dialectIdentifier: XLSQLiteDialect.identity,
            storageIdentifier: XLValueStorageIdentifier(
                rawValue: XLSQLiteStorageClass.blob.rawValue
            ),
            encode: { value, _, _ in
                .blob(try _XLJSONTranscoder.encode(value, using: configuration))
            },
            decode: { dialectValue, _, _ in
                // `XLValueCodec.decode` validates the incoming storage class
                // against `identity.storageIdentifier` before this closure
                // runs, so `dialectValue` is always `.blob` here.
                guard case .blob(let data) = dialectValue else {
                    preconditionFailure(
                        "XLValueCodec validated BLOB storage before invoking this closure."
                    )
                }
                return try _XLJSONTranscoder.decode(
                    from: data,
                    using: configuration
                )
            }
        )
    }
}


/// Dialect-agnostic `Codable` <-> `Data` transcoding shared by the SQLite
/// `text` and `blob` factories above.
///
/// Keeping this half free of `XLSQLiteValue`/`XLSQLiteStorageClass` is what
/// lets a future dialect-native JSONB mapping reuse it without duplicating
/// `JSONEncoder`/`JSONDecoder` error handling.
private enum _XLJSONTranscoder {

    static func encode<Value: Encodable>(
        _ value: Value,
        using configuration: XLJSONCodecConfiguration
    ) throws -> Data {
        do {
            return try configuration.makeEncoder().encode(value)
        }
        catch {
            // Catches `EncodingError` from `JSONEncoder` itself as well as
            // any other error a custom `encode(to:)` implementation throws,
            // so every failure gets the same "JSON encoding of ... failed"
            // wrapping instead of only the `EncodingError` case.
            throw XLJSONValueCodecError.encodingFailed(
                valueType: String(reflecting: Value.self),
                underlying: String(describing: error)
            )
        }
    }

    static func decode<Value: Decodable>(
        from data: Data,
        using configuration: XLJSONCodecConfiguration
    ) throws -> Value {
        do {
            return try configuration.makeDecoder().decode(Value.self, from: data)
        }
        catch {
            // Catches `DecodingError` from `JSONDecoder` itself as well as
            // any other error a custom `init(from:)` implementation throws,
            // so every failure gets the same "JSON decoding of ... failed"
            // wrapping instead of only the `DecodingError` case.
            throw XLJSONValueCodecError.decodingFailed(
                valueType: String(reflecting: Value.self),
                underlying: String(describing: error)
            )
        }
    }
}
