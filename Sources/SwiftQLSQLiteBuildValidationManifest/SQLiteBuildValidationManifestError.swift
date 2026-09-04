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
    case duplicateQueryID(String)
    case invalidQuery(String, String)
    case resultAliasCountMismatch(queryID: String, expected: Int, actual: Int)
    case unresolvedReference(queryID: String, kind: ReferenceKind, id: String)

    public var description: String {
        switch self {
        case .unsupportedFormatVersion(let version):
            return "Unsupported build-validation manifest format version \(version)."
        case .invalidManifest(let reason):
            return "Invalid build-validation manifest: \(reason)."
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
