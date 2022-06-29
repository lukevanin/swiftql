import Foundation

enum SQLError: Error {
    case invalidUUID(data: Data)
}
