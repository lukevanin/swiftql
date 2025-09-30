//
//  XLDatabase.swift
//  
//
//  Created by Luke Van In on 2023/07/31.
//

import Foundation
import Combine


extension Notification.Name {
    static let XLEntitiesChanged = Notification.Name("swiftql.entitiesChanged")
}

extension String {
    static let XLEntities = "swiftql.entities"
}

extension NotificationCenter {
    
    public func sqlEntitiesChangedPublisher() -> NotificationCenter.Publisher {
        publisher(for: .XLEntitiesChanged)
    }
    
    public func sqlEntitiesChangedObserver(queue: OperationQueue, observer: @escaping (Notification) -> Void) -> NSObjectProtocol {
        addObserver(
            forName: .XLEntitiesChanged,
            object: nil,
            queue: queue,
            using: observer
        )
    }
    
    public func postSQLEntitiesChangedNotification(entities: Set<String>) {
        post(
            name: .XLEntitiesChanged,
            object: nil,
            userInfo: [
                String.XLEntities: entities
            ]
        )
    }
}


extension Notification.Name {
    static let XLCommit = Notification.Name("swiftql.commit")
}

extension NotificationCenter {
    
    public func sqlCommitPublisher() -> NotificationCenter.Publisher {
        publisher(for: .XLCommit)
    }
    
    public func sqlCommitObserver(queue: OperationQueue, observer: @escaping (Notification) -> Void) -> NSObjectProtocol {
        addObserver(
            forName: .XLCommit,
            object: nil,
            queue: queue,
            using: observer
        )
    }
    
    public func postSQLCommitNotification() {
        post(
            name: .XLCommit,
            object: nil,
            userInfo: [:]
        )
    }
}

public struct XLRequestBuilder<Row> {
    
    public typealias Parameterize = (inout any XLRequest<Row>) -> Void
    
    private let statement: any XLQueryStatement<Row>
    
    private let parameterize: Parameterize
    
    public init(with statement: any XLQueryStatement<Row>, parameterize: @escaping Parameterize) {
        self.statement = statement
        self.parameterize = parameterize
    }
    
    public func build(with database: XLDatabase) -> any XLRequest<Row> {
        var request = database.makeRequest(with: statement)
        parameterize(&request)
        return request
    }
}


public protocol XLRequest<Row> {
    associatedtype Row
    mutating func set<T>(parameter reference: XLNamedBindingReference<Optional<T>>, value: T?) where T: XLBindable
    mutating func set<T>(parameter reference: XLNamedBindingReference<T>, value: T) where T: XLBindable
    func fetchAll() throws -> [Row]
    func fetchOne() throws -> Row?
    func publish() -> AnyPublisher<[Row], Error>
    func publishOne() -> AnyPublisher<Row?, Error>
}

extension XLRequest {
    
    public mutating func set<T>(_ parameter: XLNamedBindingReference<Optional<T>>, _ value: T?) where T: XLBindable  {
        set(parameter: parameter, value: value)
    }
    
    public mutating func set<T>(_ parameter: XLNamedBindingReference<T>, _ value: T) where T: XLBindable {
        set(parameter: parameter, value: value)
    }
    
    public mutating func set<T>(_ name: XLName, _ value: T) where T: XLBindable & XLLiteral {
        set(parameter: XLNamedBindingReference(name: name), value: value)
    }
}


public protocol XLWriteRequest {
    #warning("TODO: Add mutable arguments")
    #warning("TODO: Return result")
    mutating func set<T>(parameter reference: XLNamedBindingReference<Optional<T>>, value: T?) where T: XLBindable
    mutating func set<T>(parameter reference: XLNamedBindingReference<T>, value: T) where T: XLBindable
    func execute() throws
}

extension XLWriteRequest {
    
    public mutating func set<T>(_ parameter: XLNamedBindingReference<Optional<T>>, _ value: T?) where T: XLBindable  {
        set(parameter: parameter, value: value)
    }
    
    public mutating func set<T>(_ parameter: XLNamedBindingReference<T>, _ value: T) where T: XLBindable {
        set(parameter: parameter, value: value)
    }
    
    public mutating func set<T>(_ name: XLName, _ value: T) where T: XLBindable & XLLiteral {
        set(parameter: XLNamedBindingReference(name: name), value: value)
    }
}


public protocol XLDatabase {
    func makeRequest<Row>(with statement: any XLQueryStatement<Row>) -> any XLRequest<Row>
    func makeRequest(with statement: any XLUpdateStatement) -> any XLWriteRequest
    func makeRequest(with statement: any XLInsertStatement) -> any XLWriteRequest
    func makeRequest(with statement: any XLCreateStatement) -> any XLWriteRequest
    func makeRequest(with statement: any XLDeleteStatement) -> any XLWriteRequest
}

extension XLDatabase {
    
    func makeRequest<Row>(with builder: XLRequestBuilder<Row>) -> any XLRequest<Row> {
        builder.build(with: self)
    }
}




