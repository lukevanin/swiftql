#!/bin/sh
# Proves that a declared query added to a target is validated with no change
# to any query list or generator (#659).
#
# SwiftQLDeclaredQueryRegistryPlugin scans FixtureQueries on every build and
# generates FixtureQueriesDeclaredQueries. fixture-manifest writes a manifest
# from that registry and validates it. It names no query.
#
# Checks, in order:
#   1. The manifest holds the two queries the fixture declares, and passes.
#   2. A new @SQLQuery added in a new source file is in the next manifest,
#      and passes. The generator and the package manifest are unchanged.
#   3. A new @SQLQuery declaration against a table the snapshot does not
#      have fails validation with the validator's own diagnostic.
#
# The fixture is copied to a scratch directory first, so the added files never
# touch the checkout.
set -eu

fixture_root="$(cd "$(dirname "$0")" && pwd -P)"
source_root="$(cd "$fixture_root/../.." && pwd -P)"
work="$(mktemp -d "${TMPDIR:-/tmp}/swiftql-registry-fixture.XXXXXX")"
trap 'rm -rf "$work"' EXIT

cp "$fixture_root/Package.swift" "$work/Package.swift"
cp -R "$fixture_root/Sources" "$work/Sources"
SWIFTQL_SOURCE_ROOT="$source_root"
export SWIFTQL_SOURCE_ROOT

# Runs the generator. Its exit status is returned, and its output is kept in
# $work/run.log.
generate() {
    set +e
    swift run --package-path "$work" fixture-manifest "$work/out" > "$work/run.log" 2>&1
    status=$?
    set -e
    return $status
}

require_line() {
    if ! grep -qx "$1" "$work/run.log"; then
        echo "FAIL: expected the line '$1'"
        cat "$work/run.log"
        exit 1
    fi
}

query_count() {
    grep -c '^query: ' "$work/run.log" || true
}

generator_fingerprint() {
    cat "$work/Package.swift" "$work/Sources/fixture-manifest/main.swift" | cksum
}

echo "== 1. The declared queries are in the manifest, and pass =="
if ! generate; then
    echo "FAIL: expected the first generation to pass"
    cat "$work/run.log"
    exit 1
fi
require_line "query: GRDBDatabase.fixtureAuthor"
require_line "query: GRDBDatabase.fixtureAuthors"
require_line "verdict: passed"
if [ "$(query_count)" -ne 2 ]; then
    echo "FAIL: expected 2 queries"
    cat "$work/run.log"
    exit 1
fi
fingerprint_before="$(generator_fingerprint)"

echo "== 2. A query added to the target is validated with no other change =="
cat > "$work/Sources/FixtureQueries/AddedQuery.swift" <<'EOF'
import SwiftQL

extension GRDBDatabase {

    @SQLQuery
    func fixtureAuthorsNamed(name: String) -> [FixtureAuthor] {
        sqlResult { schema in
            let author = schema.table(FixtureAuthor.self)
            Select(author)
            From(author)
            Where(author.name == name)
        }
    }
}
EOF
if ! generate; then
    echo "FAIL: expected the generation with an added query to pass"
    cat "$work/run.log"
    exit 1
fi
require_line "query: GRDBDatabase.fixtureAuthorsNamed"
require_line "verdict: passed"
if [ "$(query_count)" -ne 3 ]; then
    echo "FAIL: expected 3 queries"
    cat "$work/run.log"
    exit 1
fi
if ! grep -q '"id" : "GRDBDatabase.fixtureAuthorsNamed"' "$work/out/manifest.json"; then
    echo "FAIL: the written manifest does not hold the added query"
    exit 1
fi
if [ "$(generator_fingerprint)" != "$fingerprint_before" ]; then
    echo "FAIL: the generator or the package manifest changed"
    exit 1
fi

echo "== 3. An added query against a missing table fails validation =="
cat > "$work/Sources/FixtureQueries/BrokenQuery.swift" <<'EOF'
import SwiftQL

@SQLTable
public struct FixtureMissing: Equatable {
    public var id: String
}

extension GRDBDatabase {

    @SQLQuery
    func fixtureMissingRows() -> [FixtureMissing] {
        sqlResult { schema in
            let missing = schema.table(FixtureMissing.self)
            Select(missing)
            From(missing)
        }
    }
}
EOF
if generate; then
    echo "FAIL: expected validation to fail for a query against a missing table"
    cat "$work/run.log"
    exit 1
fi
require_line "query: GRDBDatabase.fixtureMissingRows"
require_line "verdict: failed"
if ! grep -q '^diagnostic: GRDBDatabase.fixtureMissingRows: .*FixtureMissing' "$work/run.log"; then
    echo "FAIL: expected the validator's diagnostic for the missing table"
    cat "$work/run.log"
    exit 1
fi

echo "OK: declared-query discovery validates an added query with no list to edit"
