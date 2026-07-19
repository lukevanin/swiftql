/// Stable identifiers shared by adapter-neutral and real-SQLite observation
/// contract tests.
public enum SQLiteObservationConformanceCaseID:
    String,
    CaseIterable,
    Codable,
    Hashable,
    Sendable
{
    case currentInitialValue = "observation.subscription.current-initial-value"
    case freshInitialValuePerSubscriber =
        "observation.subscription.fresh-initial-per-subscriber"
    case rapidRelevantCommits = "observation.commit.rapid-relevant"
    case irrelevantTableWrite = "observation.commit.irrelevant-table-silent"
    case rollbackSilence = "observation.rollback.silent"
    case transactionCoalescing = "observation.transaction.multi-write-coalesced"
    case transientBusyRetry = "observation.retry.transient-busy"
    case permanentFailure = "observation.retry.permanent-failure"
    case zeroDemand = "observation.demand.zero"
    case incrementalDemand = "observation.demand.incremental"
    case cancellation = "observation.cancellation.terminal"
    case independentDatabases = "observation.isolation.independent-databases"
}


public struct SQLiteObservationConformanceCase: Equatable, Sendable {
    public let id: SQLiteObservationConformanceCaseID
    public let summary: String

    public init(id: SQLiteObservationConformanceCaseID, summary: String) {
        self.id = id
        self.summary = summary
    }
}


public struct SQLiteObservationUpstreamCase: Equatable, Sendable {
    public let repository: String
    public let commit: String
    public let path: String
    public let testCase: String

    public init(
        repository: String,
        commit: String,
        path: String,
        testCase: String
    ) {
        self.repository = repository
        self.commit = commit
        self.path = path
        self.testCase = testCase
    }
}


/// A stable logical subscription identity. Adapters translate their concrete
/// database and region identities into these values before validating a trace.
public struct SQLiteObservationSubscription: Equatable, Sendable {
    public let id: String
    public let databaseID: String
    public let observedTables: [String]

    public init(
        id: String,
        databaseID: String,
        observedTables: some Sequence<String>
    ) {
        self.id = id
        self.databaseID = databaseID
        self.observedTables = Array(Set(observedTables)).sorted()
    }
}


public enum SQLiteObservationMutationDisposition: String, Sendable {
    case committed
    case rolledBack = "rolled-back"
}


/// One transaction boundary visible to an observation adapter.
///
/// `writeCount` distinguishes a multi-write transaction from a single write.
/// A concrete adapter may coalesce transactions or deliver consecutive equal
/// snapshots, so the semantic validator does not impose an emission count.
public struct SQLiteObservationMutation: Equatable, Sendable {
    public let id: String
    public let databaseID: String
    public let disposition: SQLiteObservationMutationDisposition
    public let changedTables: [String]
    public let writeCount: Int

    public init(
        id: String,
        databaseID: String,
        disposition: SQLiteObservationMutationDisposition,
        changedTables: some Sequence<String>,
        writeCount: Int = 1
    ) {
        precondition(writeCount > 0, "An observation mutation must contain a write")
        self.id = id
        self.databaseID = databaseID
        self.disposition = disposition
        self.changedTables = Array(Set(changedTables)).sorted()
        self.writeCount = writeCount
    }
}


public enum SQLiteObservationDeliveryCause: Equatable, Sendable {
    case initial
    case mutation(String)
}


/// A logical result snapshot delivered by an observation.
public struct SQLiteObservationDelivery: Equatable, Sendable {
    public let subscriptionID: String
    public let databaseID: String
    public let rowIDs: [String]
    public let cause: SQLiteObservationDeliveryCause

    public init(
        subscriptionID: String,
        databaseID: String,
        rowIDs: [String],
        cause: SQLiteObservationDeliveryCause
    ) {
        self.subscriptionID = subscriptionID
        self.databaseID = databaseID
        self.rowIDs = rowIDs
        self.cause = cause
    }
}


public enum SQLiteObservationDemand: Equatable, Sendable {
    case maximum(Int)
    case unlimited
}


/// Ordered adapter-neutral events used by the observation semantic oracle.
public enum SQLiteObservationTraceEvent: Equatable, Sendable {
    case subscribed(SQLiteObservationSubscription)
    case requested(subscriptionID: String, demand: SQLiteObservationDemand)
    case mutation(SQLiteObservationMutation)
    case delivered(SQLiteObservationDelivery)
    case failed(subscriptionID: String)
    case cancelled(subscriptionID: String)
}


public enum SQLiteObservationTraceViolation: Error, Equatable, Sendable {
    case duplicateSubscription(subscriptionID: String)
    case unknownSubscription(subscriptionID: String)
    case duplicateMutation(mutationID: String)
    case unknownMutation(mutationID: String)
    case invalidDemand(subscriptionID: String, maximum: Int)
    case deliveryWithoutDemand(subscriptionID: String)
    case duplicateInitialDelivery(subscriptionID: String)
    case mutationBeforeInitialDelivery(
        subscriptionID: String,
        mutationID: String
    )
    case irrelevantMutationDelivered(
        subscriptionID: String,
        mutationID: String
    )
    case rolledBackMutationDelivered(
        subscriptionID: String,
        mutationID: String
    )
    case wrongDatabaseAttribution(
        subscriptionID: String,
        expectedDatabaseID: String,
        actualDatabaseID: String
    )
    case deliveryAfterCancellation(subscriptionID: String)
    case deliveryAfterFailure(subscriptionID: String)
}


/// Validates observation semantics without importing Combine, GRDB, or another
/// concrete adapter. Real-adapter tests record events at deterministic
/// boundaries; fake traces inject broken behavior into the same oracle.
public enum SQLiteObservationTraceValidator {

    public static func validate(
        _ events: some Sequence<SQLiteObservationTraceEvent>
    ) throws {
        var subscriptions: [String: SubscriptionState] = [:]
        var mutations: [String: SQLiteObservationMutation] = [:]

        for event in events {
            switch event {
            case .subscribed(let subscription):
                guard subscriptions[subscription.id] == nil else {
                    throw SQLiteObservationTraceViolation.duplicateSubscription(
                        subscriptionID: subscription.id
                    )
                }
                subscriptions[subscription.id] = SubscriptionState(
                    subscription: subscription
                )

            case .requested(let subscriptionID, let demand):
                var state = try requireSubscription(
                    subscriptionID,
                    from: subscriptions
                )
                switch demand {
                case .maximum(let maximum):
                    guard maximum > 0 else {
                        throw SQLiteObservationTraceViolation.invalidDemand(
                            subscriptionID: subscriptionID,
                            maximum: maximum
                        )
                    }
                    if state.outstandingDemand != nil {
                        state.outstandingDemand = state.outstandingDemand
                            .map { current in
                                let (sum, overflow) = current
                                    .addingReportingOverflow(maximum)
                                return overflow ? Int.max : sum
                            }
                    }
                case .unlimited:
                    state.outstandingDemand = nil
                }
                subscriptions[subscriptionID] = state

            case .mutation(let mutation):
                guard mutations[mutation.id] == nil else {
                    throw SQLiteObservationTraceViolation.duplicateMutation(
                        mutationID: mutation.id
                    )
                }
                mutations[mutation.id] = mutation

            case .delivered(let delivery):
                var state = try requireSubscription(
                    delivery.subscriptionID,
                    from: subscriptions
                )
                if state.isCancelled {
                    throw SQLiteObservationTraceViolation.deliveryAfterCancellation(
                        subscriptionID: delivery.subscriptionID
                    )
                }
                if state.isFailed {
                    throw SQLiteObservationTraceViolation.deliveryAfterFailure(
                        subscriptionID: delivery.subscriptionID
                    )
                }
                try validateDatabaseAttribution(
                    delivery: delivery,
                    expectedDatabaseID: state.subscription.databaseID
                )
                guard state.consumeDemand() else {
                    throw SQLiteObservationTraceViolation.deliveryWithoutDemand(
                        subscriptionID: delivery.subscriptionID
                    )
                }

                switch delivery.cause {
                case .initial:
                    guard !state.didDeliverInitial else {
                        throw SQLiteObservationTraceViolation
                            .duplicateInitialDelivery(
                                subscriptionID: delivery.subscriptionID
                            )
                    }
                    state.didDeliverInitial = true

                case .mutation(let mutationID):
                    guard state.didDeliverInitial else {
                        throw SQLiteObservationTraceViolation
                            .mutationBeforeInitialDelivery(
                                subscriptionID: delivery.subscriptionID,
                                mutationID: mutationID
                            )
                    }
                    guard let mutation = mutations[mutationID] else {
                        throw SQLiteObservationTraceViolation.unknownMutation(
                            mutationID: mutationID
                        )
                    }
                    guard mutation.databaseID == delivery.databaseID else {
                        throw SQLiteObservationTraceViolation
                            .wrongDatabaseAttribution(
                                subscriptionID: delivery.subscriptionID,
                                expectedDatabaseID: state.subscription.databaseID,
                                actualDatabaseID: mutation.databaseID
                            )
                    }
                    guard mutation.disposition == .committed else {
                        throw SQLiteObservationTraceViolation
                            .rolledBackMutationDelivered(
                                subscriptionID: delivery.subscriptionID,
                                mutationID: mutationID
                            )
                    }
                    guard !Set(mutation.changedTables).isDisjoint(
                        with: state.subscription.observedTables
                    ) else {
                        throw SQLiteObservationTraceViolation
                            .irrelevantMutationDelivered(
                                subscriptionID: delivery.subscriptionID,
                                mutationID: mutationID
                            )
                    }
                }
                subscriptions[delivery.subscriptionID] = state

            case .failed(let subscriptionID):
                var state = try requireSubscription(
                    subscriptionID,
                    from: subscriptions
                )
                state.isFailed = true
                subscriptions[subscriptionID] = state

            case .cancelled(let subscriptionID):
                var state = try requireSubscription(
                    subscriptionID,
                    from: subscriptions
                )
                state.isCancelled = true
                subscriptions[subscriptionID] = state
            }
        }
    }

    private static func requireSubscription(
        _ subscriptionID: String,
        from subscriptions: [String: SubscriptionState]
    ) throws -> SubscriptionState {
        guard let state = subscriptions[subscriptionID] else {
            throw SQLiteObservationTraceViolation.unknownSubscription(
                subscriptionID: subscriptionID
            )
        }
        return state
    }

    private static func validateDatabaseAttribution(
        delivery: SQLiteObservationDelivery,
        expectedDatabaseID: String
    ) throws {
        guard delivery.databaseID == expectedDatabaseID else {
            throw SQLiteObservationTraceViolation.wrongDatabaseAttribution(
                subscriptionID: delivery.subscriptionID,
                expectedDatabaseID: expectedDatabaseID,
                actualDatabaseID: delivery.databaseID
            )
        }
    }

    private struct SubscriptionState {
        let subscription: SQLiteObservationSubscription
        var outstandingDemand: Int? = 0
        var didDeliverInitial = false
        var isCancelled = false
        var isFailed = false

        mutating func consumeDemand() -> Bool {
            guard let finiteDemand = outstandingDemand else {
                return true
            }
            guard finiteDemand > 0 else {
                return false
            }
            outstandingDemand = finiteDemand - 1
            return true
        }
    }
}


public enum SQLiteObservationConformanceFixtures {

    public static let pinnedGRDBRepository = "groue/GRDB.swift"

    public static let pinnedGRDBCommit =
        "b83108d10f42680d78f23fe4d4d80fc88dab3212"

    public static let cases: [SQLiteObservationConformanceCase] = [
        observationCase(
            .currentInitialValue,
            "First positive demand reads the current initial value."
        ),
        observationCase(
            .freshInitialValuePerSubscriber,
            "Each subscriber owns an observation and receives a fresh initial value."
        ),
        observationCase(
            .rapidRelevantCommits,
            "Rapid relevant commits eventually expose a current durable snapshot."
        ),
        observationCase(
            .irrelevantTableWrite,
            "A committed write outside the tracked region does not expose changed state."
        ),
        observationCase(
            .rollbackSilence,
            "A rolled-back relevant write delivers no value."
        ),
        observationCase(
            .transactionCoalescing,
            "A relevant multi-write transaction exposes only committed durable state."
        ),
        observationCase(
            .transientBusyRetry,
            "Transient SQLite busy failures retry serially within the fixed budget."
        ),
        observationCase(
            .permanentFailure,
            "A permanent execution or decoding failure terminates without retry."
        ),
        observationCase(
            .zeroDemand,
            "Zero downstream demand receives no result value."
        ),
        observationCase(
            .incrementalDemand,
            "Finite demand delivers no more values than have been requested."
        ),
        observationCase(
            .cancellation,
            "Cancellation is terminal and suppresses all later values."
        ),
        observationCase(
            .independentDatabases,
            "Subscriptions are attributed only to their own database pool."
        ),
    ]

    public static let casesByID = Dictionary(
        uniqueKeysWithValues: cases.map { ($0.id, $0) }
    )

    /// Upstream GRDB cases that informed SwiftQL's independently implemented
    /// semantic contracts. No upstream test source is copied into this suite.
    public static let adoptedUpstreamCases: [
        SQLiteObservationConformanceCaseID: [SQLiteObservationUpstreamCase]
    ] = [
        .irrelevantTableWrite: [
            grdbCase(
                path: "Tests/GRDBTests/ValueObservation/ValueObservationTests.swift",
                testCase: "ValueObservationTests.testTrackingExplicitRegion"
            ),
        ],
        .transactionCoalescing: [
            grdbCase(
                path: "Tests/GRDBTests/ValueObservation/ValueObservationTests.swift",
                testCase: "ValueObservationTests.testTrackingExplicitRegion"
            ),
        ],
        .zeroDemand: [
            grdbCase(
                path: "Tests/GRDBTests/GRDBCombineTests/ValueObservationPublisherTests.swift",
                testCase: "ValueObservationPublisherTests.testDemandNoneReceivesNoElement"
            ),
        ],
        .incrementalDemand: [
            grdbCase(
                path: "Tests/GRDBTests/GRDBCombineTests/ValueObservationPublisherTests.swift",
                testCase: "ValueObservationPublisherTests.testDemandOneDoesNotReceiveTwoElements"
            ),
            grdbCase(
                path: "Tests/GRDBTests/GRDBCombineTests/ValueObservationPublisherTests.swift",
                testCase: "ValueObservationPublisherTests.testDemandTwoReceivesTwoElements"
            ),
        ],
        .cancellation: [
            grdbCase(
                path: "Tests/GRDBTests/ValueObservation/ValueObservationTests.swift",
                testCase: "ValueObservationTests.testIssue1550"
            ),
        ],
    ]

    private static func observationCase(
        _ id: SQLiteObservationConformanceCaseID,
        _ summary: String
    ) -> SQLiteObservationConformanceCase {
        SQLiteObservationConformanceCase(id: id, summary: summary)
    }

    private static func grdbCase(
        path: String,
        testCase: String
    ) -> SQLiteObservationUpstreamCase {
        SQLiteObservationUpstreamCase(
            repository: pinnedGRDBRepository,
            commit: pinnedGRDBCommit,
            path: path,
            testCase: testCase
        )
    }
}
