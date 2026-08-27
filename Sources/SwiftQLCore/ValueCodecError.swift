//
//  ValueCodecError.swift
//  SwiftQLCore
//
//  How codec selection and resolution fail, and what each failure says.
//
//  Split out of ValueCodec.swift (issue #559).
//

import Foundation


public enum XLQueryCodecSelectionError:
    Error,
    Equatable,
    Sendable,
    LocalizedError
{
    case missingCodecForStorage(
        valueType: String,
        dialect: XLDialectIdentifier,
        storage: XLValueStorageIdentifier,
        context: XLValueCodingContext
    )
    case ambiguousCodecForStorage(
        valueType: String,
        dialect: XLDialectIdentifier,
        storage: XLValueStorageIdentifier,
        candidates: [XLValueCodecKey],
        context: XLValueCodingContext
    )

    public var errorDescription: String? {
        switch self {
        case .missingCodecForStorage(
            let valueType,
            let dialect,
            let storage,
            let context
        ):
            return "No codec represents \(valueType) as \(storage) for \(dialect) at \(context)."
        case .ambiguousCodecForStorage(
            let valueType,
            let dialect,
            let storage,
            let candidates,
            let context
        ):
            return "Codecs \(candidates.map(\.description).joined(separator: ", ")) are ambiguous for \(valueType) as \(storage) for \(dialect) at \(context)."
        }
    }
}


/// Deterministic failures from codec registration, selection, and conversion.
public enum XLValueCodecError: Error, Equatable, Sendable, LocalizedError {
    case duplicateCodec(key: XLValueCodecKey, context: XLValueCodingContext)
    case unknownCodec(
        key: XLValueCodecKey,
        source: XLValueCodecSelectionSource,
        context: XLValueCodingContext
    )
    case duplicateDefault(
        valueTypeIdentifier: String,
        dialect: XLDialectIdentifier,
        keys: [XLValueCodecKey],
        context: XLValueCodingContext
    )
    case valueTypeMismatch(
        codec: XLValueCodecKey,
        expected: String,
        actual: String,
        context: XLValueCodingContext
    )
    case dialectMismatch(
        codec: XLValueCodecKey,
        expected: XLDialectIdentifier,
        actual: XLDialectIdentifier,
        context: XLValueCodingContext
    )
    case dialectTypeMismatch(
        codec: XLValueCodecKey,
        expected: String,
        actual: String,
        context: XLValueCodingContext
    )
    case storageMismatch(
        codec: XLValueCodecKey,
        expected: XLValueStorageIdentifier,
        actual: XLValueStorageIdentifier,
        context: XLValueCodingContext
    )
    case missingCodec(
        valueType: String,
        dialect: XLDialectIdentifier,
        context: XLValueCodingContext
    )
    case ambiguousCodec(
        valueType: String,
        dialect: XLDialectIdentifier,
        candidates: [XLValueCodecKey],
        context: XLValueCodingContext
    )
    case unexpectedNull(codec: XLValueCodecKey, context: XLValueCodingContext)
    case encodingFailed(
        codec: XLValueCodecKey,
        context: XLValueCodingContext,
        message: String
    )
    case decodingFailed(
        codec: XLValueCodecKey,
        context: XLValueCodingContext,
        message: String
    )

    public var errorDescription: String? {
        switch self {
        case .duplicateCodec(let key, let context):
            return "Codec \(key) is registered more than once at \(context)."
        case .unknownCodec(let key, let source, let context):
            return "The \(source.rawValue) codec \(key) is not registered at \(context)."
        case .duplicateDefault(let valueType, let dialect, let keys, let context):
            return "Multiple default codecs \(keys.map(\.description).joined(separator: ", ")) target \(valueType) for \(dialect) at \(context)."
        case .valueTypeMismatch(let codec, let expected, let actual, let context):
            return "Codec \(codec) expects \(expected), not \(actual), at \(context)."
        case .dialectMismatch(let codec, let expected, let actual, let context):
            return "Codec \(codec) expects dialect \(expected), not \(actual), at \(context)."
        case .dialectTypeMismatch(let codec, let expected, let actual, let context):
            return "Codec \(codec) expects dialect type \(expected), not \(actual), at \(context)."
        case .storageMismatch(let codec, let expected, let actual, let context):
            return "Codec \(codec) expects storage \(expected), not \(actual), at \(context)."
        case .missingCodec(let valueType, let dialect, let context):
            return "No codec is selected for \(valueType) and \(dialect) at \(context)."
        case .ambiguousCodec(let valueType, let dialect, let candidates, let context):
            return "Codecs \(candidates.map(\.description).joined(separator: ", ")) are ambiguous for \(valueType) and \(dialect) at \(context)."
        case .unexpectedNull(let codec, let context):
            return "Nonoptional codec \(codec) received or produced SQL NULL at \(context)."
        case .encodingFailed(let codec, let context, let message):
            return "Codec \(codec) could not encode at \(context): \(message)"
        case .decodingFailed(let codec, let context, let message):
            return "Codec \(codec) could not decode at \(context): \(message)"
        }
    }
}


/// Paired throwing conversion between one Swift type and one dialect value model.
///
/// `Value` intentionally has no `Sendable` requirement. The codec itself remains
/// `Sendable` because its conversion behavior is held in `@Sendable` closures.
