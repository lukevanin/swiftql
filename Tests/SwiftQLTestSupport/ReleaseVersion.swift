//
//  ReleaseVersion.swift
//  SwiftQLTestSupport
//
//  The newest released version, read from CHANGELOG.md (issue #672).
//

import Foundation


///
/// The newest version `CHANGELOG.md` records as released: the version of the
/// first `## [X.Y.Z] - YYYY-MM-DD` heading.
///
/// Documentation tests compare the published-version claims against this
/// instead of pinning a literal version. A release then dates its changelog
/// heading and bumps the documents in the same change, and no test file moves.
/// An `Unreleased` heading above it is skipped, so a milestone branch that is
/// still collecting changes reads the last release, which is what its
/// documents still claim.
///
/// That comparison only proves the documents agree with the changelog. What
/// ties the claims to the tag being published is
/// `scripts/ci/check-release-version-claims.sh`, which the release workflow
/// runs on the exact tag commit.
///
/// - Throws: ``ReleaseVersionError/noDatedHeading(path:)`` when no dated
///   heading exists, so a test fails loudly instead of comparing against
///   nothing.
///
public func swiftQLLatestReleasedVersion(
    from filePath: StaticString = #filePath
) throws -> String {
    let changelog = try swiftQLRepositoryRootURL(from: filePath)
        .appendingPathComponent("CHANGELOG.md")
    let contents = try String(contentsOf: changelog, encoding: .utf8)
    let heading = try NSRegularExpression(
        pattern: #"^## \[([0-9]+\.[0-9]+\.[0-9]+)\] - [0-9]{4}-[0-9]{2}-[0-9]{2}$"#
    )
    for line in contents.components(separatedBy: .newlines) {
        let range = NSRange(line.startIndex ..< line.endIndex, in: line)
        guard
            let match = heading.firstMatch(in: line, range: range),
            let version = Range(match.range(at: 1), in: line)
        else {
            continue
        }
        return String(line[version])
    }
    throw ReleaseVersionError.noDatedHeading(path: changelog.path)
}


public enum ReleaseVersionError: Error, CustomStringConvertible {

    case noDatedHeading(path: String)

    public var description: String {
        switch self {
        case .noDatedHeading(let path):
            return "\(path) has no dated `## [X.Y.Z] - YYYY-MM-DD` heading; "
                + "the latest released version could not be determined."
        }
    }
}
