import Foundation
import SwiftQL

@SQLTable(name: "benchmark_company")
struct BenchmarkCompany: Identifiable {
    let id: Int
    let name: String
}

@SQLTable(name: "benchmark_department")
struct BenchmarkDepartment: Identifiable {
    let id: Int
    let companyID: Int
    let name: String
}

@SQLTable(name: "benchmark_person")
struct BenchmarkPerson: Identifiable {
    let id: Int
    let companyID: Int
    let departmentID: Int
    let name: String
    let email: String
    let score: Double
    let isActive: Bool
    let payload: Data
}

@SQLResult
struct BenchmarkJoinedRow {
    let personID: Int
    let personName: String
    let departmentName: String
    let companyName: String
    let score: Double
    let isActive: Bool
}

@SQLTable(name: "benchmark_decode_fixture")
struct BenchmarkDecodeFixture: Identifiable {
    let id: Int
    let integerValue: Int
    let realValue: Double
    let textValue: String
    let blobValue: Data
    let optionalInteger: Int?
    let optionalText: String?
    let flag: Bool
}

enum BenchmarkQueries {
    static let personID = XLNamedBindingReference<Int>(name: "personID")
    static let companyID = XLNamedBindingReference<Int>(name: "companyID")
    static let minimumScore = XLNamedBindingReference<Double>(name: "minimumScore")
    static let writeStartID = XLNamedBindingReference<Int>(name: "writeStartID")
    static let writeEndID = XLNamedBindingReference<Int>(name: "writeEndID")
    static let scoreDelta = XLNamedBindingReference<Double>(name: "scoreDelta")
    static let decodeID = XLNamedBindingReference<Int>(name: "decodeID")

    static func simpleLookup() -> any XLQueryStatement<BenchmarkPerson> {
        sqlQuery { schema in
            let person = schema.table(BenchmarkPerson.self)
            return select(person)
                .from(person)
                .where(person.id == personID)
        }
    }

    static func multiJoinRead() -> any XLQueryStatement<BenchmarkJoinedRow> {
        sqlQuery { schema in
            let person = schema.table(BenchmarkPerson.self)
            let department = schema.table(BenchmarkDepartment.self)
            let company = schema.table(BenchmarkCompany.self)
            let row = BenchmarkJoinedRow.columns(
                personID: person.id,
                personName: person.name,
                departmentName: department.name,
                companyName: company.name,
                score: person.score,
                isActive: person.isActive
            )
            return select(row)
                .from(person)
                .innerJoin(department, on: department.id == person.departmentID)
                .innerJoin(company, on: company.id == department.companyID)
                .where((company.id == companyID) && (person.score >= minimumScore))
                .orderBy(person.score.descending())
                .limit(32)
        }
    }

    static func boundedWrite() -> any XLUpdateStatement<BenchmarkPerson> {
        sqlUpdate { schema in
            let person = schema.into(BenchmarkPerson.self)
            return update(person)
                .set { row in
                    row.score = person.score + scoreDelta
                }
                .where((person.id >= writeStartID) && (person.id < writeEndID))
        }
    }

    static func deterministicDecode() -> any XLQueryStatement<BenchmarkDecodeFixture> {
        sqlQuery { schema in
            let fixture = schema.table(BenchmarkDecodeFixture.self)
            return select(fixture)
                .from(fixture)
                .where(fixture.id <= decodeID)
                .orderBy(fixture.id.ascending())
        }
    }
}
