# To-do demo

A to-do application built on SwiftQL, for iOS 17 and macOS 14. Lists, to-dos,
tags, filters, sort, and search, over a real SQLite file in Application
Support.

It is here to show what an application looks like when the whole data layer is
SwiftQL: the schema, the queries, the writes, the transactions, and a SwiftUI
interface that updates itself. It is deliberately small enough to read in one
sitting.

## Open it

```
open Examples/TodoApp/TodoApp.xcodeproj
```

Pick the **TodoApp** scheme and run it on My Mac or an iOS simulator. There is
nothing to configure: the app creates its database and seeds it the first time
it launches, and reopens it untouched afterwards.

SwiftQL is a local path dependency on this repository, so the demo always
builds the working tree. A library change that breaks the demo breaks it
immediately, which is the point of it living here rather than in a repository
of its own.

To run the tests without Xcode:

```
swift test --package-path Examples/TodoApp/TodoKit
```

## How it is put together

The app target is a thin SwiftUI shell. Everything that touches SwiftQL lives
in `TodoKit`, a local package beside it.

| Path | What is in it |
| --- | --- |
| `TodoApp/` | The SwiftUI views, one set for both platforms |
| `TodoKit/Sources/TodoKit/Values.swift` | `TodoUUID`, `TodoDate`, `TodoPriority` |
| `TodoKit/Sources/TodoKit/Schema.swift` | The four tables |
| `TodoKit/Sources/TodoKit/TodoSeed.swift` | The rows a fresh database starts with |
| `TodoKit/Sources/TodoKit/TodoDatabase.swift` | Opening, creating, seeding, resetting |
| `TodoKit/Sources/TodoKit/TodoReads.swift` | The declared queries |
| `TodoKit/Sources/TodoKit/TodoFilteredRead.swift` | The list view's one composable read |
| `TodoKit/Sources/TodoKit/TodoStore.swift` | Writes and the move transaction |
| `TodoKit/Sources/TodoKit/TodoModels.swift` | The `@Observable` live-query models |
| `TodoKit/Tests/` | 62 tests over the query layer |

## What each part shows

**Tables are Swift structs.** `Schema.swift` declares `TodoList`, `Todo`,
`Tag`, and the `TodoTag` join with `@SQLTable`. Rename a column and the
compiler finds every query that used it.

**Values that are not intrinsic get a type.** SwiftQL binds `Bool`, `Int`,
`Double`, `String`, and `Data`. `Values.swift` adds `TodoUUID` and `TodoDate`
as `XLCustomType` conformances that store the same spellings SwiftQL's own
UUID and Date codecs use, and `TodoPriority` as an `XLEnum`.

**Reads are declared as functions.** `TodoReads.swift` is one `@SQLQueries`
extension: lists, a to-do by identifier, the tags on a to-do and on a whole
list (both joins across `TodoTag`), and open and total counts per list in a
single grouped aggregate rather than a count per list.

**One query serves every combination.** `TodoFilteredRead.swift` is the list
view's read. Four filters, three sort orders, and any search text, in one
statement: the filter arrives as three booleans the `Where` clause reads, the
search is always applied with `%` standing in for an empty box, and the sort
decides which `OrderBy` terms have any effect. It is the one read that is not
a declared query, and the file says why.

**Writes return what they wrote.** `TodoStore.swift` creates, updates,
toggles, and deletes with `RETURNING`, so a caller gets the row the database
holds without fetching again.

**A transaction that has to be all or nothing.** Moving a to-do between lists
renumbers the list it left and appends it to the one it joined.
`withTransaction` makes those a unit; `testAFailureMidMoveLeavesBothListsUntouched`
forces a failure part-way and checks both lists are exactly as they were.

**The interface never refetches.** Every view is fed by `XLObservableQuery`.
Completing a to-do in the detail pane updates the detail, the row in the list,
and the sidebar's open count — three independent observations of the same
commit, none of which is told to reload. Changing the filter, sort, or search
re-binds the live query rather than filtering in Swift.

**Queries are checked at build time.** `TodoKitBuildValidation` carries a
checked-in schema snapshot and a manifest of every query the demo runs, and
SwiftQL's build-tool plugin prepares each one against that snapshot on every
build. Regenerate both after changing the schema or a query:

```
Examples/TodoApp/Tools/regenerate-validation-manifest.sh
```

## What it does not do

No sync, no accounts, no notifications, no widgets, and no distribution — no
signing, no TestFlight, no App Store. It is a code demo.

Schema migrations are out of scope too. `sqlCreate` creates a table but does
not migrate one, so changing the schema means deleting the database file (or
using the debug **Reset to seeded state** action).

## Known rough edges

Building a whole application on v1.5 surfaced three places where the API
resists, all recorded on
[#469](https://github.com/lukevanin/swiftql/issues/469):

- **`LIKE` cannot appear in a declared query.** The frozen-literal guard
  rejects a parameter passed to a call, and `like(_:)` is a method with no
  operator spelling. That is why the list view's read uses named bindings.
- **Live queries and declared queries do not compose.** `XLObservableQuery`
  observes an `XLRequest`, and `@SQLQueries` does not produce one, so the three
  reads a view observes exist twice — once as a declaration, once as a
  statement.
- **A declared query cannot be called inside `withTransaction`.** The generated
  executor opens its own transaction, and SwiftQL rejects nesting, so reads
  inside a transaction use plain requests.

None of them stop the demo working. They are the kind of thing an application
finds and a fragment does not, which is most of why this exists.
