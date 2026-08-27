//
//  SQLStaticQueryDescriptor+Encoding.swift
//  SwiftQL
//
//  Bridging from a rendered `XLEncoding` to the database-independent static
//  descriptor types, which live in SwiftQLCore.
//
//  Renamed from `SQLStaticQueryDescriptor.swift` (issue #555): the old name
//  promised the descriptor types themselves, and this file holds neither --
//  only the two extensions that build one.
//

import Foundation


extension XLStaticStatementDefinition {

    /// Creates a database-independent static statement from one validated SQL
    /// rendering.
    ///
    /// The SwiftQL expression graph is deliberately discarded here. Static
    /// descriptors retain only deterministic SQL, dialect requirements,
    /// referenced entities, and immutable parameter metadata.
    ///
    /// `encoding.customFunctions` is discarded with the graph: a registration
    /// is a live closure, not deterministic metadata, so it cannot survive into
    /// a database-independent descriptor. A statement that calls a custom
    /// function therefore has to have it registered upfront with
    /// `GRDBDatabaseBuilder.addFunction(_:)` to be executed as a static
    /// descriptor -- implicit registration covers only the request and
    /// encodable-invocation paths, which still hold the encoding.
    public init(validating encoding: XLEncoding) throws {
        if let valueEncodingError = encoding.valueEncodingError {
            throw valueEncodingError
        }
        if let parameterLayoutError = encoding.parameterLayoutError {
            throw parameterLayoutError
        }
        self.init(
            sql: encoding.sql,
            dialectRequirement: encoding.dialectRequirement,
            entities: encoding.entities,
            parameterLayout: encoding.parameterLayout
        )
    }
}


extension XLContextualBindingReference {

    /// Describes this contextual parameter in a static query after rendering
    /// has assigned its deterministic logical index.
    public func staticQueryParameter(
        identity: XLQuerySlotIdentity,
        in layout: XLParameterLayout
    ) throws -> XLStaticQueryParameterMetadata {
        let parameter = try preparedParameter(in: layout)
        return XLStaticQueryParameterMetadata(
            identity: identity,
            slot: parameter.slot,
            storageIdentifier: parameter.codecIdentity.storageIdentifier
        )
    }
}
