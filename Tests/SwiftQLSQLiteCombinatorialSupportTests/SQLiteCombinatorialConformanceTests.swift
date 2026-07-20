import Foundation
import GRDB
import SwiftQL
import SwiftQLNorthwindFixtures
import SwiftQLSQLiteCombinatorialSupport
import SwiftQLSQLiteConformanceFixtures
import XCTest


final class SQLiteCombinatorialConformanceTests: XCTestCase {

    func testManifestReferencesCanonicalInventory() throws {
        let inventory = try SQLiteConformanceInventory.load()
        let manifest = try SQLiteCombinatorialSuite.makeManifest()
        let featureIDs = Set(inventory.features.map(\.id))

        XCTAssertEqual(manifest.inventoryVersion, inventory.inventoryVersion)
        for testCase in manifest.cases {
            XCTAssertTrue(
                Set(testCase.inventoryFeatureIDs).isSubset(of: featureIDs),
                testCase.id
            )
            XCTAssertTrue(
                Set(testCase.northwindAnchorCaseIDs ?? []).isSubset(of: featureIDs),
                testCase.id
            )
        }
    }

    func testGeneratedManifestIsDeterministicAndMatchesCheckedInArtifacts() throws {
        let first = try SQLiteCombinatorialSuite.makeManifest()
        let second = try SQLiteCombinatorialSuite.makeManifest()
        let firstJSON = try first.canonicalJSONData()
        let secondJSON = try second.canonicalJSONData()
        let firstSummary = try first.markdownSummary()

        XCTAssertEqual(first, second)
        XCTAssertEqual(firstJSON, secondJSON)
        XCTAssertEqual(firstSummary, try second.markdownSummary())
        XCTAssertFalse(first.cases.isEmpty)
        XCTAssertLessThanOrEqual(first.cases.count, first.hardBounds.maximumCaseCount)
        XCTAssertTrue(first.coverage.contains { coverage in
            coverage.strength == 2
                && coverage.requiredTupleCount == coverage.coveredTupleCount
        })
        XCTAssertEqual(
            first.exclusions.filter { $0.id.hasPrefix("gated.") }.count,
            8
        )
        XCTAssertTrue(first.cases.allSatisfy { !$0.inventoryFeatureIDs.isEmpty })

        try writeConfiguredOutput(
            data: firstJSON,
            environmentKey: "SWIFTQL_COMBINATORIAL_MANIFEST_PATH"
        )
        try writeConfiguredOutput(
            data: Data(firstSummary.utf8),
            environmentKey: "SWIFTQL_COMBINATORIAL_SUMMARY_PATH"
        )

        let checkedManifest = repositoryRoot
            .appendingPathComponent("Conformance/SQLite/COMBINATORIAL_CASES.json")
        let checkedSummary = repositoryRoot
            .appendingPathComponent("Conformance/SQLite/COMBINATORIAL_SUMMARY.md")
        if ProcessInfo.processInfo.environment["SWIFTQL_COMBINATORIAL_UPDATE_ARTIFACTS"] == "1" {
            try firstJSON.write(to: checkedManifest, options: .atomic)
            try Data(firstSummary.utf8).write(to: checkedSummary, options: .atomic)
        }
        else {
            XCTAssertEqual(
                try Data(contentsOf: checkedManifest),
                firstJSON,
                "Regenerate the checked manifest with SWIFTQL_COMBINATORIAL_UPDATE_ARTIFACTS=1"
            )
            XCTAssertEqual(
                try Data(contentsOf: checkedSummary),
                Data(firstSummary.utf8),
                "Regenerate the checked summary with SWIFTQL_COMBINATORIAL_UPDATE_ARTIFACTS=1"
            )
        }
    }

    func testIssue286FunctionOverloadMatrixIsExplicitAndBounded() throws {
        let manifest = try SQLiteCombinatorialSuite.makeManifest()
        let issue286Cases = manifest.cases.filter {
            $0.id.hasPrefix("c286.v1.expression.")
        }
        let expectedSuffixes: Set<String> = [
            "aggregate-average-distinct",
            "aggregate-count-distinct",
            "aggregate-group-concat-distinct",
            "aggregate-max-distinct",
            "aggregate-min-distinct",
            "aggregate-sum-distinct",
            "cast-blob-text",
            "cast-bool-integer",
            "cast-integer-real",
            "cast-integer-text",
            "cast-optional-blob-text",
            "cast-optional-bool-integer",
            "cast-optional-integer-real",
            "cast-optional-integer-text",
            "cast-optional-real-integer",
            "cast-optional-real-text",
            "cast-optional-text-blob",
            "cast-optional-text-integer",
            "cast-optional-text-real",
            "cast-real-integer",
            "cast-real-text",
            "cast-text-real",
            "comparable-max",
            "json-array-length-path",
            "numeric-round-no-places",
            "numeric-round-optional",
            "string-printf-array",
        ]
        let actualSuffixes = Set(issue286Cases.map {
            String($0.id.dropFirst("c286.v1.expression.".count))
        })

        XCTAssertEqual(actualSuffixes, expectedSuffixes)
        XCTAssertEqual(issue286Cases.count, 27)
        XCTAssertEqual(manifest.cases.count, 168)
        XCTAssertEqual(manifest.hardBounds.maximumCaseCount, 192)
        XCTAssertFalse(issue286Cases.contains { $0.id.contains("unixepoch") })
        XCTAssertTrue(issue286Cases.allSatisfy { $0.mode == .semantic })

        let expectedFeatureIDs: Set<String> = [
            "syntax.expression.aggregate-functions",
            "syntax.expression.json-functions",
            "syntax.expression.numeric-comparable-functions",
            "syntax.expression.string-functions",
            "syntax.expression.type-casts",
        ]
        XCTAssertEqual(
            Set(issue286Cases.flatMap(\.inventoryFeatureIDs)),
            expectedFeatureIDs
        )
        XCTAssertTrue(
            issue286Cases
                .filter { $0.inventoryFeatureIDs == ["syntax.expression.json-functions"] }
                .allSatisfy { $0.requiredCapabilities == ["sqlite-json-functions"] }
        )
    }

    func testPinnedRuntimeAttestsJSONFunctionCapability() throws {
        let manifest = try SQLiteCombinatorialSuite.makeManifest()
        let jsonCases = manifest.cases.filter {
            $0.inventoryFeatureIDs == ["syntax.expression.json-functions"]
        }
        let pool = try NorthwindFixture.validatedReadOnlyPool()
        defer { try? pool.close() }
        let runtime = try pool.read { database in
            try SQLiteRuntimeMetadata.capture(from: database)
        }
        let signatures = Set(runtime.functions.map {
            "\($0.name.uppercased())/\($0.argumentCount)"
        })

        XCTAssertTrue(signatures.contains("JSON_VALID/1"))
        XCTAssertTrue(signatures.contains("JSON_ARRAY_LENGTH/1"))
        XCTAssertTrue(signatures.contains("JSON_ARRAY_LENGTH/2"))
        XCTAssertEqual(jsonCases.count, 3)
        XCTAssertNoThrow(try assertRequiredCapabilities(for: jsonCases, runtime: runtime))
    }

    func testEveryPositiveCasePreparesAndSemanticOraclesExecute() throws {
        let suiteStarted = Date()
        let manifest = try SQLiteCombinatorialSuite.makeManifest()
        let selectedCases = try selectedCases(from: manifest)
        let pool = try NorthwindFixture.validatedReadOnlyPool()
        defer { try? pool.close() }

        let runtime = try pool.read { database in
            try SQLiteRuntimeMetadata.capture(from: database)
        }

        let positiveOutcomes = selectedCases.map { testCase in
            evaluatePositiveCase(testCase, runtime: runtime, pool: pool)
        }
        let positiveFailureIDs = positiveOutcomes
            .filter { $0.verdict == .failed }
            .map(\.caseID)
        var outcomes = positiveOutcomes

        let deliberateFailure = try pool.read { database in
            try makeDeliberateFailure(
                runtime: runtime,
                database: database
            )
        }
        outcomes.append(
            SQLiteCombinatorialCaseOutcome(
                caseID: deliberateFailure.testCase.id,
                stage: .prepare,
                verdict: .failed,
                elapsedMilliseconds: 0,
                failure: deliberateFailure
            )
        )
        let totalElapsedMilliseconds = Date().timeIntervalSince(suiteStarted) * 1_000

        let report = SQLiteCombinatorialRuntimeReport(
            manifestSHA256: sha256Hex(try manifest.canonicalJSONData()),
            manifestCaseCount: manifest.cases.count,
            hardBounds: manifest.hardBounds,
            maximumRuntimeMilliseconds: combinatorialMaximumRuntimeMilliseconds,
            totalElapsedMilliseconds: totalElapsedMilliseconds,
            runtimeMetadata: runtime,
            outcomes: outcomes
        )
        try writeConfiguredOutput(
            data: try report.canonicalJSONData(),
            environmentKey: "SWIFTQL_COMBINATORIAL_RUNTIME_REPORT_PATH"
        )

        // Keep this assertion after the atomic report write. A regression in a
        // real positive case must leave replayable runtime evidence in CI.
        XCTAssertTrue(
            positiveFailureIDs.isEmpty,
            "Runtime report written before positive-case failures were reported: "
                + positiveFailureIDs.joined(separator: ", ")
        )
        XCTAssertTrue(
            report.satisfiesRuntimeBound,
            "Runtime report written before the explicit suite bound was enforced"
        )
        XCTAssertEqual(positiveOutcomes.count, selectedCases.count)
        XCTAssertEqual(
            outcomes.filter { $0.caseID == deliberateBrokenRendererCaseID }.count,
            1
        )
        XCTAssertFalse(runtime.sqliteVersion.isEmpty)
        XCTAssertFalse(runtime.sqliteSourceID.isEmpty)
        XCTAssertFalse(runtime.functions.isEmpty)
        XCTAssertFalse(runtime.collations.isEmpty)
        XCTAssertFalse(runtime.schemaFNV1A64.isEmpty)
    }

    func testDeliberatelyBrokenRendererProducesStableFailureEvidence() throws {
        let pool = try NorthwindFixture.validatedReadOnlyPool()
        defer { try? pool.close() }

        let pair = try pool.read { database -> (
            SQLiteCombinatorialFailureRecord,
            SQLiteCombinatorialFailureRecord
        ) in
            let runtime = try SQLiteRuntimeMetadata.capture(from: database)
            return (
                try makeDeliberateFailure(
                    runtime: runtime,
                    database: database
                ),
                try makeDeliberateFailure(
                    runtime: runtime,
                    database: database
                )
            )
        }

        XCTAssertEqual(pair.0, pair.1)
        XCTAssertEqual(try pair.0.canonicalJSONData(), try pair.1.canonicalJSONData())
        XCTAssertEqual(pair.0.stage, .prepare)
        XCTAssertEqual(pair.0.testCase.id, deliberateBrokenRendererCaseID)
        XCTAssertEqual(pair.0.testCase.renderedSQL, pair.0.failingSQL)
        XCTAssertEqual(pair.0.originalSQL, pair.0.failingSQL)
        XCTAssertEqual(pair.0.testCase.bindings, pair.0.bindings)
        XCTAssertNil(pair.0.reducedFromCaseID)
        XCTAssertEqual(pair.0.reductionAttemptCount, 0)
        XCTAssertTrue(pair.0.reducedDimensions.isEmpty)
        XCTAssertEqual(pair.0.failureSignature.code, "1")
        XCTAssertTrue(pair.0.failureSignature.message.lowercased().contains("syntax"))
        XCTAssertFalse(pair.0.runtimeMetadata.compileOptions.isEmpty)
        XCTAssertFalse(pair.0.runtimeMetadata.functions.isEmpty)
        XCTAssertFalse(pair.0.runtimeMetadata.collations.isEmpty)
        XCTAssertFalse(pair.0.runtimeMetadata.schemaFNV1A64.isEmpty)
    }

    func testPositiveFailuresAreStructuredBeforeTheFailureDecision() throws {
        let suiteStarted = Date()
        let manifest = try SQLiteCombinatorialSuite.makeManifest()
        let pool = try NorthwindFixture.validatedReadOnlyPool()
        defer { try? pool.close() }

        let runtime = try pool.read { database in
            try SQLiteRuntimeMetadata.capture(from: database)
        }
        let cases = [
            adversarialCase(
                id: "c191.v1.adversarial.prepare",
                sql: "SELECT FROM c191_adversarial_prepare",
                mode: .prepareOnly,
                oracle: nil
            ),
            adversarialCase(
                id: "c191.v1.adversarial.execution",
                sql: "SELECT ABS(-9223372036854775808)",
                mode: .semantic,
                oracle: SQLiteCombinatorialOracle(
                    id: "oracle.c191.adversarial.unreachable",
                    kind: .rawSQL
                )
            ),
            adversarialCase(
                id: "c191.v1.adversarial.oracle",
                sql: "SELECT 1",
                mode: .semantic,
                oracle: SQLiteCombinatorialOracle(
                    id: "oracle.c191.adversarial.missing",
                    kind: .rawSQL
                )
            ),
            adversarialCase(
                id: "c191.v1.adversarial.missing-capability",
                sql: "SELECT 1",
                mode: .prepareOnly,
                oracle: nil,
                requiredCapabilities: ["function:C191_DELIBERATELY_MISSING"]
            ),
        ]
        let outcomes = cases.map { testCase in
            evaluatePositiveCase(testCase, runtime: runtime, pool: pool)
        }
        let report = SQLiteCombinatorialRuntimeReport(
            manifestSHA256: sha256Hex(try manifest.canonicalJSONData()),
            manifestCaseCount: manifest.cases.count,
            hardBounds: manifest.hardBounds,
            maximumRuntimeMilliseconds: combinatorialMaximumRuntimeMilliseconds,
            totalElapsedMilliseconds: Date().timeIntervalSince(suiteStarted) * 1_000,
            runtimeMetadata: runtime,
            outcomes: outcomes
        )
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let output = outputDirectory.appendingPathComponent("runtime-report.json")
        defer { try? FileManager.default.removeItem(at: outputDirectory) }

        try writeOutput(data: try report.canonicalJSONData(), to: output)

        let decoded = try JSONDecoder().decode(
            SQLiteCombinatorialRuntimeReport.self,
            from: Data(contentsOf: output)
        )
        XCTAssertEqual(decoded.runtimeMetadata, runtime)
        XCTAssertEqual(
            decoded.maximumRuntimeMilliseconds,
            combinatorialMaximumRuntimeMilliseconds
        )
        XCTAssertGreaterThan(decoded.maximumRuntimeMilliseconds, 0)
        XCTAssertTrue(decoded.satisfiesRuntimeBound)
        XCTAssertEqual(decoded.outcomes.map(\.caseID), cases.map(\.id).sorted())
        XCTAssertEqual(
            decoded.outcomes.map { $0.stage.rawValue }.sorted(),
            ["execution", "oracle", "prepare", "prepare"]
        )
        XCTAssertTrue(decoded.outcomes.allSatisfy { outcome in
            outcome.verdict == .failed
                && outcome.failure?.testCase.id == outcome.caseID
                && outcome.failure?.testCase.renderedSQL == outcome.failure?.failingSQL
                && outcome.failure?.bindings == outcome.failure?.testCase.bindings
                && outcome.failure?.runtimeMetadata == runtime
        })
        let missingCapability = try XCTUnwrap(decoded.outcomes.first { outcome in
            outcome.caseID == "c191.v1.adversarial.missing-capability"
        })
        XCTAssertEqual(
            missingCapability.failure?.failureSignature.code,
            "missing-capability"
        )
    }
}


private extension SQLiteCombinatorialConformanceTests {
    var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func selectedCases(
        from manifest: SQLiteCombinatorialManifest
    ) throws -> [SQLiteCombinatorialCase] {
        guard let requested = ProcessInfo.processInfo.environment[
            "SWIFTQL_COMBINATORIAL_CASE"
        ], !requested.isEmpty else {
            return manifest.cases
        }
        guard let selected = manifest.cases.first(where: { $0.id == requested }) else {
            throw SQLiteCombinatorialConformanceError.unknownCaseID(requested)
        }
        return [selected]
    }

    func writeConfiguredOutput(data: Data, environmentKey: String) throws {
        guard let path = ProcessInfo.processInfo.environment[environmentKey], !path.isEmpty else {
            return
        }
        try writeOutput(data: data, to: URL(fileURLWithPath: path))
    }

    func writeOutput(data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    func evaluatePositiveCase(
        _ testCase: SQLiteCombinatorialCase,
        runtime: SQLiteRuntimeMetadata,
        pool: DatabasePool
    ) -> SQLiteCombinatorialCaseOutcome {
        let started = Date()

        do {
            try assertRequiredCapabilities(for: [testCase], runtime: runtime)
        }
        catch {
            return failedOutcome(
                testCase,
                stage: .prepare,
                runtime: runtime,
                error: error,
                started: started
            )
        }

        do {
            return try pool.read { database in
                do {
                    let statement = try database.makeStatement(sql: testCase.renderedSQL)
                    try statement.setArguments(arguments(for: testCase))
                }
                catch {
                    return failedOutcome(
                        testCase,
                        stage: .prepare,
                        runtime: runtime,
                        error: error,
                        started: started
                    )
                }

                guard testCase.mode == .semantic else {
                    return passedOutcome(testCase, stage: .prepare, started: started)
                }

                let actual: [[DatabaseValue]]
                do {
                    actual = try resultRows(
                        database,
                        sql: testCase.renderedSQL,
                        arguments: arguments(for: testCase)
                    )
                }
                catch {
                    return failedOutcome(
                        testCase,
                        stage: .execution,
                        runtime: runtime,
                        error: error,
                        started: started
                    )
                }

                let expected: [[DatabaseValue]]
                do {
                    expected = try independentOracleRows(
                        for: testCase,
                        database: database
                    )
                }
                catch {
                    return failedOutcome(
                        testCase,
                        stage: .oracle,
                        runtime: runtime,
                        error: error,
                        started: started
                    )
                }

                let matches: Bool
                if testCase.oracle?.kind == .fixedValue {
                    matches = canonicalRows(actual) == canonicalRows(expected)
                }
                else {
                    // Raw-SQL oracles retain row order so ORDER BY and
                    // collation regressions cannot be sorted away.
                    matches = actual == expected
                }
                guard matches else {
                    return failedOutcome(
                        testCase,
                        stage: .oracle,
                        runtime: runtime,
                        error: SQLiteCombinatorialConformanceError.semanticMismatch(
                            testCase.id
                        ),
                        started: started
                    )
                }

                return passedOutcome(testCase, stage: .execution, started: started)
            }
        }
        catch {
            return failedOutcome(
                testCase,
                stage: .prepare,
                runtime: runtime,
                error: error,
                started: started
            )
        }
    }

    func passedOutcome(
        _ testCase: SQLiteCombinatorialCase,
        stage: SQLiteCombinatorialFailureStage,
        started: Date
    ) -> SQLiteCombinatorialCaseOutcome {
        SQLiteCombinatorialCaseOutcome(
            caseID: testCase.id,
            stage: stage,
            verdict: .passed,
            elapsedMilliseconds: Date().timeIntervalSince(started) * 1_000,
            failure: nil
        )
    }

    func failedOutcome(
        _ testCase: SQLiteCombinatorialCase,
        stage: SQLiteCombinatorialFailureStage,
        runtime: SQLiteRuntimeMetadata,
        error: Error,
        started: Date
    ) -> SQLiteCombinatorialCaseOutcome {
        let failure = SQLiteCombinatorialFailureRecord(
            testCase: testCase,
            originalSQL: testCase.renderedSQL,
            failingSQL: testCase.renderedSQL,
            bindings: testCase.bindings,
            stage: stage,
            failureSignature: failureSignature(for: error),
            runtimeMetadata: runtime,
            reducedFromCaseID: nil,
            reductionAttemptCount: 0,
            reducedDimensions: [],
            reproductionCommand: testCase.reproductionCommand
        )
        return SQLiteCombinatorialCaseOutcome(
            caseID: testCase.id,
            stage: stage,
            verdict: .failed,
            elapsedMilliseconds: Date().timeIntervalSince(started) * 1_000,
            failure: failure
        )
    }

    func failureSignature(for error: Error) -> SQLiteCombinatorialFailureSignature {
        if let error = error as? DatabaseError {
            return SQLiteCombinatorialFailureSignature(
                errorType: "GRDB.DatabaseError",
                code: String(error.resultCode.rawValue),
                message: error.message ?? "SQLite error"
            )
        }
        if let error = error as? SQLiteCombinatorialConformanceError {
            let code: String
            let message: String
            switch error {
            case .unknownCaseID(let caseID):
                code = "unknown-case-id"
                message = "Unknown generated case ID: \(caseID)"
            case .missingCapability(let caseID, let capability):
                code = "missing-capability"
                message = "Case \(caseID) requires unavailable capability \(capability)"
            case .unknownCapability(let caseID, let capability):
                code = "unknown-capability"
                message = "Case \(caseID) declares unknown capability \(capability)"
            case .missingOracle(let caseID):
                code = "missing-oracle"
                message = "Case \(caseID) has no independent semantic oracle"
            case .unknownOracle(let oracleID):
                code = "unknown-oracle"
                message = "No independent semantic oracle is registered for \(oracleID)"
            case .semanticMismatch(let caseID):
                code = "rows-differ"
                message = "Independent semantic oracle mismatch for \(caseID)"
            case .brokenRendererPrepared(let sql):
                code = "broken-renderer-prepared"
                message = "Deliberately invalid SQL unexpectedly prepared: \(sql)"
            }
            return SQLiteCombinatorialFailureSignature(
                errorType: "SQLiteCombinatorialConformanceError",
                code: code,
                message: message
            )
        }
        return SQLiteCombinatorialFailureSignature(
            errorType: String(reflecting: type(of: error)),
            code: nil,
            message: String(describing: error)
        )
    }

    func adversarialCase(
        id: String,
        sql: String,
        mode: SQLiteCombinatorialCaseMode,
        oracle: SQLiteCombinatorialOracle?,
        requiredCapabilities: [String] = []
    ) -> SQLiteCombinatorialCase {
        SQLiteCombinatorialCase(
            id: id,
            template: "adversarial-runtime-evidence",
            strength: "adversarial-test",
            dimensionVector: [],
            constraintIDs: [],
            inventoryFeatureIDs: ["syntax.select.core"],
            northwindAnchorCaseIDs: nil,
            requiredCapabilities: requiredCapabilities,
            renderedSQL: sql,
            bindings: [],
            mode: mode,
            oracle: oracle,
            reproductionCommand: "swift test --filter SQLiteCombinatorialConformanceTests/\(id)"
        )
    }

    func assertRequiredCapabilities(
        for cases: [SQLiteCombinatorialCase],
        runtime: SQLiteRuntimeMetadata
    ) throws {
        let functionNames = Set(runtime.functions.map { $0.name.uppercased() })
        let functionSignatures = Set(runtime.functions.map {
            "\($0.name.uppercased())/\($0.argumentCount)"
        })
        for testCase in cases {
            for capability in testCase.requiredCapabilities {
                if capability.hasPrefix("function:") {
                    let name = String(capability.dropFirst("function:".count)).uppercased()
                    guard functionNames.contains(name) else {
                        throw SQLiteCombinatorialConformanceError.missingCapability(
                            caseID: testCase.id,
                            capability: capability
                        )
                    }
                }
                else if capability == "sqlite-json-functions" {
                    let requiredSignatures: Set<String> = [
                        "JSON_ARRAY_LENGTH/1",
                        "JSON_ARRAY_LENGTH/2",
                        "JSON_VALID/1",
                    ]
                    guard requiredSignatures.isSubset(of: functionSignatures) else {
                        throw SQLiteCombinatorialConformanceError.missingCapability(
                            caseID: testCase.id,
                            capability: capability
                        )
                    }
                }
                else {
                    throw SQLiteCombinatorialConformanceError.unknownCapability(
                        caseID: testCase.id,
                        capability: capability
                    )
                }
            }
        }
    }

    func arguments(for testCase: SQLiteCombinatorialCase) -> StatementArguments {
        if testCase.bindings.allSatisfy({ $0.keyKind == .named }) {
            let pairs = testCase.bindings.map { binding in
                (binding.keyName!, databaseValue(binding.taggedValue))
            }
            return StatementArguments(Dictionary(uniqueKeysWithValues: pairs))
        }
        return StatementArguments(
            testCase.bindings
                .sorted { $0.logicalIndex < $1.logicalIndex }
                .map { databaseValue($0.taggedValue) }
        )
    }

    func databaseValue(_ value: SQLiteCombinatorialTaggedValue) -> DatabaseValue {
        switch value {
        case .null:
            return .null
        case .integer(let value):
            return value.databaseValue
        case .real(let value):
            return value.databaseValue
        case .text(let value):
            return value.databaseValue
        case .blob(let value):
            return value.databaseValue
        }
    }

    func resultRows(
        _ database: Database,
        sql: String,
        arguments: StatementArguments = StatementArguments()
    ) throws -> [[DatabaseValue]] {
        try Row.fetchAll(database, sql: sql, arguments: arguments).map { row in
            (0..<row.count).map { index -> DatabaseValue in row[index] }
        }
    }

    func independentOracleRows(
        for testCase: SQLiteCombinatorialCase,
        database: Database
    ) throws -> [[DatabaseValue]] {
        guard let oracle = testCase.oracle else {
            throw SQLiteCombinatorialConformanceError.missingOracle(testCase.id)
        }

        if testCase.id.hasPrefix("c191.v1.expression.")
            || testCase.id.hasPrefix("c286.v1.expression.") {
            return try resultRows(
                database,
                sql: try expressionOracleSQL(for: testCase.id),
                arguments: arguments(for: testCase)
            )
        }
        if testCase.id.hasPrefix("c191.v1.cte.") {
            return try fixedCTERows(for: testCase.id)
        }

        switch oracle.id {
        case "oracle.c191.northwind.customer-supplier-cities":
            return try resultRows(
                database,
                sql: """
                    SELECT City AS city, CompanyName AS companyName,
                           ContactName AS contactName, 'Customers' AS relationship
                    FROM Customers
                    UNION
                    SELECT City AS city, CompanyName AS companyName,
                           ContactName AS contactName, 'Suppliers' AS relationship
                    FROM Suppliers
                    ORDER BY city, companyName, relationship, contactName
                    """
            )
        case "oracle.c191.northwind.cte-order-subtotals":
            return try resultRows(
                database,
                sql: """
                    WITH order_subtotals AS (
                        SELECT OrderID AS orderID,
                               SUM(UnitPrice * Quantity * (1.0 - Discount)) AS subtotal
                        FROM "Order Details"
                        GROUP BY OrderID
                    )
                    SELECT orderID, subtotal
                    FROM order_subtotals
                    WHERE orderID = 10248
                    ORDER BY orderID
                    """
            )
        case "oracle.c191.left-null-grouped-pagination":
            return try resultRows(
                database,
                sql: """
                    SELECT o.ShipRegion
                    FROM Orders AS o
                    LEFT JOIN Employees AS e ON o.EmployeeID = e.EmployeeID
                    WHERE o.ShipRegion IS NULL
                    GROUP BY o.CustomerID
                    HAVING COUNT(o.OrderID) > 1
                    ORDER BY o.CustomerID COLLATE NOCASE ASC
                    LIMIT 5 OFFSET 2
                    """
            )
        case "oracle.c191.repeated-binding-aggregate":
            return try resultRows(
                database,
                sql: """
                    SELECT COUNT(o.OrderID)
                    FROM (
                        SELECT
                            source_orders.OrderID,
                            source_orders.CustomerID,
                            source_orders.EmployeeID,
                            source_orders.ShippedDate,
                            source_orders.ShipRegion
                        FROM Orders AS source_orders
                    ) AS o
                    INNER JOIN Customers AS c ON o.CustomerID = c.CustomerID
                    WHERE o.EmployeeID >= :repeated_employee_id
                      AND o.EmployeeID <= :repeated_employee_id
                    GROUP BY o.CustomerID
                    HAVING COUNT(o.OrderID) > 1
                    ORDER BY o.OrderID DESC
                    LIMIT 5 OFFSET 2
                    """,
                arguments: arguments(for: testCase)
            )
        case "oracle.c191.injection-binding":
            return try resultRows(
                database,
                sql: """
                    SELECT o.OrderID
                    FROM Orders AS o
                    CROSS JOIN Customers AS c
                    WHERE o.CustomerID = :customer_input
                    """,
                arguments: arguments(for: testCase)
            )
        default:
            throw SQLiteCombinatorialConformanceError.unknownOracle(oracle.id)
        }
    }

    func expressionOracleSQL(for caseID: String) throws -> String {
        let suffix: String
        if caseID.hasPrefix("c191.v1.expression.") {
            suffix = String(caseID.dropFirst("c191.v1.expression.".count))
        }
        else if caseID.hasPrefix("c286.v1.expression.") {
            suffix = String(caseID.dropFirst("c286.v1.expression.".count))
        }
        else {
            throw SQLiteCombinatorialConformanceError.unknownOracle(caseID)
        }
        switch suffix {
        case "aggregate-count-distinct":
            return "SELECT COUNT(DISTINCT EmployeeID) FROM Orders"
        case "aggregate-min-distinct":
            return "SELECT MIN(DISTINCT EmployeeID) FROM Orders"
        case "aggregate-max-distinct":
            return "SELECT MAX(DISTINCT EmployeeID) FROM Orders"
        case "aggregate-average-distinct":
            return "SELECT AVG(DISTINCT CAST(EmployeeID AS REAL)) FROM Orders"
        case "aggregate-sum-distinct":
            return "SELECT SUM(DISTINCT EmployeeID) FROM Orders"
        case "aggregate-group-concat-distinct":
            return "SELECT GROUP_CONCAT(DISTINCT CustomerID) FROM Orders"
        case "indexed-binding":
            return "SELECT ?1"
        case "numeric-abs":
            return "SELECT ABS(:integer_value)"
        case "numeric-round":
            return "SELECT ROUND(:real_value, 2)"
        case "numeric-round-no-places":
            return "SELECT ROUND(:real_value)"
        case "numeric-round-optional":
            return "SELECT ROUND(:optional_real_value)"
        case "numeric-floor":
            return "SELECT FLOOR(:real_value)"
        case "comparable-min":
            return "SELECT MIN(:integer_value, 191)"
        case "comparable-max":
            return "SELECT MAX(:integer_value, 191)"
        case "string-printf":
            return "SELECT PRINTF('%s-%d', :text_value, :integer_value)"
        case "string-printf-array":
            return "SELECT PRINTF('%s-%d', :text_value, :integer_value)"
        case "cast-bool-integer":
            return "SELECT :boolean_value"
        case "cast-optional-bool-integer":
            return "SELECT :optional_boolean_value"
        case "cast-integer-real":
            return "SELECT CAST(:integer_value AS REAL)"
        case "cast-integer-text":
            return "SELECT CAST(:integer_value AS TEXT)"
        case "cast-optional-integer-real":
            return "SELECT CAST(:optional_integer_value AS REAL)"
        case "cast-optional-integer-text":
            return "SELECT CAST(:optional_integer_value AS TEXT)"
        case "cast-real-integer":
            return "SELECT CAST(:real_value AS INTEGER)"
        case "cast-real-text":
            return "SELECT CAST(:real_value AS TEXT)"
        case "cast-optional-real-integer":
            return "SELECT CAST(:optional_real_value AS INTEGER)"
        case "cast-optional-real-text":
            return "SELECT CAST(:optional_real_value AS TEXT)"
        case "cast-text-integer":
            return "SELECT CAST(:text_value AS INTEGER)"
        case "cast-text-real":
            return "SELECT CAST(:text_value AS REAL)"
        case "cast-text-blob":
            return "SELECT CAST(:text_value AS BLOB)"
        case "cast-optional-text-integer":
            return "SELECT CAST(:optional_text_value AS INTEGER)"
        case "cast-optional-text-real":
            return "SELECT CAST(:optional_text_value AS REAL)"
        case "cast-optional-text-blob":
            return "SELECT CAST(:optional_text_value AS BLOB)"
        case "cast-blob-text":
            return "SELECT CAST(:blob_value AS TEXT)"
        case "cast-optional-blob-text":
            return "SELECT CAST(:optional_blob_value AS TEXT)"
        case "date-unixepoch":
            return "SELECT UNIXEPOCH(:text_value)"
        case "json-valid":
            return "SELECT JSON_VALID(:text_value)"
        case "json-array-length":
            return "SELECT JSON_ARRAY_LENGTH(:text_value)"
        case "json-array-length-path":
            return "SELECT JSON_ARRAY_LENGTH(:text_value, '$.items')"
        case "operator-arithmetic-precedence":
            return "SELECT (:integer_value + 7) * 2"
        case "operator-glob":
            return "SELECT :text_value GLOB 'A*'"
        default:
            throw SQLiteCombinatorialConformanceError.unknownOracle(caseID)
        }
    }

    func fixedCTERows(for caseID: String) throws -> [[DatabaseValue]] {
        let parts = caseID.split(separator: ".").map(String.init)
        guard parts.count == 5 else {
            throw SQLiteCombinatorialConformanceError.unknownOracle(caseID)
        }
        let shape = parts[3]
        let operation = parts[4]
        let integers: [Int64?]
        switch (shape, operation) {
        case ("ordinary-required", "union"),
             ("ordinary-required", "union-all"):
            integers = [1, 2]
        case ("ordinary-required", "intersect"),
             ("ordinary-required", "except"):
            integers = [1]
        case ("ordinary-nullable", "union"),
             ("ordinary-nullable", "union-all"):
            integers = [1, nil]
        case ("ordinary-nullable", "intersect"),
             ("ordinary-nullable", "except"):
            integers = [1]
        case ("recursive-required", "union"):
            integers = [1, 2, 3]
        case ("recursive-required", "union-all"):
            integers = [1, 2, 2, 3]
        case ("recursive-required", "intersect"):
            integers = [2]
        case ("recursive-required", "except"):
            integers = [1, 3]
        default:
            throw SQLiteCombinatorialConformanceError.unknownOracle(caseID)
        }
        return integers.map { value in
            [value.map { $0.databaseValue } ?? .null]
        }
    }

    func canonicalRows(_ rows: [[DatabaseValue]]) -> [[DatabaseValue]] {
        rows.sorted { databaseRowKey($0) < databaseRowKey($1) }
    }

    func databaseRowKey(_ row: [DatabaseValue]) -> String {
        row.map { String(reflecting: $0.storage) }.joined(separator: "\u{1f}")
    }

    func makeDeliberateFailure(
        runtime: SQLiteRuntimeMetadata,
        database: Database
    ) throws -> SQLiteCombinatorialFailureRecord {
        let brokenSQL = try XLiteEncoder(dialect: XLSQLiteDialect())
            .makeValidatedSQL(DeliberatelyBrokenRenderer())
            .sql
        let brokenCase = SQLiteCombinatorialCase(
            id: deliberateBrokenRendererCaseID,
            template: "deliberately-broken-renderer",
            strength: "deliberate-negative-control",
            dimensionVector: [],
            constraintIDs: [],
            inventoryFeatureIDs: ["syntax.select.core"],
            northwindAnchorCaseIDs: nil,
            requiredCapabilities: [],
            renderedSQL: brokenSQL,
            bindings: [],
            mode: .prepareOnly,
            oracle: nil,
            reproductionCommand: "swift test --filter SQLiteCombinatorialConformanceTests/testDeliberatelyBrokenRendererProducesStableFailureEvidence"
        )

        do {
            _ = try database.makeStatement(sql: brokenSQL)
            throw SQLiteCombinatorialConformanceError.brokenRendererPrepared(brokenSQL)
        }
        catch let error as DatabaseError {
            return SQLiteCombinatorialFailureRecord(
                testCase: brokenCase,
                originalSQL: brokenSQL,
                failingSQL: brokenSQL,
                bindings: [],
                stage: .prepare,
                failureSignature: SQLiteCombinatorialFailureSignature(
                    errorType: "GRDB.DatabaseError",
                    code: String(error.resultCode.rawValue),
                    message: error.message ?? "SQLite prepare error"
                ),
                runtimeMetadata: runtime,
                reducedFromCaseID: nil,
                reductionAttemptCount: 0,
                reducedDimensions: [],
                reproductionCommand: brokenCase.reproductionCommand
            )
        }
    }

    func sha256Hex(_ data: Data) -> String {
        PortableSHA256.hexDigest(of: data)
    }
}


private let deliberateBrokenRendererCaseID = "c191.v1.deliberately-broken-renderer"
private let combinatorialMaximumRuntimeMilliseconds = 120_000


private struct DeliberatelyBrokenRenderer: XLEncodable {
    func makeSQL(context: inout XLBuilder) {
        context.unaryPrefix("SELECT") { builder in
            builder.unaryPrefix("FROM") { nested in
                nested.name("broken_renderer_source")
            }
        }
    }
}


private enum SQLiteCombinatorialConformanceError: Error, Equatable {
    case unknownCaseID(String)
    case missingCapability(caseID: String, capability: String)
    case unknownCapability(caseID: String, capability: String)
    case missingOracle(String)
    case unknownOracle(String)
    case semanticMismatch(String)
    case brokenRendererPrepared(String)
}
