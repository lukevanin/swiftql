//
//  Entities.swift
//  
//
//  Created by Luke Van In on 2022/05/16.
//

import Foundation

@testable import SwiftQL

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
    
    final class Schema: TableSchema {
        @FieldProxy let id: PrimaryKey
        @FieldProxy let placeId: ForeignKey<Place>
        @FieldProxy let username: String
        @FieldProxy let active: Bool
        
        static let fields = [\.id, \.placeId, \.username, \.active]
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
    static let schema = TableSchema<User>(
        fields: [
            FieldSchema(name: .id, keyPath: \.id),
            FieldSchema(name: .userId, keyPath: \.userId),
            FieldSchema(name: .placeId, keyPath: \.placeId),
            FieldSchema(name: .imageURL, keyPath: \.imageURL),
            FieldSchema(name: .published, keyPath: \.published),
        ]
    )
}


struct Place: Table {
    let id: PrimaryKey
    let name: String
    let verified: Bool
}

extension Place {
    static let schema = TableSchema<User>(
        fields: [
            FieldSchema(name: .id, keyPath: \.id),
            FieldSchema(name: .name, keyPath: \.name),
            FieldSchema(name: .verified, keyPath: \.verified),
        ]
    )
}


struct Sample: Table {
    let id: PrimaryKey
    let value: Int
}

extension Sample {
    static let schema = TableSchema<User>(
        fields: [
            FieldSchema(name: .id, keyPath: \.id),
            FieldSchema(name: .value, keyPath: \.value),
        ]
    )
}



class MyDatabase: Database {
    
    /*
    final class Schema: DatabaseSchema {

        final class SampleSchema: BaseTableSchema, TableSchema {
            lazy var id = PrimaryKeyField<String>(name: "id", table: self)
            lazy var value = Field<Int>(name: "value", table: self)
            
            static let tableName = SQLIdentifier(stringLiteral: "samples")

            var tableFields: [AnyField] {
                return [id, value]
            }
            
            func entity(from row: SQLRow) -> Sample {
                Sample(
                    id: row.field(id),
                    value: row.field(value)
                )
            }
            
            func values(entity: Sample) -> [SQLIdentifier : SQLExpression] {
                [
                    id.name: StringLiteral(entity.id),
                    value.name: IntegerLiteral(entity.value)
                ]
            }
        }

        final class UserSchema: BaseTableSchema, TableSchema {
            lazy var id = PrimaryKeyField<String>(name: "id", table: self)
            lazy var placeId = ForeignKeyField<String, PlaceSchema>(name: "place_id", table: self, field: \.id)
            lazy var username = Field<String>(name: "username", table: self)
            lazy var active = Field<Bool>(name: "active", table: self)
            
            static let tableName = SQLIdentifier(stringLiteral: "users")
    
            var tableFields: [AnyField] {
                return [id, placeId, username, active]
            }
    
            func entity(from row: SQLRow) -> User {
                User(
                    id: row.field(id),
                    placeId: row.field(placeId),
                    username: row.field(username),
                    active: row.field(active)
                )
            }
            
            func values(entity: User) -> [SQLIdentifier : SQLExpression] {
                [
                    id.name: StringLiteral(entity.id),
                    placeId.name: StringLiteral(entity.placeId),
                    username.name: StringLiteral(entity.username),
                    active.name: BooleanLiteral(entity.active)
                ]
            }
        }

        final class PhotoSchema: BaseTableSchema, TableSchema {
            lazy var id = PrimaryKeyField<String>(name: "id", table: self)
            lazy var userId = ForeignKeyField<String, UserSchema>(name: "user_id", table: self, field: \.id)
            lazy var placeId = ForeignKeyField<String, PlaceSchema>(name: "place_id", table: self, field: \.id)
            lazy var imageURL = Field<URL>(name: "image_url", table: self)
            lazy var published = Field<Bool>(name: "published", table: self)
            
            static let tableName = SQLIdentifier(stringLiteral: "photos")

            var tableFields: [AnyField] {
                return [id, userId, placeId, imageURL, published]
            }
    
            func entity(from row: SQLRow) -> Photo {
                Photo(
                    id: row.field(id),
                    userId: row.field(userId),
                    placeId: row.field(placeId),
                    imageURL: row.field(imageURL),
                    published: row.field(published)
                )
            }
            
            func values(entity: Photo) -> [SQLIdentifier : SQLExpression] {
                [
                    id.name: StringLiteral(entity.id),
                    userId.name: StringLiteral(entity.userId),
                    placeId.name: StringLiteral(entity.placeId),
                    imageURL.name: URLLiteral(entity.imageURL),
                    published.name: BooleanLiteral(entity.published)
                ]
            }
        }

        final class PlaceSchema: BaseTableSchema, TableSchema {
            lazy var id = PrimaryKeyField<String>(name: "id", table: self)
            lazy var name = Field<String>(name: "name", table: self)
            lazy var verified = Field<Bool>(name: "verified", table: self)
            
            static let tableName = SQLIdentifier(stringLiteral: "places")
            
            var tableFields: [AnyField] {
                return [id, name, verified]
            }
            
            func entity(from row: SQLRow) -> Place {
                Place(
                    id: row.field(id),
                    name: row.field(name),
                    verified: row.field(verified)
                )
            }
            
            func values(entity: Place) -> [SQLIdentifier : SQLExpression] {
                [
                    id.name: StringLiteral(entity.id),
                    name.name: StringLiteral(entity.name),
                    verified.name: BooleanLiteral(entity.verified)
                ]
            }
        }

        func users() -> UserSchema {
            schema(table: UserSchema.self)
        }
        
        func photos() -> PhotoSchema {
            schema(table: PhotoSchema.self)
        }
        
        func places() -> PlaceSchema {
            schema(table: PlaceSchema.self)
        }
        
        func samples() -> SampleSchema {
            schema(table: SampleSchema.self)
        }
    }
     */
    
    
    class Schema: DatabaseSchema {
        
        func users() -> User {
            schema(table: User.self)
        }
        
        func photos() -> Photo {
            schema(table: Photo.self)
        }
        
        func places() -> Place {
            schema(table: Place.self)
        }
        
        func samples() -> Sample {
            schema(table: Sample.self)
        }

    }

    
    let connection: DatabaseConnection
    
    init(connection: DatabaseConnection) {
        self.connection = connection
    }
}
