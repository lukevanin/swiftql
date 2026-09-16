import SwiftQL

@SQLTable
public struct FixtureAuthor: Equatable {
    public var id: String
    public var name: String
}
