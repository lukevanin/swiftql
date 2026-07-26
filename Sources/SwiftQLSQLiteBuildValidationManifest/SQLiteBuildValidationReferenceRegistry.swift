import Foundation


/// External #190/#191/#254 registry membership.
///
/// The manifest model does not depend on the (test-only) targets that own the
/// canonical #190 inventory, #191 combinatorial cases, or #254 Northwind
/// fixture, so it cannot resolve references itself. Callers that have loaded
/// those canonical sources inject a conformance here instead of the manifest
/// minting a parallel copy of any of the three ID spaces.
public protocol SQLiteBuildValidationReferenceRegistry: Sendable {
    func resolvesConformanceFeatureID(_ id: String) -> Bool
    func resolvesConformanceCaseID(_ id: String) -> Bool
    func resolvesNorthwindAnchorCaseID(_ id: String) -> Bool
}


/// A registry backed by explicit in-memory ID sets.
///
/// Useful for tests, and for callers that have already loaded the canonical
/// #190/#191/#254 sources and want a value-type conformance instead of
/// implementing the protocol themselves.
public struct SQLiteBuildValidationStaticReferenceRegistry:
    SQLiteBuildValidationReferenceRegistry
{

    public let conformanceFeatureIDs: Set<String>
    public let conformanceCaseIDs: Set<String>
    public let northwindAnchorCaseIDs: Set<String>

    public init(
        conformanceFeatureIDs: Set<String>,
        conformanceCaseIDs: Set<String>,
        northwindAnchorCaseIDs: Set<String>
    ) {
        self.conformanceFeatureIDs = conformanceFeatureIDs
        self.conformanceCaseIDs = conformanceCaseIDs
        self.northwindAnchorCaseIDs = northwindAnchorCaseIDs
    }

    public func resolvesConformanceFeatureID(_ id: String) -> Bool {
        conformanceFeatureIDs.contains(id)
    }

    public func resolvesConformanceCaseID(_ id: String) -> Bool {
        conformanceCaseIDs.contains(id)
    }

    public func resolvesNorthwindAnchorCaseID(_ id: String) -> Bool {
        northwindAnchorCaseIDs.contains(id)
    }
}
