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
