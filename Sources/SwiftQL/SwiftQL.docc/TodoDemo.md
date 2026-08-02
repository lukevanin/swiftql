# The to-do demo

Read a whole application built on SwiftQL, one layer at a time.

## Overview

The other articles cover one topic each. This one walks through an application
where those topics have to work together: a to-do app for iOS 17 and macOS 14
whose entire data layer is SwiftQL, living in the repository at
[`Examples/TodoApp`](https://github.com/lukevanin/swiftql/tree/main/Examples/TodoApp).

Open `Examples/TodoApp/TodoApp.xcodeproj` and run the **TodoApp** scheme. There
is nothing to configure — the app creates its database and seeds it the first
time it launches. SwiftQL is a local path dependency on the repository, so the
demo always builds the working tree, and CI builds and tests it on every pull
request.

Every excerpt below is cut verbatim from the demo's sources, and a test in this
package fails if one of them stops matching.

Where the tutorial in <doc:/tutorials/SwiftQL> has you type a query from an
empty file, this article explains one that already exists. Read the tutorial to
learn the API; read this to see what it looks like at application scale.

## The schema

Four tables: lists, to-dos, tags, and the many-to-many join between to-dos and
tags. Each is an ordinary Swift struct.

<!-- source: Examples/TodoApp/TodoKit/Sources/TodoKit/Schema.swift -->
```swift
@SQLTable
public struct TodoList: Equatable, Identifiable, Sendable {

    public var id: TodoUUID

    public var name: String

    /// Where the list sits in the sidebar. Renumbered when a list moves.
    public var position: Int

    public var createdAt: TodoDate
}
```

`TodoUUID` and `TodoDate` are not intrinsic SwiftQL types. SwiftQL binds
`Bool`, `Int`, `Double`, `String`, and `Data`; anything else reaches SQLite
through a type that says how to read it, bind it, and render it. That is
`XLCustomType`, and conforming to `XLComparable` alongside it is what makes
`==` and `<` available in a `Where` clause. See <doc:CustomTypes> for the full
contract and <doc:NumericDateCodecs> for the codecs the demo's stored forms
match. Priority is an `XLEnum` — see <doc:Enums>.

## Declared reads

The demo's reads are functions. One `@SQLQueries` extension holds all of them,
which is the form <doc:DeclaredQueries> recommends for product code.

This is the aggregate behind the sidebar's counts. Open and total per list, in
one grouped query rather than a count per list:

<!-- source: Examples/TodoApp/TodoKit/Sources/TodoKit/TodoReads.swift -->
```swift
        func listCounts() -> [TodoListCounts] {
            sqlResult { schema in
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
            }
        }
```

The demo also joins across the link table to fetch a to-do's tags, and does it
once for a whole list rather than once per row.

## One query, every combination

The list view offers four filters, three sort orders, and a search box. That is
not twelve queries plus a search variant. It is one statement.

The filter arrives as three booleans the `Where` clause reads, rather than as a
mode the query branches on:

<!-- source: Examples/TodoApp/TodoKit/Sources/TodoKit/TodoQuery.swift -->
```swift
    var flags: (includesCompleted: Bool, includesActive: Bool, overdueOnly: Bool) {
        switch self {
        case .all:
            return (true, true, false)
        case .active:
            return (false, true, false)
        case .completed:
            return (true, false, false)
        case .overdue:
            return (false, true, true)
        }
    }
```

Search is always applied, with `%` standing in for an empty box, so the clause
is never added or removed — only sometimes vacuous. Sort works the same way:
each `OrderBy` term is a conditional on the sort parameter, and a term whose
condition is false collapses to a constant that orders every row equally, so it
contributes nothing and the next term decides.

This is the one read in the demo that is not a declared query. A declared
query's frozen-literal guard rejects a parameter passed as an argument to a
call, and `like(_:)` is a method — so text search cannot appear in a
declaration. The demo uses named bindings for that statement instead, and says
so where it does.

## Writes that return their row

Create, update, toggle, and delete all use `RETURNING`, so a caller gets the
row the database holds without fetching again:

<!-- source: Examples/TodoApp/TodoKit/Sources/TodoKit/TodoStore.swift -->
```swift
    @discardableResult
    public func setCompleted(_ isCompleted: Bool, todoID id: TodoUUID) throws -> Todo {
        let schema = XLSchema()
        let table = schema.into(Todo.self)
        return try written(
            database.makeRequest(
                with: update(table)
                    .set { row in row.isCompleted = isCompleted }
                    .where(table.id == id)
                    .returning(schema.table(Todo.self))
            ).fetchAll(),
            or: id
        )
    }
```

Writes are not declarations. Declared queries are `SELECT`-only in v1.5, so the
demo's writes use the functional statement syntax from <doc:FunctionalSyntax>.
Still typed, still no SQL strings.

## A transaction that has to be all or nothing

Moving a to-do to another list renumbers the list it left and appends it to the
one it joined. Those writes only make sense together, so they run in one
`withTransaction` scope — see <doc:AdvancedUsage> for the full contract.

The demo's test suite forces a failure part-way through and checks that both
lists are exactly as they were. That case is the reason the operation takes an
injectable failure point at all.

## An interface that never refetches

Every view is fed by a live query. The models are thin: they own an
``XLObservableQuery`` and nothing else.

<!-- source: Examples/TodoApp/TodoKit/Sources/TodoKit/TodoModels.swift -->
```swift
@available(iOS 17, macOS 14, *)
@Observable
@MainActor
public final class TodoSidebarModel {

    public let lists: XLObservableQuery<TodoList>

    public let counts: XLObservableQuery<TodoListCounts>

    public init(database: TodoDatabase) {
        lists = XLObservableQuery(database.listsRequest)
        counts = XLObservableQuery(database.listCountsRequest)
    }
```

Completing a to-do in the detail pane updates the detail, the row in the list,
and the sidebar's open count. Three independent observations of the same
commit, none of which knows about the others, and no reload call anywhere. See
<doc:LiveQueries> for the observation, buffering, and cancellation contracts
these inherit.

Changing the filter, sort, or search text does not filter rows already in
memory. It builds a new binding packet and replaces the observation, because a
live query captures its packet once.

One thing to know before reaching for a declaration here: ``XLObservableQuery``
observes an ``XLRequest``, and `@SQLQueries` does not produce one. The three
reads the demo observes therefore exist twice — once as a declaration, once as
a statement.

## Queries checked before the app runs

The demo carries a checked-in schema snapshot and a manifest of every query it
runs. SwiftQL's build-tool plugin prepares each query against that snapshot on
every build, so a query that no longer matches the schema fails the build
rather than the app.

Regenerate both after changing the schema or a query:

```text
Examples/TodoApp/Tools/regenerate-validation-manifest.sh
```

CI regenerates them and fails on any diff, so a query edited without
regenerating cannot keep validating the old shape.

## Where to go next

- The demo's own
  [README](https://github.com/lukevanin/swiftql/blob/main/Examples/TodoApp/README.md)
  maps every file to the feature it exercises, and lists the places building it
  found the API resisting.
- <doc:/tutorials/SwiftQL> builds one query from an empty file.
- <doc:DeclaredQueries>, <doc:LiveQueries>, and <doc:NumericDateCodecs> are the
  reference topics this article draws on most.
