//
//  SQLDatabase.swift
//  
//
//  Created by Luke Van In on 2023/07/31.
//

import Foundation
#if canImport(Combine)
import Combine
#else
import OpenCombine
import OpenCombineFoundation
#endif


extension Notification.Name {
    static let XLEntitiesChanged = Notification.Name("swiftql.entitiesChanged")
}

extension String {
    static let XLEntities = "swiftql.entities"
}

extension NotificationCenter {
    
    @available(*, deprecated, message: "GRDB live queries no longer consume global entity notifications. Use XLRequest.publish() or GRDB ValueObservation.")
    public func sqlEntitiesChangedPublisher() -> NotificationCenter.Publisher {
        publisher(for: .XLEntitiesChanged)
    }
    
    @available(*, deprecated, message: "GRDB live queries no longer consume global entity notifications. Use XLRequest.publish() or GRDB ValueObservation.")
    public func sqlEntitiesChangedObserver(queue: OperationQueue, observer: @escaping @Sendable (Notification) -> Void) -> NSObjectProtocol {
        addObserver(
            forName: .XLEntitiesChanged,
            object: nil,
            queue: queue,
            using: observer
        )
    }
    
    @available(*, deprecated, message: "GRDB live queries no longer consume global entity notifications. Observe with XLRequest.publish() or GRDB ValueObservation.")
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
    
    @available(*, deprecated, message: "GRDB live queries no longer consume global commit notifications. Use XLRequest.publish() or GRDB ValueObservation.")
    public func sqlCommitPublisher() -> NotificationCenter.Publisher {
        publisher(for: .XLCommit)
    }
    
    @available(*, deprecated, message: "GRDB live queries no longer consume global commit notifications. Use XLRequest.publish() or GRDB ValueObservation.")
    public func sqlCommitObserver(queue: OperationQueue, observer: @escaping @Sendable (Notification) -> Void) -> NSObjectProtocol {
        addObserver(
            forName: .XLCommit,
            object: nil,
            queue: queue,
            using: observer
        )
    }
    
    @available(*, deprecated, message: "GRDB live queries no longer consume global commit notifications. Observe with XLRequest.publish() or GRDB ValueObservation.")
    public func postSQLCommitNotification() {
        post(
            name: .XLCommit,
            object: nil,
            userInfo: [:]
        )
    }
}


///
/// Constructs a prepared select query statement with parameters.
///
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


///
/// A prepared select query statement.
///
/// Read ``parameterLayout`` to construct an immutable `XLInvocationBindings` packet, then pass
/// that packet to the binding-aware fetch or publish method for each execution. This keeps the
/// prepared request's static SQL separate from its per-invocation values.
///
/// The mutating `set` methods remain available as v1 source-compatibility shims while callers migrate
/// to invocation packets. Use the fetch methods to execute the query, or the publish methods to create
/// an adapter-backed Combine publisher that observes the query's database region.
///
public protocol XLRequest<Row> {
    associatedtype Row

    /// Immutable static parameter metadata captured when the request was prepared.
    var parameterLayout: XLParameterLayout { get }
    
    ///
    /// Assigns a literal value to an optional named variable parameter.
    ///
    /// - Parameter reference: Named variable parameter to assign.
    /// - Parameter value: Optional value to assign to the named parameter.
    ///
    mutating func set<T>(parameter reference: XLNamedBindingReference<Optional<T>>, value: T?) where T: XLBindable
    
    ///
    /// Assigns a literal value to a variable parameter.
    ///
    /// - Parameter reference: Named variable parameter to assign.
    /// - Parameter value: Value to assign to the named parameter.
    ///
    mutating func set<T>(parameter reference: XLNamedBindingReference<T>, value: T) where T: XLBindable
    
    ///
    /// Fetches all rows returned by the query.
    ///
    /// The fetch is atomic: if executing the query or decoding any row fails, no partial result is returned.
    ///
    /// - Throws: The original query-execution or row-decoding error.
    ///
    func fetchAll() throws -> [Row]

    /// Fetches all rows with one immutable per-invocation binding packet.
    func fetchAll(bindings: any XLInvocationBindingPacket) throws -> [Row]
    
    ///
    /// Fetches the first row returned by the query.
    ///
    /// - Throws: The original query-execution or row-decoding error.
    ///
    func fetchOne() throws -> Row?

    /// Fetches the first row with one immutable per-invocation binding packet.
    func fetchOne(bindings: any XLInvocationBindingPacket) throws -> Row?
    
    ///
    /// Creates a Combine Publisher that observes and emits all rows from the query.
    ///
    /// Observation starts when a subscriber first requests positive demand. Each subscriber receives a
    /// fresh initial value and owns an independent observation. Subscribing with zero demand performs no
    /// database work. Adapter-specific scheduling, write visibility, and connection boundaries apply.
    ///
    /// The publisher fails with the original query-execution or row-decoding error instead of emitting a
    /// partial result. An adapter may expose an explicit retry policy; GRDB-backed requests remain terminal
    /// by default and retry only when their database is configured to do so.
    ///
    func publish() -> AnyPublisher<[Row], Error>

    /// Observes all rows using one immutable packet for every retry and refresh.
    func publish(bindings: any XLInvocationBindingPacket) -> AnyPublisher<[Row], Error>
    
    ///
    /// Creates a Combine Publisher that observes and emits the first row from the query.
    ///
    /// Observation starts when a subscriber first requests positive demand. Each subscriber receives a
    /// fresh initial value and owns an independent observation. Subscribing with zero demand performs no
    /// database work. Adapter-specific scheduling, write visibility, and connection boundaries apply.
    ///
    /// The publisher fails with the original query-execution or row-decoding error. An adapter may expose
    /// an explicit retry policy; GRDB-backed requests remain terminal by default and retry only when their
    /// database is configured to do so.
    ///
    func publishOne() -> AnyPublisher<Row?, Error>

    /// Observes the first row using one immutable packet for every retry and refresh.
    func publishOne(bindings: any XLInvocationBindingPacket) -> AnyPublisher<Row?, Error>
}

extension XLRequest {

    /// Compatibility default for request adapters that do not yet expose static
    /// parameter metadata.
    public var parameterLayout: XLParameterLayout {
        .empty
    }

    /// Compatibility default for existing adapters. Empty packets preserve the
    /// original zero-argument execution path; nonempty packets fail explicitly.
    public func fetchAll(
        bindings: any XLInvocationBindingPacket
    ) throws -> [Row] {
        try validateCompatibilityBindings(bindings)
        return try fetchAll()
    }

    /// Compatibility default for existing adapters. Empty packets preserve the
    /// original zero-argument execution path; nonempty packets fail explicitly.
    public func fetchOne(
        bindings: any XLInvocationBindingPacket
    ) throws -> Row? {
        try validateCompatibilityBindings(bindings)
        return try fetchOne()
    }

    /// Compatibility default for existing adapters. Invalid packets fail on
    /// subscription instead of being silently ignored.
    public func publish(
        bindings: any XLInvocationBindingPacket
    ) -> AnyPublisher<[Row], Error> {
        do {
            try validateCompatibilityBindings(bindings)
            return publish()
        }
        catch {
            return Fail(error: error).eraseToAnyPublisher()
        }
    }

    /// Compatibility default for existing adapters. Invalid packets fail on
    /// subscription instead of being silently ignored.
    public func publishOne(
        bindings: any XLInvocationBindingPacket
    ) -> AnyPublisher<Row?, Error> {
        do {
            try validateCompatibilityBindings(bindings)
            return publishOne()
        }
        catch {
            return Fail(error: error).eraseToAnyPublisher()
        }
    }

    private func validateCompatibilityBindings(
        _ bindings: any XLInvocationBindingPacket
    ) throws {
        guard bindings.layout.isEmpty,
              bindings.bindingCount == 0,
              bindings.isComplete else {
            throw XLRequestBindingError.unsupportedInvocationBindings(
                requestType: String(reflecting: Self.self),
                layout: bindings.layout
            )
        }
    }
    
    ///
    /// Convenience method used to set an optional named parameter on the request.
    ///
    public mutating func set<T>(_ parameter: XLNamedBindingReference<Optional<T>>, _ value: T?) where T: XLBindable  {
        set(parameter: parameter, value: value)
    }
    
    ///
    /// Convenience method used to set a named parameter on the request.
    ///
    public mutating func set<T>(_ parameter: XLNamedBindingReference<T>, _ value: T) where T: XLBindable {
        set(parameter: parameter, value: value)
    }
    
    ///
    /// Convenience method used to set the value of a parameter by its literal string name.
    ///
    public mutating func set<T>(_ name: XLName, _ value: T) where T: XLBindable & XLLiteral {
        set(parameter: XLNamedBindingReference(name: name), value: value)
    }
}


///
/// A prepared statement that modifies the database, such as a create, update, insert, or delete statement.
///
/// `XLWriteRequest` differs from `XLRequest` in that it does not provide methods to return results
/// from executing the request.
///
public protocol XLWriteRequest {

    /// Immutable static parameter metadata captured when the request was prepared.
    var parameterLayout: XLParameterLayout { get }
    
    ///
    /// Assigns a literal value to an optional named variable parameter.
    ///
    /// - Parameter reference: Named variable parameter to assign.
    /// - Parameter value: Optional value to assign to the named parameter.
    ///
    mutating func set<T>(parameter reference: XLNamedBindingReference<Optional<T>>, value: T?) where T: XLBindable

    ///
    /// Assigns a literal value to a named variable parameter.
    ///
    /// - Parameter reference: Named variable parameter to assign.
    /// - Parameter value: Value to assign to the named parameter.
    ///
    mutating func set<T>(parameter reference: XLNamedBindingReference<T>, value: T) where T: XLBindable
    
    ///
    /// Executes the statement.
    ///
    func execute() throws

    /// Executes the statement with one immutable per-invocation binding packet.
    func execute(bindings: any XLInvocationBindingPacket) throws
}

extension XLWriteRequest {

    /// Compatibility default for request adapters that do not yet expose static
    /// parameter metadata.
    public var parameterLayout: XLParameterLayout {
        .empty
    }

    /// Compatibility default for existing adapters. Empty packets preserve the
    /// original zero-argument execution path; nonempty packets fail explicitly.
    public func execute(
        bindings: any XLInvocationBindingPacket
    ) throws {
        guard bindings.layout.isEmpty,
              bindings.bindingCount == 0,
              bindings.isComplete else {
            throw XLRequestBindingError.unsupportedInvocationBindings(
                requestType: String(reflecting: Self.self),
                layout: bindings.layout
            )
        }
        try execute()
    }
    
    ///
    /// Convenience method used to set an optional named parameter on the request.
    ///
    public mutating func set<T>(_ parameter: XLNamedBindingReference<Optional<T>>, _ value: T?) where T: XLBindable  {
        set(parameter: parameter, value: value)
    }
    
    ///
    /// Convenience method used to set a named parameter on the request.
    ///
    public mutating func set<T>(_ parameter: XLNamedBindingReference<T>, _ value: T) where T: XLBindable {
        set(parameter: parameter, value: value)
    }
    
    ///
    /// Convenience method used to set the value of a parameter by its literal string name.
    ///
    public mutating func set<T>(_ name: XLName, _ value: T) where T: XLBindable & XLLiteral {
        set(parameter: XLNamedBindingReference(name: name), value: value)
    }
}


///
/// A database that can execute select, update, insert, create, and delete statements.
///
public protocol XLDatabase {
    
    ///
    /// Constructs a prepared query request from a query statement.
    ///
    func makeRequest<Row>(with statement: any XLQueryStatement<Row>) -> any XLRequest<Row>
    
    ///
    /// Constructs a prepared update request from an update statement.
    ///
    func makeRequest(with statement: any XLUpdateStatement) -> any XLWriteRequest
    
    ///
    /// Creates a prepared insert request from an insert statement.
    ///
    func makeRequest(with statement: any XLInsertStatement) -> any XLWriteRequest
    
    ///
    /// Creates a prepared create request from a create statement.
    ///
    func makeRequest(with statement: any XLCreateStatement) -> any XLWriteRequest
    
    ///
    /// Creates a prepared delete request from a delete statement.
    ///
    func makeRequest(with statement: any XLDeleteStatement) -> any XLWriteRequest
}

extension XLDatabase {
    
    ///
    /// Convenience method used to make a request for the database using a request builder.
    ///
    func makeRequest<Row>(with builder: XLRequestBuilder<Row>) -> any XLRequest<Row> {
        builder.build(with: self)
    }
}
