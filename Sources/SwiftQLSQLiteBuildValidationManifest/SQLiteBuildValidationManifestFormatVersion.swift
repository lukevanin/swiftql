import Foundation


/// The version of SwiftQL's build-validation manifest sidecar schema.
///
/// Version 1 is frozen. Changing field inclusion, ordering, canonical JSON
/// normalization, or the identifiers used for #190/#191/#254 reference
/// resolution requires a new format version. Decoding an unrecognized version
/// fails closed rather than guessing at compatibility.
public struct SQLiteBuildValidationManifestFormatVersion:
    RawRepresentable,
    Hashable,
    Sendable,
    CustomStringConvertible,
    Codable
{

    public static let v1 = Self(rawValue: 1)

    public static let current = Self.v1

    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public var description: String {
        String(rawValue)
    }
}
