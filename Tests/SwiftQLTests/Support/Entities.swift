//
//  Entities.swift
//  
//
//  Created by Luke Van In on 2022/05/16.
//

import Foundation

import SwiftQL

// MARK: - ENTITIES

struct User: Table {
    var id: PrimaryKey
    var placeId: ForeignKey<Place>
    var username: String
    var active: Bool
}

extension User {
//    static let schema = TableSchema<User>(
//        fields: [
//            FieldSchema(name: .id, keyPath: \.id),
//            FieldSchema(name: .placeId, keyPath: \.placeId),
//            FieldSchema(name: .username, keyPath: \.username),
//            FieldSchema(name: .active, keyPath: \.active),
//        ]
//    )
    
    final class Schema: TableSchema<User> {        
        @Field(name: "id") var id: PrimaryKey = .defaultValue
        @Field(name: "place_id") var placeId: ForeignKey<Place> = .defaultValue
        @Field(name: "username") var username: String = .defaultValue
        @Field(name: "active") var active: Bool = .defaultValue
    }
    
    init(_ schema: Schema) {
        self = User(
            id: schema.id,
            placeId: schema.placeId,
            username: schema.username,
            active: schema.active
        )
    }
    
    func _values() ->  [AnyLiteral] {
        [
            Literal(id),
            Literal(placeId),
            Literal(username),
            Literal(active)
        ]
    }
}


struct Photo: Table {
    var id: PrimaryKey
    var userId: ForeignKey<User>
    var placeId: ForeignKey<Place>
    var imageURL: URL
    var published: Bool
}

extension Photo {
//    static let schema = TableSchema<User>(
//        fields: [
//            FieldSchema(name: .id, keyPath: \.id),
//            FieldSchema(name: .userId, keyPath: \.userId),
//            FieldSchema(name: .placeId, keyPath: \.placeId),
//            FieldSchema(name: .imageURL, keyPath: \.imageURL),
//            FieldSchema(name: .published, keyPath: \.published),
//        ]
//    )
    
    final class Schema: TableSchema<Photo> {
        @Field(name: "id") var id: PrimaryKey = .defaultValue
        @Field(name: "user_id") var userId: ForeignKey<User> = .defaultValue
        @Field(name: "place_id") var placeId: ForeignKey<Place> = .defaultValue
        @Field(name: "image_url") var imageURL: URL = .defaultValue
        @Field(name: "published") var published: Bool = .defaultValue
    }
    
    init(_ schema: Schema) {
        self.init(
            id: schema.id,
            userId: schema.userId,
            placeId: schema.placeId,
            imageURL: schema.imageURL,
            published: schema.published
        )
    }
    
    func _values() -> [AnyLiteral] {
        [
            Literal(id),
            Literal(userId),
            Literal(placeId),
            Literal(imageURL),
            Literal(published),
        ]
    }
}


struct Place: Table {
    let id: PrimaryKey
    let name: String
    let verified: Bool
}

extension Place {
//    static let schema = TableSchema<User>(
//        fields: [
//            FieldSchema(name: .id, keyPath: \.id),
//            FieldSchema(name: .name, keyPath: \.name),
//            FieldSchema(name: .verified, keyPath: \.verified),
//        ]
//    )
    
    final class Schema: TableSchema<Place> {
        @Field(name: "id") var id: PrimaryKey = .defaultValue
        @Field(name: "name") var name: String = .defaultValue
        @Field(name: "verified") var verified: Bool = .defaultValue
    }
    
    init(_ schema: Schema) {
        self.init(
            id: schema.id,
            name: schema.name,
            verified: schema.verified
        )
    }
    
    func _values() -> [AnyLiteral] {
        [
            Literal(id),
            Literal(name),
            Literal(verified)
        ]
    }
}


struct Sample: Table {
    let id: PrimaryKey
    let value: Int
}

extension Sample {
    
    final class Schema: TableSchema<Sample> {
        @Field(name: "id") var id: PrimaryKey = .defaultValue
        @Field(name: "value") var value: Int = .defaultValue
    }
    
    init(_ schema: Schema) {
        self.init(
            id: schema.id,
            value: schema.value
        )
    }
    
    func _values() -> [AnyLiteral] {
        [
            Literal(id),
            Literal(value)
        ]
    }
}
