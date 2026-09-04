import Foundation
import SwiftQLSQLiteBuildValidationManifest


public struct SQLiteBuildValidationValidatorPlaceholderOccurrence:
    Codable,
    Equatable,
    Sendable
{
    public let spelling: String
    public let byteOffset: Int
    public let physicalIndex: Int

    public init(spelling: String, byteOffset: Int, physicalIndex: Int) {
        self.spelling = spelling
        self.byteOffset = byteOffset
        self.physicalIndex = physicalIndex
    }

    private enum CodingKeys: String, CodingKey {
        case spelling
        case byteOffset = "byte_offset"
        case physicalIndex = "physical_index"
    }
}


public struct SQLiteBuildValidationUnsupportedPlaceholder:
    Codable,
    Equatable,
    Sendable
{
    public let spelling: String
    public let byteOffset: Int
    public let reason: String

    public init(spelling: String, byteOffset: Int, reason: String) {
        self.spelling = spelling
        self.byteOffset = byteOffset
        self.reason = reason
    }

    private enum CodingKeys: String, CodingKey {
        case spelling
        case byteOffset = "byte_offset"
        case reason
    }
}


/// Quote/comment-aware evidence for SwiftQL's supported placeholder spellings.
///
/// This is deliberately smaller than SQLite's tokenizer. It recognizes only
/// the two forms emitted by `XLSQLiteDialect`: `:name` and one-based `?N`.
/// Anonymous `?`, `@name`, and `$name` remain explicit unsupported evidence.
public struct SQLiteBuildValidationValidatorPlaceholderAnalysis:
    Codable,
    Equatable,
    Sendable
{
    public let physicalParameterCount: Int
    public let parameters: [SQLitePreparedParameter]
    public let occurrences: [SQLiteBuildValidationValidatorPlaceholderOccurrence]
    public let unsupported: [SQLiteBuildValidationUnsupportedPlaceholder]
    public let collisions: [String]

    public init(
        physicalParameterCount: Int,
        parameters: [SQLitePreparedParameter],
        occurrences: [SQLiteBuildValidationValidatorPlaceholderOccurrence],
        unsupported: [SQLiteBuildValidationUnsupportedPlaceholder],
        collisions: [String]
    ) {
        self.physicalParameterCount = physicalParameterCount
        self.parameters = parameters
        self.occurrences = occurrences
        self.unsupported = unsupported
        self.collisions = collisions.sorted()
    }

    private enum CodingKeys: String, CodingKey {
        case physicalParameterCount = "physical_parameter_count"
        case parameters
        case occurrences
        case unsupported
        case collisions
    }
}


/// The validator's view of a query's placeholders: everything the manifest
/// scanner sees, plus the spellings SwiftQL never emits and the slot collisions
/// that make a declared parameter ambiguous.
///
/// The scan itself is ``SQLiteBuildValidationPlaceholderLexer``, shared with the
/// manifest (#566). The two must agree on which slot each placeholder binds --
/// the manifest cross-checks its declared parameters against its scan when a
/// manifest is built, and this scan is cross-checked against the same
/// parameters and against SQLite's real parameter table when the manifest is
/// validated. Two implementations that drift produce a manifest that builds and
/// then fails validation for no visible reason.
public enum SQLiteBuildValidationValidatorPlaceholderScanner {

    public static func scan(
        _ sql: String
    ) -> SQLiteBuildValidationValidatorPlaceholderAnalysis {
        var physicalNameByIndex: [Int: String] = [:]
        var occurrences: [SQLiteBuildValidationValidatorPlaceholderOccurrence] = []
        var unsupported: [SQLiteBuildValidationUnsupportedPlaceholder] = []
        var collisions: [String] = []

        let stream = SQLiteBuildValidationPlaceholderLexer.scan(sql)
        for token in stream.tokens {
            switch token.kind {
            case .indexed, .named:
                guard let physicalIndex = token.physicalIndex else {
                    continue
                }
                register(
                    spelling: token.spelling,
                    physicalIndex: physicalIndex,
                    byteOffset: token.byteOffset,
                    physicalNameByIndex: &physicalNameByIndex,
                    occurrences: &occurrences,
                    collisions: &collisions
                )
            case .anonymous:
                unsupported.append(SQLiteBuildValidationUnsupportedPlaceholder(
                    spelling: token.spelling,
                    byteOffset: token.byteOffset,
                    reason: "Anonymous ? placeholders are not emitted by SwiftQL static descriptors."
                ))
            case .invalidIndex:
                unsupported.append(SQLiteBuildValidationUnsupportedPlaceholder(
                    spelling: token.spelling,
                    byteOffset: token.byteOffset,
                    reason: "Indexed placeholders require a positive one-based SQLite index."
                ))
            case .foreignSigil:
                unsupported.append(SQLiteBuildValidationUnsupportedPlaceholder(
                    spelling: token.spelling,
                    byteOffset: token.byteOffset,
                    reason: "Only SwiftQL-emitted :name and ?N placeholders are supported."
                ))
            }
        }

        // SQLite sizes a statement's parameter table by the largest index used,
        // so an unused slot is a real gap in it rather than an absence. The
        // table is reported with those gaps present and unnamed.
        let parameters: [SQLitePreparedParameter]
        if stream.largestPhysicalIndex == 0 {
            parameters = []
        } else {
            parameters = (1...stream.largestPhysicalIndex).map {
                SQLitePreparedParameter(
                    physicalIndex: $0,
                    name: physicalNameByIndex[$0]
                )
            }
        }
        return SQLiteBuildValidationValidatorPlaceholderAnalysis(
            physicalParameterCount: stream.largestPhysicalIndex,
            parameters: parameters,
            occurrences: occurrences,
            unsupported: unsupported,
            collisions: collisions
        )
    }
}


private extension SQLiteBuildValidationValidatorPlaceholderScanner {

    /// Records one occurrence, and reports a collision when a slot is named by
    /// two different spellings -- `:first` and `?1` both binding slot 1, say.
    /// The manifest can declare only one key for a slot, so which of the two it
    /// means is unanswerable.
    static func register(
        spelling: String,
        physicalIndex: Int,
        byteOffset: Int,
        physicalNameByIndex: inout [Int: String],
        occurrences: inout [SQLiteBuildValidationValidatorPlaceholderOccurrence],
        collisions: inout [String]
    ) {
        if let existing = physicalNameByIndex[physicalIndex],
           existing != spelling {
            collisions.append(
                "Physical parameter \(physicalIndex) is named by both '\(existing)' and '\(spelling)'."
            )
        } else {
            physicalNameByIndex[physicalIndex] = spelling
        }
        occurrences.append(SQLiteBuildValidationValidatorPlaceholderOccurrence(
            spelling: spelling,
            byteOffset: byteOffset,
            physicalIndex: physicalIndex
        ))
    }
}
