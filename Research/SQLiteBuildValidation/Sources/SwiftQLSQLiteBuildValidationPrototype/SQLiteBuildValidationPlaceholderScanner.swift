import Foundation


package struct SQLiteBuildValidationPlaceholderOccurrence:
    Codable,
    Equatable,
    Sendable
{
    package let spelling: String
    package let byteOffset: Int
    package let physicalIndex: Int

    package init(spelling: String, byteOffset: Int, physicalIndex: Int) {
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


package struct SQLiteBuildValidationUnsupportedPlaceholder:
    Codable,
    Equatable,
    Sendable
{
    package let spelling: String
    package let byteOffset: Int
    package let reason: String

    package init(spelling: String, byteOffset: Int, reason: String) {
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
package struct SQLiteBuildValidationPlaceholderAnalysis:
    Codable,
    Equatable,
    Sendable
{
    package let physicalParameterCount: Int
    package let parameters: [SQLitePreparedParameter]
    package let occurrences: [SQLiteBuildValidationPlaceholderOccurrence]
    package let unsupported: [SQLiteBuildValidationUnsupportedPlaceholder]
    package let collisions: [String]

    package init(
        physicalParameterCount: Int,
        parameters: [SQLitePreparedParameter],
        occurrences: [SQLiteBuildValidationPlaceholderOccurrence],
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


package enum SQLiteBuildValidationPlaceholderScanner {
    package static func scan(
        _ sql: String
    ) -> SQLiteBuildValidationPlaceholderAnalysis {
        let bytes = Array(sql.utf8)
        var physicalNameByIndex: [Int: String] = [:]
        var physicalIndexByNamedToken: [String: Int] = [:]
        var largestPhysicalIndex = 0
        var occurrences: [SQLiteBuildValidationPlaceholderOccurrence] = []
        var unsupported: [SQLiteBuildValidationUnsupportedPlaceholder] = []
        var collisions: [String] = []
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
                    unsupported.append(SQLiteBuildValidationUnsupportedPlaceholder(
                        spelling: "?",
                        byteOffset: index,
                        reason: "Anonymous ? placeholders are not emitted by SwiftQL static descriptors."
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
                    unsupported.append(SQLiteBuildValidationUnsupportedPlaceholder(
                        spelling: spelling,
                        byteOffset: index,
                        reason: "Indexed placeholders require a positive one-based SQLite index."
                    ))
                    index = tokenEnd
                    continue
                }
                largestPhysicalIndex = max(largestPhysicalIndex, physicalIndex)
                register(
                    spelling: spelling,
                    physicalIndex: physicalIndex,
                    byteOffset: index,
                    physicalNameByIndex: &physicalNameByIndex,
                    occurrences: &occurrences,
                    collisions: &collisions
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
                } else {
                    physicalIndex = largestPhysicalIndex + 1
                    largestPhysicalIndex = physicalIndex
                    physicalIndexByNamedToken[spelling] = physicalIndex
                }
                register(
                    spelling: spelling,
                    physicalIndex: physicalIndex,
                    byteOffset: index,
                    physicalNameByIndex: &physicalNameByIndex,
                    occurrences: &occurrences,
                    collisions: &collisions
                )
                index = tokenEnd
                continue
            }

            if currentByte == 0x40 || currentByte == 0x24 { // @name or $name
                let tokenEnd = consumeName(startingAt: index + 1, bytes: bytes)
                let end = max(index + 1, tokenEnd)
                let spelling = String(
                    decoding: bytes[index..<end],
                    as: UTF8.self
                )
                unsupported.append(SQLiteBuildValidationUnsupportedPlaceholder(
                    spelling: spelling,
                    byteOffset: index,
                    reason: "Only SwiftQL-emitted :name and ?N placeholders are supported."
                ))
                index = end
                continue
            }

            index += 1
        }

        let parameters: [SQLitePreparedParameter]
        if largestPhysicalIndex == 0 {
            parameters = []
        } else {
            parameters = (1...largestPhysicalIndex).map {
                SQLitePreparedParameter(
                    physicalIndex: $0,
                    name: physicalNameByIndex[$0]
                )
            }
        }
        return SQLiteBuildValidationPlaceholderAnalysis(
            physicalParameterCount: largestPhysicalIndex,
            parameters: parameters,
            occurrences: occurrences,
            unsupported: unsupported,
            collisions: collisions
        )
    }
}


private extension SQLiteBuildValidationPlaceholderScanner {
    static func register(
        spelling: String,
        physicalIndex: Int,
        byteOffset: Int,
        physicalNameByIndex: inout [Int: String],
        occurrences: inout [SQLiteBuildValidationPlaceholderOccurrence],
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
        occurrences.append(SQLiteBuildValidationPlaceholderOccurrence(
            spelling: spelling,
            byteOffset: byteOffset,
            physicalIndex: physicalIndex
        ))
    }

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
            if bytes[index] == 0x5D {
                return index + 1
            }
            index += 1
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
