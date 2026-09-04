import Foundation


/// Maps the spelling `EXPLAIN QUERY PLAN` uses for a row source back to the
/// real table it names.
///
/// EQP prints whichever spelling the statement used, so a statement written
/// as `FROM "Orders" AS "t0"` produces `SCAN t0`. A diagnostic that says
/// "t0 is fully scanned" tells a reader nothing, and `CREATE INDEX` needs the
/// table name rather than the alias, so the alias has to be resolved before
/// either is useful.
///
/// This is deliberately a narrow, pattern-based scanner, not a SQL parser. It
/// recognises the two rendering styles this repository actually produces —
/// the quoted style SwiftQL renders (`FROM "Order Details" AS "t0"`) and the
/// bare style the hand-written Northwind anchor statements use
/// (`FROM Orders o`) — and resolves nothing it is not confident about. An
/// unresolved alias is reported as unresolved; it is never guessed at.
///
/// Two situations are excluded rather than guessed at:
///
/// - **CTE names.** `WITH "cte0" AS (SELECT …)` looks, to a naive
///   `FROM`/`JOIN … AS …` scan, exactly like a table binding once the outer
///   query says `FROM "cte0" AS "t0"` — but `"cte0"` is not a table, and
///   `CREATE INDEX` on it would fail. A CTE is identified by the `AS (` that
///   follows its name, which a table alias never has.
/// - **Alias reuse across scopes.** The same alias can legitimately bind to
///   different tables in an outer query and a subquery. Resolving that needs
///   real scope tracking this scanner does not do, so a conflicting rebinding
///   drops the alias entirely rather than keeping whichever was scanned last.
public enum SQLiteBuildValidationPlanTableResolver {

    /// Every alias this scanner can resolve, mapped to its real table.
    ///
    /// A table used without an alias maps to itself, so a caller can look up
    /// a plan node's spelling without first knowing whether it is an alias.
    public static func tableAliases(in sql: String) -> [String: String] {
        let sql = normalizedWhitespace(sql)
        let cteNames = self.cteNames(in: sql)

        var bindings: [String: String] = [:]
        var ambiguousAliases: Set<String> = []
        for keyword in [" FROM ", " JOIN "] {
            var searchStart = sql.startIndex
            while let range = sql.range(of: keyword, range: searchStart..<sql.endIndex) {
                let remainder = String(sql[range.upperBound...])
                if let (table, alias) = parseTableAlias(remainder) {
                    if let existing = bindings[alias], existing != table {
                        ambiguousAliases.insert(alias)
                    } else {
                        bindings[alias] = table
                    }
                } else if let table = parseUnaliasedTable(remainder) {
                    if let existing = bindings[table], existing != table {
                        ambiguousAliases.insert(table)
                    } else {
                        bindings[table] = table
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

    /// Resolves one plan node's table spelling, or `nil` when this scanner
    /// cannot say with confidence.
    public static func table(
        forPlanNodeSpelling spelling: String,
        in sql: String
    ) -> String? {
        tableAliases(in: sql)[spelling]
    }

    /// A table alias binding is always `<table> AS <alias>` or
    /// `<table> <alias>`. A CTE definition is `<name> AS (<subquery>)` — `AS`
    /// followed directly by `(`. That distinction, not keyword context, is
    /// what identifies a name as a CTE.
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

    private static func name(
        precedingEndIndex index: String.Index,
        in sql: String
    ) -> String? {
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

    /// Words that can follow a table name where an alias would otherwise be,
    /// and are not one. `FROM Orders JOIN …` binds no alias for `Orders`.
    private static let nonAliasKeywords: Set<String> = [
        "as", "cross", "excluding", "full", "group", "having", "inner", "join",
        "left", "limit", "natural", "on", "order", "outer", "right", "union",
        "using", "where", "window",
    ]

    private static func parseTableAlias(
        _ text: String
    ) -> (table: String, alias: String)? {
        var scanner = NameScanner(text)
        guard let table = scanner.nextName() else {
            return nil
        }
        scanner.skipWhitespace()
        if scanner.consume("AS") {
            scanner.skipWhitespace()
            guard let alias = scanner.nextName() else {
                return nil
            }
            return (table, alias)
        }
        // The bare `FROM Orders o` form. Only a name that cannot be a clause
        // keyword counts as an alias.
        guard let candidate = scanner.nextName(),
              !nonAliasKeywords.contains(candidate.lowercased()) else {
            return nil
        }
        return (table, candidate)
    }

    private static func parseUnaliasedTable(_ text: String) -> String? {
        var scanner = NameScanner(text)
        return scanner.nextName()
    }

    /// Collapses every run of whitespace, including the newlines and
    /// indentation multi-line statements are written with, so every boundary
    /// check above can assume clause keywords are surrounded by one space.
    private static func normalizedWhitespace(_ sql: String) -> String {
        " " + sql
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ") + " "
    }
}


/// Scans a single name — a bare word, or a double-quoted identifier that may
/// contain spaces (`"Order Details"`) — plus literal keywords between names.
private struct NameScanner {
    private let characters: [Character]
    private var position = 0

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
        skipWhitespace()
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
        while index < characters.count,
              characters[index].isLetter || characters[index].isNumber || characters[index] == "_" {
            name.append(characters[index])
            index += 1
        }
        position = index
        return name
    }
}
