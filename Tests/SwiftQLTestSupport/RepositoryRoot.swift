//
//  RepositoryRoot.swift
//  SwiftQLTestSupport
//
//  Finding the repository root from a source file's own path (issue #557).
//

import Foundation


///
/// The repository root, found by walking up from `filePath` until a directory
/// containing `Package.swift` is reached.
///
/// Prefixed rather than named `repositoryRootURL` because several test types
/// already have a method of that name; a bare free function would be shadowed
/// by them and the call would silently keep meaning the old ladder.
///
/// Tests that read repository files used to climb a fixed number of
/// `deletingLastPathComponent()` calls from `#filePath`. That is a silent
/// dependency on how deep the calling file happens to sit: moving a test one
/// directory makes the ladder land somewhere else entirely, and what the test
/// then reads is whatever is at that path -- or nothing, reported as a missing
/// file rather than as a wrong root.
///
/// - Throws: ``RepositoryRootError/notFound(startingAt:)`` when no ancestor has
///   a `Package.swift`, naming where the walk started. Failing loudly matters:
///   the alternative is a test asserting against a file it did not find.
///
public func swiftQLRepositoryRootURL(
    from filePath: StaticString = #filePath
) throws -> URL {
    let start = URL(fileURLWithPath: "\(filePath)")
    var directory = start.deletingLastPathComponent()
    while true {
        let manifest = directory.appendingPathComponent("Package.swift")
        if FileManager.default.fileExists(atPath: manifest.path) {
            return directory
        }
        let parent = directory.deletingLastPathComponent()
        guard parent.path != directory.path else {
            throw RepositoryRootError.notFound(startingAt: start.path)
        }
        directory = parent
    }
}


public enum RepositoryRootError: Error, CustomStringConvertible {

    case notFound(startingAt: String)

    public var description: String {
        switch self {
        case .notFound(let path):
            return "No Package.swift in any directory above \(path); "
                + "the repository root could not be determined."
        }
    }
}
