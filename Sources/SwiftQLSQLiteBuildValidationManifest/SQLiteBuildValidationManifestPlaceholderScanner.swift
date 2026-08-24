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


enum SQLiteBuildValidationManifestPlaceholderScanner {

    static func scan(
        _ sql: String
    ) -> SQLiteBuildValidationManifestPlaceholderAnalysis {
        let bytes = Array(sql.utf8)
        var physicalIndexByNamedToken: [String: Int] = [:]
        var largestPhysicalIndex = 0
        var occurrences: [SQLiteBuildValidationManifestPlaceholderOccurrence] = []
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
                    index += 1
                    continue
                }
                let spelling = String(
                    decoding: bytes[index..<tokenEnd],
                    as: UTF8.self
                )
                guard let physicalIndex = Int(spelling.dropFirst()),
                      physicalIndex > 0 else {
                    index = tokenEnd
                    continue
                }
                largestPhysicalIndex = max(largestPhysicalIndex, physicalIndex)
                occurrences.append(
                    SQLiteBuildValidationManifestPlaceholderOccurrence(
                        spelling: spelling,
                        physicalIndex: physicalIndex
                    )
                )
                index = tokenEnd
                continue
            }

            if currentByte == 0x3A { // :name
                let tokenEnd = consumeName(startingAt: index + 1, bytes: bytes)
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
                occurrences.append(
                    SQLiteBuildValidationManifestPlaceholderOccurrence(
                        spelling: spelling,
                        physicalIndex: physicalIndex
                    )
                )
                index = tokenEnd
                continue
            }

            index += 1
        }

        return SQLiteBuildValidationManifestPlaceholderAnalysis(
            occurrences: occurrences
        )
    }
}


private extension SQLiteBuildValidationManifestPlaceholderScanner {

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
