import Foundation

import GRDB
import SwiftQL
import SwiftQLSQLiteBuildValidationManifest
import SwiftQLSQLiteBuildValidationValidator
import TodoKit

// Regenerates the two files SwiftQL's build-time validation plugin reads out
// of the target it is attached to. That is TodoKitBuildValidation today, and
// the destination is an argument rather than a constant so that folding the
// validation target back into TodoKit (see BuildValidation.swift) needs no
// change here:
//
//   swiftql-build-validation-snapshot.sqlite — the demo's schema, as a
//       checked-in SQLite file the validator prepares statements against.
//   swiftql-build-validation-manifest.json  — one entry per declared query,
//       carrying the rendered SQL and its parameter and result metadata.
//
// SwiftQL does not yet generate a manifest from `@SQLQueries` declarations,
// so the query list below mirrors the declarations in TodoKit by hand. Both
// sides render their SQL through the same SwiftQL statement builders, so a
// schema change that invalidates a query fails the demo's build rather than
// passing silently.

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data(
        "usage: todo-validation-manifest TARGET_DIRECTORY\n".utf8
    ))
    exit(64)
}

let targetDirectory = URL(fileURLWithPath: arguments[1], isDirectory: true)
let snapshotURL = targetDirectory
    .appendingPathComponent("swiftql-build-validation-snapshot.sqlite")
let manifestURL = targetDirectory
    .appendingPathComponent("swiftql-build-validation-manifest.json")

let encoder = XLiteEncoder(dialect: XLSQLiteDialect())

/// Namespaces every entry this generator writes.
let namespace = "todo-demo"

/// A declared query, paired with the metadata the manifest needs about it.
struct ManifestedQuery {
    /// The query's local name. The manifest namespaces it: the entry id
    /// becomes `todo-demo.<name>` and the definition identity
    /// `todo-demo/<name>@1`, matching how SwiftQL's own manifests are keyed.
    let name: String
    let statement: any XLEncodable
    let cardinality: XLQueryCardinality
    /// Parameter name to its Swift type and SQLite storage. Logical and
    /// physical indices come from scanning the rendered SQL, so they cannot
    /// drift out of step with the statement.
    var parameters: [String: ParameterKind] = [:]
    let results: [SQLiteBuildValidationResultEntry]
}

/// The Swift-to-SQLite shapes the demo's parameters take.
enum ParameterKind {
    case text
    case integer

    var valueTypeIdentifier: String {
        switch self {
        case .text: return "swift.string"
        case .integer: return "swift.int"
        }
    }

    var valueTypeName: String {
        switch self {
        case .text: return "Swift.String"
        case .integer: return "Swift.Int"
        }
    }

    var storageIdentifier: String {
        switch self {
        case .text: return "text"
        case .integer: return "integer"
        }
    }
}

/// The `:name` placeholders in a rendered statement, in first-encounter
/// order — which is the order SQLite assigns bind positions in.
///
/// Quoted text is skipped: an inlined date literal such as
/// `'2100-01-01T00:00:00.000Z'` contains colons that are not placeholders.
func placeholderNames(in sql: String) -> [String] {
    var names: [String] = []
    var seen: Set<String> = []
    let characters = Array(sql)
    var index = 0

    func skipQuoted(_ quote: Character) {
        index += 1
        while index < characters.count {
            if characters[index] == quote {
                // A doubled quote is an escaped one, not the end.
                if index + 1 < characters.count, characters[index + 1] == quote {
                    index += 2
                    continue
                }
                index += 1
                return
            }
            index += 1
        }
    }

    while index < characters.count {
        let character = characters[index]
        if character == "'" || character == "\"" {
            skipQuoted(character)
            continue
        }
        guard character == ":" else {
            index += 1
            continue
        }
        var end = index + 1
        while end < characters.count,
              characters[end].isLetter
                || characters[end].isNumber
                || characters[end] == "_" {
            end += 1
        }
        let name = String(characters[(index + 1)..<end])
        if !name.isEmpty, seen.insert(name).inserted {
            names.append(name)
        }
        index = max(end, index + 1)
    }
    return names
}


/// One value in a returned row.
func resultEntry(
    index: Int,
    alias: String,
    valueTypeIdentifier: String,
    valueTypeName: String,
    storageIdentifier: String,
    nullability: String = "required"
) -> SQLiteBuildValidationResultEntry {
    SQLiteBuildValidationResultEntry(
        index: index,
        identity: "result/\(alias)",
        declaredAlias: alias,
        valueTypeIdentifier: valueTypeIdentifier,
        valueTypeName: valueTypeName,
        nullability: nullability,
        codec: nil,
        storageIdentifier: storageIdentifier
    )
}


// MARK: - Schema

let schemaStatements: [any XLEncodable] = [
    sqlCreate(TodoList.self),
    sqlCreate(Todo.self),
    sqlCreate(Tag.self),
    sqlCreate(TodoTag.self),
]

// MARK: - Declared queries

// One entry per declared query in TodoReads.swift, declared here in the same
// order. SQLiteBuildValidationManifest.canonicalJSONData() sorts the query
// list when encoding, so the emitted manifest JSON does not preserve this
// order -- only the generator's own declarations mirror TodoReads.swift.
let uuidResult = { (index: Int, alias: String) in
    resultEntry(
        index: index,
        alias: alias,
        valueTypeIdentifier: "swift.string",
        valueTypeName: "Swift.String",
        storageIdentifier: "text"
    )
}
let textResult = uuidResult
let intResult = { (index: Int, alias: String) in
    resultEntry(
        index: index,
        alias: alias,
        valueTypeIdentifier: "swift.int",
        valueTypeName: "Swift.Int",
        storageIdentifier: "integer"
    )
}
let boolResult = { (index: Int, alias: String) in
    resultEntry(
        index: index,
        alias: alias,
        valueTypeIdentifier: "swift.bool",
        valueTypeName: "Swift.Bool",
        storageIdentifier: "integer"
    )
}
let nullableTextResult = { (index: Int, alias: String) in
    resultEntry(
        index: index,
        alias: alias,
        valueTypeIdentifier: "swift.string",
        valueTypeName: "Swift.String",
        storageIdentifier: "text",
        nullability: "nullable"
    )
}

let queries: [ManifestedQuery] = [
    ManifestedQuery(
        name: "todo-lists",
        statement: sql { schema in
            let list = schema.table(TodoList.self)
            Select(list)
            From(list)
            OrderBy(list.position.ascending(), list.name.ascending())
        },
        cardinality: .many,
        results: [
            uuidResult(0, "id"),
            textResult(1, "name"),
            intResult(2, "position"),
            textResult(3, "createdAt"),
        ]
    ),
    ManifestedQuery(
        name: "todos",
        statement: sql { schema in
            let todo = schema.table(Todo.self)
            Select(todo)
            From(todo)
            OrderBy(todo.createdAt.ascending(), todo.position.ascending())
        },
        cardinality: .many,
        results: [
            uuidResult(0, "id"),
            uuidResult(1, "listID"),
            textResult(2, "title"),
            textResult(3, "notes"),
            nullableTextResult(4, "dueAt"),
            intResult(5, "priority"),
            boolResult(6, "isCompleted"),
            intResult(7, "position"),
            textResult(8, "createdAt"),
        ]
    ),
    ManifestedQuery(
        name: "todo-list-by-id",
        statement: sql { schema in
            let list = schema.table(TodoList.self)
            Select(list)
            From(list)
            Where(list.id == XLNamedBindingReference<TodoUUID>(name: "id"))
        },
        cardinality: .zeroOrOne,
        parameters: ["id": .text],
        results: [
            uuidResult(0, "id"),
            textResult(1, "name"),
            intResult(2, "position"),
            textResult(3, "createdAt"),
        ]
    ),
    ManifestedQuery(
        name: "todo-by-id",
        statement: sql { schema in
            let todo = schema.table(Todo.self)
            Select(todo)
            From(todo)
            Where(todo.id == XLNamedBindingReference<TodoUUID>(name: "id"))
        },
        cardinality: .zeroOrOne,
        parameters: ["id": .text],
        results: [
            uuidResult(0, "id"),
            uuidResult(1, "listID"),
            textResult(2, "title"),
            textResult(3, "notes"),
            nullableTextResult(4, "dueAt"),
            intResult(5, "priority"),
            boolResult(6, "isCompleted"),
            intResult(7, "position"),
            textResult(8, "createdAt"),
        ]
    ),
    ManifestedQuery(
        name: "filtered-todos",
        statement: TodoFilteredRead.statement,
        cardinality: .many,
        parameters: [
            "listID": .text,
            "includesCompleted": .integer,
            "includesActive": .integer,
            "overdueOnly": .integer,
            "referenceDate": .text,
            "searchPattern": .text,
            "sortOrder": .integer,
        ],
        results: [
            uuidResult(0, "id"),
            uuidResult(1, "listID"),
            textResult(2, "title"),
            textResult(3, "notes"),
            nullableTextResult(4, "dueAt"),
            intResult(5, "priority"),
            boolResult(6, "isCompleted"),
            intResult(7, "position"),
            textResult(8, "createdAt"),
        ]
    ),
    ManifestedQuery(
        name: "tags-for-todo",
        statement: sql { schema in
            let link = schema.table(TodoTag.self)
            let tag = schema.table(Tag.self)
            Select(TodoTagPair.columns(
                todoID: link.todoID,
                tagID: tag.id,
                tagName: tag.name
            ))
            From(link)
            Join.Inner(tag, on: tag.id == link.tagID)
            Where(link.todoID == XLNamedBindingReference<TodoUUID>(name: "todoID"))
            OrderBy(tag.name.ascending())
        },
        cardinality: .many,
        parameters: ["todoID": .text],
        results: [
            uuidResult(0, "todoID"),
            uuidResult(1, "tagID"),
            textResult(2, "tagName"),
        ]
    ),
    ManifestedQuery(
        name: "tags-for-list",
        statement: sql { schema in
            let todo = schema.table(Todo.self)
            let link = schema.table(TodoTag.self)
            let tag = schema.table(Tag.self)
            Select(TodoTagPair.columns(
                todoID: link.todoID,
                tagID: tag.id,
                tagName: tag.name
            ))
            From(link)
            Join.Inner(todo, on: todo.id == link.todoID)
            Join.Inner(tag, on: tag.id == link.tagID)
            Where(todo.listID == XLNamedBindingReference<TodoUUID>(name: "listID"))
            OrderBy(tag.name.ascending())
        },
        cardinality: .many,
        parameters: ["listID": .text],
        results: [
            uuidResult(0, "todoID"),
            uuidResult(1, "tagID"),
            textResult(2, "tagName"),
        ]
    ),
    ManifestedQuery(
        name: "list-counts",
        statement: sql { schema in
            let todo = schema.table(Todo.self)
            Select(TodoListCounts.columns(
                listID: todo.listID,
                openCount: when(todo.isCompleted == false, then: 1)
                    .else(0)
                    .sumOrNull() ?? 0,
                totalCount: all().count()
            ))
            From(todo)
            GroupBy(todo.listID)
        },
        cardinality: .many,
        results: [
            uuidResult(0, "listID"),
            intResult(1, "openCount"),
            intResult(2, "totalCount"),
        ]
    ),
    ManifestedQuery(
        name: "tags",
        statement: sql { schema in
            let tag = schema.table(Tag.self)
            Select(tag)
            From(tag)
            OrderBy(tag.name.ascending())
        },
        cardinality: .many,
        results: [
            uuidResult(0, "id"),
            textResult(1, "name"),
        ]
    ),
    ManifestedQuery(
        name: "todo-tags",
        statement: sql { schema in
            let link = schema.table(TodoTag.self)
            Select(link)
            From(link)
        },
        cardinality: .many,
        results: [
            uuidResult(0, "todoID"),
            uuidResult(1, "tagID"),
        ]
    ),
]

// MARK: - Snapshot

try? FileManager.default.removeItem(at: snapshotURL)
for suffix in ["-journal", "-wal", "-shm"] {
    let sidecar = URL(fileURLWithPath: snapshotURL.path + suffix)
    try? FileManager.default.removeItem(at: sidecar)
}

// A `DatabaseQueue` leaves the snapshot in rollback-journal mode with no
// sidecar files, which is what the validator requires of an immutable
// checked-in artifact. A WAL-mode file would need its `-shm` companion to
// open read-only.
let snapshotQueue = try DatabaseQueue(path: snapshotURL.path)
try snapshotQueue.write { database in
    for statement in schemaStatements {
        try database.execute(sql: encoder.makeValidatedSQL(statement).sql)
    }
}
try snapshotQueue.close()

let snapshotData = try Data(contentsOf: snapshotURL)

// MARK: - Manifest

let queryEntries = try queries.map { query -> SQLiteBuildValidationQueryEntry in
    let sql = try encoder.makeValidatedSQL(query.statement).sql
    let names = placeholderNames(in: sql)
    let parameters = names.enumerated().map { index, name -> SQLiteBuildValidationParameterEntry in
        guard let kind = query.parameters[name] else {
            FileHandle.standardError.write(Data(
                "error: \(query.name) renders :\(name) but declares no kind for it\n".utf8
            ))
            exit(1)
        }
        return SQLiteBuildValidationParameterEntry(
            logicalIndex: index,
            physicalIndex: index + 1,
            identity: "parameter/\(name)",
            keyKind: .named,
            keyName: name,
            keyIndex: nil,
            valueTypeIdentifier: kind.valueTypeIdentifier,
            valueTypeName: kind.valueTypeName,
            nullability: "required",
            codec: nil,
            storageIdentifier: kind.storageIdentifier
        )
    }
    if parameters.count != query.parameters.count {
        FileHandle.standardError.write(Data(
            "error: \(query.name) declares \(query.parameters.count) parameters but renders \(parameters.count)\n".utf8
        ))
        exit(1)
    }
    return SQLiteBuildValidationQueryEntry(
        id: "\(namespace).\(query.name)",
        definitionIdentity: "\(namespace)/\(query.name)@1",
        descriptorIdentity: "swiftql-query-v1-todo-demo",
        sql: sql,
        dialectIdentifier: XLSQLiteDialect.identity.rawValue,
        cardinality: query.cardinality.rawValue,
        parameters: parameters,
        results: query.results
    )
}

func manifest(
    schemaRowCount: Int,
    schemaFingerprint: String
) -> SQLiteBuildValidationManifest {
    SQLiteBuildValidationManifest(
        conformanceInventoryVersion: "190.1.0",
        combinatorialManifestVersion: "c191-v2",
        schemaSnapshot: SQLiteBuildValidationSchemaSnapshot(
            identifier: "todo-demo.schema",
            databaseSHA256: SQLiteBuildValidationSHA256.hexDigest(
                of: snapshotData
            ),
            databaseByteCount: snapshotData.count,
            schemaRowCount: schemaRowCount,
            schemaFingerprint: schemaFingerprint
        ),
        queries: queryEntries
    )
}

// The snapshot's own row count and schema fingerprint are whatever the
// validator observes when it opens the file, so ask it rather than
// recomputing them here. The provisional values below only have to be
// structurally valid for that first pass.
let probeReport = try SQLiteBuildValidator.validate(
    manifest: manifest(
        schemaRowCount: 1,
        schemaFingerprint: String(repeating: "0", count: 16)
    ),
    againstDatabaseAt: snapshotURL
)
guard let observed = probeReport.runtimeMetadata else {
    FileHandle.standardError.write(Data(
        "error: the validator captured no SQLite runtime metadata\n".utf8
    ))
    exit(1)
}

let finalManifest = manifest(
    schemaRowCount: observed.schemaRowCount,
    schemaFingerprint: observed.schemaFNV1A64
)
try finalManifest.canonicalJSONData().write(to: manifestURL, options: .atomic)

// Prove the artifacts this run just wrote actually pass, so a regeneration
// can never leave the repository in a state the plugin rejects.
let finalReport = try SQLiteBuildValidator.validate(
    manifest: finalManifest,
    againstDatabaseAt: snapshotURL
)
guard finalReport.overallVerdict == .passed else {
    FileHandle.standardError.write(try finalReport.canonicalJSONData())
    FileHandle.standardError.write(Data("\n".utf8))
    exit(1)
}

print("wrote \(snapshotURL.path)")
print("wrote \(manifestURL.path)")
