# JSON

Store, read, and change JSON documents inside SQLite.

## Overview

SQLite has no JSON storage class. A JSON document is ordinary `TEXT`, or a
`BLOB` when it is stored in SQLite's binary form, JSONB. What SQLite adds is a
set of functions and two operators that read and rewrite those documents in
place, so a query can reach inside a document instead of loading it, decoding
it in Swift, and writing the whole thing back.

SwiftQL exposes that surface as typed expressions. Nothing here is a raw-SQL
escape hatch: a path is a text operand, and a written value is a bound
parameter or an escaped literal like any other.

## Declaring a column that holds JSON

A JSON column is a `String` column. Nothing marks it as JSON, because nothing
in SQLite does either.

<!-- test: XLDocumentationTests.testDocumentationJSON -->
```swift
@SQLTable
struct Note: Identifiable {

    let id: String

    let title: String

    /// A JSON object, for example:
    /// `{"tags":["home","urgent"],"priority":2,"due":null}`
    let metadata: String
}
```

Use ``XLExpression/validJSONOrNull()`` in a `CHECK` constraint or a test if
the column must hold well-formed JSON. SQLite does not enforce that by itself.

## Naming a value with a path

A path names one element inside a document. Build it from segments rather than
writing the string by hand:

<!-- test: XLDocumentationTests.testDocumentationJSON -->
```swift
let priority = XLJSONPath.root.key("priority")   // $.priority
let firstTag = XLJSONPath.root.key("tags").index(0)  // $.tags[0]
let lastTag = XLJSONPath.root.key("tags").last   // $.tags[#-1]
```

``XLJSONPath`` quotes a key only where SQLite's path grammar needs it, so
`key("a.b")` names the single key `a.b` instead of reading as "b inside a".
See the type's documentation for the one key shape that is not portable across
SQLite versions.

## Reading a value

There are three ways to read, and they differ in what they return.

<!-- test: XLDocumentationTests.testDocumentationJSON -->
```swift
let statement = sql { schema in
    let note = schema.table(Note.self)
    Select(
        note.metadata.jsonValue(
            at: XLJSONPath.root.key("priority"),
            as: Int.self
        )
    )
    From(note)
}
```

``XLExpression/jsonValue(at:as:)`` renders SQLite's `->>` operator and returns
a SQL value in the type you ask for. A selected string arrives without its
JSON quotes.

``XLExpression/jsonElement(at:)`` renders `->` and returns JSON text instead,
so a selected string keeps its quotes and a JSON `null` arrives as the four
characters `null`. Reach for it when the element is itself a document you want
to pass to another JSON function.

``XLExpression/jsonExtract(at:as:)`` is the function form of `->>`. Its
value is that it also takes more than one path, in which case SQLite collects
the results into a JSON array:

<!-- test: XLDocumentationTests.testDocumentationJSON -->
```swift
let pair = sql { schema in
    let note = schema.table(Note.self)
    Select(
        note.metadata.jsonExtract(
            at: XLJSONPath.root.key("priority"),
            XLJSONPath.root.key("tags")
        )
    )
    From(note)
}
```

Every read is optional, because a path that matches nothing gives SQL `NULL`
in all three. A JSON `null` is where they part:

| Read | A path that matches nothing | A JSON `null` |
| --- | --- | --- |
| ``XLExpression/jsonValue(at:as:)`` | SQL `NULL` | SQL `NULL` |
| ``XLExpression/jsonExtract(at:as:)`` | SQL `NULL` | SQL `NULL` |
| ``XLExpression/jsonElement(at:)`` | SQL `NULL` | the text `null` |

The multiple-path `jsonExtract(at:_:_:)` is different again: it returns an
array, so a path that matches nothing contributes a JSON `null` entry rather
than making the whole result `NULL`. The array has one entry per path
whatever happens, which is what keeps entry order and path order the same.

## Changing a document

The mutation functions return a new document. They do not write to the table
by themselves; put one in an `Update` to store the result.

<!-- test: XLDocumentationTests.testDocumentationJSON -->
```swift
let promote = sql { schema in
    let note = schema.into(Note.self)
    Update(note)
    Setting(note) { row in
        row.metadata = note.metadata
            .jsonSetting((XLJSONPath.root.key("priority"), 1))
            .coalesce(note.metadata)
    }
    Where(note.id == "note-1")
}
```

Every mutation result is optional, because SQLite returns `NULL` when the
document is `NULL`. `metadata` is declared non-optional here, so `coalesce`
supplies the original document for that case and the types line up. A column
declared `String?` takes the result directly.

The five functions differ only in when they write:

| Function | Writes |
| --- | --- |
| ``XLExpression/jsonInserting(_:_:)`` | Only where nothing is there |
| ``XLExpression/jsonReplacing(_:_:)`` | Only where something is there |
| ``XLExpression/jsonSetting(_:_:)`` | Either way |
| ``XLExpression/jsonRemoving(at:_:)`` | Deletes each named path |
| ``XLExpression/jsonPatched(with:)`` | Applies an RFC 7396 merge patch |

## Building JSON in a query

`jsonArray` and `jsonObject` build a document from expressions:

<!-- test: XLDocumentationTests.testDocumentationJSON -->
```swift
let summary = sql { schema in
    let note = schema.table(Note.self)
    Select(jsonObject(("id", note.id), ("title", note.title)))
    From(note)
}
```

A value that is already JSON is added as a quoted string, not as a nested
document. Pass it through ``XLExpression/minifiedJSON()`` first to nest it.

Two aggregates collect a whole result set:

<!-- test: XLDocumentationTests.testDocumentationJSON -->
```swift
let titles = sql { schema in
    let note = schema.table(Note.self)
    Select(note.title.jsonGroupArray())
    From(note)
}
```

``jsonGroupObject(name:value:)`` does the same for name/value pairs. Neither
returns `NULL`: an empty group gives `[]` and `{}`.

## Inspecting a document

``XLExpression/jsonType()`` reports what is at the root or at a path,
``XLExpression/jsonArrayLength()`` counts an array,
``XLExpression/validJSONOrNull()`` reports whether the text parses, and
``XLExpression/jsonErrorPosition()`` says where it stopped parsing when it
does not. ``XLExpression/minifiedJSON()`` and ``XLExpression/prettyJSON()``
normalise the layout, and ``XLExpression/jsonQuoted()`` turns a SQL value into
its JSON form.

<!-- test: XLDocumentationTests.testDocumentationJSON -->
```swift
let malformed = sql { schema in
    let note = schema.table(Note.self)
    Select(note.metadata.jsonErrorPosition())
    From(note)
    Where(note.metadata.validJSONOrNull() == false)
}
```

## When JSONB is worth using

JSONB is the same data in SQLite's parsed form, stored as a `BLOB`. Every
`jsonb_` function has a `json_` twin that behaves identically except for the
result's representation.

Storing JSONB is worth it when the same document is read by more than one
expression in a statement, or read far more often than it is written, because
SQLite skips reparsing the text each time. It is not worth it when the column
is mostly written, or when the raw text has to stay readable to something
other than SQLite.

<!-- test: XLDocumentationTests.testDocumentationJSON -->
```swift
let compact = sql { schema in
    let note = schema.table(Note.self)
    Select(note.metadata.minifiedJSONB())
    From(note)
}
```

The functions whose result is a SQL value rather than JSON — `json_type`,
`json_valid`, `json_array_length`, `json_quote`, `json_error_position` and
`json_pretty` — have no JSONB twin. They read a JSONB input directly.

## SQLite versions

Not every part of this surface is available on every SQLite. SwiftQL renders
the SQL either way; it is the engine that refuses.

| Feature | Needs |
| --- | --- |
| `json_extract`, the mutation functions, the aggregates, `json_type`, `json_valid`, `json_array_length`, `json_quote` | SQLite 3.9.0 |
| `->` and `->>` | SQLite 3.38.0 |
| `json_error_position` | SQLite 3.42.0 |
| `json_valid(X, F)` with flags, and every `jsonb_` function | SQLite 3.45.0 |
| `json_pretty` | SQLite 3.46.0 |

Apple's platforms ship the system SQLite, and its version follows the OS
rather than the application. Check the runtime before depending on a newer
function, or link a SQLite of your own.
