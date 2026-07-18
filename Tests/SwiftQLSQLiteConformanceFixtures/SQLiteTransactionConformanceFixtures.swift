/// Stable identifiers shared by adapter-neutral and real-SQLite transaction
/// contract tests.
public enum SQLiteTransactionConformanceCaseID:
    String,
    CaseIterable,
    Codable,
    Hashable,
    Sendable
{
    case emptyCommit = "commit.empty"
    case multipleStatementCommit = "commit.multiple-statements"
    case returnValue = "commit.return-value"
    case explicitRollback = "rollback.explicit-request"
    case bodyErrorRollback = "rollback.body-error"
    case constraintFailureRollback = "rollback.constraint-failure"
    case bindFailureRollback = "rollback.bind-failure"
    case decodeFailureRollback = "rollback.decode-failure"
    case driverFailureRollback = "rollback.driver-failure"
    case earlyExitRollback = "rollback.early-exit"
    case connectionPinning = "ownership.connection-pinning"
    case pinnedConnectionVisibility = "visibility.pinned-connection"
    case pooledCommitVisibility = "visibility.pool-after-commit"
    case pooledRollbackVisibility = "visibility.pool-after-rollback"
    case singleConnectionVisibilityCapability = "capability.single-connection-visibility"
    case postFailureReuse = "cleanup.post-failure-reuse"
    case independentDatabases = "isolation.independent-databases"
    case nestedTransactionCapability = "capability.nested-transaction"
}


public enum SQLiteTransactionStateExpectation: String, Sendable {
    case commit
    case rollback
    case unchangedUnsupported
}


/// One stable logical row used by the adapter-neutral transaction oracle.
public struct SQLiteTransactionStateRow: Equatable, Hashable, Sendable {
    public static let conformanceValue: Int64 = 253

    public let id: String
    public let value: Int64

    public init(id: String, value: Int64) {
        self.id = id
        self.value = value
    }
}


/// Adapter-neutral transaction state represented by stable logical rows.
///
/// Real adapters construct this snapshot from a fresh read boundary after the
/// transaction. Fake adapters can use it directly to prove that a broken
/// commit, rollback, insert, or update implementation is detected by the same
/// oracle.
public struct SQLiteTransactionStateSnapshot: Equatable, Sendable {
    public let rows: [SQLiteTransactionStateRow]

    public init(rows: some Sequence<SQLiteTransactionStateRow>) {
        self.rows = Array(Set(rows)).sorted { lhs, rhs in
            if lhs.id == rhs.id {
                return lhs.value < rhs.value
            }
            return lhs.id < rhs.id
        }
    }

    public init(rowIDs: some Sequence<String>) {
        self.init(
            rows: rowIDs.map {
                SQLiteTransactionStateRow(id: $0, value: 0)
            }
        )
    }

    public var rowIDs: [String] {
        rows.map(\.id)
    }
}


public enum SQLiteTransactionStateViolation: Error, Equatable, Sendable {
    case unexpectedState(
        caseID: SQLiteTransactionConformanceCaseID,
        expected: SQLiteTransactionStateSnapshot,
        actual: SQLiteTransactionStateSnapshot
    )
}


public struct SQLiteTransactionConformanceCase: Sendable {
    public let id: SQLiteTransactionConformanceCaseID
    public let expectation: SQLiteTransactionStateExpectation
    public let insertedRows: [SQLiteTransactionStateRow]

    public init(
        id: SQLiteTransactionConformanceCaseID,
        expectation: SQLiteTransactionStateExpectation,
        insertedRowIDs: [String]
    ) {
        self.id = id
        self.expectation = expectation
        self.insertedRows = insertedRowIDs.map {
            SQLiteTransactionStateRow(
                id: $0,
                value: SQLiteTransactionStateRow.conformanceValue
            )
        }
    }

    public var insertedRowIDs: [String] {
        insertedRows.map(\.id)
    }

    public func expectedState(
        from before: SQLiteTransactionStateSnapshot
    ) -> SQLiteTransactionStateSnapshot {
        switch expectation {
        case .commit:
            return SQLiteTransactionStateSnapshot(
                rows: before.rows + insertedRows
            )
        case .rollback, .unchangedUnsupported:
            return before
        }
    }

    public func validate(
        before: SQLiteTransactionStateSnapshot,
        after: SQLiteTransactionStateSnapshot
    ) throws {
        let expected = expectedState(from: before)
        guard after == expected else {
            throw SQLiteTransactionStateViolation.unexpectedState(
                caseID: id,
                expected: expected,
                actual: after
            )
        }
    }
}


public enum SQLiteTransactionCapabilityID: String, Codable, Hashable, Sendable {
    case explicitRollbackByError = "explicit-rollback-by-error"
    case singleConnectionDriver = "single-connection-driver"
    case nestedTransactionOrSavepoint = "nested-transaction-or-savepoint"
    case taskCancellation = "task-cancellation"
}


public struct SQLiteTransactionCapabilityDisposition: Equatable, Sendable {
    public let isSupported: Bool
    public let blockingIssue: Int?
    public let reason: String

    public init(
        isSupported: Bool,
        blockingIssue: Int?,
        reason: String
    ) {
        self.isSupported = isSupported
        self.blockingIssue = blockingIssue
        self.reason = reason
    }
}


public enum SQLiteTransactionCapabilityError: Error, Equatable, Sendable {
    case unsupported(
        capability: SQLiteTransactionCapabilityID,
        blockingIssue: Int,
        reason: String
    )
}


public enum SQLiteTransactionConformanceFixtures {

    public static let cases: [SQLiteTransactionConformanceCase] = [
        transactionCase(.emptyCommit, .commit, insertedRowIDs: []),
        transactionCase(
            .multipleStatementCommit,
            .commit,
            insertedRowIDs: [
                "commit.multiple-statements.1",
                "commit.multiple-statements.2",
            ]
        ),
        transactionCase(.returnValue, .commit),
        transactionCase(.explicitRollback, .rollback),
        transactionCase(.bodyErrorRollback, .rollback),
        transactionCase(.constraintFailureRollback, .rollback),
        transactionCase(.bindFailureRollback, .rollback),
        transactionCase(.decodeFailureRollback, .rollback),
        transactionCase(.driverFailureRollback, .rollback),
        transactionCase(.earlyExitRollback, .rollback),
        transactionCase(.connectionPinning, .commit),
        transactionCase(.pinnedConnectionVisibility, .commit),
        transactionCase(.pooledCommitVisibility, .commit),
        transactionCase(.pooledRollbackVisibility, .rollback),
        transactionCase(
            .singleConnectionVisibilityCapability,
            .unchangedUnsupported,
            insertedRowIDs: []
        ),
        transactionCase(.postFailureReuse, .commit),
        transactionCase(.independentDatabases, .commit),
        transactionCase(
            .nestedTransactionCapability,
            .unchangedUnsupported,
            insertedRowIDs: []
        ),
    ]

    public static let casesByID = Dictionary(
        uniqueKeysWithValues: cases.map { ($0.id, $0) }
    )

    /// The current synchronous v1 driver rolls back when the transaction body
    /// throws and preserves that exact error. Nested/savepoint entry and task
    /// cancellation need the explicit adapter hooks tracked by v2 issue #113;
    /// they are asserted as deterministic unsupported capabilities, not skipped.
    public static let capabilities: [
        SQLiteTransactionCapabilityID: SQLiteTransactionCapabilityDisposition
    ] = [
        .explicitRollbackByError: SQLiteTransactionCapabilityDisposition(
            isSupported: true,
            blockingIssue: nil,
            reason: "A dedicated caller error requests rollback and is preserved."
        ),
        .singleConnectionDriver: SQLiteTransactionCapabilityDisposition(
            isSupported: false,
            blockingIssue: 113,
            reason: "The v1 GRDB driver accepts a DatabasePool, not a single-connection writer."
        ),
        .nestedTransactionOrSavepoint: SQLiteTransactionCapabilityDisposition(
            isSupported: false,
            blockingIssue: 113,
            reason: "The v1 driver has no nested transaction or savepoint hook."
        ),
        .taskCancellation: SQLiteTransactionCapabilityDisposition(
            isSupported: false,
            blockingIssue: 113,
            reason: "The v1 transaction closure is synchronous and has no cancellation hook."
        ),
    ]

    public static func require(
        _ capability: SQLiteTransactionCapabilityID
    ) throws {
        guard let disposition = capabilities[capability] else {
            preconditionFailure("Missing transaction capability disposition")
        }
        guard !disposition.isSupported else {
            return
        }
        guard let blockingIssue = disposition.blockingIssue else {
            preconditionFailure("Unsupported transaction capability needs a blocker")
        }
        throw SQLiteTransactionCapabilityError.unsupported(
            capability: capability,
            blockingIssue: blockingIssue,
            reason: disposition.reason
        )
    }

    private static func transactionCase(
        _ id: SQLiteTransactionConformanceCaseID,
        _ expectation: SQLiteTransactionStateExpectation,
        insertedRowIDs: [String]? = nil
    ) -> SQLiteTransactionConformanceCase {
        SQLiteTransactionConformanceCase(
            id: id,
            expectation: expectation,
            insertedRowIDs: insertedRowIDs ?? [id.rawValue]
        )
    }
}
