import Foundation


/// A single `alias.column <op> …` comparison found in a statement's `WHERE`
/// clause.
package struct WhereComparison: Equatable, Sendable {
    package enum ComparisonKind: Sendable {
        case equality
        case range
    }

    package let alias: String
    package let column: String
    package let kind: ComparisonKind
}


/// One equality (or `IS`, for a nullable left join) join key: `alias.column`
/// on one side of a `JOIN … ON` condition.
package struct JoinKey: Equatable, Sendable {
    package let alias: String
    package let column: String
}


/// Extracts index-candidate signal (equality/range predicates, join keys,
/// `ORDER BY` columns) from a statement's rendered SQL text for one table
/// alias.
///
/// This is deliberately a narrow, pattern-based extractor, not a SQL parser.
/// The #390/#391 corpus renders SQL in two styles this extractor recognises
/// — the #191 combinatorial manifest's quoted, parenthesised style
/// (`("t0"."orderID" == 10248)`) and this repo's own hand-written Northwind
/// anchor style (`o.OrderID = ?`, no quotes, no wrapping parens) — via a
/// single identifier scanner that accepts both forms. A `WHERE` clause
/// containing `OR` *anywhere* — not just at the top level; this check is a
/// blunt substring test, deliberately more conservative than "does this
/// `OR` actually change precedence" — or a conjunct that isn't a plain
/// column/operator comparison, yields no comparisons for that clause —
/// never a guessed or partial one. Statements this extractor can't
/// confidently read simply produce no candidate, the same "never coerce"
/// discipline #391 applies to unrecognised plan shapes.
package enum IndexCandidateExtraction {
    package static func whereComparisons(for alias: String, in sql: String) -> [WhereComparison] {
        let sql = normalizeWhitespace(sql)
        guard let clause = extractClause(sql, after: "WHERE", stoppingAt: ["GROUP BY", "ORDER BY", "LIMIT"]) else {
            return []
        }
        guard !clause.contains(" OR ") else {
            return []
        }
        return splitTopLevelConjuncts(clause).compactMap { conjunct in
            parseComparison(conjunct, aliasFilter: alias)
        }
    }

    package static func orderByColumns(for alias: String, in sql: String) -> [String] {
        let sql = normalizeWhitespace(sql)
        guard let clause = extractClause(sql, after: "ORDER BY", stoppingAt: ["LIMIT"]) else {
            return []
        }
        return splitTopLevel(clause, on: ",").compactMap { term in
            // An ORDER BY term's leading parenthesis (if any) only wraps the
            // expression, not the trailing COLLATE/ASC/DESC — e.g.
            // `("t0"."x" COLLATE NOCASE) ASC` — so trim leading "(" alone
            // rather than requiring the whole term to be paren-wrapped.
            let trimmed = term.trimmingCharacters(in: .whitespaces).drop { $0 == "(" }
            var scanner = IdentifierScanner(String(trimmed))
            guard let pair = scanner.nextIdentifierPair() else {
                return nil
            }
            return pair.alias == alias ? pair.identifier : nil
        }
    }

    package static func joinKeys(for alias: String, in sql: String) -> [JoinKey] {
        let sql = normalizeWhitespace(sql)
        return joinConditions(in: sql).flatMap { left, right -> [JoinKey] in
            var keys: [JoinKey] = []
            if left.alias == alias {
                keys.append(JoinKey(alias: alias, column: left.identifier))
            }
            if right.alias == alias {
                keys.append(JoinKey(alias: alias, column: right.identifier))
            }
            return keys
        }
    }

    /// Maps every `FROM`/`JOIN` alias to its real table name — needed
    /// because `CREATE INDEX` requires the table name, not the alias, and a
    /// table name can contain a space (`"Order Details"`) while its alias
    /// never does.
    /// Only returns bindings this extractor can resolve with confidence.
    /// Two situations are deliberately excluded rather than guessed at:
    ///
    /// - **CTE names.** `WITH "cte0" AS (SELECT …)` looks, to a naive
    ///   `FROM`/`JOIN … AS …` scan, exactly like a table alias binding once
    ///   the outer query does `FROM "cte0" AS "t0"` — but `"cte0"` is not a
    ///   real table, and `CREATE INDEX` on it would fail. CTE names are
    ///   detected separately (by the `AS (` that immediately follows them,
    ///   which a table alias never has) and excluded.
    /// - **Alias reuse across nested scopes.** The same alias name (e.g.
    ///   `"t0"`) can legitimately be bound to a different table in an outer
    ///   query and a subquery (`FROM "Orders" AS "t0" WHERE "t0"."x" IN
    ///   (SELECT … FROM "Employees" AS "t0" …)`). Resolving this correctly
    ///   requires real scope tracking this extractor doesn't do, so a
    ///   conflicting rebinding removes the alias from the result entirely
    ///   rather than silently keeping whichever occurrence was scanned last.
    package static func tableAliasMap(in sql: String) -> [String: String] {
        let sql = normalizeWhitespace(sql)
        let cteNames = self.cteNames(in: sql)

        var bindings: [String: String] = [:]
        var ambiguousAliases: Set<String> = []
        for keyword in [" FROM ", " JOIN "] {
            var searchStart = sql.startIndex
            while let range = sql.range(of: keyword, range: searchStart..<sql.endIndex) {
                let remainder = String(sql[range.upperBound...])
                if let (table, alias) = parseTableAlias(remainder) {
                    if let existingTable = bindings[alias], existingTable != table {
                        ambiguousAliases.insert(alias)
                    } else {
                        bindings[alias] = table
                    }
                }
                searchStart = range.upperBound
            }
        }
        for alias in ambiguousAliases {
            bindings.removeValue(forKey: alias)
        }
        for (alias, table) in bindings where cteNames.contains(table) {
            bindings.removeValue(forKey: alias)
        }
        return bindings
    }

    /// A table alias binding is always `<table> AS <alias>` — `AS` followed
    /// by an identifier. A CTE definition is `<name> AS (<subquery>)` — `AS`
    /// followed directly by `(`. That distinction, not any keyword context,
    /// is what identifies a name as a CTE rather than a table.
    private static func cteNames(in sql: String) -> Set<String> {
        var names: Set<String> = []
        var searchRange = sql.startIndex..<sql.endIndex
        while let asParenRange = sql.range(of: " AS (", range: searchRange) {
            if let name = name(precedingEndIndex: asParenRange.lowerBound, in: sql) {
                names.insert(name)
            }
            searchRange = asParenRange.upperBound..<sql.endIndex
        }
        return names
    }

    private static func name(precedingEndIndex index: String.Index, in sql: String) -> String? {
        var end = index
        while end > sql.startIndex, sql[sql.index(before: end)] == " " {
            end = sql.index(before: end)
        }
        guard end > sql.startIndex else {
            return nil
        }
        if sql[sql.index(before: end)] == "\"" {
            guard end > sql.index(after: sql.startIndex) else {
                return nil
            }
            var start = sql.index(before: sql.index(before: end))
            while start > sql.startIndex, sql[start] != "\"" {
                start = sql.index(before: start)
            }
            guard sql[start] == "\"" else {
                return nil
            }
            return String(sql[sql.index(after: start)..<sql.index(before: end)])
        }

        var start = end
        while start > sql.startIndex {
            let previous = sql.index(before: start)
            guard sql[previous].isLetter || sql[previous].isNumber || sql[previous] == "_" else {
                break
            }
            start = previous
        }
        guard start < end else {
            return nil
        }
        return String(sql[start..<end])
    }

    private static func parseTableAlias(_ text: String) -> (table: String, alias: String)? {
        var scanner = NameScanner(text)
        guard let table = scanner.nextName() else {
            return nil
        }
        scanner.skipWhitespace()
        guard scanner.consume("AS") else {
            return nil
        }
        scanner.skipWhitespace()
        guard let alias = scanner.nextName() else {
            return nil
        }
        return (table, alias)
    }

    /// Collapses every run of whitespace (including the newlines and
    /// indentation this repo's own multi-line anchor statements are written
    /// with) to a single space, so every other boundary check in this file
    /// can assume clause keywords are always surrounded by exactly one
    /// space.
    private static func normalizeWhitespace(_ sql: String) -> String {
        sql.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    // MARK: - Clause extraction

    private static let stopKeywordsAfterOn = ["JOIN", "WHERE", "GROUP BY", "ORDER BY", "LIMIT"]

    private static func extractClause(
        _ sql: String,
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

    /// Finds every `ON <condition>` clause in the statement and parses it as
    /// a simple equality (or `IS`) comparison between two qualified
    /// identifiers. Tolerates both a parenthesised condition (the
    /// combinatorial corpus's style) and a bare, unparenthesised one ending
    /// at the next clause keyword (this repo's own anchor-statement style).
    private static func joinConditions(in sql: String) -> [(IdentifierScanner.Pair, IdentifierScanner.Pair)] {
        var results: [(IdentifierScanner.Pair, IdentifierScanner.Pair)] = []
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

            if let comparison = parseJoinCondition(condition) {
                results.append(comparison)
            }
            searchStart = onRange.upperBound
        }
        return results
    }

    private static let joinOperators = ["==", "=", "IS"]

    private static func parseJoinCondition(
        _ condition: String
    ) -> (IdentifierScanner.Pair, IdentifierScanner.Pair)? {
        var scanner = IdentifierScanner(condition.trimmingCharacters(in: .whitespaces))
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

    /// Splits `WHERE` clause text on top-level ` AND `, tolerant of the
    /// combinatorial corpus's rendering style, which wraps the whole clause
    /// and every conjunct in parentheses (e.g.
    /// `(("a"."x" >= 1) AND ("a"."x" <= 2))`), as well as an unwrapped,
    /// unparenthesised single comparison.
    private static func splitTopLevelConjuncts(_ clause: String) -> [String] {
        splitTopLevel(unwrapOuterParens(clause), on: " AND ").map(unwrapOuterParens)
    }

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

    /// True only if the leading `(` closes at the very end of `inner` (i.e.
    /// that pair wraps the whole string), rather than e.g. `(a) AND (b)`
    /// where the leading `(` closes long before the trailing `)`.
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

    // MARK: - Comparison parsing

    private static let comparisonOperators = ["==", "=", ">=", "<=", ">", "<"]

    private static func parseComparison(_ conjunct: String, aliasFilter: String) -> WhereComparison? {
        var scanner = IdentifierScanner(conjunct)
        guard let pair = scanner.nextIdentifierPair(), pair.alias == aliasFilter else {
            return nil
        }
        scanner.skipWhitespace()
        for operatorToken in comparisonOperators where scanner.peekMatches(operatorToken) {
            let kind: WhereComparison.ComparisonKind = (operatorToken == "==" || operatorToken == "=")
                ? .equality
                : .range
            return WhereComparison(alias: pair.alias, column: pair.identifier, kind: kind)
        }
        return nil
    }
}


/// Scans a leading `alias.identifier` pair from the current position, where
/// each half is either a bare word (`[A-Za-z_][A-Za-z0-9_]*`) or a
/// double-quoted identifier (`"any characters except a quote"`). Mirrors the
/// manual-parsing style already used by `EQPPlanShapeClassifier` rather than
/// reaching for a regex-based SQL grammar.
private struct IdentifierScanner {
    struct Pair: Equatable {
        let alias: String
        let identifier: String
    }

    private let characters: [Character]
    private var position: Int = 0

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

    private mutating func consume(_ token: String) -> Bool {
        guard peekMatches(token) else {
            return false
        }
        position += token.count
        return true
    }

    private mutating func nextIdentifier() -> String? {
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
        while index < characters.count, characters[index].isLetter || characters[index].isNumber || characters[index] == "_" {
            identifier.append(characters[index])
            index += 1
        }
        position = index
        return identifier
    }
}


/// Scans a single name — either a bare word or a double-quoted identifier
/// that may contain spaces (`"Order Details"`) — plus literal keywords
/// (`AS`) between names. Used only for `FROM`/`JOIN … AS …` table-alias
/// parsing, where (unlike a column reference) the name itself can contain
/// whitespace.
private struct NameScanner {
    private let characters: [Character]
    private var position: Int = 0

    init(_ text: String) {
        self.characters = Array(text)
    }

    mutating func skipWhitespace() {
        while position < characters.count, characters[position] == " " {
            position += 1
        }
    }

    mutating func consume(_ token: String) -> Bool {
        let tokenCharacters = Array(token)
        guard position + tokenCharacters.count <= characters.count,
              Array(characters[position..<(position + tokenCharacters.count)]) == tokenCharacters else {
            return false
        }
        position += tokenCharacters.count
        return true
    }

    mutating func nextName() -> String? {
        guard position < characters.count else {
            return nil
        }
        if characters[position] == "\"" {
            var name = ""
            var index = position + 1
            while index < characters.count, characters[index] != "\"" {
                name.append(characters[index])
                index += 1
            }
            guard index < characters.count else {
                return nil
            }
            position = index + 1
            return name
        }

        guard characters[position].isLetter || characters[position] == "_" else {
            return nil
        }
        var name = ""
        var index = position
        while index < characters.count, characters[index].isLetter || characters[index].isNumber || characters[index] == "_" {
            name.append(characters[index])
            index += 1
        }
        position = index
        return name
    }
}
