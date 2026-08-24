//
//  GRDBCodecResolutionFailure.swift
//  SwiftQL
//
//  Why a declared codec cannot be used against a database, separated from how
//  that is reported (issue #561).
//
//  The same three-step resolution -- right dialect, registered at all, same
//  identity -- was written out in three places, each raising its own kind of
//  error. Three copies of a check is three chances for one to gain a step the
//  others do not, and the whole point of the check is that a codec resolved by
//  another database is only usable when it is provably the same codec.
//

import Foundation


///
/// Why a slot's declared codec cannot be used against a given database.
///
enum GRDBCodecResolutionFailure {

    /// The codec belongs to a different SQL dialect.
    case dialectMismatch(XLValueCodecIdentity)

    /// No codec is registered for the key at all.
    case unavailable(XLValueCodecIdentity)

    /// A codec is registered for the key, but it is not the same one the slot
    /// was rendered against -- same name, different meaning.
    case identityMismatch(
        expected: XLValueCodecIdentity,
        actual: XLValueCodecIdentity
    )

    /// Reported against a bound parameter, where the caller's contract is
    /// `XLInvocationBindingError`.
    func bindingError(
        slot: XLParameterSlot,
        expectedDialectIdentifier: XLDialectIdentifier
    ) -> XLInvocationBindingError {
        switch self {
        case .dialectMismatch(let codecIdentity):
            return .preparedCodecDialectMismatch(
                slot: slot,
                codecIdentity: codecIdentity,
                expectedDialectIdentifier: expectedDialectIdentifier
            )
        case .unavailable(let codecIdentity):
            return .preparedCodecUnavailable(
                slot: slot,
                codecIdentity: codecIdentity
            )
        case .identityMismatch(let expected, let actual):
            return .preparedCodecIdentityMismatch(
                slot: slot,
                expected: expected,
                actual: actual
            )
        }
    }

    /// Reported against a static descriptor's result slot, where the caller's
    /// contract is `GRDBStaticQueryError` and the descriptor is named.
    func staticQueryError(
        identity: XLQueryIdentity,
        slot: XLStaticQueryResultSlot,
        expectedDialectIdentifier: XLDialectIdentifier
    ) -> GRDBStaticQueryError {
        switch self {
        case .dialectMismatch(let codecIdentity):
            return .resultCodecDialectMismatch(
                identity: identity,
                slot: slot,
                codecIdentity: codecIdentity,
                expectedDialectIdentifier: expectedDialectIdentifier
            )
        case .unavailable(let codecIdentity):
            return .resultCodecUnavailable(
                identity: identity,
                slot: slot,
                codecIdentity: codecIdentity
            )
        case .identityMismatch(let expected, let actual):
            return .resultCodecIdentityMismatch(
                identity: identity,
                slot: slot,
                expected: expected,
                actual: actual
            )
        }
    }
}
