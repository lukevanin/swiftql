import Foundation


extension XLStaticStatementDefinition {

    /// Creates a database-independent static statement from one validated SQL
    /// rendering.
    ///
    /// The SwiftQL expression graph is deliberately discarded here. Static
    /// descriptors retain only deterministic SQL, dialect requirements,
    /// referenced entities, and immutable parameter metadata.
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
