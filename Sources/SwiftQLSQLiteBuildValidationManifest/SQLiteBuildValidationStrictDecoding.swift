import Foundation


/// Reads only a document's `format_version`, ignoring every other key.
///
/// Both checked-in build-validation inputs (the manifest and the plan
/// suppression file) decode this first and dispatch on it, so a document in a
/// version this reader does not know reports an unsupported version instead of
/// whatever decoding error its unfamiliar body happens to trigger.
package struct SQLiteBuildValidationFormatVersionProbe: Decodable {

    package let formatVersion: Int

    package static func decode(_ data: Data) throws -> Int {
        try JSONDecoder().decode(Self.self, from: data).formatVersion
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion = "format_version"
    }
}


/// Returns the coding path of the first key in `decoder`'s JSON object that
/// `Keys` does not define, or `nil` when every key is known.
///
/// Synthesized `Decodable` silently ignores unknown keys, so a misspelled
/// optional key decodes as "absent" and quietly disables whatever it was meant
/// to configure. Every build-validation input type calls this from its own
/// `init(from:)` so a typo fails closed. The first unknown key is chosen in
/// sorted order so the reported path does not vary between runs.
package func sqliteBuildValidationUnknownKeyPath<Keys>(
    in decoder: any Decoder,
    allowedKeys: Keys.Type
) throws -> String? where Keys: CodingKey & CaseIterable {
    let allowed = Set(Keys.allCases.map(\.stringValue))
    let present = try decoder.container(keyedBy: SQLiteBuildValidationAnyKey.self)
        .allKeys
        .map(\.stringValue)
    guard let unknown = present.filter({ !allowed.contains($0) }).sorted().first else {
        return nil
    }
    return sqliteBuildValidationCodingPathDescription(
        decoder.codingPath + [SQLiteBuildValidationAnyKey(stringValue: unknown)]
    )
}


/// Spells a coding path the way a reader locates it in the JSON:
/// `queries[0].parameters[1].key_nmae`.
package func sqliteBuildValidationCodingPathDescription(
    _ path: [any CodingKey]
) -> String {
    var description = ""
    for key in path {
        if let index = key.intValue {
            description += "[\(index)]"
        } else {
            description += description.isEmpty ? key.stringValue : ".\(key.stringValue)"
        }
    }
    return description
}


private struct SQLiteBuildValidationAnyKey: CodingKey {

    let stringValue: String
    let intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}
