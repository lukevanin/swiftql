import ComparisonBenchmarkSupport
import Darwin
import Foundation

@main
enum ComparisonBenchmarkMain {
    private static let implementations: Set<String> = [
        "generated_raw_sqlite",
        "grdb_codable",
        "grdb_manual",
        "lighter",
        "sqlite_data",
        "sqlite_swift_manual",
        "sqlite_swift_typed",
    ]

    static func main() {
        do {
            let configuration = try ComparisonBenchmarkConfiguration.parse(
                allowedImplementations: implementations
            )
            let fixtureURL = try fixture()
            switch configuration.implementation {
            case "generated_raw_sqlite":
                try GeneratedRawSQLiteControl(databasePath: fixtureURL.path)
                    .run(configuration: configuration)
            case "grdb_codable":
                try GRDBCodableControl(databasePath: fixtureURL.path)
                    .run(configuration: configuration)
            case "grdb_manual":
                try GRDBManualControl(databasePath: fixtureURL.path)
                    .run(configuration: configuration)
            case "lighter":
                try LighterControl.run(configuration: configuration)
            case "sqlite_data":
                try SQLiteDataControl(databasePath: fixtureURL.path)
                    .run(configuration: configuration)
            case "sqlite_swift_manual":
                try SQLiteSwiftManualControl(databasePath: fixtureURL.path)
                    .run(configuration: configuration)
            case "sqlite_swift_typed":
                try SQLiteSwiftTypedControl(databasePath: fixtureURL.path)
                    .run(configuration: configuration)
            default:
                preconditionFailure("validated implementation was not dispatched")
            }
        } catch {
            FileHandle.standardError.write(Data("error: \(error)\n".utf8))
            Darwin.exit(2)
        }
    }

    private static func fixture() throws -> URL {
        guard let url = Bundle.module.url(
            forResource: "northwind-performance",
            withExtension: "sqlite"
        ) else {
            throw ComparisonBenchmarkError.missingFixture(
                "Bundle.module/northwind-performance.sqlite"
            )
        }
        return url
    }
}
