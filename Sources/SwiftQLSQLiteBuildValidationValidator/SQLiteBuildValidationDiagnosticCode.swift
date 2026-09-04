import Foundation


/// Every diagnostic code the validator emits.
///
/// The codes are a contract in both directions: a report reader keys off them,
/// and the validator itself re-matches its own codes to decide whether a schema
/// mismatch short-circuits query preparation and whether a query can be
/// prepared at all. Spelling them as literals at both ends meant a typo in
/// either place silently switched a decision off with nothing failing -- the
/// research prototype shipped for months missing `capability.compile-option`
/// from its preparation-blocking set, which is exactly that bug (#566).
///
/// The raw values are the report's on-disk codes and are frozen: canonical
/// report bytes are a determinism gate.
public enum SQLiteBuildValidationDiagnosticCode:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    // MARK: Schema snapshot identity

    case schemaByteCount = "schema.byte-count"
    case schemaSnapshotSHA = "schema.snapshot-sha"
    case schemaRowCount = "schema.row-count"
    case schemaFingerprint = "schema.fingerprint"

    /// Emitted once per manifest entry when a schema identity mismatch made
    /// preparing that entry pointless.
    case schemaMismatchSkipped = "schema.mismatch-skipped"

    // MARK: Runtime evidence

    case runtimeCapture = "runtime.capture"

    // MARK: Capabilities

    case capabilityDialect = "capability.dialect"
    case capabilityDialectFlags = "capability.dialect-flags"
    case capabilitySQLiteVersion = "capability.sqlite-version"
    case capabilityFunction = "capability.function"
    case capabilityCollation = "capability.collation"
    case capabilityCompileOption = "capability.compile-option"
    case capabilityModule = "capability.module"
    case capabilityExtension = "capability.extension"
    case capabilitySQLiteJSONFunctions = "capability.sqlite-json-functions"
    case capabilityMissing = "capability.missing"

    // MARK: Codecs

    case codecValueType = "codec.value-type"
    case codecDialect = "codec.dialect"
    case codecStorage = "codec.storage"
    case codecMissing = "codec.missing"

    // MARK: Statement preparation

    case statementEmpty = "statement.empty"
    case statementEmbeddedNUL = "statement.embedded-nul"
    case statementMultiple = "statement.multiple"
    case sqlitePrepareFailed = "sqlite.prepare.failed"
    case sqliteFinalizeFailed = "sqlite.finalize.failed"

    // MARK: Parameters and results

    case parameterCount = "parameter.count"
    case parameterKey = "parameter.key"
    case parameterMetadata = "parameter.metadata"
    case parameterSyntax = "parameter.syntax"
    case resultCount = "result.count"
    case resultName = "result.name"

    /// Every code reporting that the live snapshot's identity does not match
    /// the manifest's schema snapshot.
    ///
    /// This scopes the schema-mismatch short-circuit to identity checks
    /// specifically, rather than to every `.schema`-stage `.failed` diagnostic
    /// a future check might add.
    public static let schemaIdentityMismatch: Set<Self> = [
        .schemaByteCount,
        .schemaSnapshotSHA,
        .schemaRowCount,
        .schemaFingerprint,
    ]

    /// Every code whose `unsupported` verdict means the query cannot be
    /// prepared at all, so preparation is skipped rather than attempted and
    /// reported as a SQLite failure the author cannot act on.
    ///
    /// Derived from ``CapabilityKind`` rather than listed by hand: a new
    /// capability kind joins this set by existing, which is the omission that
    /// produced the `capability.compile-option` bug.
    public static let preparationBlocking: Set<Self> = {
        var codes = Set(CapabilityKind.allCases.map(\.diagnosticCode))
        codes.formUnion([.capabilityDialect, .capabilityDialectFlags, .capabilitySQLiteVersion])
        // A capability the validator cannot observe at all is reported as
        // `capability.missing`, and that does not block preparation: the
        // caller may legitimately own it (see the opaque-capability seam).
        codes.remove(.capabilityMissing)
        return codes
    }()
}


/// The kinds of capability a manifest query can require, and the one place an
/// identifier is classified into one.
///
/// The classification used to be written out three times -- once to decide
/// whether a capability is observable at all, once to resolve it against
/// runtime evidence, and once to pick its diagnostic code -- with the same
/// prefixes and the same case folding repeated in each. Any of the three could
/// gain a kind the others did not.
public enum CapabilityKind: CaseIterable, Sendable {

    /// A SQL function, as `function:JSON_VALID`.
    case function

    /// A collating sequence, as `collation:NOCASE`.
    case collation

    /// A SQLite build option, as `compile-option:ENABLE_FTS5`.
    case compileOption

    /// A virtual-table module, as `module:fts5`.
    case module

    /// A loaded extension, as `extension:spellfix`.
    case loadedExtension

    /// SQLite's JSON function family, spelled `sqlite-json-functions` with no
    /// prefix and resolved by probing for `JSON_VALID`.
    case sqliteJSONFunctions

    /// A capability SwiftQL's own SQLite support guarantees --
    /// `named-bindings`, `transactions`, and the like. Always available.
    case intrinsic

    /// Anything else. Not observable from a SQLite connection, so it can only
    /// be satisfied by the caller declaring it explicitly.
    case opaque

    /// Identifiers that name a capability SwiftQL's SQLite support always
    /// provides. Matched after case folding.
    private static let intrinsicIdentifiers: Set<String> = [
        "named-bindings",
        "indexed-bindings",
        "sqlite-core-parser",
        "sqlite-storage-classes",
        "compound-select",
        "recursive-cte",
        "transactions",
    ]

    private static let jsonFunctionsIdentifier = "sqlite-json-functions"

    /// The `<prefix>:` each prefixed kind is spelled with.
    private var prefix: String? {
        switch self {
        case .function:
            return "function:"
        case .collation:
            return "collation:"
        case .compileOption:
            return "compile-option:"
        case .module:
            return "module:"
        case .loadedExtension:
            return "extension:"
        case .sqliteJSONFunctions, .intrinsic, .opaque:
            return nil
        }
    }

    /// Classifies one capability identifier, returning its kind and -- for a
    /// prefixed kind -- the name after the prefix.
    ///
    /// Matching folds case throughout. An identifier like `Function:JSON_VALID`
    /// names the same capability as `function:JSON_VALID`, and classifying the
    /// two differently is how a recognized capability silently becomes
    /// unavailable.
    public static func classify(_ id: String) -> (kind: Self, name: String?) {
        let foldedID = id.lowercased()
        for kind in Self.allCases {
            guard
                let prefix = kind.prefix,
                foldedID.hasPrefix(prefix)
            else {
                continue
            }
            let name = String(id.dropFirst(prefix.count))
            // A bare prefix is still that kind of capability -- it is just
            // one that names nothing, so nothing can resolve it. It keeps the
            // kind, and with it the kind's diagnostic code, rather than being
            // reported as an unrecognized capability.
            return (kind, name.isEmpty ? nil : name)
        }
        if foldedID == Self.jsonFunctionsIdentifier {
            return (.sqliteJSONFunctions, nil)
        }
        if Self.intrinsicIdentifiers.contains(foldedID) {
            return (.intrinsic, nil)
        }
        return (.opaque, nil)
    }

    /// Whether a capability of this kind can be seen on a SQLite connection.
    ///
    /// A kind that cannot is satisfiable only by the caller declaring it, and
    /// its absence can never be proven. `intrinsic` is deliberately on the
    /// unobservable side: those identifiers name guarantees SwiftQL's own
    /// SQLite support makes, not features a connection reports, so with no
    /// runtime evidence captured a caller may still declare one.
    public var isObservable: Bool {
        switch self {
        case .intrinsic, .opaque:
            return false
        case .function, .collation, .compileOption, .module, .loadedExtension,
             .sqliteJSONFunctions:
            return true
        }
    }

    /// The code reported when a capability of this kind is unavailable.
    public var diagnosticCode: SQLiteBuildValidationDiagnosticCode {
        switch self {
        case .function:
            return .capabilityFunction
        case .collation:
            return .capabilityCollation
        case .compileOption:
            return .capabilityCompileOption
        case .module:
            return .capabilityModule
        case .loadedExtension:
            return .capabilityExtension
        case .sqliteJSONFunctions:
            return .capabilitySQLiteJSONFunctions
        case .intrinsic, .opaque:
            return .capabilityMissing
        }
    }
}
