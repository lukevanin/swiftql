import Foundation
@testable import SwiftQL


/// A representative nested `Codable` value used by the JSON codec contract
/// and GRDB round-trip tests: a struct with a nested struct, an array, an
/// optional, and an enum with an associated value.
struct JSONCodecFixtureAddress: Codable, Equatable {
    var street: String
    var city: String
}


enum JSONCodecFixtureContactMethod: Codable, Equatable {
    case email(String)
    case phone(String)
}


struct JSONCodecFixtureProfile: Codable, Equatable {
    var name: String
    var tags: [String]
    var address: JSONCodecFixtureAddress?
    var contact: JSONCodecFixtureContactMethod
    var loyaltyPoints: Int

    enum CodingKeys: String, CodingKey {
        case name
        case tags
        case address
        case contact
        case loyaltyPoints
    }

    init(
        name: String,
        tags: [String],
        address: JSONCodecFixtureAddress?,
        contact: JSONCodecFixtureContactMethod,
        loyaltyPoints: Int = 0
    ) {
        self.name = name
        self.tags = tags
        self.address = address
        self.contact = contact
        self.loyaltyPoints = loyaltyPoints
    }

    // Demonstrates schema evolution: `loyaltyPoints` was added after JSON
    // rows already existed. Older stored JSON that omits the key still
    // decodes, using an explicit default instead of failing.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        tags = try container.decode([String].self, forKey: .tags)
        address = try container.decodeIfPresent(
            JSONCodecFixtureAddress.self,
            forKey: .address
        )
        contact = try container.decode(
            JSONCodecFixtureContactMethod.self,
            forKey: .contact
        )
        loyaltyPoints = try container.decodeIfPresent(
            Int.self,
            forKey: .loyaltyPoints
        ) ?? 0
    }
}


/// A plain-keyed type with no explicit `CodingKeys`, used to show two JSON
/// codecs for the same Swift type with different key strategies producing
/// different, independently selectable representations.
struct JSONCodecFixtureMetric: Codable, Equatable {
    let sampleCount: Int
    let averageValue: Double
}


/// A type whose default encoding can fail: `JSONEncoder` rejects non-finite
/// `Double` values by default, so this exercises the encoder-failure path.
struct JSONCodecFixtureReading: Codable, Equatable {
    let value: Double
}


let jsonCodecFixtureProfileType = XLValueTypeIdentifier(
    rawValue: "com.example.tests.json-profile"
)

let jsonCodecFixtureTextKey = XLValueCodecKey(
    id: "com.example.tests.json-profile.text",
    version: 1
)

let jsonCodecFixtureBlobKey = XLValueCodecKey(
    id: "com.example.tests.json-profile.blob",
    version: 1
)

let jsonCodecFixtureProfileTextCodec = XLJSONValueCodec.text(
    key: jsonCodecFixtureTextKey,
    valueTypeIdentifier: jsonCodecFixtureProfileType
) as XLValueCodec<JSONCodecFixtureProfile, XLSQLiteDialect>

let jsonCodecFixtureProfileBlobCodec = XLJSONValueCodec.blob(
    key: jsonCodecFixtureBlobKey,
    valueTypeIdentifier: jsonCodecFixtureProfileType
) as XLValueCodec<JSONCodecFixtureProfile, XLSQLiteDialect>


let jsonCodecFixtureMetricType = XLValueTypeIdentifier(
    rawValue: "com.example.tests.json-metric"
)

let jsonCodecFixtureMetricDefaultKeysKey = XLValueCodecKey(
    id: "com.example.tests.json-metric.default-keys",
    version: 1
)

let jsonCodecFixtureMetricSnakeCaseKey = XLValueCodecKey(
    id: "com.example.tests.json-metric.snake-case",
    version: 1
)

let jsonCodecFixtureMetricDefaultKeysCodec = XLJSONValueCodec.text(
    key: jsonCodecFixtureMetricDefaultKeysKey,
    valueTypeIdentifier: jsonCodecFixtureMetricType
) as XLValueCodec<JSONCodecFixtureMetric, XLSQLiteDialect>

let jsonCodecFixtureMetricSnakeCaseCodec = XLJSONValueCodec.text(
    key: jsonCodecFixtureMetricSnakeCaseKey,
    valueTypeIdentifier: jsonCodecFixtureMetricType,
    configuration: XLJSONCodecConfiguration(
        keyEncodingStrategy: .convertToSnakeCase,
        keyDecodingStrategy: .convertFromSnakeCase
    )
) as XLValueCodec<JSONCodecFixtureMetric, XLSQLiteDialect>
