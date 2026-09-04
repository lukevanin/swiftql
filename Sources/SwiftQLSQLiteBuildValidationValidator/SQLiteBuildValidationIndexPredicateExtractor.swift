import Foundation


/// One `alias.column <op> …` comparison found in a statement's `WHERE`
/// clause.
public struct SQLiteBuildValidationWhereComparison: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// `=` or `==`. SQLite can seed an index seek from it.
        case equality
        /// `<`, `<=`, `>`, `>=`. Narrows a seek once, and nothing after it in
        /// a composite index narrows anything further.
        case range
    }

    public let alias: String
    public let column: String
    public let kind: Kind

    public init(alias: String, column: String, kind: Kind) {
        self.alias = alias
        self.column = column
        self.kind = kind
    }
}


/// One join key: `alias.column` on one side of a `JOIN … ON` equality.
///
/// A join key is an equality constraint too — SQLite seeds a seek on it once
/// per outer row exactly as it would from a `WHERE` equality, it just
/// supplies the bound value at run time instead of from the statement text.
public struct SQLiteBuildValidationJoinKey: Equatable, Sendable {
    public let alias: String
    public let column: String

    public init(alias: String, column: String) {
        self.alias = alias
        self.column = column
    }
}


/// One `ORDER BY` term, with everything about it that decides whether an
/// index can satisfy the sort.
public struct SQLiteBuildValidationOrderByTerm: Equatable, Sendable {
    public enum Direction: String, Equatable, Sendable {
        case ascending = "asc"
        case descending = "desc"
    }

    public let alias: String
    public let column: String
    /// `nil` when the statement did not say, which SQLite reads as ascending
    /// and an index satisfies either way.
    public let direction: Direction?
    public let collation: String?

    public init(
        alias: String,
        column: String,
        direction: Direction?,
        collation: String?
    ) {
        self.alias = alias
        self.column = column
        self.direction = direction
        self.collation = collation
    }
}


/// Extracts the signal an index candidate is built from — equality and range
/// predicates, join keys, and `ORDER BY` terms — out of a statement's
/// rendered SQL.
///
/// Deliberately a narrow, pattern-based extractor rather than a SQL parser.
/// It recognises the two rendering styles this repository produces: the
/// quoted, parenthesised style SwiftQL renders (`("t0"."orderID" == 10248)`)
/// and the bare style hand-written Northwind anchors use (`o.OrderID = ?`).
///
/// Anything it cannot read confidently yields nothing rather than a partial
/// or guessed answer. A `WHERE` clause containing `OR` anywhere — a blunt
/// substring test, deliberately more conservative than asking whether that
/// `OR` actually changes precedence — yields no comparisons at all, because
/// a disjunction does not constrain an index seek the way a conjunction does.
public enum SQLiteBuildValidationIndexPredicateExtractor {

    public static func whereComparisons(
        for alias: String,
        in sql: String
    ) -> [SQLiteBuildValidationWhereComparison] {
        let sql = normalizedWhitespace(sql)
        guard let clause = clause(
            in: sql,
            after: "WHERE",
            stoppingAt: ["GROUP BY", "ORDER BY", "LIMIT", "WINDOW"]
        ) else {
            return []
        }
        guard !clause.contains(" OR ") else {
            return []
        }
        return splitTopLevel(unwrapOuterParens(clause), on: " AND ")
            .map(unwrapOuterParens)
            .compactMap { comparison($0, alias: alias) }
    }

    public static func joinKeys(
        for alias: String,
        in sql: String
    ) -> [SQLiteBuildValidationJoinKey] {
        let sql = normalizedWhitespace(sql)
        return joinConditions(in: sql).flatMap { left, right -> [SQLiteBuildValidationJoinKey] in
            var keys: [SQLiteBuildValidationJoinKey] = []
            if left.alias == alias {
                keys.append(SQLiteBuildValidationJoinKey(alias: alias, column: left.identifier))
            }
            if right.alias == alias {
                keys.append(SQLiteBuildValidationJoinKey(alias: alias, column: right.identifier))
            }
            return keys
        }
    }

    /// Every `ORDER BY` term, in statement order, until the first one this
    /// extractor cannot read as a plain qualified column.
    ///
    /// Ordering is positional: an index satisfies a sort only if its columns
    /// match the `ORDER BY` terms from the first one onwards. So a term that
    /// cannot be read — an expression, a bare unqualified column, a term
    /// belonging to a different table — ends the list rather than being
    /// skipped over. Skipping it would produce a column list that claims to
    /// satisfy an ordering it does not.
    public static func orderByTerms(
        for alias: String,
        in sql: String
    ) -> (terms: [SQLiteBuildValidationOrderByTerm], isComplete: Bool) {
        let sql = normalizedWhitespace(sql)
        guard let clause = clause(
            in: sql,
            after: "ORDER BY",
            stoppingAt: ["LIMIT", "WINDOW"]
        ) else {
            return ([], true)
        }
        var terms: [SQLiteBuildValidationOrderByTerm] = []
        let rendered = splitTopLevel(clause, on: ",")
        for text in rendered {
            guard let term = orderByTerm(text, alias: alias) else {
                return (terms, false)
            }
            terms.append(term)
        }
        return (terms, true)
    }

    // MARK: - Term parsing

    private static func orderByTerm(
        _ text: String,
        alias: String
    ) -> SQLiteBuildValidationOrderByTerm? {
        // A term's leading parenthesis, when SwiftQL renders one, wraps the
        // expression but not the trailing COLLATE/ASC/DESC.
        let trimmed = text.trimmingCharacters(in: .whitespaces)
            .drop(while: { $0 == "(" })
        var scanner = SQLiteBuildValidationIdentifierScanner(String(trimmed))
        guard let pair = scanner.nextIdentifierPair(), pair.alias == alias else {
            return nil
        }
        var remainder = scanner.remainder()
            .trimmingCharacters(in: CharacterSet(charactersIn: " )"))

        var collation: String?
        if let collateRange = remainder.range(of: "COLLATE ") {
            var collateScanner = SQLiteBuildValidationIdentifierScanner(
                String(remainder[collateRange.upperBound...])
            )
            guard let name = collateScanner.nextIdentifier() else {
                return nil
            }
            collation = name
            remainder = (
                String(remainder[remainder.startIndex..<collateRange.lowerBound])
                    + collateScanner.remainder()
            ).trimmingCharacters(in: CharacterSet(charactersIn: " )"))
        }

        let direction: SQLiteBuildValidationOrderByTerm.Direction?
        switch remainder.uppercased() {
        case "":
            direction = nil
        case "ASC":
            direction = .ascending
        case "DESC":
            direction = .descending
        default:
            // Trailing text this extractor does not recognise — NULLS FIRST,
            // an expression suffix, anything else. Reading it as a plain
            // column would claim an ordering the index may not provide.
            return nil
        }
        return SQLiteBuildValidationOrderByTerm(
            alias: pair.alias,
            column: pair.identifier,
            direction: direction,
            collation: collation
        )
    }

    private static let comparisonOperators = ["==", "=", ">=", "<=", ">", "<"]

    private static func comparison(
        _ conjunct: String,
        alias: String
    ) -> SQLiteBuildValidationWhereComparison? {
        var scanner = SQLiteBuildValidationIdentifierScanner(conjunct)
        guard let pair = scanner.nextIdentifierPair(), pair.alias == alias else {
            return nil
        }
        scanner.skipWhitespace()
        for operatorToken in comparisonOperators where scanner.peekMatches(operatorToken) {
            let kind: SQLiteBuildValidationWhereComparison.Kind =
                (operatorToken == "==" || operatorToken == "=") ? .equality : .range
            return SQLiteBuildValidationWhereComparison(
                alias: pair.alias,
                column: pair.identifier,
                kind: kind
            )
        }
        return nil
    }

    // MARK: - Clause scanning

    private static let stopKeywordsAfterOn = [
        "JOIN", "WHERE", "GROUP BY", "ORDER BY", "LIMIT",
    ]

    private static func clause(
        in sql: String,
        after keyword: String,
        stoppingAt stopKeywords: [String]
    ) -> String? {
        guard let keywordRange = sql.range(of: " \(keyword) ") else {
            return nil
        }
        var clause = String(sql[keywordRange.upperBound...])
        for stopKeyword in stopKeywords {
            if let stopRange = clause.range(of: " \(stopKeyword) ") {
                clause = String(clause[clause.startIndex..<stopRange.lowerBound])
            }
        }
        return clause.trimmingCharacters(in: .whitespaces)
    }

    private static func joinConditions(
        in sql: String
    ) -> [(SQLiteBuildValidationIdentifierScanner.Pair, SQLiteBuildValidationIdentifierScanner.Pair)] {
        var results: [(
            SQLiteBuildValidationIdentifierScanner.Pair,
            SQLiteBuildValidationIdentifierScanner.Pair
        )] = []
        var searchStart = sql.startIndex
        while let onRange = sql.range(of: " ON ", range: searchStart..<sql.endIndex) {
            var remainder = String(sql[onRange.upperBound...])
            var trimmedLeadingParen = false
            if remainder.hasPrefix("(") {
                remainder = String(remainder.dropFirst())
                trimmedLeadingParen = true
            }
            var condition = remainder
            for stopKeyword in stopKeywordsAfterOn {
                if let stopRange = condition.range(of: " \(stopKeyword)") {
                    condition = String(condition[condition.startIndex..<stopRange.lowerBound])
                }
            }
            if trimmedLeadingParen, let closeIndex = condition.firstIndex(of: ")") {
                condition = String(condition[condition.startIndex..<closeIndex])
            }
            if let parsed = joinCondition(condition) {
                results.append(parsed)
            }
            searchStart = onRange.upperBound
        }
        return results
    }

    private static let joinOperators = ["==", "=", "IS"]

    private static func joinCondition(
        _ condition: String
    ) -> (
        SQLiteBuildValidationIdentifierScanner.Pair,
        SQLiteBuildValidationIdentifierScanner.Pair
    )? {
        var scanner = SQLiteBuildValidationIdentifierScanner(
            condition.trimmingCharacters(in: .whitespaces)
        )
        guard let left = scanner.nextIdentifierPair() else {
            return nil
        }
        scanner.skipWhitespace()
        guard let operatorToken = joinOperators.first(where: { scanner.peekMatches($0) }) else {
            return nil
        }
        scanner.advance(by: operatorToken.count)
        scanner.skipWhitespace()
        guard let right = scanner.nextIdentifierPair() else {
            return nil
        }
        return (left, right)
    }

    // MARK: - Text handling

    private static func normalizedWhitespace(_ sql: String) -> String {
        " " + sql
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ") + " "
    }

    /// Splits `text` on `separator` wherever it occurs at paren depth zero.
    ///
    /// Unbalanced parentheses never produce a guessed split: the whole string
    /// comes back as one piece, which downstream reads as "unparseable"
    /// rather than as a set of conjuncts.
    private static func splitTopLevel(_ text: String, on separator: String) -> [String] {
        var depth = 0
        var pieces: [String] = []
        var current = ""
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "(" {
                depth += 1
            } else if text[index] == ")" {
                depth -= 1
                guard depth >= 0 else {
                    return [text.trimmingCharacters(in: .whitespaces)]
                }
            }
            if depth == 0, text[index...].hasPrefix(separator) {
                pieces.append(current)
                current = ""
                index = text.index(index, offsetBy: separator.count)
                continue
            }
            current.append(text[index])
            index = text.index(after: index)
        }
        pieces.append(current)
        guard depth == 0 else {
            return [text.trimmingCharacters(in: .whitespaces)]
        }
        return pieces.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func unwrapOuterParens(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespaces)
        while result.hasPrefix("("), result.hasSuffix(")") {
            let inner = String(result.dropFirst().dropLast())
            guard isFullyWrapped(inner) else {
                break
            }
            result = inner.trimmingCharacters(in: .whitespaces)
        }
        return result
    }

    /// True only when the leading `(` closes at the very end, rather than
    /// e.g. `(a) AND (b)` where it closes long before the trailing `)`.
    private static func isFullyWrapped(_ inner: String) -> Bool {
        var depth = 0
        for character in inner {
            if character == "(" {
                depth += 1
            } else if character == ")" {
                depth -= 1
                if depth < 0 {
                    return false
                }
            }
        }
        return depth == 0
    }
}


/// Scans `alias.identifier`, where each half is a bare word or a
/// double-quoted identifier.
///
/// Hand-written rather than a regex grammar, matching the style the plan
/// classifier and table resolver already use.
struct SQLiteBuildValidationIdentifierScanner {
    struct Pair: Equatable {
        let alias: String
        let identifier: String
    }

    private let characters: [Character]
    private var position = 0

    init(_ text: String) {
        self.characters = Array(text)
    }

    mutating func nextIdentifierPair() -> Pair? {
        skipWhitespace()
        guard let alias = nextIdentifier(), consume(".") else {
            return nil
        }
        guard let identifier = nextIdentifier() else {
            return nil
        }
        return Pair(alias: alias, identifier: identifier)
    }

    mutating func skipWhitespace() {
        while position < characters.count, characters[position] == " " {
            position += 1
        }
    }

    func peekMatches(_ token: String) -> Bool {
        let tokenCharacters = Array(token)
        guard position + tokenCharacters.count <= characters.count else {
            return false
        }
        return Array(characters[position..<(position + tokenCharacters.count)]) == tokenCharacters
    }

    mutating func advance(by count: Int) {
        position += count
    }

    func remainder() -> String {
        String(characters[position...])
    }

    @discardableResult
    mutating func consume(_ token: String) -> Bool {
        guard peekMatches(token) else {
            return false
        }
        position += token.count
        return true
    }

    mutating func nextIdentifier() -> String? {
        skipWhitespace()
        guard position < characters.count else {
            return nil
        }
        if characters[position] == "\"" {
            var identifier = ""
            var index = position + 1
            while index < characters.count, characters[index] != "\"" {
                identifier.append(characters[index])
                index += 1
            }
            guard index < characters.count else {
                return nil
            }
            position = index + 1
            return identifier
        }

        guard characters[position].isLetter || characters[position] == "_" else {
            return nil
        }
        var identifier = ""
        var index = position
        while index < characters.count,
              characters[index].isLetter || characters[index].isNumber || characters[index] == "_" {
            identifier.append(characters[index])
            index += 1
        }
        position = index
        return identifier
    }
}
