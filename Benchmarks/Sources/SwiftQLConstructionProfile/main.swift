// Deterministic allocation-and-timing profiler for issue #166.
//
// The checked-in #128 benchmark measures the combined
// `swiftql_construction_and_rendering` phase but records only wall-clock
// samples, which carry material process-to-process DVFS/core-placement noise on
// Apple silicon. This tool adds two pieces of evidence that the timing harness
// cannot:
//
//   1. A deterministic per-operation heap-allocation count (via the in-process
//      `malloc_logger` hook), which is immune to scheduler noise and attributes
//      allocation cost to the exact construction and rendering sub-phases.
//   2. A construction-only vs. rendering-only timing split of the same phase.
//
// It reuses SwiftQL's public API and rebuilds the exact two read queries the
// #128 harness measures (`simple_parameterized_lookup` and
// `representative_multi_join_read`). It is diagnostic evidence, not a CI gate.

#if canImport(Darwin)
import Darwin
#endif
import Foundation
import SwiftQL

// MARK: - Deterministic allocation counter (Darwin malloc_logger hook)

#if canImport(Darwin)
private typealias MallocLoggerFn = @convention(c) (
    UInt32, UInt, UInt, UInt, UInt, UInt32
) -> Void

// MALLOC_LOG_TYPE_ALLOCATE == 2. An allocation event has that bit set and a
// non-zero result pointer (realloc sets ALLOCATE|DEALLOCATE; we still count it
// as one allocation, which matches "gross heap allocations issued").
private let mallocLogTypeAllocate: UInt32 = 2

nonisolated(unsafe) private var allocationCount: Int = 0
nonisolated(unsafe) private var allocationBytes: Int = 0
nonisolated(unsafe) private var counting = false

// The callback runs with the malloc lock held, so it must not allocate. It only
// touches fixed globals, which is allocation-free. `nonisolated(unsafe)` opts the
// top-level (main-actor-isolated) declaration out of isolation checking; this
// single-threaded diagnostic tool never touches it concurrently.
nonisolated(unsafe) private let countingLogger: MallocLoggerFn = { type, arg1, arg2, arg3, result, _ in
    guard counting else { return }
    if (type & mallocLogTypeAllocate) != 0 && result != 0 {
        allocationCount += 1
        // For malloc/calloc the requested size is arg2; for realloc arg3.
        allocationBytes += Int(arg3 != 0 ? arg3 : arg2)
    }
}

private func installAllocationCounter() -> Bool {
    guard let slot = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "malloc_logger") else {
        return false
    }
    slot.assumingMemoryBound(to: Optional<MallocLoggerFn>.self).pointee = countingLogger
    return true
}

private struct AllocationSample {
    var count: Int
    var bytes: Int
}

private func measureAllocations(iterations: Int, _ body: () -> Void) -> AllocationSample {
    // Warm once outside the count to settle any one-time lazy state.
    body()
    allocationCount = 0
    allocationBytes = 0
    counting = true
    for _ in 0..<iterations { body() }
    counting = false
    return AllocationSample(count: allocationCount, bytes: allocationBytes)
}
#endif

// MARK: - Timing

private func median(_ xs: [UInt64]) -> Double {
    let s = xs.sorted()
    let n = s.count
    if n == 0 { return 0 }
    return n % 2 == 1 ? Double(s[n / 2]) : Double(s[n / 2 - 1] + s[n / 2]) / 2
}

private func measureNanos(warmups: Int, samples: Int, _ body: () -> Void) -> Double {
    for _ in 0..<warmups { body() }
    var out = [UInt64]()
    out.reserveCapacity(samples)
    for _ in 0..<samples {
        let start = DispatchTime.now().uptimeNanoseconds
        body()
        let end = DispatchTime.now().uptimeNanoseconds
        out.append(end - start)
    }
    return median(out) / 1000.0 // microseconds
}

// MARK: - Exact #128 read queries (rebuilt against the public API)

@SQLTable(name: "benchmark_company")
struct ProfileCompany: Identifiable {
    let id: Int
    let name: String
}

@SQLTable(name: "benchmark_department")
struct ProfileDepartment: Identifiable {
    let id: Int
    let companyID: Int
    let name: String
}

@SQLTable(name: "benchmark_person")
struct ProfilePerson: Identifiable, Equatable {
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
struct ProfileJoinedRow: Equatable {
    let personID: Int
    let personName: String
    let departmentName: String
    let companyName: String
    let score: Double
    let isActive: Bool
}

private let personID = XLNamedBindingReference<Int>(name: "personID")
private let companyID = XLNamedBindingReference<Int>(name: "companyID")
private let minimumScore = XLNamedBindingReference<Double>(name: "minimumScore")

private func simpleLookup() -> any XLQueryStatement<ProfilePerson> {
    sqlQuery { schema in
        let person = schema.table(ProfilePerson.self)
        return select(person)
            .from(person)
            .where(person.id == personID)
    }
}

private func multiJoinRead() -> any XLQueryStatement<ProfileJoinedRow> {
    sqlQuery { schema in
        let person = schema.table(ProfilePerson.self)
        let department = schema.table(ProfileDepartment.self)
        let company = schema.table(ProfileCompany.self)
        let row = ProfileJoinedRow.columns(
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

// MARK: - Driver

nonisolated(unsafe) let encoder = XLiteEncoder(formatter: XLiteFormatter())

struct CaseProfile {
    let name: String
    let sql: String
    let constructionAllocs: Int
    let constructionBytes: Int
    let renderAllocs: Int
    let renderBytes: Int
    let combinedAllocs: Int
    let combinedBytes: Int
    let constructionMicros: Double
    let renderMicros: Double
    let combinedMicros: Double
}

func profileCase(
    _ name: String,
    make: @escaping () -> XLEncodable,
    iterations: Int,
    warmups: Int,
    samples: Int
) -> CaseProfile {
    let prebuilt = make()
    let renderedSQL = encoder.makeSQL(prebuilt).sql

    #if canImport(Darwin)
    let construction = measureAllocations(iterations: iterations) { _ = make() }
    let render = measureAllocations(iterations: iterations) { _ = encoder.makeSQL(prebuilt) }
    let combined = measureAllocations(iterations: iterations) { _ = encoder.makeSQL(make()) }
    #else
    let construction = AllocationSample(count: 0, bytes: 0)
    let render = AllocationSample(count: 0, bytes: 0)
    let combined = AllocationSample(count: 0, bytes: 0)
    #endif

    let ctorMicros = measureNanos(warmups: warmups, samples: samples) { _ = make() }
    let renderMicros = measureNanos(warmups: warmups, samples: samples) { _ = encoder.makeSQL(prebuilt) }
    let combinedMicros = measureNanos(warmups: warmups, samples: samples) { _ = encoder.makeSQL(make()) }

    return CaseProfile(
        name: name,
        sql: renderedSQL,
        constructionAllocs: construction.count / iterations,
        constructionBytes: construction.bytes / iterations,
        renderAllocs: render.count / iterations,
        renderBytes: render.bytes / iterations,
        combinedAllocs: combined.count / iterations,
        combinedBytes: combined.bytes / iterations,
        constructionMicros: ctorMicros,
        renderMicros: renderMicros,
        combinedMicros: combinedMicros
    )
}

// CLI: --iterations N --warmups N --samples N --json PATH
var iterations = 20_000
var warmups = 200
var samples = 4_000
var jsonPath: String?
var args = Array(CommandLine.arguments.dropFirst())
var i = 0
while i < args.count {
    switch args[i] {
    case "--iterations": i += 1; iterations = Int(args[i]) ?? iterations
    case "--warmups": i += 1; warmups = Int(args[i]) ?? warmups
    case "--samples": i += 1; samples = Int(args[i]) ?? samples
    case "--json": i += 1; jsonPath = args[i]
    default: break
    }
    i += 1
}

#if canImport(Darwin)
let installed = installAllocationCounter()
if !installed {
    FileHandle.standardError.write(Data("warning: could not install malloc_logger; allocation counts will be 0\n".utf8))
}
#endif

let cases = [
    profileCase("simple_parameterized_lookup", make: { simpleLookup() },
                iterations: iterations, warmups: warmups, samples: samples),
    profileCase("representative_multi_join_read", make: { multiJoinRead() },
                iterations: iterations, warmups: warmups, samples: samples),
]

print("SwiftQL construction/rendering allocation + timing profile (issue #166)")
print("iterations=\(iterations) (allocs)  warmups=\(warmups) samples=\(samples) (timing)")
print("")
for c in cases {
    print("[\(c.name)]")
    print("  SQL: \(c.sql)")
    print("  allocations/op   construction=\(c.constructionAllocs)  render=\(c.renderAllocs)  combined=\(c.combinedAllocs)")
    print("  bytes/op         construction=\(c.constructionBytes)  render=\(c.renderBytes)  combined=\(c.combinedBytes)")
    print(String(format: "  median us/op     construction=%.3f  render=%.3f  combined=%.3f",
                 c.constructionMicros, c.renderMicros, c.combinedMicros))
    print("")
}

if let jsonPath {
    var obj: [String: Any] = [
        "iterations": iterations,
        "warmups": warmups,
        "samples": samples,
    ]
    obj["cases"] = cases.map { c in
        [
            "name": c.name,
            "sql": c.sql,
            "allocationsPerOp": ["construction": c.constructionAllocs, "render": c.renderAllocs, "combined": c.combinedAllocs],
            "bytesPerOp": ["construction": c.constructionBytes, "render": c.renderBytes, "combined": c.combinedBytes],
            "medianMicros": ["construction": c.constructionMicros, "render": c.renderMicros, "combined": c.combinedMicros],
        ]
    }
    let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: URL(fileURLWithPath: jsonPath))
    print("Wrote \(jsonPath)")
}
