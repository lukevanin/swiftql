import Foundation
import Combine
import GRDB
import XCTest
@testable import SwiftQL


final class InvocationBindingsGRDBTests: XCTestCase {

    func testContextualDateUUIDAndCustomValuesExecuteWithoutV1LiteralConformance() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let dateReference = try fixture.database.contextualBinding(
            Date.self,
            expressedAs: String.self,
            named: "date"
        )
        let dateRequest = fixture.database.makeRequest(
            with: sql { _ in Select(dateReference) }
        )
        let datePacket = try packet(
            layout: dateRequest.parameterLayout,
            binding: dateReference.encode(date, in: dateRequest.parameterLayout)
        )
        XCTAssertEqual(
            try dateRequest.fetchOne(bindings: datePacket),
            String(date.timeIntervalSince1970)
        )

        let uuid = UUID(uuidString: "12345678-1234-5678-9ABC-DEF012345678")!
        let uuidReference = try fixture.database.contextualBinding(
            UUID.self,
            expressedAs: Data.self,
            named: "uuid"
        )
        let uuidRequest = fixture.database.makeRequest(
            with: sql { _ in Select(uuidReference) }
        )
        let uuidPacket = try packet(
            layout: uuidRequest.parameterLayout,
            binding: uuidReference.encode(uuid, in: uuidRequest.parameterLayout)
        )
        XCTAssertEqual(
            try uuidRequest.fetchOne(bindings: uuidPacket),
            uuidData(uuid)
        )

        let token = InvocationToken(rawValue: 82)
        let tokenReference = try fixture.database.contextualBinding(
            InvocationToken.self,
            expressedAs: Int.self,
            named: "token"
        )
        let tokenRequest = fixture.database.makeRequest(
            with: sql { _ in Select(tokenReference) }
        )
        let tokenPacket = try packet(
            layout: tokenRequest.parameterLayout,
            binding: tokenReference.encode(token, in: tokenRequest.parameterLayout)
        )
        XCTAssertEqual(try tokenRequest.fetchOne(bindings: tokenPacket), 82)

        let optionalDateReference = try fixture.database.contextualBinding(
            Date.self,
            expressedAs: Optional<String>.self,
            named: "optionalDate",
            nullability: .nullable
        )
        let optionalDateRequest = fixture.database.makeRequest(
            with: sql { _ in Select(optionalDateReference.isNull()) }
        )
        let nullPacket = try packet(
            layout: optionalDateRequest.parameterLayout,
            binding: optionalDateReference.encodeOptional(
                nil,
                in: optionalDateRequest.parameterLayout
            )
        )
        XCTAssertEqual(
            try optionalDateRequest.fetchOne(bindings: nullPacket),
            true
        )
    }

    func testIntrinsicPacketsPreserveStorageValuesAndDistinguishMissingFromNull() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        let textReference = XLNamedBindingReference<String>(name: "text")
        let textRequest = fixture.database.makeRequest(
            with: sql { _ in Select(textReference) }
        )
        XCTAssertEqual(
            try textRequest.fetchOne(
                bindings: try packet(
                    layout: textRequest.parameterLayout,
                    value: .text("O'Brien; DROP TABLE records; --")
                )
            ),
            "O'Brien; DROP TABLE records; --"
        )

        let integerReference = XLNamedBindingReference<Int>(name: "integer")
        let integerRequest = fixture.database.makeRequest(
            with: sql { _ in Select(integerReference) }
        )
        XCTAssertEqual(
            try integerRequest.fetchOne(
                bindings: try packet(
                    layout: integerRequest.parameterLayout,
                    value: .integer(82)
                )
            ),
            82
        )

        let repeatedRequest = fixture.database.makeRequest(
            with: sql { _ in Select(integerReference + integerReference) }
        )
        XCTAssertEqual(repeatedRequest.parameterLayout.count, 1)
        XCTAssertEqual(
            try repeatedRequest.fetchOne(
                bindings: try packet(
                    layout: repeatedRequest.parameterLayout,
                    value: .integer(21)
                )
            ),
            42
        )

        let realReference = XLNamedBindingReference<Double>(name: "real")
        let realRequest = fixture.database.makeRequest(
            with: sql { _ in Select(realReference) }
        )
        XCTAssertEqual(
            try realRequest.fetchOne(
                bindings: try packet(
                    layout: realRequest.parameterLayout,
                    value: .real(1.25)
                )
            ),
            1.25
        )

        let blobReference = XLNamedBindingReference<Data>(name: "blob")
        let blobRequest = fixture.database.makeRequest(
            with: sql { _ in Select(blobReference) }
        )
        let blob = Data([0x00, 0x27, 0xFF])
        XCTAssertEqual(
            try blobRequest.fetchOne(
                bindings: try packet(
                    layout: blobRequest.parameterLayout,
                    value: .blob(blob)
                )
            ),
            blob
        )

        let optionalReference = XLNamedBindingReference<Optional<String>>(
            name: "optional"
        )
        let optionalRequest = fixture.database.makeRequest(
            with: sql { _ in Select(optionalReference.isNull()) }
        )
        let missing = XLInvocationBindings<XLSQLiteValue>(
            layout: optionalRequest.parameterLayout
        )
        XCTAssertThrowsError(try optionalRequest.fetchOne(bindings: missing)) { error in
            guard case .missingBindings? = error as? XLInvocationBindingError else {
                return XCTFail("Expected missing binding, received \(error)")
            }
        }
        XCTAssertEqual(
            try optionalRequest.fetchOne(
                bindings: try packet(
                    layout: optionalRequest.parameterLayout,
                    value: .null
                )
            ),
            true
        )
    }

    func testPublicPreparedInvocationExecutesContextualCodecPacketsConcurrently() async throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        let reference = try fixture.database.contextualBinding(
            InvocationToken.self,
            expressedAs: Int.self,
            named: "value"
        )
        let invocation = fixture.database.prepareInvocation(
            with: sql { _ in Select(reference) }
        )
        requireSendable(invocation)
        let layout = invocation.parameterLayout
        let parameter = try reference.preparedParameter(in: layout)
        requireSendable(parameter)

        let values = try await withThrowingTaskGroup(
            of: XLSQLiteValue.self,
            returning: [XLSQLiteValue].self
        ) { group in
            for value in 0 ..< 32 {
                group.addTask {
                    let packet = try XLInvocationBindings(
                        layout: layout,
                        bindings: [
                            parameter.encode(
                                InvocationToken(rawValue: Int64(value))
                            )
                        ]
                    )
                    guard let result = try invocation.fetchOneValues(
                        bindings: packet
                    )?.first else {
                        throw InvocationFixtureError.missingRow
                    }
                    return result
                }
            }

            var results: [XLSQLiteValue] = []
            for try await result in group {
                results.append(result)
            }
            return results
        }

        XCTAssertEqual(
            Set(values),
            Set((0 ..< 32).map { .integer(Int64($0)) })
        )
    }

    func testPreparedInvocationValidatesItsDatabaseCodecSnapshot() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        let dateReference = try fixture.database.contextualBinding(
            Date.self,
            expressedAs: String.self,
            named: "date"
        )
        let statement = sql { _ in Select(dateReference) }

        let emptyConfiguration = try XLValueCodingConfiguration()
        let missingCodecDatabase = try GRDBDatabase(
            databasePool: fixture.database.databasePool,
            codingConfiguration: emptyConfiguration,
            formatter: XLiteFormatter(),
            logger: nil
        )
        let missingCodecInvocation = missingCodecDatabase.prepareInvocation(
            with: statement
        )
        let missingCodecPacket = XLInvocationBindings<XLSQLiteValue>(
            layout: missingCodecInvocation.parameterLayout
        )
        XCTAssertThrowsError(
            try missingCodecInvocation.fetchOneValues(
                bindings: missingCodecPacket
            )
        ) { error in
            guard case .preparedCodecUnavailable(
                let slot,
                let codecIdentity
            ) = error as? XLInvocationBindingError else {
                return XCTFail("Expected unavailable prepared codec, received \(error)")
            }
            XCTAssertEqual(slot.key, .named("date"))
            XCTAssertEqual(codecIdentity, dateReference.declaration.codecIdentity)
        }

        let expectedIdentity = try XCTUnwrap(
            dateReference.declaration.codecIdentity
        )
        let mismatchedCodec = XLValueCodec<Date, XLSQLiteDialect>(
            key: expectedIdentity.key,
            valueTypeIdentifier: expectedIdentity.valueTypeIdentifier,
            dialectIdentifier: expectedIdentity.dialectIdentifier,
            storageIdentifier: XLValueStorageIdentifier(rawValue: "integer"),
            encode: { value, _, _ in
                .integer(Int64(value.timeIntervalSince1970))
            },
            decode: { value, _, _ in
                guard case .integer(let seconds) = value else {
                    throw InvocationFixtureError.invalidValue
                }
                return Date(timeIntervalSince1970: TimeInterval(seconds))
            }
        )
        let mismatchedConfiguration = try XLValueCodingConfiguration(
            registry: XLValueCodecRegistry().registering(mismatchedCodec)
        )
        let mismatchedCodecDatabase = try GRDBDatabase(
            databasePool: fixture.database.databasePool,
            codingConfiguration: mismatchedConfiguration,
            formatter: XLiteFormatter(),
            logger: nil
        )
        let mismatchedCodecInvocation = mismatchedCodecDatabase.prepareInvocation(
            with: statement
        )
        let mismatchedCodecPacket = XLInvocationBindings<XLSQLiteValue>(
            layout: mismatchedCodecInvocation.parameterLayout
        )
        XCTAssertThrowsError(
            try mismatchedCodecInvocation.fetchOneValues(
                bindings: mismatchedCodecPacket
            )
        ) { error in
            guard case .preparedCodecIdentityMismatch(
                let slot,
                let expected,
                let actual
            ) = error as? XLInvocationBindingError else {
                return XCTFail("Expected prepared codec identity mismatch, received \(error)")
            }
            XCTAssertEqual(slot.key, .named("date"))
            XCTAssertEqual(expected, expectedIdentity)
            XCTAssertEqual(actual, mismatchedCodec.identity)
        }
    }

    func testCodecSelectionDialectAndDriverFailuresRetainParameterContext() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        let unknownKey = XLValueCodecKey(
            id: "tests.missing-date-codec",
            version: 1
        )
        let unknownContext = XLValueCodingContext(
            site: .parameter,
            path: XLValueCodingPath(["query", "unknownDate"])
        )
        XCTAssertThrowsError(
            try fixture.database.contextualBinding(
                Date.self,
                expressedAs: String.self,
                named: "unknownDate",
                context: unknownContext,
                selection: XLValueCodecSelection(
                    explicitCodecKey: unknownKey
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? XLValueCodecError,
                .unknownCodec(
                    key: unknownKey,
                    source: .explicit,
                    context: unknownContext
                )
            )
        }

        let foreignIdentity = XLValueCodecIdentity(
            key: XLValueCodecKey(id: "tests.foreign.text", version: 1),
            valueTypeIdentifier: XLValueTypeIdentifier(
                rawValue: "tests.foreign-value"
            ),
            dialectIdentifier: XLDialectIdentifier(
                rawValue: "tests.foreign-dialect"
            ),
            storageIdentifier: XLValueStorageIdentifier(rawValue: "text")
        )
        let foreignDeclaration = XLParameterDeclaration(
            key: .named("foreign"),
            valueTypeIdentifier: foreignIdentity.valueTypeIdentifier,
            valueTypeName: "Tests.ForeignValue",
            nullability: .required,
            codecIdentity: foreignIdentity,
            codingContext: XLValueCodingContext(
                site: .parameter,
                path: XLValueCodingPath("foreign")
            )
        )
        let foreignInvocation = fixture.database.prepareInvocation(
            with: sql { _ in
                Select(DeclaredParameterExpression<String>(
                    declaration: foreignDeclaration
                ))
            }
        )
        let foreignPacket = XLInvocationBindings<XLSQLiteValue>(
            layout: foreignInvocation.parameterLayout
        )
        XCTAssertThrowsError(
            try foreignInvocation.fetchOneValues(bindings: foreignPacket)
        ) { error in
            guard case .preparedCodecDialectMismatch(
                let slot,
                let codecIdentity,
                let expectedDialect
            ) = error as? XLInvocationBindingError else {
                return XCTFail("Expected prepared codec dialect mismatch, received \(error)")
            }
            XCTAssertEqual(slot.key, .named("foreign"))
            XCTAssertEqual(codecIdentity, foreignIdentity)
            XCTAssertEqual(expectedDialect, XLSQLiteDialect.identity)
        }

        let driver = GRDBDatabaseDriver(
            databasePool: fixture.database.databasePool,
            dialect: fixture.database.dialect
        )
        let driverSlot = XLParameterSlot(
            index: XLLogicalParameterIndex(0),
            key: .indexed(0),
            valueTypeIdentifier: XLValueTypeIdentifier(rawValue: "swift.int"),
            valueTypeName: String(reflecting: Int.self),
            nullability: .required,
            codecIdentity: nil,
            codingContext: XLValueCodingContext(
                site: .parameter,
                path: XLValueCodingPath("driverValue")
            )
        )
        let driverLayout = try XLParameterLayout(slots: [driverSlot])
        let driverExecutor = GRDBInvocationExecutor(
            driver: driver,
            logicalStatement: XLLogicalPreparedStatement(
                databaseIdentifier: driver.databaseIdentifier,
                dialectRequirement: XLDialectRequirement(
                    identity: XLSQLiteDialect.identity,
                    capabilities: [.indexedBindings]
                ),
                sql: "SELECT ?1, ?2",
                parameterLayout: driverLayout
            )
        )
        let driverPacket = try XLInvocationBindings(
            layout: driverLayout,
            bindings: [
                try XLInvocationBinding(
                    slot: driverSlot,
                    value: XLSQLiteValue.integer(82)
                )
            ]
        )
        XCTAssertThrowsError(
            try driverExecutor.fetchOne(bindings: driverPacket)
        ) { error in
            guard case .driverArgumentValidationFailed(
                let layout,
                let message
            ) = error as? XLInvocationBindingError else {
                return XCTFail("Expected driver argument validation failure, received \(error)")
            }
            XCTAssertEqual(layout, driverLayout)
            XCTAssertFalse(message.isEmpty)
        }

        let invalidDriverSlot = XLParameterSlot(
            index: XLLogicalParameterIndex(0),
            key: .indexed(-1),
            valueTypeIdentifier: XLValueTypeIdentifier(rawValue: "swift.int"),
            valueTypeName: String(reflecting: Int.self),
            nullability: .required,
            codecIdentity: nil,
            codingContext: XLValueCodingContext(
                site: .parameter,
                path: XLValueCodingPath("invalidDriverValue")
            )
        )
        let invalidDriverLayout = try XLParameterLayout(
            slots: [invalidDriverSlot]
        )
        let invalidDriverExecutor = GRDBInvocationExecutor(
            driver: driver,
            logicalStatement: XLLogicalPreparedStatement(
                databaseIdentifier: driver.databaseIdentifier,
                dialectRequirement: XLDialectRequirement(
                    identity: XLSQLiteDialect.identity,
                    capabilities: [.indexedBindings]
                ),
                sql: "SELECT ?1",
                parameterLayout: invalidDriverLayout
            )
        )
        let invalidDriverPacket = try XLInvocationBindings(
            layout: invalidDriverLayout,
            bindings: [
                try XLInvocationBinding(
                    slot: invalidDriverSlot,
                    value: XLSQLiteValue.integer(82)
                )
            ]
        )
        XCTAssertThrowsError(
            try invalidDriverExecutor.fetchOne(bindings: invalidDriverPacket)
        ) { error in
            guard case .driverBindingFailed(
                let slot,
                let codecIdentity,
                let context,
                let message
            ) = error as? XLInvocationBindingError else {
                return XCTFail("Expected contextual driver bind failure, received \(error)")
            }
            XCTAssertEqual(slot, invalidDriverSlot)
            XCTAssertNil(codecIdentity)
            XCTAssertEqual(context, invalidDriverSlot.codingContext)
            XCTAssertFalse(message.isEmpty)
        }
    }

    func testIndexedAndNonaliasingMixedSQLiteParametersExecute() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        let indexedDeclaration = intrinsicIntegerDeclaration(
            key: .indexed(2),
            path: "indexed"
        )
        let indexedInvocation = fixture.database.prepareInvocation(
            with: sql { _ in
                Select(DeclaredParameterExpression<Int>(
                    declaration: indexedDeclaration
                ))
            }
        )
        let indexedSlot = try XCTUnwrap(
            indexedInvocation.parameterLayout.slots.first
        )
        let indexedPacket = try XLInvocationBindings(
            layout: indexedInvocation.parameterLayout,
            bindings: [
                try XLInvocationBinding(
                    slot: indexedSlot,
                    value: XLSQLiteValue.integer(82)
                )
            ]
        )
        XCTAssertEqual(
            try indexedInvocation.fetchOneValues(
                bindings: indexedPacket
            )?.first,
            .integer(82)
        )

        let namedDeclaration = intrinsicIntegerDeclaration(
            key: .named("namedValue"),
            path: "namedValue"
        )
        let mixedInvocation = fixture.database.prepareInvocation(
            with: sql { _ in
                Select(MixedIntegerParameterExpression(
                    lhs: namedDeclaration,
                    rhs: indexedDeclaration
                ))
            }
        )
        let mixedSlots = mixedInvocation.parameterLayout.slots
        XCTAssertEqual(mixedSlots.map(\.key), [
            .named("namedValue"),
            .indexed(2),
        ])
        let mixedPacket = try XLInvocationBindings(
            layout: mixedInvocation.parameterLayout,
            bindings: [
                try XLInvocationBinding(
                    slot: mixedSlots[0],
                    value: XLSQLiteValue.integer(20)
                ),
                try XLInvocationBinding(
                    slot: mixedSlots[1],
                    value: XLSQLiteValue.integer(22)
                ),
            ]
        )
        XCTAssertEqual(
            try mixedInvocation.fetchOneValues(bindings: mixedPacket)?.first,
            .integer(42)
        )

        let numericNamedDeclaration = intrinsicIntegerDeclaration(
            key: .named("3"),
            path: "numericNamed"
        )
        let numericNamedAndIndexedInvocation = fixture.database.prepareInvocation(
            with: sql { _ in
                Select(MixedIntegerParameterExpression(
                    lhs: numericNamedDeclaration,
                    rhs: indexedDeclaration
                ))
            }
        )
        let numericNamedAndIndexedSlots =
            numericNamedAndIndexedInvocation.parameterLayout.slots
        XCTAssertEqual(numericNamedAndIndexedSlots.map(\.key), [
            .named("3"),
            .indexed(2),
        ])
        let numericNamedAndIndexedPacket = try XLInvocationBindings(
            layout: numericNamedAndIndexedInvocation.parameterLayout,
            bindings: [
                try XLInvocationBinding(
                    slot: numericNamedAndIndexedSlots[0],
                    value: XLSQLiteValue.integer(30)
                ),
                try XLInvocationBinding(
                    slot: numericNamedAndIndexedSlots[1],
                    value: XLSQLiteValue.integer(12)
                ),
            ]
        )
        XCTAssertEqual(
            try numericNamedAndIndexedInvocation.fetchOneValues(
                bindings: numericNamedAndIndexedPacket
            )?.first,
            .integer(42)
        )
    }

    func testLayoutMismatchAndLegacyCodecBypassFailBeforeDriverExecution() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        let dateReference = try fixture.database.contextualBinding(
            Date.self,
            expressedAs: String.self,
            named: "date"
        )
        let request = fixture.database.makeRequest(
            with: sql { _ in Select(dateReference) }
        )
        let wrongPacket = XLInvocationBindings<XLSQLiteValue>(layout: .empty)
        XCTAssertThrowsError(try request.fetchOne(bindings: wrongPacket)) { error in
            guard case .packetLayoutMismatch? = error as? XLInvocationBindingError else {
                return XCTFail("Expected layout mismatch, received \(error)")
            }
        }

        XCTAssertThrowsError(
            try dateReference.encodeOptional(
                nil,
                in: request.parameterLayout
            )
        ) { error in
            guard case .nullForRequiredParameter? = error as? XLInvocationBindingError else {
                return XCTFail("Expected required-null failure, received \(error)")
            }
        }

        let contextualSlot = try XCTUnwrap(request.parameterLayout.slots.first)
        XCTAssertThrowsError(
            try XLInvocationBinding(
                slot: contextualSlot,
                value: XLSQLiteValue.text("forged-without-codec")
            )
        ) { error in
            guard case .codecBindingRequiresPreparedParameter(
                let slot,
                let codecIdentity
            ) = error as? XLInvocationBindingError else {
                return XCTFail("Expected contextual codec provenance failure, received \(error)")
            }
            XCTAssertEqual(slot, contextualSlot)
            XCTAssertEqual(codecIdentity, contextualSlot.codecIdentity)
        }

        // The executor still validates storage defensively for trusted package
        // producers such as future descriptor adapters.
        let invalidStorageBinding = XLInvocationBinding(
            preparedCodecSlot: contextualSlot,
            value: XLSQLiteValue.integer(82)
        )
        let invalidStoragePacket = try XLInvocationBindings(
            layout: request.parameterLayout,
            bindings: [invalidStorageBinding]
        )
        XCTAssertThrowsError(
            try request.fetchOne(bindings: invalidStoragePacket)
        ) { error in
            guard case .dialectValueStorageMismatch(
                let slot,
                let codecIdentity,
                let actualStorage
            ) = error as? XLInvocationBindingError else {
                return XCTFail("Expected contextual storage failure, received \(error)")
            }
            XCTAssertEqual(slot, contextualSlot)
            XCTAssertEqual(codecIdentity, contextualSlot.codecIdentity)
            XCTAssertEqual(actualStorage.rawValue, "integer")
        }

        var compatibilityRequest = request
        compatibilityRequest.set(
            XLNamedBindingReference<String>(name: "date"),
            "bypass"
        )
        XCTAssertThrowsError(try compatibilityRequest.fetchOne()) { error in
            guard case .parameterMetadataMismatch? = error as? XLInvocationBindingError else {
                return XCTFail("Expected contextual codec guard, received \(error)")
            }
        }

        let integerReference = XLNamedBindingReference<Int>(name: "typed")
        var wrongLegacyTypeRequest = fixture.database.makeRequest(
            with: sql { _ in Select(integerReference) }
        )
        wrongLegacyTypeRequest.set(
            XLNamedBindingReference<String>(name: "typed"),
            "not-an-integer"
        )
        XCTAssertThrowsError(try wrongLegacyTypeRequest.fetchOne()) { error in
            guard case .parameterMetadataMismatch? = error as? XLInvocationBindingError else {
                return XCTFail("Expected legacy type mismatch, received \(error)")
            }
        }

        XCTAssertThrowsError(
            try fixture.database.contextualBinding(
                Date.self,
                expressedAs: Int.self,
                named: "date"
            )
        ) { error in
            guard case .storageMismatch? = error as? XLValueCodecError else {
                return XCTFail("Expected literal storage mismatch, received \(error)")
            }
        }

        let firstConflict = try fixture.database.contextualBinding(
            Date.self,
            expressedAs: String.self,
            named: "conflict",
            context: XLValueCodingContext(
                site: .parameter,
                path: XLValueCodingPath("first")
            )
        )
        let secondConflict = try fixture.database.contextualBinding(
            Date.self,
            expressedAs: String.self,
            named: "conflict",
            context: XLValueCodingContext(
                site: .parameter,
                path: XLValueCodingPath("second")
            )
        )
        let conflictRequest = fixture.database.makeRequest(
            with: sql { _ in Select(firstConflict + secondConflict) }
        )
        let conflictPacket = try packet(
            layout: conflictRequest.parameterLayout,
            binding: firstConflict.encode(
                Date(timeIntervalSince1970: 82),
                in: conflictRequest.parameterLayout
            )
        )
        XCTAssertThrowsError(
            try conflictRequest.fetchOne(bindings: conflictPacket)
        ) { error in
            guard case .conflictingParameterIndex? = error as? XLInvocationBindingError else {
                return XCTFail("Expected deferred layout conflict, received \(error)")
            }
        }
    }

    func testPublisherRetainsOneImmutablePacketForObservation() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        try fixture.database.makeRequest(
            with: sqlCreate(InvocationRecord.self)
        ).execute()
        try fixture.database.makeRequest(
            with: sqlInsert(InvocationRecord(id: 1))
        ).execute()
        try fixture.database.makeRequest(
            with: sqlInsert(InvocationRecord(id: 2))
        ).execute()

        let id = XLNamedBindingReference<Int>(name: "id")
        let request = fixture.database.makeRequest(
            with: sql { schema in
                let record = schema.table(InvocationRecord.self)
                Select(record)
                From(record)
                Where(record.id == id)
            }
        )
        let packet = try packet(
            layout: request.parameterLayout,
            value: .integer(2)
        )
        let receivedInitial = expectation(
            description: "packet-backed initial observation"
        )
        let receivedRefresh = expectation(
            description: "packet-backed refreshed observation"
        )
        var outputs: [[InvocationRecord]] = []
        var failure: Error?
        let cancellable = request.publish(bindings: packet).sink(
            receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    failure = error
                    if outputs.isEmpty {
                        receivedInitial.fulfill()
                    }
                    else {
                        receivedRefresh.fulfill()
                    }
                }
            },
            receiveValue: { value in
                outputs.append(value)
                if outputs.count == 1 {
                    receivedInitial.fulfill()
                }
                else if outputs.count == 2 {
                    receivedRefresh.fulfill()
                }
            }
        )

        wait(for: [receivedInitial], timeout: 2)
        XCTAssertEqual(outputs, [[InvocationRecord(id: 2)]])

        try fixture.database.databasePool.write { database in
            try database.execute(
                sql: "DELETE FROM InvocationRecord WHERE id = ?",
                arguments: [2]
            )
        }

        wait(for: [receivedRefresh], timeout: 2)
        cancellable.cancel()
        XCTAssertNil(failure)
        XCTAssertEqual(outputs, [
            [InvocationRecord(id: 2)],
            [],
        ])
    }

    private func packet(
        layout: XLParameterLayout,
        value: XLSQLiteValue
    ) throws -> XLInvocationBindings<XLSQLiteValue> {
        guard let slot = layout.slots.first else {
            throw InvocationFixtureError.missingSlot
        }
        return try packet(
            layout: layout,
            binding: XLInvocationBinding(slot: slot, value: value)
        )
    }

    private func packet(
        layout: XLParameterLayout,
        binding: XLInvocationBinding<XLSQLiteValue>
    ) throws -> XLInvocationBindings<XLSQLiteValue> {
        try XLInvocationBindings(layout: layout, bindings: [binding])
    }
}


private struct DeclaredParameterExpression<Literal: XLLiteral>: XLExpression {
    typealias T = Literal

    let declaration: XLParameterDeclaration

    func makeSQL(context: inout XLBuilder) {
        Literal.wrapSQL(context: &context) { context in
            context.parameter(declaration)
        }
    }
}


private struct MixedIntegerParameterExpression: XLExpression {
    typealias T = Int

    let lhs: XLParameterDeclaration
    let rhs: XLParameterDeclaration

    func makeSQL(context: inout XLBuilder) {
        context.binaryOperator(
            "+",
            left: { context in context.parameter(lhs) },
            right: { context in context.parameter(rhs) }
        )
    }
}


private func intrinsicIntegerDeclaration(
    key: XLBindingKey,
    path: String
) -> XLParameterDeclaration {
    XLParameterDeclaration(
        key: key,
        valueTypeIdentifier: XLValueTypeIdentifier(rawValue: "swift.int"),
        valueTypeName: String(reflecting: Int.self),
        nullability: .required,
        codecIdentity: nil,
        codingContext: XLValueCodingContext(
            site: .parameter,
            path: XLValueCodingPath(path)
        )
    )
}


private func requireSendable<T: Sendable>(_: T) {}


@SQLTable(name: "InvocationRecord")
private struct InvocationRecord: Equatable {
    let id: Int
}


private struct InvocationToken {
    let rawValue: Int64
}


private struct InvocationFixture {
    let directoryURL: URL
    let database: GRDBDatabase

    func tearDown() {
        try? database.databasePool.close()
        try? FileManager.default.removeItem(at: directoryURL)
    }
}


private enum InvocationFixtureError: Error {
    case invalidValue
    case missingRow
    case missingSlot
}


private func makeFixture() throws -> InvocationFixture {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("swiftql-invocation-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
        at: directoryURL,
        withIntermediateDirectories: false
    )

    let dateCodec = XLValueCodec<Date, XLSQLiteDialect>(
        key: XLValueCodecKey(id: "tests.date.text", version: 1),
        valueTypeIdentifier: XLValueTypeIdentifier(rawValue: "foundation.Date"),
        dialectIdentifier: XLSQLiteDialect.identity,
        storageIdentifier: XLValueStorageIdentifier(rawValue: "text"),
        encode: { value, _, _ in
            .text(String(value.timeIntervalSince1970))
        },
        decode: { value, _, _ in
            guard case .text(let text) = value,
                  let seconds = TimeInterval(text) else {
                throw InvocationFixtureError.invalidValue
            }
            return Date(timeIntervalSince1970: seconds)
        }
    )
    let uuidCodec = XLValueCodec<UUID, XLSQLiteDialect>(
        key: XLValueCodecKey(id: "tests.uuid.blob", version: 1),
        valueTypeIdentifier: XLValueTypeIdentifier(rawValue: "foundation.UUID"),
        dialectIdentifier: XLSQLiteDialect.identity,
        storageIdentifier: XLValueStorageIdentifier(rawValue: "blob"),
        encode: { value, _, _ in .blob(uuidData(value)) },
        decode: { _, _, _ in throw InvocationFixtureError.invalidValue }
    )
    let tokenCodec = XLValueCodec<InvocationToken, XLSQLiteDialect>(
        key: XLValueCodecKey(id: "tests.token.integer", version: 1),
        valueTypeIdentifier: XLValueTypeIdentifier(rawValue: "tests.InvocationToken"),
        dialectIdentifier: XLSQLiteDialect.identity,
        storageIdentifier: XLValueStorageIdentifier(rawValue: "integer"),
        encode: { value, _, _ in .integer(value.rawValue) },
        decode: { value, _, _ in
            guard case .integer(let rawValue) = value else {
                throw InvocationFixtureError.invalidValue
            }
            return InvocationToken(rawValue: rawValue)
        }
    )
    let registry = try XLValueCodecRegistry()
        .registering(dateCodec)
        .registering(uuidCodec)
        .registering(tokenCodec)
    let configuration = try XLValueCodingConfiguration(
        registry: registry,
        defaultCodecKeys: [
            dateCodec.identity.key,
            uuidCodec.identity.key,
            tokenCodec.identity.key,
        ]
    )
    let databasePool = try DatabasePool(
        path: directoryURL.appendingPathComponent("database.sqlite").path
    )
    return try InvocationFixture(
        directoryURL: directoryURL,
        database: GRDBDatabase(
            databasePool: databasePool,
            codingConfiguration: configuration,
            formatter: XLiteFormatter(),
            logger: nil
        )
    )
}


private func uuidData(_ value: UUID) -> Data {
    var uuid = value.uuid
    return withUnsafeBytes(of: &uuid) { Data($0) }
}
