// A model file needs only the SQLite module, with no GRDB driver, so this
// one imports SwiftQLSQLite alone, as an application's model files do. It is
// the downstream check that the macros' expansions resolve in such a file
// (issue #790).
import SwiftQLSQLite

@SQLTable
public struct FixtureAuthor: Equatable {
    public var id: String
    public var name: String
}
