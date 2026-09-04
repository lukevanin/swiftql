//
//  SQLQueryIdentityEncodingV1.swift
//  SwiftQLCore
//
//  The frozen v1 byte encoding a durable query identity is derived from.
//
//  In its own file (issue #559) because of what it is rather than how big it
//  is: an identity computed under this encoding is written into build
//  artifacts and compared across builds, so changing a length prefix or a
//  normalization step here silently invalidates every identity ever recorded.
//  A file named for the frozen format is a place to say that once.
//

import Foundation


package struct XLCanonicalByteWriter {

    package private(set) var output: [UInt8] = []

    package init() {
    }

    package mutating func byte(_ value: UInt8) {
        output.append(value)
    }

    package mutating func bytes(_ values: [UInt8]) {
        output.append(contentsOf: values)
    }

    package mutating func uint16(_ value: UInt16) {
        output.append(UInt8((value >> 8) & 0xff))
        output.append(UInt8(value & 0xff))
    }

    package mutating func uint64(_ value: UInt64) {
        for shift in stride(from: 56, through: 0, by: -8) {
            output.append(UInt8((value >> UInt64(shift)) & 0xff))
        }
    }

    package mutating func string(_ value: String) {
        let bytes = Array(value.utf8)
        uint64(UInt64(bytes.count))
        self.bytes(bytes)
    }

    package mutating func stringArray(_ values: [String]) {
        uint64(UInt64(values.count))
        for value in values {
            string(value)
        }
    }

    package mutating func metadataString(_ value: String) {
        string(value.precomposedStringWithCanonicalMapping)
    }

    package mutating func metadataStringArray(_ values: [String]) {
        uint64(UInt64(values.count))
        for value in values {
            metadataString(value)
        }
    }

    package mutating func optional<Value>(
        _ value: Value?,
        write: (inout Self, Value) -> Void
    ) {
        guard let value else {
            byte(0)
            return
        }
        byte(1)
        write(&self, value)
    }

    /// The written bytes as lowercase hexadecimal.
    ///
    /// Identity material has to survive being used as a SQL identifier, which
    /// arbitrary bytes do not.
    /// The lowercase hex alphabet, built once rather than per access.
    private static let hexDigits = Array("0123456789abcdef".utf8)

    package var hexEncoded: String {
        let digits = Self.hexDigits
        var encoded: [UInt8] = []
        encoded.reserveCapacity(output.count * 2)
        for byte in output {
            encoded.append(digits[Int(byte >> 4)])
            encoded.append(digits[Int(byte & 0x0f)])
        }
        return String(decoding: encoded, as: UTF8.self)
    }
}


func _xlExactUTF8Equal(_ lhs: String, _ rhs: String) -> Bool {
    Array(lhs.utf8) == Array(rhs.utf8)
}


func _xlHashExactUTF8(_ value: String, into hasher: inout Hasher) {
    let bytes = Array(value.utf8)
    hasher.combine(bytes.count)
    for byte in bytes {
        hasher.combine(byte)
    }
}
