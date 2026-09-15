import Foundation


/// Deterministic, fail-closed failures constructing or validating a manifest.
public enum SQLiteBuildValidationManifestError:
    Error,
    Equatable,
    Sendable,
    CustomStringConvertible
{

    public enum ReferenceKind: String, Equatable, Sendable {
        case conformanceFeature = "#190 conformance feature"
        case conformanceCase = "#191 conformance case"
        case northwindAnchor = "#254 Northwind anchor"
    }

    case unsupportedFormatVersion(SQLiteBuildValidationManifestFormatVersion)
    case invalidManifest(String)
    /// A JSON object carried a key its type does not define, for example a
    /// misspelled optional key. `path` locates the key, such as
    /// `queries[0].parameters[1].key_nmae`.
    case unknownKey(path: String)
    case duplicateQueryID(String)
    case invalidQuery(String, String)
    case resultAliasCountMismatch(queryID: String, expected: Int, actual: Int)
    case unresolvedReference(queryID: String, kind: ReferenceKind, id: String)

    public var description: String {
        switch self {
        case .unsupportedFormatVersion(let version):
            return "Unsupported build-validation manifest format version \(version); this reader reads versions \(SQLiteBuildValidationManifestFormatVersion.supported.map(\.description).joined(separator: ", "))."
        case .invalidManifest(let reason):
            return "Invalid build-validation manifest: \(reason)."
        case .unknownKey(let path):
            return "Invalid build-validation manifest: unknown key '\(path)'."
        case .duplicateQueryID(let id):
            return "Build-validation query id '\(id)' is duplicated."
        case .invalidQuery(let id, let reason):
            return "Invalid build-validation query '\(id)': \(reason)."
        case .resultAliasCountMismatch(let queryID, let expected, let actual):
            return "Build-validation query '\(queryID)' supplied \(actual) result aliases for \(expected) result slots."
        case .unresolvedReference(let queryID, let kind, let id):
            return "Build-validation query '\(queryID)' references unknown \(kind.rawValue) '\(id)'."
        }
    }
}


/// Throws ``SQLiteBuildValidationManifestError/unknownKey(path:)`` when
/// `decoder`'s JSON object carries a key `Keys` does not define.
func sqliteBuildValidationManifestRejectUnknownKeys<Keys>(
    in decoder: any Decoder,
    allowedKeys: Keys.Type
) throws where Keys: CodingKey & CaseIterable {
    if let path = try sqliteBuildValidationUnknownKeyPath(
        in: decoder,
        allowedKeys: allowedKeys
    ) {
        throw SQLiteBuildValidationManifestError.unknownKey(path: path)
    }
}
