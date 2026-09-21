import Foundation
import GRDB
import SwiftQL

private struct BenchmarkCodecValue: Equatable {
    let rawValue: Int64
}

public final class SwiftQLBenchmarkRunner {
    private static let simplePersonID = 257
    private static let joinedCompanyID = 3
    private static let joinedMinimumScore = 40.0
    private static let writeStartID = 200
    private static let writeEndID = 264
    private static let writeScoreDelta = 1.25
    private static let decodeMaximumID = 2
    private static let expectedWriteCount = 64

    private let encoder = XLiteEncoder(formatter: XLiteFormatter())

    public init() {
    }

    public func run(
        configuration: BenchmarkConfiguration,
        packageRoot: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) throws -> BenchmarkReport {
        try configuration.validate()

        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("swiftql-benchmark-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        let databaseURL = temporaryDirectory.appendingPathComponent("fixture.sqlite")
        let databasePool = try DatabasePool(path: databaseURL.path)

        defer {
            try? databasePool.close()
            try? fileManager.removeItem(at: temporaryDirectory)
        }

        let environment = BenchmarkEnvironmentCollector.collect(packageRoot: packageRoot)
        let fixture = try databasePool.writeWithoutTransaction { database in
            try setupFixture(in: database)

            let databaseMetadata = try collectDatabaseMetadata(from: database)
            let simpleArguments: StatementArguments = [
                "personID": Self.simplePersonID,
            ]
            let joinedArguments: StatementArguments = [
                "companyID": Self.joinedCompanyID,
                "minimumScore": Self.joinedMinimumScore,
            ]
            let writeArguments: StatementArguments = [
                "writeStartID": Self.writeStartID,
                "writeEndID": Self.writeEndID,
                "scoreDelta": Self.writeScoreDelta,
            ]
            let decodeArguments: StatementArguments = [
                "decodeID": Self.decodeMaximumID,
            ]

            let simple = try makeReadCase(
                identifier: "simple_parameterized_lookup",
                purpose: "Indexed lookup of one row by a named integer parameter.",
                configuration: configuration,
                database: database,
                arguments: simpleArguments,
                parameters: [
                    Self.parameter(
                        name: "personID",
                        swiftType: "Int",
                        sqliteStorageClass: "INTEGER",
                        value: String(Self.simplePersonID)
                    ),
                ],
                expectedRowCount: 1,
                expectedDecodedRows: [Self.expectedSimplePerson],
                makeStatement: BenchmarkQueries.simpleLookup,
                consumeDecoded: Self.consumePerson
            )

            let simpleInlineLiterals = try makeReadCase(
                identifier: "simple_lookup_inline_literals",
                purpose: "The simple lookup with its person ID rendered inline as a SQL literal instead of a named binding.",
                configuration: configuration,
                database: database,
                arguments: StatementArguments(),
                parameters: [],
                expectedRowCount: 1,
                expectedDecodedRows: [Self.expectedSimplePerson],
                makeStatement: {
                    BenchmarkQueries.simpleLookupInlineLiterals(personID: Self.simplePersonID)
                },
                consumeDecoded: Self.consumePerson
            )

            let joined = try makeReadCase(
                identifier: "representative_multi_join_read",
                purpose: "Bounded two-join read that decodes columns from person, department, and company.",
                configuration: configuration,
                database: database,
                arguments: joinedArguments,
                parameters: [
                    Self.parameter(
                        name: "companyID",
                        swiftType: "Int",
                        sqliteStorageClass: "INTEGER",
                        value: String(Self.joinedCompanyID)
                    ),
                    Self.parameter(
                        name: "minimumScore",
                        swiftType: "Double",
                        sqliteStorageClass: "REAL",
                        value: String(Self.joinedMinimumScore)
                    ),
                ],
                expectedRowCount: 32,
                expectedDecodedRows: Self.expectedJoinedRows,
                makeStatement: BenchmarkQueries.multiJoinRead,
                consumeDecoded: Self.consumeJoinedRow
            )

            let joinedInlineLiterals = try makeReadCase(
                identifier: "representative_multi_join_read_inline_literals",
                purpose: "The multi-join read with its company ID and minimum score rendered inline as SQL literals.",
                configuration: configuration,
                database: database,
                arguments: StatementArguments(),
                parameters: [],
                expectedRowCount: 32,
                expectedDecodedRows: Self.expectedJoinedRows,
                makeStatement: {
                    BenchmarkQueries.multiJoinReadInlineLiterals(
                        companyID: Self.joinedCompanyID,
                        minimumScore: Self.joinedMinimumScore
                    )
                },
                consumeDecoded: Self.consumeJoinedRow
            )

            let write = try makeWriteCase(
                identifier: "bounded_write",
                purpose: "Range update of exactly 64 rows with deterministic rollback after every operation.",
                configuration: configuration,
                database: database,
                arguments: writeArguments,
                parameters: [
                    Self.parameter(
                        name: "writeStartID",
                        swiftType: "Int",
                        sqliteStorageClass: "INTEGER",
                        value: String(Self.writeStartID)
                    ),
                    Self.parameter(
                        name: "writeEndID",
                        swiftType: "Int",
                        sqliteStorageClass: "INTEGER",
                        value: String(Self.writeEndID)
                    ),
                    Self.parameter(
                        name: "scoreDelta",
                        swiftType: "Double",
                        sqliteStorageClass: "REAL",
                        value: String(Self.writeScoreDelta)
                    ),
                ],
                makeStatement: BenchmarkQueries.boundedWrite
            )

            let writeInlineLiterals = try makeWriteCase(
                identifier: "bounded_write_inline_literals",
                purpose: "The bounded write with its ID range and score delta rendered inline as SQL literals.",
                configuration: configuration,
                database: database,
                arguments: StatementArguments(),
                parameters: [],
                makeStatement: {
                    BenchmarkQueries.boundedWriteInlineLiterals(
                        startID: Self.writeStartID,
                        endID: Self.writeEndID,
                        scoreDelta: Self.writeScoreDelta
                    )
                }
            )

            let decode = try makeReadCase(
                identifier: "deterministic_row_decode",
                purpose: "Two wide deterministic rows covering INTEGER, REAL, TEXT, BLOB, Bool, and nullable values.",
                configuration: configuration,
                database: database,
                arguments: decodeArguments,
                parameters: [
                    Self.parameter(
                        name: "decodeID",
                        swiftType: "Int",
                        sqliteStorageClass: "INTEGER",
                        value: String(Self.decodeMaximumID)
                    ),
                ],
                expectedRowCount: 2,
                expectedDecodedRows: Self.expectedDecodeRows,
                makeStatement: BenchmarkQueries.deterministicDecode,
                consumeDecoded: Self.consumeDecodeFixture
            )

            let decodeInlineLiterals = try makeReadCase(
                identifier: "deterministic_row_decode_inline_literals",
                purpose: "The wide-row decode with its maximum ID rendered inline as a SQL literal.",
                configuration: configuration,
                database: database,
                arguments: StatementArguments(),
                parameters: [],
                expectedRowCount: 2,
                expectedDecodedRows: Self.expectedDecodeRows,
                makeStatement: {
                    BenchmarkQueries.deterministicDecodeInlineLiterals(
                        maximumID: Self.decodeMaximumID
                    )
                },
                consumeDecoded: Self.consumeDecodeFixture
            )

            return (
                databaseMetadata: databaseMetadata,
                cases: [
                    simple,
                    simpleInlineLiterals,
                    joined,
                    joinedInlineLiterals,
                    write,
                    writeInlineLiterals,
                    decode,
                    decodeInlineLiterals,
                ]
            )
        }

        let contextualCodec = try makeContextualCodecCase(
            configuration: configuration,
            databasePool: databasePool
        )
        // SwiftQL's own production phases run through a GRDBDatabase over the
        // same pool after the fixture's writer access has returned, because
        // every request takes its own connection access.
        let swiftQLDatabase = try GRDBDatabase(
            databasePool: databasePool,
            formatter: XLiteFormatter(),
            logger: nil
        )
        let swiftQLPhases = try measureSwiftQLPhases(
            configuration: configuration,
            databasePool: databasePool,
            database: swiftQLDatabase
        )
        let sqlCases = try fixture.cases.map { benchmarkCase -> BenchmarkCaseReport in
            guard let extraPhases = swiftQLPhases[benchmarkCase.identifier] else {
                throw BenchmarkError.invalidReport(
                    "no SwiftQL production phases for \(benchmarkCase.identifier)"
                )
            }
            return adding(extraPhases, to: benchmarkCase)
        }
        let report = BenchmarkReport(
            formatVersion: BenchmarkReport.currentFormatVersion,
            generatedAt: Self.timestamp(),
            monotonicClock: "DispatchTime.uptimeNanoseconds",
            sampleUnit: "nanoseconds_per_operation",
            configuration: configuration,
            environment: environment,
            database: fixture.databaseMetadata,
            fixture: BenchmarkFixtureMetadata(
                version: 1,
                companyCount: 8,
                departmentCount: 32,
                personCount: 512,
                decodeFixtureRowCount: 2
            ),
            schemaSQL: Self.schemaSQL,
            cases: sqlCases + [contextualCodec]
        )

        try report.validate()
        return report
    }

    private func makeReadCase<Output: Equatable>(
        identifier: String,
        purpose: String,
        configuration: BenchmarkConfiguration,
        database: Database,
        arguments: StatementArguments,
        parameters: [BenchmarkParameter],
        expectedRowCount: Int,
        expectedDecodedRows: [Output],
        makeStatement: () -> any XLQueryStatement<Output>,
        consumeDecoded: (Output) throws -> UInt64
    ) throws -> BenchmarkCaseReport {
        let decodingStatement = makeStatement()
        let encoding = encoder.makeSQL(decodingStatement)
        let capturedRows = try Row.fetchAll(
            database,
            sql: encoding.sql,
            arguments: arguments
        )
        guard capturedRows.count == expectedRowCount else {
            throw BenchmarkError.missingFixture(
                "\(identifier) expected \(expectedRowCount) rows but fetched \(capturedRows.count)"
            )
        }

        let decoder = GRDBRowDecoder(reader: decodingStatement)
        let decodedFixture = try capturedRows.map { try decoder.decode($0) }
        guard decodedFixture == expectedDecodedRows else {
            throw BenchmarkError.decoding(
                "\(identifier) fixture did not decode to the exact expected values"
            )
        }

        var phases = try measureCommonPhases(
            configuration: configuration,
            database: database,
            sql: encoding.sql,
            arguments: arguments,
            makeEncoding: { self.encoder.makeSQL(makeStatement()) }
        )

        let executionStatement = try database.makeStatement(sql: encoding.sql)
        try executionStatement.setArguments(arguments)
        let execution = try BenchmarkSampler(configuration: configuration).measure(
            notes: [
                "Includes GRDB's required pre-execution reset and SQLite stepping of every result row.",
                "Excludes statement preparation, argument binding, GRDB Row materialization, and SwiftQL decoding.",
            ],
            operation: {
                try executionStatement.execute()
            },
            consume: { _ in
                UInt64(executionStatement.columnCount + expectedRowCount)
            }
        )
        phases[.execution] = .measured(.execution, measurement: execution)

        let decoding = try BenchmarkSampler(configuration: configuration).measure(
            notes: [
                "Decodes the complete captured result set through the production GRDBRowAdapter, XLColumnValuesRowReader, and GRDBRowDecoder path.",
                "Includes decoded-output array allocation; captured GRDB rows, SQL execution, semantic verification, checksumming, and result destruction are outside the timestamp.",
            ],
            operation: {
                try capturedRows.map { try decoder.decode($0) }
            },
            consume: { decodedRows in
                guard decodedRows == expectedDecodedRows else {
                    throw BenchmarkError.decoding(
                        "\(identifier) produced unexpected values while sampling"
                    )
                }
                var checksum: UInt64 = 0
                for row in decodedRows {
                    checksum &+= try consumeDecoded(row)
                }
                return checksum
            }
        )
        phases[.rowDecoding] = .measured(.rowDecoding, measurement: decoding)

        return BenchmarkCaseReport(
            identifier: identifier,
            purpose: purpose,
            sql: encoding.sql,
            parameters: parameters,
            queryPlan: try queryPlan(
                database: database,
                sql: encoding.sql,
                arguments: arguments
            ),
            expectedResultRowCount: expectedRowCount,
            expectedAffectedRowCount: nil,
            phases: orderedPhases(phases)
        )
    }

    private func makeWriteCase(
        identifier: String,
        purpose: String,
        configuration: BenchmarkConfiguration,
        database: Database,
        arguments: StatementArguments,
        parameters: [BenchmarkParameter],
        makeStatement: () -> any XLUpdateStatement<BenchmarkPerson>
    ) throws -> BenchmarkCaseReport {
        let encoding = encoder.makeSQL(makeStatement())
        var phases = try measureCommonPhases(
            configuration: configuration,
            database: database,
            sql: encoding.sql,
            arguments: arguments,
            makeEncoding: { self.encoder.makeSQL(makeStatement()) }
        )

        let statement = try database.makeStatement(sql: encoding.sql)
        try statement.setArguments(arguments)
        let scoreBefore = try requiredDouble(
            database,
            sql: "SELECT SUM(score) FROM benchmark_person"
        )
        let savepoint = "swiftql_benchmark_write"

        let execution = try BenchmarkSampler(configuration: configuration).measure(
            notes: [
                "Updates exactly 64 rows; GRDB's pre-execution reset and SQLite execution are timed.",
                "SAVEPOINT entry, changes-count verification, rollback, release, and post-rollback checksum are outside the timestamp.",
            ],
            beforeSample: {
                try database.execute(sql: "SAVEPOINT \(savepoint)")
            },
            afterSample: {
                try database.execute(sql: "ROLLBACK TO \(savepoint)")
                try database.execute(sql: "RELEASE \(savepoint)")
                let scoreAfter = try self.requiredDouble(
                    database,
                    sql: "SELECT SUM(score) FROM benchmark_person"
                )
                guard scoreAfter == scoreBefore else {
                    throw BenchmarkError.missingFixture("bounded write rollback changed the fixture checksum")
                }
            },
            operation: {
                try statement.execute()
            },
            consume: { _ in
                guard database.changesCount == Self.expectedWriteCount else {
                    throw BenchmarkError.missingFixture(
                        "bounded write affected \(database.changesCount) rows instead of \(Self.expectedWriteCount)"
                    )
                }
                return UInt64(database.changesCount)
            }
        )
        phases[.execution] = .measured(.execution, measurement: execution)
        phases[.rowDecoding] = .notApplicable(
            .rowDecoding,
            reason: "The bounded UPDATE does not have a RETURNING clause and therefore produces no row to decode."
        )

        return BenchmarkCaseReport(
            identifier: identifier,
            purpose: purpose,
            sql: encoding.sql,
            parameters: parameters,
            queryPlan: try queryPlan(
                database: database,
                sql: encoding.sql,
                arguments: arguments
            ),
            expectedResultRowCount: nil,
            expectedAffectedRowCount: Self.expectedWriteCount,
            phases: orderedPhases(phases)
        )
    }

    private func makeContextualCodecCase(
        configuration benchmarkConfiguration: BenchmarkConfiguration,
        databasePool: DatabasePool
    ) throws -> BenchmarkCaseReport {
        let codecKey = XLValueCodecKey(
            id: "swiftql.benchmark.contextual-integer",
            version: 1
        )
        let codec = XLValueCodec<BenchmarkCodecValue, XLSQLiteDialect>(
            key: codecKey,
            valueTypeIdentifier: XLValueTypeIdentifier(
                rawValue: "swiftql.benchmark.contextual-value"
            ),
            dialectIdentifier: XLSQLiteDialect.identity,
            storageIdentifier: XLValueStorageIdentifier(
                rawValue: XLSQLiteStorageClass.integer.rawValue
            ),
            encode: { value, _, _ in
                .integer(value.rawValue)
            },
            decode: { value, _, context in
                guard case .integer(let rawValue) = value else {
                    throw BenchmarkError.decoding(
                        "contextual codec expected INTEGER at \(context)"
                    )
                }
                return BenchmarkCodecValue(rawValue: rawValue)
            }
        )
        let registry = try XLValueCodecRegistry().registering(codec)
        let valueCodingConfiguration = try XLValueCodingConfiguration(
            registry: registry,
            defaultCodecKeys: [codecKey]
        )
        let swiftQLDatabase = try GRDBDatabase(
            databasePool: databasePool,
            codingConfiguration: valueCodingConfiguration,
            formatter: XLiteFormatter(),
            logger: nil
        )
        let input = BenchmarkCodecValue(rawValue: 257)
        let parameterReference = try swiftQLDatabase.contextualBinding(
            BenchmarkCodecValue.self,
            expressedAs: Int.self,
            named: "codecValue"
        )
        let query = sql { _ in Select(parameterReference) }
        let parameterLayout = swiftQLDatabase.makeRequest(with: query).parameterLayout
        let parameter = try parameterReference.preparedParameter(
            in: parameterLayout
        )
        let resultCodec = try valueCodingConfiguration.resolvedCodec(
            for: BenchmarkCodecValue.self,
            using: swiftQLDatabase.dialect,
            context: XLValueCodingContext(
                site: .result,
                path: XLValueCodingPath("codecValue")
            )
        )
        let fixturePacket = try XLInvocationBindings(
            layout: parameterLayout,
            bindings: [parameter.encode(input)]
        ).validatingComplete()
        guard fixturePacket.bindings.map(\.value) == [.integer(input.rawValue)] else {
            throw BenchmarkError.decoding(
                "contextual codec did not produce its declared INTEGER representation"
            )
        }

        let sql = swiftQLDatabase.encoder.makeSQL(query).sql
        let statementArguments = { (packet: XLInvocationBindings<XLSQLiteValue>) throws
            -> StatementArguments in
            guard packet.bindings.count == 1,
                  let binding = packet.bindings.first,
                  binding.slot.key == .named("codecValue"),
                  case .integer(let rawValue) = binding.value else {
                throw BenchmarkError.decoding(
                    "contextual invocation packet did not contain its normalized named INTEGER"
                )
            }
            return ["codecValue": rawValue]
        }
        let fixtureArguments = try statementArguments(fixturePacket)
        let rawPhases = try databasePool.read { database in
            let bindingStatement = try database.makeStatement(sql: sql)
            let binding = try BenchmarkSampler(
                configuration: benchmarkConfiguration
            ).measure(
                notes: [
                    "Includes pre-resolved XLPreparedParameter encode and declared-storage validation, immutable XLInvocationBindings construction/completeness validation, StatementArguments construction from the packet's normalized value, and public Statement.setArguments.",
                    "Excludes registry/default resolution, parameter-layout construction, request construction, and execution; the measured boundary is the production invocation packet followed by direct GRDB binding.",
                ],
                operation: {
                    let packet = try XLInvocationBindings(
                        layout: parameterLayout,
                        bindings: [parameter.encode(input)]
                    ).validatingComplete()
                    try bindingStatement.setArguments(statementArguments(packet))
                    return packet
                },
                consume: { packet in
                    guard packet == fixturePacket else {
                        throw BenchmarkError.decoding(
                            "contextual invocation packet changed while sampling"
                        )
                    }
                    guard bindingStatement.arguments == fixtureArguments else {
                        throw BenchmarkError.invalidReport(
                            "contextual packet binding produced unexpected arguments"
                        )
                    }
                    return UInt64(input.rawValue)
                }
            )

            let capturedRow = try Row.fetchOne(
                database,
                sql: sql,
                arguments: fixtureArguments
            )
            guard let capturedRow else {
                throw BenchmarkError.missingFixture(
                    "contextual codec SELECT did not return its deterministic row"
                )
            }
            return (
                binding: binding,
                capturedRow: capturedRow,
                queryPlan: try queryPlan(
                    database: database,
                    sql: sql,
                    arguments: fixtureArguments
                )
            )
        }

        let decoding = try BenchmarkSampler(configuration: benchmarkConfiguration).measure(
            notes: [
                "Includes extraction of one INTEGER from a captured GRDB Row, normalization to XLSQLiteValue, pre-resolved storage validation, and throwing decode.",
                "Excludes SQL execution, row creation, semantic verification, checksumming, and decoded-value destruction; this is a one-scalar contextual comparison, not the multi-field result-macro baseline.",
            ],
            operation: {
                let rawValue: Int64 = rawPhases.capturedRow[0]
                return try resultCodec.decode(.integer(rawValue))
            },
            consume: { decoded in
                guard decoded == input else {
                    throw BenchmarkError.decoding(
                        "contextual codec produced an unexpected value while sampling"
                    )
                }
                return UInt64(decoded.rawValue)
            }
        )

        var phases: [BenchmarkPhase: BenchmarkPhaseReport] = [
            .swiftQLConstructionAndRendering: .notApplicable(
                .swiftQLConstructionAndRendering,
                reason: "The case measures a prebuilt immutable codec snapshot, not SQL DSL construction or rendering."
            ),
            .coldStatementPreparation: .notApplicable(
                .coldStatementPreparation,
                reason: "Statement preparation is already isolated by the SQL cases and does not invoke value codecs."
            ),
            .cachedStatementLookup: .notApplicable(
                .cachedStatementLookup,
                reason: "Statement-cache lookup is already isolated by the SQL cases and does not invoke value codecs."
            ),
            .statementResetAndBinding: .measured(
                .statementResetAndBinding,
                measurement: rawPhases.binding
            ),
            .execution: .notApplicable(
                .execution,
                reason: "Public request execution also decodes its scalar result, so it cannot satisfy the execution phase's SQLite-only boundary."
            ),
            .rowDecoding: .measured(.rowDecoding, measurement: decoding),
        ]
        for phase in Self.swiftQLProductionPhases {
            phases[phase] = .notApplicable(
                phase,
                reason: "The contextual-codec case isolates value-codec conversion; the SQL cases measure SwiftQL's production binding, execution, materialization, decoding, fetchAll(), and execute() phases."
            )
        }

        return BenchmarkCaseReport(
            identifier: "contextual_value_codec",
            purpose: "One deterministic INTEGER value encoded and decoded through an immutable contextual codec configuration.",
            sql: sql,
            parameters: [
                Self.parameter(
                    name: "codecValue",
                    swiftType: "BenchmarkCodecValue",
                    sqliteStorageClass: "INTEGER",
                    value: String(input.rawValue)
                ),
            ],
            queryPlan: rawPhases.queryPlan,
            expectedResultRowCount: 1,
            expectedAffectedRowCount: nil,
            phases: orderedPhases(phases)
        )
    }

    // MARK: SwiftQL production phases (format version 2)

    private static let swiftQLProductionPhases: [BenchmarkPhase] = [
        .swiftQLBinding,
        .swiftQLExecution,
        .swiftQLRowMaterialization,
        .swiftQLRowDecoding,
        .swiftQLFetchAll,
        .swiftQLExecute,
    ]

    private static let scoreChecksumSQL = "SELECT SUM(score) FROM benchmark_person"

    /// Restores the bounded write's 64 scores to their fixture values. SQLite
    /// divides the same integer by 10.0 as `setupFixture`, so every restored
    /// REAL is bit-identical and the score checksum matches exactly.
    private static var restoreWriteRangeSQL: String {
        "UPDATE benchmark_person SET score = ((id * 37) % 1000) / 10.0 WHERE id >= \(writeStartID) AND id < \(writeEndID)"
    }

    private func adding(
        _ extraPhases: [BenchmarkPhase: BenchmarkPhaseReport],
        to benchmarkCase: BenchmarkCaseReport
    ) -> BenchmarkCaseReport {
        var phases: [BenchmarkPhase: BenchmarkPhaseReport] = [:]
        for phaseReport in benchmarkCase.phases {
            phases[phaseReport.phase] = phaseReport
        }
        for (phase, phaseReport) in extraPhases {
            phases[phase] = phaseReport
        }
        return BenchmarkCaseReport(
            identifier: benchmarkCase.identifier,
            purpose: benchmarkCase.purpose,
            sql: benchmarkCase.sql,
            parameters: benchmarkCase.parameters,
            queryPlan: benchmarkCase.queryPlan,
            expectedResultRowCount: benchmarkCase.expectedResultRowCount,
            expectedAffectedRowCount: benchmarkCase.expectedAffectedRowCount,
            phases: orderedPhases(phases)
        )
    }

    private func measureSwiftQLPhases(
        configuration: BenchmarkConfiguration,
        databasePool: DatabasePool,
        database: GRDBDatabase
    ) throws -> [String: [BenchmarkPhase: BenchmarkPhaseReport]] {
        var phases: [String: [BenchmarkPhase: BenchmarkPhaseReport]] = [:]

        phases["simple_parameterized_lookup"] = try measureSwiftQLReadPhases(
            configuration: configuration,
            database: database,
            makeStatement: BenchmarkQueries.simpleLookup,
            bind: { request in
                request.set(parameter: BenchmarkQueries.personID, value: Self.simplePersonID)
            },
            expectedRows: [Self.expectedSimplePerson],
            consumeDecoded: Self.consumePerson
        )
        phases["simple_lookup_inline_literals"] = try measureSwiftQLReadPhases(
            configuration: configuration,
            database: database,
            makeStatement: {
                BenchmarkQueries.simpleLookupInlineLiterals(personID: Self.simplePersonID)
            },
            bind: { _ in },
            expectedRows: [Self.expectedSimplePerson],
            consumeDecoded: Self.consumePerson
        )

        phases["representative_multi_join_read"] = try measureSwiftQLReadPhases(
            configuration: configuration,
            database: database,
            makeStatement: BenchmarkQueries.multiJoinRead,
            bind: { request in
                request.set(parameter: BenchmarkQueries.companyID, value: Self.joinedCompanyID)
                request.set(parameter: BenchmarkQueries.minimumScore, value: Self.joinedMinimumScore)
            },
            expectedRows: Self.expectedJoinedRows,
            consumeDecoded: Self.consumeJoinedRow
        )
        phases["representative_multi_join_read_inline_literals"] = try measureSwiftQLReadPhases(
            configuration: configuration,
            database: database,
            makeStatement: {
                BenchmarkQueries.multiJoinReadInlineLiterals(
                    companyID: Self.joinedCompanyID,
                    minimumScore: Self.joinedMinimumScore
                )
            },
            bind: { _ in },
            expectedRows: Self.expectedJoinedRows,
            consumeDecoded: Self.consumeJoinedRow
        )

        phases["bounded_write"] = try measureSwiftQLWritePhases(
            configuration: configuration,
            databasePool: databasePool,
            database: database,
            makeStatement: BenchmarkQueries.boundedWrite,
            bind: { request in
                request.set(parameter: BenchmarkQueries.writeStartID, value: Self.writeStartID)
                request.set(parameter: BenchmarkQueries.writeEndID, value: Self.writeEndID)
                request.set(parameter: BenchmarkQueries.scoreDelta, value: Self.writeScoreDelta)
            }
        )
        phases["bounded_write_inline_literals"] = try measureSwiftQLWritePhases(
            configuration: configuration,
            databasePool: databasePool,
            database: database,
            makeStatement: {
                BenchmarkQueries.boundedWriteInlineLiterals(
                    startID: Self.writeStartID,
                    endID: Self.writeEndID,
                    scoreDelta: Self.writeScoreDelta
                )
            },
            bind: { _ in }
        )

        phases["deterministic_row_decode"] = try measureSwiftQLReadPhases(
            configuration: configuration,
            database: database,
            makeStatement: BenchmarkQueries.deterministicDecode,
            bind: { request in
                request.set(parameter: BenchmarkQueries.decodeID, value: Self.decodeMaximumID)
            },
            expectedRows: Self.expectedDecodeRows,
            consumeDecoded: Self.consumeDecodeFixture
        )
        phases["deterministic_row_decode_inline_literals"] = try measureSwiftQLReadPhases(
            configuration: configuration,
            database: database,
            makeStatement: {
                BenchmarkQueries.deterministicDecodeInlineLiterals(
                    maximumID: Self.decodeMaximumID
                )
            },
            bind: { _ in },
            expectedRows: Self.expectedDecodeRows,
            consumeDecoded: Self.consumeDecodeFixture
        )

        return phases
    }

    private func measureSwiftQLReadPhases<Output: Equatable & Sendable>(
        configuration: BenchmarkConfiguration,
        database: GRDBDatabase,
        makeStatement: () -> any XLQueryStatement<Output>,
        bind: (inout any XLRequest<Output>) -> Void,
        expectedRows: [Output],
        consumeDecoded: (Output) throws -> UInt64
    ) throws -> [BenchmarkPhase: BenchmarkPhaseReport] {
        var request = database.makeRequest(with: makeStatement())
        bind(&request)
        let probe = try GRDBRequestPhaseProbe(request: request)

        let connectionPhases = try probe.withConnection { connection -> (
            binding: BenchmarkMeasurement,
            execution: BenchmarkMeasurement,
            materialization: BenchmarkMeasurement,
            rows: [[XLSQLiteValue]]
        ) in
            let statement = try connection.bind()
            let expectedBindingCount = statement.bindingCount
            let rows = try connection.materializedRows(statement)
            guard rows.count == expectedRows.count else {
                throw BenchmarkError.missingFixture(
                    "SwiftQL production path materialized \(rows.count) rows instead of \(expectedRows.count)"
                )
            }
            let expectedValueCount = rows.reduce(0) { $0 + $1.count }

            let binding = try BenchmarkSampler(configuration: configuration).measure(
                notes: [
                    "Builds the request's invocation packet from its named bindings (empty for inline literals), validates it against the parameter layout, takes the connection's cached statement, binds the validated values, and validates GRDB's arguments: the GRDBInvocationExecutor calls that fetchAll() makes.",
                    "Runs inside one already-open read access; request construction, rendering, and connection access are excluded.",
                ],
                operation: {
                    try connection.bind()
                },
                consume: { bound in
                    guard bound.bindingCount == expectedBindingCount else {
                        throw BenchmarkError.invalidReport("SwiftQL binding count changed while sampling")
                    }
                    return UInt64(bound.bindingCount)
                }
            )

            let execution = try BenchmarkSampler(configuration: configuration).measure(
                notes: [
                    "Opens GRDB's row cursor on the bound production statement (reset and SQLite argument binding) and steps every result row without reading a column.",
                    "Excludes SwiftQL binding, column materialization, and decoding.",
                ],
                operation: {
                    try connection.step(statement)
                },
                consume: { rowCount in
                    guard rowCount == expectedRows.count else {
                        throw BenchmarkError.missingFixture("SwiftQL stepping visited \(rowCount) rows")
                    }
                    return UInt64(rowCount)
                }
            )

            let materialization = try BenchmarkSampler(configuration: configuration).measure(
                notes: [
                    "Steps every result row and normalizes every column to XLSQLiteValue through the production forEachRow cursor loop, without decoding.",
                    "Includes opening and stepping the cursor, so it is not additive with swiftql_execution.",
                ],
                operation: {
                    try connection.materialize(statement)
                },
                consume: { valueCount in
                    guard valueCount == expectedValueCount else {
                        throw BenchmarkError.missingFixture("SwiftQL materialized \(valueCount) values")
                    }
                    return UInt64(valueCount)
                }
            )

            return (binding, execution, materialization, rows)
        }

        guard try probe.decode(connectionPhases.rows) == expectedRows else {
            throw BenchmarkError.decoding(
                "SwiftQL production decoding did not produce the exact expected values"
            )
        }

        let decoding = try BenchmarkSampler(configuration: configuration).measure(
            notes: [
                "Decodes the complete result, materialized once before sampling, through GRDBRowDecoder.decode(values:), the per-row call inside fetchAll().",
                "Includes decoded-output array allocation; SQL execution and column materialization are excluded.",
            ],
            operation: {
                try probe.decode(connectionPhases.rows)
            },
            consume: { decodedRows in
                guard decodedRows == expectedRows else {
                    throw BenchmarkError.decoding("SwiftQL production decoding changed while sampling")
                }
                var checksum: UInt64 = 0
                for row in decodedRows {
                    checksum &+= try consumeDecoded(row)
                }
                return checksum
            }
        )

        let fetchAll = try BenchmarkSampler(configuration: configuration).measure(
            notes: [
                "Public XLRequest.fetchAll() on a prepared request with its bindings set: packet validation, one pooled read access, binding, stepping, materialization, and decoding.",
                "Request construction and rendering are excluded; semantic verification and checksumming follow the end timestamp.",
            ],
            operation: {
                try request.fetchAll()
            },
            consume: { fetchedRows in
                guard fetchedRows == expectedRows else {
                    throw BenchmarkError.decoding("fetchAll() produced unexpected rows while sampling")
                }
                var checksum: UInt64 = 0
                for row in fetchedRows {
                    checksum &+= try consumeDecoded(row)
                }
                return checksum
            }
        )

        return [
            .swiftQLBinding: .measured(.swiftQLBinding, measurement: connectionPhases.binding),
            .swiftQLExecution: .measured(.swiftQLExecution, measurement: connectionPhases.execution),
            .swiftQLRowMaterialization: .measured(
                .swiftQLRowMaterialization,
                measurement: connectionPhases.materialization
            ),
            .swiftQLRowDecoding: .measured(.swiftQLRowDecoding, measurement: decoding),
            .swiftQLFetchAll: .measured(.swiftQLFetchAll, measurement: fetchAll),
            .swiftQLExecute: .notApplicable(
                .swiftQLExecute,
                reason: "A SELECT runs through fetchAll(); XLWriteRequest.execute() applies only to a statement that returns no rows."
            ),
        ]
    }

    private func measureSwiftQLWritePhases(
        configuration: BenchmarkConfiguration,
        databasePool: DatabasePool,
        database: GRDBDatabase,
        makeStatement: () -> any XLUpdateStatement<BenchmarkPerson>,
        bind: (inout any XLWriteRequest) -> Void
    ) throws -> [BenchmarkPhase: BenchmarkPhaseReport] {
        var request = database.makeRequest(with: makeStatement())
        bind(&request)
        let probe = try GRDBRequestPhaseProbe<Void>(writeRequest: request)
        let scoreBefore = try databasePool.read { database in
            try self.requiredDouble(database, sql: Self.scoreChecksumSQL)
        }
        let savepoint = "swiftql_benchmark_production_write"

        let connectionPhases = try probe.withConnection { connection -> (
            binding: BenchmarkMeasurement,
            execution: BenchmarkMeasurement
        ) in
            let statement = try connection.bind()
            let expectedBindingCount = statement.bindingCount

            let binding = try BenchmarkSampler(configuration: configuration).measure(
                notes: [
                    "Builds the request's invocation packet from its named bindings (empty for inline literals), validates it against the parameter layout, takes the writer's cached statement, binds the validated values, and validates GRDB's arguments: the GRDBInvocationExecutor calls that execute() makes.",
                    "Runs inside one already-open writer access; request construction, rendering, connection access, and the transaction are excluded.",
                ],
                operation: {
                    try connection.bind()
                },
                consume: { bound in
                    guard bound.bindingCount == expectedBindingCount else {
                        throw BenchmarkError.invalidReport("SwiftQL binding count changed while sampling")
                    }
                    return UInt64(bound.bindingCount)
                }
            )

            let execution = try BenchmarkSampler(configuration: configuration).measure(
                notes: [
                    "Executes the bound production statement once: GRDB reset, SQLite argument binding, and the 64-row UPDATE.",
                    "SAVEPOINT entry, changes-count verification, rollback, release, and the post-rollback checksum are outside the timestamp.",
                ],
                beforeSample: {
                    try connection.withUnmeasuredDatabase { database in
                        try database.execute(sql: "SAVEPOINT \(savepoint)")
                    }
                },
                afterSample: {
                    try connection.withUnmeasuredDatabase { database in
                        try database.execute(sql: "ROLLBACK TO \(savepoint)")
                        try database.execute(sql: "RELEASE \(savepoint)")
                        let scoreAfter = try self.requiredDouble(database, sql: Self.scoreChecksumSQL)
                        guard scoreAfter == scoreBefore else {
                            throw BenchmarkError.missingFixture(
                                "SwiftQL production write rollback changed the fixture checksum"
                            )
                        }
                    }
                },
                operation: {
                    try connection.execute(statement)
                },
                consume: { _ in
                    try connection.withUnmeasuredDatabase { database in
                        guard database.changesCount == Self.expectedWriteCount else {
                            throw BenchmarkError.missingFixture(
                                "SwiftQL production write affected \(database.changesCount) rows instead of \(Self.expectedWriteCount)"
                            )
                        }
                        return UInt64(database.changesCount)
                    }
                }
            )

            return (binding, execution)
        }

        let execute = try BenchmarkSampler(configuration: configuration).measure(
            notes: [
                "Public XLWriteRequest.execute() on a prepared request with its bindings set: packet validation, one pooled write transaction with its commit, binding, and the 64-row UPDATE.",
                "Checking the committed score total, restoring the 64 scores, and checking the fixture checksum happen after the end timestamp in separate accesses.",
            ],
            afterSample: {
                try databasePool.write { database in
                    try database.execute(sql: Self.restoreWriteRangeSQL)
                    let scoreAfter = try self.requiredDouble(database, sql: Self.scoreChecksumSQL)
                    guard scoreAfter == scoreBefore else {
                        throw BenchmarkError.missingFixture(
                            "restoring the bounded write changed the fixture checksum"
                        )
                    }
                }
            },
            operation: {
                try request.execute()
            },
            consume: { _ in
                let scoreAfterWrite = try databasePool.read { database in
                    try self.requiredDouble(database, sql: Self.scoreChecksumSQL)
                }
                let expectedDelta = Double(Self.expectedWriteCount) * Self.writeScoreDelta
                guard abs(scoreAfterWrite - scoreBefore - expectedDelta) < 1e-6 else {
                    throw BenchmarkError.missingFixture(
                        "execute() did not add the bounded write's score delta"
                    )
                }
                return UInt64(Self.expectedWriteCount)
            }
        )

        let noRowsReason = "The bounded UPDATE does not have a RETURNING clause and therefore produces no row to materialize, decode, or fetch."
        return [
            .swiftQLBinding: .measured(.swiftQLBinding, measurement: connectionPhases.binding),
            .swiftQLExecution: .measured(.swiftQLExecution, measurement: connectionPhases.execution),
            .swiftQLRowMaterialization: .notApplicable(.swiftQLRowMaterialization, reason: noRowsReason),
            .swiftQLRowDecoding: .notApplicable(.swiftQLRowDecoding, reason: noRowsReason),
            .swiftQLFetchAll: .notApplicable(.swiftQLFetchAll, reason: noRowsReason),
            .swiftQLExecute: .measured(.swiftQLExecute, measurement: execute),
        ]
    }

    private func measureCommonPhases(
        configuration: BenchmarkConfiguration,
        database: Database,
        sql: String,
        arguments: StatementArguments,
        makeEncoding: () -> XLEncoding
    ) throws -> [BenchmarkPhase: BenchmarkPhaseReport] {
        var phases: [BenchmarkPhase: BenchmarkPhaseReport] = [:]

        let construction = try BenchmarkSampler(configuration: configuration).measure(
            notes: [
                "Includes complete SwiftQL schema/meta construction and XLiteEncoder rendering.",
                "Excludes all GRDB and database work.",
            ],
            operation: makeEncoding,
            consume: { encoding in
                guard encoding.sql == sql else {
                    throw BenchmarkError.invalidReport("DSL rendering was not deterministic")
                }
                return UInt64(encoding.sql.utf8.count + encoding.entities.count)
            }
        )
        phases[.swiftQLConstructionAndRendering] = .measured(
            .swiftQLConstructionAndRendering,
            measurement: construction
        )

        let preparation = try BenchmarkSampler(configuration: configuration).measure(
            notes: [
                "Uncached Database.makeStatement(sql:) on one already-open, schema-warm connection.",
                "The returned Statement remains alive until after the end timestamp, so finalization is excluded.",
            ],
            operation: {
                try database.makeStatement(sql: sql)
            },
            consume: { statement in
                UInt64(statement.sql.utf8.count + statement.columnCount)
            }
        )
        phases[.coldStatementPreparation] = .measured(
            .coldStatementPreparation,
            measurement: preparation
        )

        let primedStatement = try database.cachedStatement(sql: sql)
        let primedIdentity = ObjectIdentifier(primedStatement)
        let cachedLookup = try BenchmarkSampler(configuration: configuration).measure(
            notes: [
                "The exact SQL string is primed once; each sample is a same-connection public cache hit.",
                "Object identity is verified after each timestamp.",
            ],
            operation: {
                try database.cachedStatement(sql: sql)
            },
            consume: { statement in
                guard ObjectIdentifier(statement) == primedIdentity else {
                    throw BenchmarkError.invalidReport("cached statement identity changed")
                }
                return UInt64(bitPattern: Int64(ObjectIdentifier(statement).hashValue))
            }
        )
        phases[.cachedStatementLookup] = .measured(
            .cachedStatementLookup,
            measurement: cachedLookup
        )

        let bindingStatement = try database.makeStatement(sql: sql)
        let binding = try BenchmarkSampler(configuration: configuration).measure(
            notes: [
                "Times public Statement.setArguments only.",
                "Intentionally includes validation, reset, clear-bindings, and binding; arguments are built outside the timestamp.",
            ],
            operation: {
                try bindingStatement.setArguments(arguments)
            },
            consume: { _ in
                let boundArguments = bindingStatement.arguments
                guard boundArguments == arguments else {
                    throw BenchmarkError.invalidReport("bound arguments changed")
                }
                return UInt64(boundArguments.description.utf8.count)
            }
        )
        phases[.statementResetAndBinding] = .measured(
            .statementResetAndBinding,
            measurement: binding
        )

        return phases
    }

    private func orderedPhases(
        _ phases: [BenchmarkPhase: BenchmarkPhaseReport]
    ) -> [BenchmarkPhaseReport] {
        BenchmarkPhase.allCases.compactMap { phases[$0] }
    }

    private func queryPlan(
        database: Database,
        sql: String,
        arguments: StatementArguments
    ) throws -> [String] {
        try Row.fetchAll(
            database,
            sql: "EXPLAIN QUERY PLAN \(sql)",
            arguments: arguments
        ).map { row in
            let detail: String = row["detail"]
            return detail
        }
    }

    private func setupFixture(in database: Database) throws {
        for statement in Self.schemaSQL {
            try database.execute(sql: statement)
        }

        try database.inTransaction {
            let companyInsert = try database.makeStatement(
                sql: "INSERT INTO benchmark_company (id, name) VALUES (?, ?)"
            )
            for id in 1 ... 8 {
                try companyInsert.execute(arguments: [id, "Company \(id)"])
            }

            let departmentInsert = try database.makeStatement(
                sql: "INSERT INTO benchmark_department (id, companyID, name) VALUES (?, ?, ?)"
            )
            for id in 1 ... 32 {
                let companyID = ((id - 1) % 8) + 1
                try departmentInsert.execute(
                    arguments: [id, companyID, "Department \(id)"]
                )
            }

            let personInsert = try database.makeStatement(
                sql: """
                    INSERT INTO benchmark_person
                        (id, companyID, departmentID, name, email, score, isActive, payload)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """
            )
            for id in 1 ... 512 {
                let departmentID = ((id - 1) % 32) + 1
                let companyID = ((departmentID - 1) % 8) + 1
                let score = Double((id * 37) % 1_000) / 10
                let payload = Data((0 ..< 16).map { UInt8((id + $0) % 256) })
                let values: [(any DatabaseValueConvertible)?] = [
                    id,
                    companyID,
                    departmentID,
                    "Person \(id)",
                    "person\(id)@example.test",
                    score,
                    id % 3 != 0,
                    payload,
                ]
                try personInsert.execute(arguments: StatementArguments(values))
            }

            let decodeInsert = try database.makeStatement(
                sql: """
                    INSERT INTO benchmark_decode_fixture
                        (id, integerValue, realValue, textValue, blobValue, optionalInteger, optionalText, flag)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """
            )
            for id in 1 ... 2 {
                let optionalInteger: (any DatabaseValueConvertible)? = id == 1 ? nil : 42
                let optionalText: (any DatabaseValueConvertible)? = id == 1 ? nil : "present"
                let values: [(any DatabaseValueConvertible)?] = [
                    id,
                    id * 10,
                    Double(id) + 0.25,
                    "Decode fixture \(id)",
                    Data([UInt8(id), 1, 2, 3, 4, 5, 6, 7]),
                    optionalInteger,
                    optionalText,
                    id == 2,
                ]
                try decodeInsert.execute(arguments: StatementArguments(values))
            }
            return .commit
        }
    }

    private func collectDatabaseMetadata(
        from database: Database
    ) throws -> BenchmarkDatabaseMetadata {
        BenchmarkDatabaseMetadata(
            storage: "temporary file-backed SQLite database",
            sqliteVersion: try requiredString(database, sql: "SELECT sqlite_version()"),
            sqliteSourceID: try requiredString(database, sql: "SELECT sqlite_source_id()"),
            compileOptions: try String.fetchAll(
                database,
                sql: "PRAGMA compile_options"
            ).sorted(),
            journalMode: try requiredString(database, sql: "PRAGMA journal_mode"),
            synchronous: try requiredInt(database, sql: "PRAGMA synchronous"),
            pageSizeBytes: try requiredInt(database, sql: "PRAGMA page_size")
        )
    }

    private func requiredString(_ database: Database, sql: String) throws -> String {
        guard let value = try String.fetchOne(database, sql: sql) else {
            throw BenchmarkError.missingFixture("no value returned by \(sql)")
        }
        return value
    }

    private func requiredInt(_ database: Database, sql: String) throws -> Int {
        guard let value = try Int.fetchOne(database, sql: sql) else {
            throw BenchmarkError.missingFixture("no value returned by \(sql)")
        }
        return value
    }

    private func requiredDouble(_ database: Database, sql: String) throws -> Double {
        guard let value = try Double.fetchOne(database, sql: sql) else {
            throw BenchmarkError.missingFixture("no value returned by \(sql)")
        }
        return value
    }

    private static func parameter(
        name: String,
        swiftType: String,
        sqliteStorageClass: String,
        value: String
    ) -> BenchmarkParameter {
        BenchmarkParameter(
            name: name,
            swiftType: swiftType,
            sqliteStorageClass: sqliteStorageClass,
            valueDescription: value
        )
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    private static func consumePerson(_ row: BenchmarkPerson) -> UInt64 {
        UInt64(row.id)
            &+ UInt64(row.companyID)
            &+ UInt64(row.departmentID)
            &+ UInt64(row.name.utf8.count)
            &+ UInt64(row.email.utf8.count)
            &+ row.score.bitPattern
            &+ UInt64(row.payload.count)
            &+ (row.isActive ? 1 : 0)
    }

    private static func consumeJoinedRow(_ row: BenchmarkJoinedRow) -> UInt64 {
        UInt64(row.personID)
            &+ UInt64(row.personName.utf8.count)
            &+ UInt64(row.departmentName.utf8.count)
            &+ UInt64(row.companyName.utf8.count)
            &+ row.score.bitPattern
            &+ (row.isActive ? 1 : 0)
    }

    private static func consumeDecodeFixture(_ row: BenchmarkDecodeFixture) -> UInt64 {
        UInt64(row.id)
            &+ UInt64(row.integerValue)
            &+ row.realValue.bitPattern
            &+ UInt64(row.textValue.utf8.count)
            &+ UInt64(row.blobValue.count)
            &+ UInt64(row.optionalInteger ?? 0)
            &+ UInt64(row.optionalText?.utf8.count ?? 0)
            &+ (row.flag ? 1 : 0)
    }

    private static var expectedSimplePerson: BenchmarkPerson {
        let id = simplePersonID
        return BenchmarkPerson(
            id: id,
            companyID: 1,
            departmentID: 1,
            name: "Person \(id)",
            email: "person\(id)@example.test",
            score: 50.9,
            isActive: true,
            payload: Data((0 ..< 16).map { UInt8((id + $0) % 256) })
        )
    }

    private static var expectedJoinedRows: [BenchmarkJoinedRow] {
        let candidates = (1 ... 512).compactMap { id -> BenchmarkJoinedRow? in
            let departmentID = ((id - 1) % 32) + 1
            let companyID = ((departmentID - 1) % 8) + 1
            let score = Double((id * 37) % 1_000) / 10
            guard companyID == joinedCompanyID, score >= joinedMinimumScore else {
                return nil
            }
            return BenchmarkJoinedRow(
                personID: id,
                personName: "Person \(id)",
                departmentName: "Department \(departmentID)",
                companyName: "Company \(companyID)",
                score: score,
                isActive: id % 3 != 0
            )
        }
        return Array(
            candidates.sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.personID < rhs.personID
                }
                return lhs.score > rhs.score
            }.prefix(32)
        )
    }

    private static var expectedDecodeRows: [BenchmarkDecodeFixture] {
        (1 ... decodeMaximumID).map { id in
            let integerValue = id * 10
            let realValue = Double(id) + 0.25
            let textValue = "Decode fixture \(id)"
            let blobValue = Data([UInt8(id), 1, 2, 3, 4, 5, 6, 7])
            let optionalInteger: Int? = id == 1 ? nil : 42
            let optionalText: String? = id == 1 ? nil : "present"
            let flag = id == 2
            return BenchmarkDecodeFixture(
                id: id,
                integerValue: integerValue,
                realValue: realValue,
                textValue: textValue,
                blobValue: blobValue,
                optionalInteger: optionalInteger,
                optionalText: optionalText,
                flag: flag
            )
        }
    }

    private static let schemaSQL = [
        """
        CREATE TABLE benchmark_company (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL
        )
        """,
        """
        CREATE TABLE benchmark_department (
            id INTEGER PRIMARY KEY,
            companyID INTEGER NOT NULL REFERENCES benchmark_company(id),
            name TEXT NOT NULL
        )
        """,
        """
        CREATE TABLE benchmark_person (
            id INTEGER PRIMARY KEY,
            companyID INTEGER NOT NULL REFERENCES benchmark_company(id),
            departmentID INTEGER NOT NULL REFERENCES benchmark_department(id),
            name TEXT NOT NULL,
            email TEXT NOT NULL,
            score REAL NOT NULL,
            isActive INTEGER NOT NULL,
            payload BLOB NOT NULL
        )
        """,
        "CREATE INDEX benchmark_person_company ON benchmark_person(companyID)",
        "CREATE INDEX benchmark_person_department ON benchmark_person(departmentID)",
        "CREATE INDEX benchmark_person_score ON benchmark_person(score)",
        """
        CREATE TABLE benchmark_decode_fixture (
            id INTEGER PRIMARY KEY,
            integerValue INTEGER NOT NULL,
            realValue REAL NOT NULL,
            textValue TEXT NOT NULL,
            blobValue BLOB NOT NULL,
            optionalInteger INTEGER,
            optionalText TEXT,
            flag INTEGER NOT NULL
        )
        """,
    ]
}
