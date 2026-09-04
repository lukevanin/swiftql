import Foundation


/// The one canonical JSON encoding used for every build-validation artifact.
///
/// Both the manifest and the report are byte-determinism gates: the plugin
/// treats an unchanged report as "nothing to re-run", and CI asserts that two
/// runs over the same inputs produce identical bytes. Keys are sorted so the
/// encoding does not depend on declaration order, slashes are left unescaped so
/// a path reads as a path, and the output ends in exactly one newline so a
/// file's last byte does not depend on the encoder's own trailing whitespace.
///
/// One implementation, not two (#566): the manifest and validator each carried
/// a verbatim copy. Determinism agreeing across the two artifacts is the
/// property being gated, so it cannot rest on two definitions staying equal.
package enum SQLiteBuildValidationCanonicalJSON {

    package static func encode<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys,
            .withoutEscapingSlashes,
        ]
        var data = try encoder.encode(value)
        while data.last == 0x0A {
            data.removeLast()
        }
        data.append(0x0A)
        return data
    }
}


/// Sorts and deduplicates a list of identifiers.
///
/// Every list a build-validation artifact carries goes through this. The
/// artifacts are compared byte for byte, so two invocations that declare the
/// same identifiers in a different order, or one of them twice, have to encode
/// identically.
package func sqliteBuildValidationSortedUnique(_ values: [String]) -> [String] {
    Array(Set(values)).sorted()
}
