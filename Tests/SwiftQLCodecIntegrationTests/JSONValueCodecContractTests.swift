import Foundation
import XCTest
@testable import SwiftQL


/// Contract-level coverage for ``XLJSONValueCodec``, mirroring
/// `ValueCodecContractTests` in `SwiftQLCoreTests`: pure value-level checks
/// against `XLSQLiteDialect` with no real SQLite connection. Real GRDB/SQLite
/// round trips live in `JSONValueCodecGRDBTests`.
final class JSONValueCodecContractTests: XCTestCase {

    private let dialect = XLSQLiteDialect()

    private let parameterContext = XLValueCodingContext(
        site: .parameter,
        path: XLValueCodingPath(["customer", "profile"])
    )

    private let resultContext = XLValueCodingContext(
        site: .result,
        path: XLValueCodingPath(["customer", "profile"])
    )

    private let sampleProfile = JSONCodecFixtureProfile(
        name: "Ada Lovelace",
        tags: ["engineer", "mathematician"],
        address: JSONCodecFixtureAddress(street: "12 Analytical Ave", city: "London"),
        contact: .email("ada@example.com"),
        loyaltyPoints: 42
    )

    // MARK: - Round trips

    func testNestedValueRoundTripsAsText() throws {
        let configuration = try XLValueCodingConfiguration(
            registry: try XLValueCodecRegistry().registering(jsonCodecFixtureProfileTextCodec),
            defaultCodecKeys: [jsonCodecFixtureTextKey]
        )

        let encoded = try configuration.encode(
            sampleProfile,
            using: dialect,
            context: parameterContext
        )
        guard case .text(let json) = encoded else {
            return XCTFail("Expected TEXT storage, got \(encoded)")
        }
        // Canonicalization: sorted keys make the JSON deterministic.
        XCTAssertTrue(json.hasPrefix("{\"address\""))

        let decoded = try configuration.decode(
            JSONCodecFixtureProfile.self,
            from: encoded,
            using: dialect,
            context: resultContext
        )
        XCTAssertEqual(decoded, sampleProfile)
    }

    func testNestedValueRoundTripsAsBlob() throws {
        let configuration = try XLValueCodingConfiguration(
            registry: try XLValueCodecRegistry().registering(jsonCodecFixtureProfileBlobCodec),
            defaultCodecKeys: [jsonCodecFixtureBlobKey]
        )

        let encoded = try configuration.encode(
            sampleProfile,
            using: dialect,
            context: parameterContext
        )
        guard case .blob = encoded else {
            return XCTFail("Expected BLOB storage, got \(encoded)")
        }

        let decoded = try configuration.decode(
            JSONCodecFixtureProfile.self,
            from: encoded,
            using: dialect,
            context: resultContext
        )
        XCTAssertEqual(decoded, sampleProfile)
    }

    // MARK: - TEXT and BLOB are not interchangeable

    func testTextAndBlobCodecsAreNotInterchangeable() throws {
        let registry = try XLValueCodecRegistry()
            .registering(jsonCodecFixtureProfileTextCodec)
            .registering(jsonCodecFixtureProfileBlobCodec)
        let configuration = try XLValueCodingConfiguration(registry: registry)

        XCTAssertNotEqual(
            jsonCodecFixtureProfileTextCodec.identity.storageIdentifier,
            jsonCodecFixtureProfileBlobCodec.identity.storageIdentifier
        )
        XCTAssertNotEqual(
            jsonCodecFixtureProfileTextCodec.identity.stableIdentityComponents,
            jsonCodecFixtureProfileBlobCodec.identity.stableIdentityComponents
        )

        let blobEncoded = try configuration.encode(
            sampleProfile,
            using: dialect,
            context: parameterContext,
            selection: XLValueCodecSelection(explicitCodecKey: jsonCodecFixtureBlobKey)
        )

        // Asking the TEXT codec to decode BLOB-shaped bytes is a stable,
        // structured storage-mismatch failure, not a silent reinterpretation.
        XCTAssertThrowsError(
            try configuration.decode(
                JSONCodecFixtureProfile.self,
                from: blobEncoded,
                using: dialect,
                context: resultContext,
                selection: XLValueCodecSelection(explicitCodecKey: jsonCodecFixtureTextKey)
            )
        ) { error in
            guard case .storageMismatch? = error as? XLValueCodecError else {
                return XCTFail("Expected storageMismatch, got \(error)")
            }
        }
    }

    // MARK: - NULL and optionality compose outside the codec

    func testOptionalWrappingComposesOutsideTheNonoptionalCodec() throws {
        let configuration = try XLValueCodingConfiguration(
            registry: try XLValueCodecRegistry().registering(jsonCodecFixtureProfileTextCodec),
            defaultCodecKeys: [jsonCodecFixtureTextKey]
        )

        XCTAssertEqual(
            try configuration.encodeOptional(
                Optional<JSONCodecFixtureProfile>.none,
                using: dialect,
                context: parameterContext
            ),
            .null
        )
        let decodedNil: JSONCodecFixtureProfile? = try configuration.decodeOptional(
            JSONCodecFixtureProfile.self,
            from: .null,
            using: dialect,
            context: resultContext
        )
        XCTAssertNil(decodedNil)

        let decodedSome: JSONCodecFixtureProfile? = try configuration.decodeOptional(
            JSONCodecFixtureProfile.self,
            from: try configuration.encode(
                sampleProfile,
                using: dialect,
                context: parameterContext
            ),
            using: dialect,
            context: resultContext
        )
        XCTAssertEqual(decodedSome, sampleProfile)
    }

    // MARK: - Schema evolution and unknown fields

    func testMissingNewerFieldDecodesUsingItsApplicationDefault() throws {
        let configuration = try XLValueCodingConfiguration(
            registry: try XLValueCodecRegistry().registering(jsonCodecFixtureProfileTextCodec),
            defaultCodecKeys: [jsonCodecFixtureTextKey]
        )
        // Encode a value, then simulate JSON written before `loyaltyPoints`
        // existed by dropping the key from the resulting JSON object. This
        // uses the codec's own encoder for the enum/nested shape instead of
        // a hand-written literal, so the fixture never silently drifts from
        // what the codec actually produces.
        let profile = JSONCodecFixtureProfile(
            name: "Grace Hopper",
            tags: ["engineer"],
            address: nil,
            contact: .email("grace@example.com"),
            loyaltyPoints: 999
        )
        let legacyJSON = try removingKeys(
            ["loyaltyPoints"],
            from: encodedProfileJSON(profile, using: configuration)
        )

        let decoded = try configuration.decode(
            JSONCodecFixtureProfile.self,
            from: .text(legacyJSON),
            using: dialect,
            context: resultContext,
            selection: XLValueCodecSelection(explicitCodecKey: jsonCodecFixtureTextKey)
        )
        XCTAssertEqual(decoded.name, "Grace Hopper")
        XCTAssertNil(decoded.address)
        XCTAssertEqual(decoded.loyaltyPoints, 0)
    }

    func testUnknownFieldsAreIgnoredRatherThanFailing() throws {
        let configuration = try XLValueCodingConfiguration(
            registry: try XLValueCodecRegistry().registering(jsonCodecFixtureProfileTextCodec),
            defaultCodecKeys: [jsonCodecFixtureTextKey]
        )
        let profile = JSONCodecFixtureProfile(
            name: "Katherine Johnson",
            tags: [],
            address: nil,
            contact: .phone("555-0100"),
            loyaltyPoints: 10
        )
        let jsonWithUnknownField = try addingField(
            name: "futureField",
            value: "ignored",
            to: encodedProfileJSON(profile, using: configuration)
        )

        let decoded = try configuration.decode(
            JSONCodecFixtureProfile.self,
            from: .text(jsonWithUnknownField),
            using: dialect,
            context: resultContext,
            selection: XLValueCodecSelection(explicitCodecKey: jsonCodecFixtureTextKey)
        )
        XCTAssertEqual(decoded.name, "Katherine Johnson")
        XCTAssertEqual(decoded.contact, .phone("555-0100"))
        XCTAssertEqual(decoded.loyaltyPoints, 10)
    }

    private func encodedProfileJSON(
        _ profile: JSONCodecFixtureProfile,
        using configuration: XLValueCodingConfiguration
    ) throws -> String {
        // A non-TEXT result here would mean the codec/registry wiring in
        // this test regressed, so fail the test rather than skip it.
        guard case .text(let json) = try configuration.encode(
            profile,
            using: dialect,
            context: parameterContext,
            selection: XLValueCodecSelection(explicitCodecKey: jsonCodecFixtureTextKey)
        ) else {
            throw JSONValueCodecTestFixtureError.expectedTextStorage
        }
        return json
    }

    private func removingKeys(_ keys: Set<String>, from json: String) throws -> String {
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        )
        for key in keys {
            object.removeValue(forKey: key)
        }
        let data = try JSONSerialization.data(withJSONObject: object)
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }

    private func addingField(name: String, value: String, to json: String) throws -> String {
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        )
        object[name] = value
        let data = try JSONSerialization.data(withJSONObject: object)
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }

    // MARK: - Malformed data and structured failures

    func testMalformedJSONFailsWithAStructuredDecodingError() throws {
        let configuration = try XLValueCodingConfiguration(
            registry: try XLValueCodecRegistry().registering(jsonCodecFixtureProfileTextCodec),
            defaultCodecKeys: [jsonCodecFixtureTextKey]
        )

        XCTAssertThrowsError(
            try configuration.decode(
                JSONCodecFixtureProfile.self,
                from: .text("{not valid json"),
                using: dialect,
                context: resultContext
            )
        ) { error in
            guard case .decodingFailed(let codec, let context, let message)? =
                error as? XLValueCodecError else {
                return XCTFail("Expected decodingFailed, got \(error)")
            }
            XCTAssertEqual(codec, jsonCodecFixtureTextKey)
            XCTAssertEqual(context, resultContext)
            XCTAssertTrue(
                message.contains("JSON decoding"),
                "Expected the underlying DecodingError context in: \(message)"
            )
        }
    }

    func testTypeMismatchedJSONFailsWithAStructuredDecodingError() throws {
        let configuration = try XLValueCodingConfiguration(
            registry: try XLValueCodecRegistry().registering(jsonCodecFixtureProfileTextCodec),
            defaultCodecKeys: [jsonCodecFixtureTextKey]
        )
        // "name" should be a string, not a number.
        let badlyTypedJSON = """
            {"name":123,"tags":[],"contact":{"email":"x@example.com"},"loyaltyPoints":0}
            """

        XCTAssertThrowsError(
            try configuration.decode(
                JSONCodecFixtureProfile.self,
                from: .text(badlyTypedJSON),
                using: dialect,
                context: resultContext
            )
        ) { error in
            guard case .decodingFailed? = error as? XLValueCodecError else {
                return XCTFail("Expected decodingFailed, got \(error)")
            }
        }
    }

    func testNonFiniteDoubleFailsWithAStructuredEncodingError() throws {
        let key = XLValueCodecKey(id: "com.example.tests.json-reading", version: 1)
        let codec = XLJSONValueCodec.text(
            key: key,
            valueTypeIdentifier: XLValueTypeIdentifier(rawValue: "com.example.tests.json-reading")
        ) as XLValueCodec<JSONCodecFixtureReading, XLSQLiteDialect>
        let configuration = try XLValueCodingConfiguration(
            registry: try XLValueCodecRegistry().registering(codec),
            defaultCodecKeys: [key]
        )

        XCTAssertThrowsError(
            try configuration.encode(
                JSONCodecFixtureReading(value: .infinity),
                using: dialect,
                context: parameterContext
            )
        ) { error in
            guard case .encodingFailed(let errorCodec, let context, let message)? =
                error as? XLValueCodecError else {
                return XCTFail("Expected encodingFailed, got \(error)")
            }
            XCTAssertEqual(errorCodec, key)
            XCTAssertEqual(context, parameterContext)
            XCTAssertTrue(
                message.contains("JSON encoding"),
                "Expected the underlying EncodingError context in: \(message)"
            )
        }
    }

    // MARK: - Two configurations for one Swift type, no wrapper structs

    func testTwoKeyStrategyConfigurationsCoexistWithoutWrapperStructs() throws {
        let registry = try XLValueCodecRegistry()
            .registering(jsonCodecFixtureMetricDefaultKeysCodec)
            .registering(jsonCodecFixtureMetricSnakeCaseCodec)
        let configuration = try XLValueCodingConfiguration(registry: registry)
        let metric = JSONCodecFixtureMetric(sampleCount: 12, averageValue: 3.5)

        let defaultKeysEncoded = try configuration.encode(
            metric,
            using: dialect,
            context: parameterContext,
            selection: XLValueCodecSelection(
                explicitCodecKey: jsonCodecFixtureMetricDefaultKeysKey
            )
        )
        let snakeCaseEncoded = try configuration.encode(
            metric,
            using: dialect,
            context: parameterContext,
            selection: XLValueCodecSelection(
                explicitCodecKey: jsonCodecFixtureMetricSnakeCaseKey
            )
        )

        guard case .text(let defaultKeysJSON) = defaultKeysEncoded,
              case .text(let snakeCaseJSON) = snakeCaseEncoded else {
            return XCTFail("Expected TEXT storage for both codecs.")
        }
        XCTAssertTrue(defaultKeysJSON.contains("sampleCount"))
        XCTAssertTrue(snakeCaseJSON.contains("sample_count"))
        XCTAssertNotEqual(defaultKeysJSON, snakeCaseJSON)

        XCTAssertEqual(
            try configuration.decode(
                JSONCodecFixtureMetric.self,
                from: defaultKeysEncoded,
                using: dialect,
                context: resultContext,
                selection: XLValueCodecSelection(
                    explicitCodecKey: jsonCodecFixtureMetricDefaultKeysKey
                )
            ),
            metric
        )
        XCTAssertEqual(
            try configuration.decode(
                JSONCodecFixtureMetric.self,
                from: snakeCaseEncoded,
                using: dialect,
                context: resultContext,
                selection: XLValueCodecSelection(
                    explicitCodecKey: jsonCodecFixtureMetricSnakeCaseKey
                )
            ),
            metric
        )
    }
}


private enum JSONValueCodecTestFixtureError: Error {
    case expectedTextStorage
}
