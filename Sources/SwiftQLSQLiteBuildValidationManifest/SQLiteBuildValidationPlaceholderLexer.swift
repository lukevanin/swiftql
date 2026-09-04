import Foundation


/// One placeholder-shaped token found in a query's SQL.
package struct SQLiteBuildValidationPlaceholderToken: Equatable, Sendable {

    package enum Kind: Equatable, Sendable {

        /// `?N` with a positive one-based index, which SQLite binds to that
        /// physical slot directly.
        case indexed

        /// `:name`. Its physical slot is its first-encounter position among
        /// all placeholders, and every later occurrence of the same name
        /// shares that slot -- SQLite's own binding semantics.
        case named

        /// A bare `?`. SQLite accepts it; SwiftQL never emits it, and its
        /// physical slot is indistinguishable from an unused `?N` gap.
        case anonymous

        /// `?0`, or `?` followed by digits that do not parse as a positive
        /// index.
        case invalidIndex

        /// `@name` or `$name` -- a SQLite placeholder sigil SwiftQL does not
        /// emit.
        case foreignSigil
    }

    package let kind: Kind

    /// The token exactly as written, sigil included.
    package let spelling: String

    /// Where the token starts, in bytes from the beginning of the SQL. Byte
    /// offsets rather than character offsets, because that is what a diagnostic
    /// can point at unambiguously in SQL that is not ASCII.
    package let byteOffset: Int

    /// The SQLite physical parameter slot this token binds, for the kinds that
    /// bind one. `nil` for every other kind.
    package let physicalIndex: Int?
}


/// What one pass of the lexer found.
package struct SQLiteBuildValidationPlaceholderTokenStream: Equatable, Sendable {

    package let tokens: [SQLiteBuildValidationPlaceholderToken]

    /// The highest physical slot any token binds, which is also SQLite's
    /// physical parameter count for the statement -- SQLite sizes its
    /// parameter table by the largest index used, leaving unused slots as
    /// gaps.
    package let largestPhysicalIndex: Int
}


/// The quote- and comment-aware scan over a query's SQL that finds every
/// placeholder and assigns each one its SQLite physical slot.
///
/// This is deliberately far smaller than SQLite's tokenizer: it needs to know
/// where placeholders are, and which text they cannot be inside -- string
/// literals, quoted and bracketed identifiers, line and block comments.
///
/// It is one implementation on purpose (#566). The manifest builder and the
/// validator both scan the same SQL and must reach the same physical-slot
/// assignment: the manifest cross-checks declared parameters against its scan
/// when a manifest is built, and the validator cross-checks the same
/// parameters against its own scan and against SQLite's real parameter table
/// when the manifest is validated. Two implementations that disagree produce a
/// manifest that builds and then fails validation for no reason a reader can
/// see. They used to share ~82 lines of identical lexing, separately.
package enum SQLiteBuildValidationPlaceholderLexer {

    package static func scan(
        _ sql: String
    ) -> SQLiteBuildValidationPlaceholderTokenStream {
        let bytes = Array(sql.utf8)
        var physicalIndexByNamedToken: [String: Int] = [:]
        var largestPhysicalIndex = 0
        var tokens: [SQLiteBuildValidationPlaceholderToken] = []
        var index = 0

        while index < bytes.count {
            let currentByte = bytes[index]
            if currentByte == 0x2D, byte(at: index + 1, in: bytes) == 0x2D {
                index = skipLineComment(startingAt: index + 2, bytes: bytes)
                continue
            }
            if currentByte == 0x2F, byte(at: index + 1, in: bytes) == 0x2A {
                index = skipBlockComment(startingAt: index + 2, bytes: bytes)
                continue
            }
            if currentByte == 0x27 || currentByte == 0x22 || currentByte == 0x60 {
                index = skipQuoted(
                    startingAt: index + 1,
                    delimiter: currentByte,
                    bytes: bytes
                )
                continue
            }
            if currentByte == 0x5B {
                index = skipBracketQuoted(startingAt: index + 1, bytes: bytes)
                continue
            }

            if currentByte == 0x3F { // ? or ?NNN
                let tokenEnd = consumeDigits(startingAt: index + 1, bytes: bytes)
                guard tokenEnd > index + 1 else {
                    tokens.append(SQLiteBuildValidationPlaceholderToken(
                        kind: .anonymous,
                        spelling: "?",
                        byteOffset: index,
                        physicalIndex: nil
                    ))
                    index += 1
                    continue
                }
                let spelling = String(
                    decoding: bytes[index..<tokenEnd],
                    as: UTF8.self
                )
                guard let physicalIndex = Int(spelling.dropFirst()),
                      physicalIndex > 0 else {
                    tokens.append(SQLiteBuildValidationPlaceholderToken(
                        kind: .invalidIndex,
                        spelling: spelling,
                        byteOffset: index,
                        physicalIndex: nil
                    ))
                    index = tokenEnd
                    continue
                }
                largestPhysicalIndex = max(largestPhysicalIndex, physicalIndex)
                tokens.append(SQLiteBuildValidationPlaceholderToken(
                    kind: .indexed,
                    spelling: spelling,
                    byteOffset: index,
                    physicalIndex: physicalIndex
                ))
                index = tokenEnd
                continue
            }

            if currentByte == 0x3A { // :name
                let tokenEnd = consumeName(startingAt: index + 1, bytes: bytes)
                // A bare `:` names nothing and is not a placeholder.
                guard tokenEnd > index + 1 else {
                    index += 1
                    continue
                }
                let spelling = String(
                    decoding: bytes[index..<tokenEnd],
                    as: UTF8.self
                )
                let physicalIndex: Int
                if let existing = physicalIndexByNamedToken[spelling] {
                    physicalIndex = existing
                }
                else {
                    physicalIndex = largestPhysicalIndex + 1
                    largestPhysicalIndex = physicalIndex
                    physicalIndexByNamedToken[spelling] = physicalIndex
                }
                tokens.append(SQLiteBuildValidationPlaceholderToken(
                    kind: .named,
                    spelling: spelling,
                    byteOffset: index,
                    physicalIndex: physicalIndex
                ))
                index = tokenEnd
                continue
            }

            if currentByte == 0x40 || currentByte == 0x24 { // @name or $name
                let tokenEnd = consumeName(startingAt: index + 1, bytes: bytes)
                let end = max(index + 1, tokenEnd)
                tokens.append(SQLiteBuildValidationPlaceholderToken(
                    kind: .foreignSigil,
                    spelling: String(decoding: bytes[index..<end], as: UTF8.self),
                    byteOffset: index,
                    physicalIndex: nil
                ))
                index = end
                continue
            }

            index += 1
        }

        return SQLiteBuildValidationPlaceholderTokenStream(
            tokens: tokens,
            largestPhysicalIndex: largestPhysicalIndex
        )
    }
}


private extension SQLiteBuildValidationPlaceholderLexer {

    static func byte(at index: Int, in bytes: [UInt8]) -> UInt8? {
        bytes.indices.contains(index) ? bytes[index] : nil
    }

    static func skipLineComment(startingAt index: Int, bytes: [UInt8]) -> Int {
        var index = index
        while index < bytes.count, bytes[index] != 0x0A, bytes[index] != 0x0D {
            index += 1
        }
        return index
    }

    static func skipBlockComment(startingAt index: Int, bytes: [UInt8]) -> Int {
        var index = index
        while index < bytes.count {
            if bytes[index] == 0x2A, byte(at: index + 1, in: bytes) == 0x2F {
                return index + 2
            }
            index += 1
        }
        return index
    }

    /// Skips a quoted run, honouring SQLite's doubled-delimiter escape: `''`
    /// inside a string literal is one quote, not the end of the literal.
    static func skipQuoted(
        startingAt index: Int,
        delimiter: UInt8,
        bytes: [UInt8]
    ) -> Int {
        var index = index
        while index < bytes.count {
            guard bytes[index] == delimiter else {
                index += 1
                continue
            }
            if byte(at: index + 1, in: bytes) == delimiter {
                index += 2
                continue
            }
            return index + 1
        }
        return index
    }

    static func skipBracketQuoted(startingAt index: Int, bytes: [UInt8]) -> Int {
        var index = index
        while index < bytes.count {
            guard bytes[index] == 0x5D else {
                index += 1
                continue
            }
            if byte(at: index + 1, in: bytes) == 0x5D {
                index += 2
                continue
            }
            return index + 1
        }
        return index
    }

    static func consumeDigits(startingAt index: Int, bytes: [UInt8]) -> Int {
        var index = index
        while index < bytes.count, (0x30...0x39).contains(bytes[index]) {
            index += 1
        }
        return index
    }

    static func consumeName(startingAt index: Int, bytes: [UInt8]) -> Int {
        var index = index
        while index < bytes.count, isNameByte(bytes[index]) {
            index += 1
        }
        return index
    }

    static func isNameByte(_ byte: UInt8) -> Bool {
        (0x30...0x39).contains(byte)
            || (0x41...0x5A).contains(byte)
            || byte == 0x5F
            || (0x61...0x7A).contains(byte)
            || byte >= 0x80
    }
}
