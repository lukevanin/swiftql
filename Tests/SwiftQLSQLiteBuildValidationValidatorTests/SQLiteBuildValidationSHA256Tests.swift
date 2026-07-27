import Foundation
import XCTest
@testable import SwiftQLSQLiteBuildValidationValidator


final class SQLiteBuildValidationSHA256Tests: XCTestCase {
    func testStandardTestVectors() {
        // NIST/FIPS 180-4 examples, plus the empty-string and a multi-block
        // input to exercise the streaming block-boundary and tail-padding
        // logic (a single 64-byte block cannot cover both).
        let cases: [(input: String, expected: String)] = [
            ("", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
            ("abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
            (
                "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
                "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
            ),
        ]
        for testCase in cases {
            XCTAssertEqual(
                SQLiteBuildValidationSHA256.hexDigest(
                    of: Data(testCase.input.utf8)
                ),
                testCase.expected,
                "input: \(testCase.input)"
            )
        }
    }

    func testExactBlockBoundaryAndMultiBlockInputsHashDeterministically() {
        // Exactly 64 bytes: the streaming loop consumes it as one full block
        // and the padding tail becomes a second, wholly synthetic block.
        let exactlyOneBlock = Data(repeating: 0x41, count: 64)
        // Large enough to span many full blocks plus a partial tail.
        let multiBlock = Data(repeating: 0x5A, count: 10_000)

        for data in [exactlyOneBlock, multiBlock] {
            let first = SQLiteBuildValidationSHA256.hexDigest(of: data)
            let second = SQLiteBuildValidationSHA256.hexDigest(of: data)
            XCTAssertEqual(first, second)
            XCTAssertEqual(first.count, 64)
            XCTAssertTrue(first.allSatisfy { $0.isHexDigit && !$0.isUppercase })
        }
    }
}
