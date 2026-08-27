import Foundation


/// One SQL-text occurrence of a supported SwiftQL placeholder spelling.
struct SQLiteBuildValidationManifestPlaceholderOccurrence: Equatable {
    let spelling: String
    let physicalIndex: Int
}


/// Quote/comment-aware evidence for SwiftQL's supported placeholder spellings.
///
/// This is deliberately smaller than SQLite's tokenizer. It recognizes only
/// the two forms emitted by `XLSQLiteDialect`: `:name` and one-based `?N`.
/// The physical index of a named token is its first-encounter position among
/// all placeholders in the rendered SQL; repeated occurrences of the same
/// name share that index, matching SQLite's own binding semantics.
struct SQLiteBuildValidationManifestPlaceholderAnalysis: Equatable {
    let occurrences: [SQLiteBuildValidationManifestPlaceholderOccurrence]
}


/// The manifest's view of a query's placeholders: only the spellings SwiftQL
/// emits, and only the fact that they bind a given slot.
///
/// The scan itself is ``SQLiteBuildValidationPlaceholderLexer``, shared with the
/// validator (#566). What is kept from it differs -- the manifest has no
/// diagnostics to raise and nothing to say about a placeholder SwiftQL would
/// never have written -- but the slot assignment has to be identical on both
/// sides, so there is one implementation of it.
enum SQLiteBuildValidationManifestPlaceholderScanner {

    static func scan(
        _ sql: String
    ) -> SQLiteBuildValidationManifestPlaceholderAnalysis {
        let stream = SQLiteBuildValidationPlaceholderLexer.scan(sql)
        let occurrences = stream.tokens.compactMap { token
            -> SQLiteBuildValidationManifestPlaceholderOccurrence? in
            guard
                token.kind == .indexed || token.kind == .named,
                let physicalIndex = token.physicalIndex
            else {
                return nil
            }
            return SQLiteBuildValidationManifestPlaceholderOccurrence(
                spelling: token.spelling,
                physicalIndex: physicalIndex
            )
        }
        return SQLiteBuildValidationManifestPlaceholderAnalysis(
            occurrences: occurrences
        )
    }
}
