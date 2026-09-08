import Foundation

// The one place in the demo that reaches past SwiftQL to GRDB, and the reason
// is worth stating plainly: SwiftQL has no index DDL. `sqlCreate` builds a
// table from an `@SQLTable` type and nothing builds an index, so there is no
// SwiftQL spelling of the statements below. Typed DDL is v2 work (#139); when
// it lands, these become declarations and this import goes away.
//
// Until then this is the honest shape of the gap the v1.8 index advisor
// exposes: it can tell you exactly which index to add, prove the plan
// improves, and hand you the statement — and the library cannot run it for
// you.
import GRDB

import SwiftQL


/// The indices SwiftQL's v1.8 index advisor verified against this schema.
///
/// Every statement here was produced by `swiftql-build-validate
/// --plan-output … --verify-index-candidates` and accepted by the improvement
/// rule, which means each one was created on a disposable copy of the demo's
/// checked-in snapshot and the motivating query re-planned to prove the plan
/// changed. None of them was written by hand.
///
/// ## Why the demo had none before
///
/// SwiftQL's generated `CREATE TABLE` declares no primary key, so before this
/// every lookup by `id` was a full table scan and every `ORDER BY` built a
/// temporary B-tree. That is not a criticism of the advisor's usefulness: it
/// is what the advisor found.
///
/// ## The cost
///
/// Nine indices over four tables is a lot for a schema this small, and it is
/// the right trade here only because a to-do app reads constantly and writes
/// a row at a time. Each index is a second B-tree that every insert, delete,
/// and update of its columns maintains. On a write-heavy table the same
/// advice would need weighing rather than taking.
public enum TodoIndices {

    /// The verified statements, in the order the advisor emitted them.
    ///
    /// `IF NOT EXISTS`, because ``TodoDatabase`` runs them on every launch for
    /// the same reason it runs `CREATE TABLE IF NOT EXISTS`: a database whose
    /// schema was written but whose indices were not is a state a crash can
    /// leave behind, and re-running repairs it for nothing.
    public static let statements: [String] = [
        // todo-demo.tags-for-list, todo-demo.tags-for-todo:
        // automatic_covering_index -> index_search on the tag lookup.
        #"CREATE INDEX IF NOT EXISTS "ix_advisor_tag_id_name" ON "Tag" ("id", "name" ASC)"#,
        // todo-demo.tags: removes the temporary B-tree for ORDER BY name.
        #"CREATE INDEX IF NOT EXISTS "ix_advisor_tag_name" ON "Tag" ("name" ASC)"#,
        // todo-demo.todos: removes the temporary B-tree for the created-at
        // ordering.
        #"CREATE INDEX IF NOT EXISTS "ix_advisor_todo_createdat_position" ON "Todo" ("createdAt" ASC, "position" ASC)"#,
        // todo-demo.todo-by-id: full_table_scan -> index_search. The demo has
        // no primary key, so this is the only thing that makes a lookup by
        // identifier a seek.
        #"CREATE INDEX IF NOT EXISTS "ix_advisor_todo_id" ON "Todo" ("id")"#,
        // todo-demo.tags-for-list: full_table_scan -> covering index search
        // on the driving side of the join.
        #"CREATE INDEX IF NOT EXISTS "ix_advisor_todo_listid_id" ON "Todo" ("listID", "id")"#,
        // todo-demo.checklist-summaries: full_table_scan -> index_search, and
        // the ORDER BY sort disappears with it.
        #"CREATE INDEX IF NOT EXISTS "ix_advisor_todo_listid_position" ON "Todo" ("listID", "position" ASC)"#,
        // todo-demo.todo-list-by-id: full_table_scan -> index_search.
        #"CREATE INDEX IF NOT EXISTS "ix_advisor_todolist_id" ON "TodoList" ("id")"#,
        // todo-demo.todo-lists: removes the temporary B-tree for the sidebar
        // ordering.
        #"CREATE INDEX IF NOT EXISTS "ix_advisor_todolist_position_name" ON "TodoList" ("position" ASC, "name" ASC)"#,
        // todo-demo.tags-for-list, todo-demo.tags-for-todo:
        // automatic_covering_index -> covering index search on the link table.
        #"CREATE INDEX IF NOT EXISTS "ix_advisor_todotag_todoid_tagid" ON "TodoTag" ("todoID", "tagID")"#,
    ]

    /// Creates every index on `databasePool`, which must already hold the
    /// demo's tables.
    ///
    /// Deliberately not inside a SwiftQL transaction scope: that scope already
    /// owns the pool's writer, and a second write from inside it would be a
    /// nested write on the same connection.
    public static func create(in databasePool: DatabasePool) throws {
        try databasePool.write { database in
            for statement in statements {
                try database.execute(sql: statement)
            }
        }
    }
}
