import Foundation
import SwiftQL

@SQLTable struct Studio {
    var id: String
    var name: String
    var country: String
}

@SQLTable struct Album {
    var id: String
    var studioId: String
    var title: String
    var year: Int
}

@SQLResult struct AlbumCredit: Equatable {
    let title: String
    let year: Int
    let studioName: String
}

func albumCredits(recordedIn country: String, databaseURL: URL) throws -> [AlbumCredit] {
    let database = try GRDBDatabase(url: databaseURL, logger: nil)

    try database.makeRequest(with: sqlCreate(Studio.self)).execute()
    try database.makeRequest(with: sqlCreate(Album.self)).execute()

    let studios = [
        Studio(id: "abbey-road", name: "Abbey Road", country: "GB"),
        Studio(id: "sun", name: "Sun", country: "US"),
    ]
    let albums = [
        Album(id: "revolver", studioId: "abbey-road", title: "Revolver", year: 1966),
        Album(id: "abbey-road", studioId: "abbey-road", title: "Abbey Road", year: 1969),
        Album(id: "sun-sessions", studioId: "sun", title: "The Sun Sessions", year: 1976),
    ]

    try database.withTransaction { scope in
        for studio in studios {
            try scope.makeRequest(with: sqlInsert(studio)).execute()
        }
        for album in albums {
            try scope.makeRequest(with: sqlInsert(album)).execute()
        }
    }
}
