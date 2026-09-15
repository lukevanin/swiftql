import Foundation


/// The version of SwiftQL's build-validation manifest sidecar schema.
///
/// Each version is frozen once released. Changing field inclusion, a field's
/// required-ness, canonical JSON normalization, or the identifiers used for
/// #190/#191/#254 reference resolution requires a new integer version; there
/// is no additive "1.x" minor version, and a reader rejects any key a
/// manifest's types do not define. Decoding an unrecognized version fails
/// closed rather than guessing at compatibility.
///
/// - Version 1 requires fixture provenance
///   (`conformance_inventory_version`, `combinatorial_manifest_version`), at
///   least one query, and `value_type_name` on every slot.
/// - Version 2 makes the two provenance fields optional, allows an empty
///   `queries` list, and makes `value_type_name` optional, so a manifest
///   generated from an application's own declarations can be valid without
///   inventing fixture provenance. Every other check is unchanged.
///
/// A reader of the current version also reads every earlier version.
public struct SQLiteBuildValidationManifestFormatVersion:
    RawRepresentable,
    Hashable,
    Sendable,
    CustomStringConvertible,
    Codable
{

    public static let v1 = Self(rawValue: 1)

    public static let v2 = Self(rawValue: 2)

    /// The version new manifests are written in.
    public static let current = Self.v2

    /// Every version this reader decodes and validates.
    public static let supported: [Self] = [.v1, .v2]

    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public var isSupported: Bool {
        Self.supported.contains(self)
    }

    public var description: String {
        String(rawValue)
    }
}
