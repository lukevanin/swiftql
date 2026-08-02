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
}
