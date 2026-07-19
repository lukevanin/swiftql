import XCTest

import SwiftQLSQLiteConformanceFixtures


final class SQLiteObservationConformanceBoundaryTests: XCTestCase {

    func testFixtureRegistersEveryStableCaseAndPinnedUpstreamReference() {
        XCTAssertEqual(
            Set(SQLiteObservationConformanceFixtures.cases.map(\.id)),
            Set(SQLiteObservationConformanceCaseID.allCases)
        )
        XCTAssertEqual(
            SQLiteObservationConformanceFixtures.cases.count,
            SQLiteObservationConformanceCaseID.allCases.count
        )
        XCTAssertEqual(
            SQLiteObservationConformanceFixtures.pinnedGRDBCommit,
            "b83108d10f42680d78f23fe4d4d80fc88dab3212"
        )

        let adopted = SQLiteObservationConformanceFixtures.adoptedUpstreamCases
        XCTAssertEqual(
            Set(adopted.keys),
            [
                .irrelevantTableWrite,
                .transactionCoalescing,
                .zeroDemand,
                .incrementalDemand,
                .cancellation,
            ]
        )
        XCTAssertEqual(adopted[.incrementalDemand]?.count, 2)
        for references in adopted.values {
            for reference in references {
                XCTAssertEqual(
                    reference.repository,
                    SQLiteObservationConformanceFixtures.pinnedGRDBRepository
                )
                XCTAssertEqual(
                    reference.commit,
                    SQLiteObservationConformanceFixtures.pinnedGRDBCommit
                )
                XCTAssertTrue(reference.path.hasSuffix(".swift"))
                XCTAssertEqual(
                    reference.testCase.split(separator: ".").last?.hasPrefix("test"),
                    true
                )
            }
        }
    }

    func testInventoryRegistersCompletedObservationSuiteAndPinnedProvenance() throws {
        let inventory = try SQLiteConformanceInventory.load()
        let suite = try XCTUnwrap(
            inventory.suites.first { $0.issue == 255 }
        )
        let expectedCaseIDs = SQLiteObservationConformanceCaseID.allCases.map(
            \.rawValue
        )
        let expectedEvidenceIDs = [
            "evidence.observation.fixture-contract",
            "evidence.observation.oracle-positive",
            "evidence.observation.oracle-rejects-rollback",
            "evidence.observation.oracle-rejects-post-cancellation",
            "evidence.observation.oracle-rejects-wrong-database",
            "evidence.observation.initial.sqlite",
            "evidence.observation.subscribers.sqlite",
            "evidence.observation.rapid-commits.sqlite",
            "evidence.observation.irrelevant-write.sqlite",
            "evidence.observation.rollback.sqlite",
            "evidence.observation.transaction.sqlite",
            "evidence.observation.zero-demand.sqlite",
            "evidence.observation.incremental-demand.sqlite",
            "evidence.observation.cancel-before-demand.sqlite",
            "evidence.observation.cancel-in-flight.sqlite",
            "evidence.observation.cancellation.sqlite",
            "evidence.observation.independent-databases.sqlite",
            "evidence.observation.retry-recovers.sqlite",
            "evidence.observation.retry-exhaustion.sqlite",
            "evidence.observation.permanent-failure.sqlite",
        ]

        XCTAssertEqual(suite.id, "suite.255.observation-stress")
        XCTAssertEqual(suite.milestone, "v1.3")
        XCTAssertEqual(suite.status, .completed)
        XCTAssertEqual(suite.caseIDs, expectedCaseIDs)
        XCTAssertEqual(suite.evidenceIDs, expectedEvidenceIDs)

        let featuresByID = Dictionary(
            uniqueKeysWithValues: inventory.features.map { ($0.id, $0) }
        )
        let evidenceByID = Dictionary(
            uniqueKeysWithValues: inventory.evidence.map { ($0.id, $0) }
        )
        let suiteEvidenceIDs = Set(suite.evidenceIDs)
        let adoptedCases = SQLiteObservationConformanceFixtures
            .adoptedUpstreamCases

        for caseID in SQLiteObservationConformanceCaseID.allCases {
            let feature = try XCTUnwrap(
                featuresByID[caseID.rawValue],
                caseID.rawValue
            )
            XCTAssertEqual(feature.status, .supported, caseID.rawValue)
            XCTAssertEqual(
                feature.adoptionStatus,
                .alreadyCovered,
                caseID.rawValue
            )
            XCTAssertTrue(
                Set(feature.evidenceIDs).isSubset(of: suiteEvidenceIDs),
                caseID.rawValue
            )

            let upstreamCases = adoptedCases[caseID] ?? []
            XCTAssertEqual(
                feature.kind,
                upstreamCases.isEmpty ? .adapterContract : .adoptedBehavior,
                caseID.rawValue
            )
            XCTAssertEqual(
                feature.provenance.count,
                upstreamCases.count,
                caseID.rawValue
            )
            for (provenance, upstream) in zip(
                feature.provenance,
                upstreamCases
            ) {
                XCTAssertEqual(provenance.repository, upstream.repository)
                XCTAssertEqual(provenance.commit, upstream.commit)
                XCTAssertEqual(provenance.path, upstream.path)
                XCTAssertEqual(provenance.upstreamCase, upstream.testCase)
                XCTAssertEqual(provenance.licenseSPDX, "MIT")
                XCTAssertEqual(provenance.licenseFilePath, "LICENSE")
                XCTAssertEqual(
                    provenance.licenseBlobSHA,
                    "550890c8912ca08ff000249777b9eeb46411f189"
                )
                XCTAssertFalse(provenance.copiedMaterial)
                XCTAssertNil(provenance.noticePath)
            }
        }

        for evidenceID in expectedEvidenceIDs {
            let evidence = try XCTUnwrap(evidenceByID[evidenceID], evidenceID)
            if evidence.realSQLite {
                XCTAssertTrue(
                    evidence.layers.contains(.observation),
                    evidenceID
                )
                XCTAssertTrue(evidence.layers.contains(.prepare), evidenceID)
                XCTAssertEqual(
                    evidence.environmentIDs,
                    ["sqlite-3.51.0-macos-arm64"],
                    evidenceID
                )
            }
            else {
                XCTAssertTrue(evidence.environmentIDs.isEmpty, evidenceID)
            }
        }
    }

    func testSemanticValidatorAcceptsCommittedRelevantTrace() {
        XCTAssertNoThrow(
            try SQLiteObservationTraceValidator.validate(validTrace())
        )
    }

    func testSemanticValidatorAcceptsConsecutiveEqualSnapshotsForOneMutation() {
        let subscription = fixtureSubscription()
        let committed = fixtureMutation(databaseID: subscription.databaseID)
        let equalDelivery = SQLiteObservationDelivery(
            subscriptionID: subscription.id,
            databaseID: subscription.databaseID,
            rowIDs: ["seed", "committed"],
            cause: .mutation(committed.id)
        )
        let events = initialEvents(for: subscription) + [
            .mutation(committed),
            .delivered(equalDelivery),
            .delivered(equalDelivery),
            .cancelled(subscriptionID: subscription.id),
        ]

        XCTAssertNoThrow(
            try SQLiteObservationTraceValidator.validate(events)
        )
    }

    func testSemanticValidatorRejectsInjectedRollbackLeak() {
        let subscription = fixtureSubscription()
        let rollback = SQLiteObservationMutation(
            id: "rollback-1",
            databaseID: subscription.databaseID,
            disposition: .rolledBack,
            changedTables: ["ObservedRecord"]
        )
        let events = initialEvents(for: subscription) + [
            .mutation(rollback),
            .delivered(
                SQLiteObservationDelivery(
                    subscriptionID: subscription.id,
                    databaseID: subscription.databaseID,
                    rowIDs: ["leaked"],
                    cause: .mutation(rollback.id)
                )
            ),
        ]

        XCTAssertThrowsError(
            try SQLiteObservationTraceValidator.validate(events)
        ) { error in
            XCTAssertEqual(
                error as? SQLiteObservationTraceViolation,
                .rolledBackMutationDelivered(
                    subscriptionID: subscription.id,
                    mutationID: rollback.id
                )
            )
        }
    }

    func testSemanticValidatorRejectsInjectedPostCancellationDelivery() {
        let subscription = fixtureSubscription()
        let committed = fixtureMutation(databaseID: subscription.databaseID)
        let events = initialEvents(for: subscription) + [
            .cancelled(subscriptionID: subscription.id),
            .mutation(committed),
            .delivered(
                SQLiteObservationDelivery(
                    subscriptionID: subscription.id,
                    databaseID: subscription.databaseID,
                    rowIDs: ["late"],
                    cause: .mutation(committed.id)
                )
            ),
        ]

        XCTAssertThrowsError(
            try SQLiteObservationTraceValidator.validate(events)
        ) { error in
            XCTAssertEqual(
                error as? SQLiteObservationTraceViolation,
                .deliveryAfterCancellation(subscriptionID: subscription.id)
            )
        }
    }

    func testSemanticValidatorRejectsInjectedWrongDatabaseAttribution() {
        let subscription = fixtureSubscription()
        let foreignMutation = fixtureMutation(databaseID: "secondary.sqlite")
        let events = initialEvents(for: subscription) + [
            .mutation(foreignMutation),
            .delivered(
                SQLiteObservationDelivery(
                    subscriptionID: subscription.id,
                    databaseID: subscription.databaseID,
                    rowIDs: ["foreign"],
                    cause: .mutation(foreignMutation.id)
                )
            ),
        ]

        XCTAssertThrowsError(
            try SQLiteObservationTraceValidator.validate(events)
        ) { error in
            XCTAssertEqual(
                error as? SQLiteObservationTraceViolation,
                .wrongDatabaseAttribution(
                    subscriptionID: subscription.id,
                    expectedDatabaseID: subscription.databaseID,
                    actualDatabaseID: foreignMutation.databaseID
                )
            )
        }
    }

    private func validTrace() -> [SQLiteObservationTraceEvent] {
        let subscription = fixtureSubscription()
        let committed = fixtureMutation(databaseID: subscription.databaseID)
        return initialEvents(for: subscription) + [
            .mutation(committed),
            .delivered(
                SQLiteObservationDelivery(
                    subscriptionID: subscription.id,
                    databaseID: subscription.databaseID,
                    rowIDs: ["seed", "committed"],
                    cause: .mutation(committed.id)
                )
            ),
            .cancelled(subscriptionID: subscription.id),
        ]
    }

    private func initialEvents(
        for subscription: SQLiteObservationSubscription
    ) -> [SQLiteObservationTraceEvent] {
        [
            .subscribed(subscription),
            .requested(subscriptionID: subscription.id, demand: .unlimited),
            .delivered(
                SQLiteObservationDelivery(
                    subscriptionID: subscription.id,
                    databaseID: subscription.databaseID,
                    rowIDs: ["seed"],
                    cause: .initial
                )
            ),
        ]
    }

    private func fixtureSubscription() -> SQLiteObservationSubscription {
        SQLiteObservationSubscription(
            id: "subscriber-1",
            databaseID: "primary.sqlite",
            observedTables: ["ObservedRecord"]
        )
    }

    private func fixtureMutation(
        databaseID: String
    ) -> SQLiteObservationMutation {
        SQLiteObservationMutation(
            id: "commit-1",
            databaseID: databaseID,
            disposition: .committed,
            changedTables: ["ObservedRecord"]
        )
    }
}
