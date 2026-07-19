import Foundation
import XCTest
@testable import SwiftQL


final class XLFieldReaderTests: XCTestCase {

    func testFieldReaderBindsEveryReadToOneIndex() throws {
        let columns = RecordingColumnReader()
        let field = XLFieldReader(reader: columns, at: 7)

        XCTAssertEqual(field.index, 7)
        XCTAssertFalse(try field.isNull())
        XCTAssertEqual(try field.readInteger(), 107)
        XCTAssertEqual(try field.readReal(), 7.5)
        XCTAssertEqual(try field.readText(), "field-7")
        XCTAssertEqual(try field.readBlob(), Data([0x07]))
        XCTAssertEqual(
            columns.calls,
            [
                .isNull(7),
                .integer(7),
                .real(7),
                .text(7),
                .blob(7),
            ]
        )
    }

    func testFieldReaderPreservesStructuredErrorIndex() {
        let expected = XLColumnReadError(
            index: 3,
            expectedType: "Int",
            failure: .typeMismatch(actualType: "TEXT")
        )
        let field = XLFieldReader(
            reader: ThrowingColumnReader(error: expected),
            at: 3
        )

        XCTAssertThrowsError(try field.readInteger()) { error in
            XCTAssertEqual(error as? XLColumnReadError, expected)
        }
    }

    func testSequentialRowReaderCreatesOneFieldPerColumn() throws {
        let columns = RecordingColumnReader()
        let row = XLColumnValuesRowReader<(Int, String)>()
        row.reset(reader: columns)

        let integer: Int = try row.column(0, alias: "integer")
        let text: String = try row.column("", alias: "text")

        XCTAssertEqual(integer, 100)
        XCTAssertEqual(text, "field-1")
        XCTAssertEqual(columns.calls, [.integer(0), .text(1)])
    }

    func testExistingColumnReaderLiteralConformerUsesFieldBridge() throws {
        let columns = RecordingColumnReader()
        let literal = try LegacyColumnReaderLiteral(
            reader: XLFieldReader(reader: columns, at: 4)
        )

        XCTAssertEqual(literal.value, 104)
        XCTAssertEqual(columns.calls, [.integer(4)])
    }

    func testNewFieldReaderLiteralConformerSupportsLegacyCallShape() throws {
        let columns = RecordingColumnReader()
        let literal = try FieldReaderLiteral(reader: columns, at: 2)

        XCTAssertEqual(literal.value, 102)
        XCTAssertEqual(columns.calls, [.integer(2)])
    }
}


private final class RecordingColumnReader: XLColumnReader {

    enum Call: Equatable {
        case isNull(Int)
        case integer(Int)
        case real(Int)
        case text(Int)
        case blob(Int)
    }

    private(set) var calls: [Call] = []

    func isNull(at index: Int) -> Bool {
        calls.append(.isNull(index))
        return false
    }

    func readInteger(at index: Int) -> Int {
        calls.append(.integer(index))
        return index + 100
    }

    func readReal(at index: Int) -> Double {
        calls.append(.real(index))
        return Double(index) + 0.5
    }

    func readText(at index: Int) -> String {
        calls.append(.text(index))
        return "field-\(index)"
    }

    func readBlob(at index: Int) -> Data {
        calls.append(.blob(index))
        return Data([UInt8(index)])
    }
}


private struct ThrowingColumnReader: XLColumnReader {
    let error: XLColumnReadError

    func isNull(at index: Int) throws -> Bool {
        throw error
    }

    func readInteger(at index: Int) throws -> Int {
        throw error
    }

    func readReal(at index: Int) throws -> Double {
        throw error
    }

    func readText(at index: Int) throws -> String {
        throw error
    }

    func readBlob(at index: Int) throws -> Data {
        throw error
    }
}


private struct LegacyColumnReaderLiteral: XLLiteral {
    let value: Int

    init(reader: any XLColumnReader, at index: Int) throws {
        self.value = try reader.readInteger(at: index)
    }

    func bind(context: inout XLBindingContext) {
        context.bindInteger(value: value)
    }
}


private struct FieldReaderLiteral: XLLiteral {
    let value: Int

    init(reader: XLFieldReader) throws {
        self.value = try reader.readInteger()
    }

    func bind(context: inout XLBindingContext) {
        context.bindInteger(value: value)
    }
}
