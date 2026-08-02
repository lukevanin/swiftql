#!/bin/bash
#
# TEMPORARY diagnostic harness for #530. Not part of the release gates and
# removed before this branch merges.
#
# Xcode 16.2 is not installable on the machine the fix was written on, so the
# pinned Swift 6.0 cell in CI is the only toolchain that can answer which
# construct segfaults `swift-frontend`. Bisecting one construct per CI run
# would take a day, so this builds every candidate as its own target in one
# package, builds them one at a time, keeps going past a crash, and prints a
# table plus every crash's full stack dump.
#
# SwiftQL itself is built once and reused by every probe, so the whole sweep
# costs about one demo build.

set -uo pipefail

repository_root="$(cd "$(dirname "$0")/../.." && pwd -P)"
demo_sources="$repository_root/Examples/TodoApp/TodoKit/Sources/TodoKit"
playground_pages="$repository_root/Examples/GettingStarted.playground/Pages"

output_directory="${1:-${TMPDIR:-/tmp}/swiftql-probe-530}"
mkdir -p "$output_directory"
output_directory="$(cd "$output_directory" && pwd -P)"

harness="${SWIFTQL_PROBE_ROOT:-${TMPDIR:-/tmp}/swiftql-probe-530-package}"
rm -rf "$harness"
mkdir -p "$harness/Sources"

# --- Probe sources ---------------------------------------------------------

# Every library probe gets the demo's own value types and table declarations,
# so a probe differs from the demo only in the statement under test.
add_library_probe() {
    local name="$1"
    mkdir -p "$harness/Sources/$name"
    cp "$demo_sources/Values.swift" "$harness/Sources/$name/Values.swift"
    cp "$demo_sources/Schema.swift" "$harness/Sources/$name/Schema.swift"
    cat > "$harness/Sources/$name/Probe.swift"
}

# A playground page is top-level code, so it has to be an executable target's
# main.swift, exactly as check-playground-pages.sh builds it.
add_page_probe() {
    local name="$1"
    local page="$2"
    mkdir -p "$harness/Sources/$name"
    cp "$playground_pages/$page.xcplaygroundpage/Contents.swift" \
        "$harness/Sources/$name/main.swift"
}

probe_names=()
probe_kinds=()
probe_notes=()

register() {
    probe_names+=("$1")
    probe_kinds+=("$2")
    probe_notes+=("$3")
}

# P01 -- the demo's crashing statement, unchanged: custom-typed table, inside
# a transaction, INSERT ... RETURNING decoded with fetchAll().
register P01 library "demo shape: txn + insert.values.returning + fetchAll"
add_library_probe P01 <<'SWIFT'
import Foundation
import SwiftQL

public enum ProbeError: Error { case noRow }

public func probe(_ database: GRDBDatabase, _ todo: Todo) throws -> Todo {
    try database.withTransaction { scope in
        let schema = XLSchema()
        let table = schema.table(Todo.self)
        let rows = try scope.makeRequest(
            with: insert(table)
                .values(Todo.MetaInsert(todo))
                .returning(table)
        ).fetchAll()
        guard let written = rows.first else { throw ProbeError.noRow }
        return written
    }
}
SWIFT

# P02 -- P01 without the transaction. Separates "opened existential inside a
# generic closure" from "opened existential".
register P02 library "no txn: insert.values.returning + fetchAll"
add_library_probe P02 <<'SWIFT'
import Foundation
import SwiftQL

public enum ProbeError: Error { case noRow }

public func probe(_ database: GRDBDatabase, _ todo: Todo) throws -> Todo {
    let schema = XLSchema()
    let table = schema.table(Todo.self)
    let rows = try database.makeRequest(
        with: insert(table)
            .values(Todo.MetaInsert(todo))
            .returning(table)
    ).fetchAll()
    guard let written = rows.first else { throw ProbeError.noRow }
    return written
}
SWIFT

# P03 -- P01 with the RETURNING dropped, so makeRequest returns the
# non-parameterised `any XLWriteRequest` instead of `any XLRequest<Row>`.
register P03 library "txn + insert.values + execute (no RETURNING)"
add_library_probe P03 <<'SWIFT'
import Foundation
import SwiftQL

public func probe(_ database: GRDBDatabase, _ todo: Todo) throws {
    try database.withTransaction { scope in
        let schema = XLSchema()
        let table = schema.table(Todo.self)
        try scope.makeRequest(
            with: insert(table).values(Todo.MetaInsert(todo))
        ).execute()
    }
}
SWIFT

# P04 -- P01 with a plain SELECT in place of INSERT ... RETURNING. Both go
# through `any XLRequest<Todo>.fetchAll()`, so this isolates the statement.
register P04 library "txn + select + fetchAll"
add_library_probe P04 <<'SWIFT'
import Foundation
import SwiftQL

public func probe(_ database: GRDBDatabase) throws -> [Todo] {
    try database.withTransaction { scope in
        try scope.makeRequest(with: sql { schema in
            let todo = schema.table(Todo.self)
            Select(todo)
            From(todo)
        }).fetchAll()
    }
}
SWIFT

# P05 -- P02 with the result bound to a local of explicit type, to see whether
# the crash follows the inferred opened-existential result.
register P05 library "no txn: insert.values.returning, annotated request"
add_library_probe P05 <<'SWIFT'
import Foundation
import SwiftQL

public enum ProbeError: Error { case noRow }

public func probe(_ database: GRDBDatabase, _ todo: Todo) throws -> Todo {
    let schema = XLSchema()
    let table = schema.table(Todo.self)
    let statement = insert(table)
        .values(Todo.MetaInsert(todo))
        .returning(table)
    let request: any XLRequest<Todo> = database.makeRequest(with: statement)
    let rows = try request.fetchAll()
    guard let written = rows.first else { throw ProbeError.noRow }
    return written
}
SWIFT

# P06 -- an intrinsic-typed table only (String/Int/Bool), same statement as
# P02. Separates the statement shape from the demo's XLCustomType columns.
register P06 library "intrinsic-typed table: insert.values.returning + fetchAll"
mkdir -p "$harness/Sources/P06"
cat > "$harness/Sources/P06/Probe.swift" <<'SWIFT'
import Foundation
import SwiftQL

@SQLTable
public struct Plain: Equatable, Sendable {
    public var id: String
    public var name: String
    public var count: Int
}

public enum ProbeError: Error { case noRow }

public func probe(_ database: GRDBDatabase, _ value: Plain) throws -> Plain {
    let schema = XLSchema()
    let table = schema.table(Plain.self)
    let rows = try database.makeRequest(
        with: insert(table)
            .values(Plain.MetaInsert(value))
            .returning(table)
    ).fetchAll()
    guard let written = rows.first else { throw ProbeError.noRow }
    return written
}
SWIFT

# P07 -- intrinsic-typed table, no RETURNING, plain create + execute. The
# smallest write path there is; page 1 of the playground is this shape.
register P07 library "intrinsic-typed table: sqlCreate + execute"
mkdir -p "$harness/Sources/P07"
cat > "$harness/Sources/P07/Probe.swift" <<'SWIFT'
import Foundation
import SwiftQL

@SQLTable
public struct Plain2: Equatable, Sendable {
    public var id: String
    public var name: String
    public var count: Int
}

public func probe(_ database: GRDBDatabase) throws {
    try database.makeRequest(with: sqlCreate(Plain2.self)).execute()
}
SWIFT

# P08..P12 -- the playground pages exactly as CI builds them. 1, 2 and 4 fail
# on the pinned cell; 3 and 5 pass, and are here as controls.
register P08 executable "playground page 1 Defining tables"
add_page_probe P08 "1 Defining tables"
register P09 executable "playground page 2 Inserting data"
add_page_probe P09 "2 Inserting data"
register P10 executable "playground page 3 Running select queries (control)"
add_page_probe P10 "3 Running select queries"
register P11 executable "playground page 4 Update statements"
add_page_probe P11 "4 Update statements"
register P12 executable "playground page 5 Delete statements (control)"
add_page_probe P12 "5 Delete statements"

# --- Package manifest ------------------------------------------------------

{
    printf '// swift-tools-version: 5.9\n'
    printf 'import PackageDescription\n\n'
    printf 'let package = Package(\n'
    printf '    name: "Probe530",\n'
    printf '    platforms: [.iOS(.v16), .macOS(.v13)],\n'
    printf '    dependencies: [.package(name: "SwiftQL", path: "%s")],\n' \
        "$repository_root"
    printf '    targets: [\n'
    for index in "${!probe_names[@]}"; do
        name="${probe_names[$index]}"
        if [[ "${probe_kinds[$index]}" == "executable" ]]; then
            printf '        .executableTarget(\n'
        else
            printf '        .target(\n'
        fi
        printf '            name: "%s",\n' "$name"
        printf '            dependencies: [\n'
        printf '                .product(name: "SwiftQL", package: "SwiftQL"),\n'
        printf '                .product(name: "SwiftQLExamples", package: "SwiftQL"),\n'
        printf '            ]\n'
        printf '        ),\n'
    done
    printf '    ]\n'
    printf ')\n'
} > "$harness/Package.swift"

# --- Sweep -----------------------------------------------------------------

printf '==> Probing %s constructs against %s\n' \
    "${#probe_names[@]}" "$(xcrun swift --version | head -1)"

results="$output_directory/results.txt"
: > "$results"

for index in "${!probe_names[@]}"; do
    name="${probe_names[$index]}"
    note="${probe_notes[$index]}"
    log="$output_directory/$name.log"

    printf '==> %s: %s\n' "$name" "$note"
    (cd "$harness" && xcrun swift build --target "$name") > "$log" 2>&1
    status=$?

    if (( status == 0 )); then
        verdict=PASS
    elif grep -q 'due to signal 11' "$log"; then
        verdict=CRASH
    else
        verdict=ERROR
    fi

    printf '%-5s %-6s %s\n' "$name" "$verdict" "$note" >> "$results"
    printf '    %s\n' "$verdict"

    if [[ "$verdict" != PASS ]]; then
        # The whole point of the harness: keep the stack dump. The excerpt
        # check-playground-pages.sh prints (`tail -5`) is why #530 had no
        # backtrace for the playground pages to begin with.
        sed -n '/Stack dump:/,/^$/p' "$log" | head -60
        grep -E '^[0-9]+ +swift-frontend' "$log" | head -20
        grep -E 'error: ' "$log" | head -10
    fi
done

printf '\n==> Results\n'
cat "$results"
