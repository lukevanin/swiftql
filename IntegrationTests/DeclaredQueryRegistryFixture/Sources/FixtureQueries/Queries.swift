import SwiftQL

@SQLQueries
extension GRDBDatabase {

    private struct Query {

        func fixtureAuthors() -> [FixtureAuthor] {
            sqlResult { schema in
                let author = schema.table(FixtureAuthor.self)
                Select(author)
                From(author)
            }
        }
    }
}

extension GRDBDatabase {

    @SQLQuery
    func fixtureAuthor(id: String) -> FixtureAuthor? {
        sqlResult { schema in
            let author = schema.table(FixtureAuthor.self)
            Select(author)
            From(author)
            Where(author.id == id)
        }
    }
}
