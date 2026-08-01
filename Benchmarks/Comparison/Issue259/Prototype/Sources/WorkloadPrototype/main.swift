import Foundation

/// Dispatches one workload through one implementation. Keeping the three
/// adapters behind one enum rather than a protocol keeps each library's own
/// return types visible in its adapter instead of forcing them through a
/// shared existential that would add an allocation none of them normally pay.
private enum PrototypeAdapter {
    case swiftql(SwiftQLPrototypeAdapter)
    case grdb(GRDBPrototypeAdapter)
    case sqliteSwift(SQLiteSwiftPrototypeAdapter)

    init(configuration: PrototypeConfiguration) throws {
        let url = configuration.databaseURL
        let writable = configuration.workload.requiresWritableDatabase
        switch configuration.implementation {
        case .swiftql:
            self = .swiftql(try SwiftQLPrototypeAdapter(databaseURL: url, writable: writable))
        case .grdb:
            self = .grdb(try GRDBPrototypeAdapter(databaseURL: url, writable: writable))
        case .sqliteSwift:
            self = .sqliteSwift(
                try SQLiteSwiftPrototypeAdapter(databaseURL: url, writable: writable)
            )
        }
    }

    func pointLookup(iteration: Int) throws -> PrototypeOrder? {
        switch self {
        case let .swiftql(adapter): return try adapter.pointLookup(iteration: iteration)
        case let .grdb(adapter): return try adapter.pointLookup(iteration: iteration)
        case let .sqliteSwift(adapter): return try adapter.pointLookup(iteration: iteration)
        }
    }

    func joinAggregate() throws -> [PrototypeCountryVolume] {
        switch self {
        case let .swiftql(adapter): return try adapter.joinAggregate()
        case let .grdb(adapter): return try adapter.joinAggregate()
        case let .sqliteSwift(adapter): return try adapter.joinAggregate()
        }
    }

    func transactionalWrite() throws -> Int {
        switch self {
        case let .swiftql(adapter): return try adapter.transactionalWrite()
        case let .grdb(adapter): return try adapter.transactionalWrite()
        case let .sqliteSwift(adapter): return try adapter.transactionalWrite()
        }
    }
}

func runPrototype() throws {
    let configuration = try PrototypeConfiguration.parse()
    let adapter = try PrototypeAdapter(configuration: configuration)
    let oracle = try PrototypeStateOracle(databaseURL: configuration.databaseURL)
    let keys = PrototypeConstants.lookupKeys

    switch configuration.workload {
    case .pointLookup:
        try PrototypeDriver.run(
            configuration: configuration,
            operation: { iteration in try adapter.pointLookup(iteration: iteration) },
            verify: { iteration, row in
                guard let row else {
                    throw PrototypeError.unexpectedRowCount(
                        workload: configuration.workload.rawValue,
                        expected: 1,
                        actual: 0
                    )
                }
                let expectedKey = keys[iteration % keys.count]
                guard row.orderID == expectedKey else {
                    throw PrototypeError.unexpectedRowCount(
                        workload: configuration.workload.rawValue,
                        expected: expectedKey,
                        actual: row.orderID
                    )
                }
            },
            checksum: { _, row in
                var checksum = PrototypeChecksum()
                checksum.combine(row!)
                return checksum.value
            },
            expectedChecksum: { iteration in
                try oracle.checksumOrder(orderID: keys[iteration % keys.count])
            }
        )

    case .joinAggregate:
        try PrototypeDriver.run(
            configuration: configuration,
            operation: { _ in try adapter.joinAggregate() },
            verify: { _, rows in
                guard rows.count == PrototypeConstants.expectedCountryGroupCount else {
                    throw PrototypeError.unexpectedRowCount(
                        workload: configuration.workload.rawValue,
                        expected: PrototypeConstants.expectedCountryGroupCount,
                        actual: rows.count
                    )
                }
            },
            checksum: { _, rows in
                var checksum = PrototypeChecksum()
                for row in rows {
                    checksum.combine(row)
                }
                return checksum.value
            },
            expectedChecksum: { _ in try oracle.checksumCountryVolumes() }
        )

    case .transactionalWrite:
        try oracle.clearScratchRows()
        try PrototypeDriver.run(
            configuration: configuration,
            operation: { _ in try adapter.transactionalWrite() },
            verify: { _, inserted in
                guard inserted == PrototypeConstants.writeBatchSize else {
                    throw PrototypeError.unexpectedChangeCount(
                        expected: PrototypeConstants.writeBatchSize,
                        actual: inserted
                    )
                }
                let committed = try oracle.scratchRowCount()
                guard committed == PrototypeConstants.writeBatchSize else {
                    throw PrototypeError.unexpectedChangeCount(
                        expected: PrototypeConstants.writeBatchSize,
                        actual: committed
                    )
                }
            },
            checksum: { _, _ in try oracle.checksumScratchRows() },
            expectedChecksum: { _ in PrototypeConstants.expectedScratchChecksum },
            reset: { try oracle.clearScratchRows() }
        )
    }
}

do {
    try runPrototype()
} catch let error as PrototypeError {
    FileHandle.standardError.write(Data("error: \(error.description)\n".utf8))
    exit(1)
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
