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
    final class Schema: TableSchemaOf<User> {
        @Field(name: "place_id") var placeId: ForeignKey<Place> = .defaultValue
        @Field(name: "username") var username: String = .defaultValue
        @Field(name: "active") var active: Bool = .defaultValue
    }
    
    init(schema: Schema) {
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
    
    func _bind(schema: Schema) {
        schema.id = id
        schema.placeId = placeId
        schema.username = username
        schema.active = active
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
    final class Schema: TableSchemaOf<Photo> {
        @Field(name: "user_id") var userId: ForeignKey<User> = .defaultValue
        @Field(name: "place_id") var placeId: ForeignKey<Place> = .defaultValue
        @Field(name: "image_url") var imageURL: URL = .defaultValue
        @Field(name: "published") var published: Bool = .defaultValue
    }
    
    init(schema: Schema) {
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
    
    func _bind(schema: Schema) {
        schema.id = id
        schema.userId = userId
        schema.placeId = placeId
        schema.imageURL = imageURL
        schema.published = published
    }
}


struct Place: Table {
    let id: PrimaryKey
    let name: String
    let verified: Bool
}

extension Place {
    final class Schema: TableSchemaOf<Place> {
        @Field(name: "name") var name: String = .defaultValue
        @Field(name: "verified") var verified: Bool = .defaultValue
    }
    
    init(schema: Schema) {
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
    
    func _bind(schema: Schema) {
        schema.id = id
        schema.name = name
        schema.verified = verified
    }
}


struct Sample: Table {
    let id: PrimaryKey
    let value: Int
}

extension Sample {
    
    final class Schema: TableSchemaOf<Sample> {
        @Field(name: "value") var value: Int = .defaultValue
    }
    
    init(schema: Schema) {
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
    
    func _bind(schema: Schema) {
        schema.id = id
        schema.value = value
    }
}


final class MyDatabase: DatabaseProtocol {
    
    final class Schema: AnyDatabaseSchema {
    
        var users: User.Schema {
            makeSchema()
        }
        
        var places: Place.Schema {
            makeSchema()
        }
        
        var photos: Photo.Schema {
            makeSchema()
        }
        
        var samples: Sample.Schema {
            makeSchema()
        }
    }
}
