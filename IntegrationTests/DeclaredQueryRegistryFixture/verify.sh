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
#
# Each check builds fixture-manifest, and then runs it as a second step
# (#772). The build and the run each have a time limit, and the operating
# system's kill of either one is told apart from a real failure. Only the run
# gives a check its result, so a failed build can no longer look like a
# failed validation.
set -eu

fixture_root="$(cd "$(dirname "$0")" && pwd -P)"
source_root="$(cd "$fixture_root/../.." && pwd -P)"
work="$(mktemp -d "${TMPDIR:-/tmp}/swiftql-registry-fixture.XXXXXX")"
trap 'rm -rf "$work"' EXIT

cp "$fixture_root/Package.swift" "$work/Package.swift"
cp -R "$fixture_root/Sources" "$work/Sources"
SWIFTQL_SOURCE_ROOT="$source_root"
export SWIFTQL_SOURCE_ROOT

# The number of compiler processes SwiftPM starts at the same time. SwiftPM
# starts one process for each core by default. This package builds
# swift-syntax and SwiftQL from source, and the macOS CI runner has 3 cores
# and a small memory size.
#
# A cap of two processes lowers the peak memory of a cold build. These are
# local measurements of the peak resident size of all processes of the build,
# on macOS 26 on arm64 with Swift 6.4:
#
#   14 processes (that machine's core count): 3.42 GB, 24 s
#    3 processes (the CI runner's core count): 1.78 GB, 45 s
#    2 processes:                              1.38 GB, 53 s
#
# Read the limit of this evidence before you change the value. No measurement
# of the memory of the macOS runner itself exists, so nobody has shown that
# the cap stops the kill. The runner kills the process after the build of
# fixture-manifest reports that it is complete, so a lower peak during the
# build is the best remedy available without such a measurement. The retry
# below covers what the cap does not.
jobs="${SWIFTQL_FIXTURE_JOBS:-2}"

# The time limit in seconds for one build and for one run. A hung build must
# fail with a message of its own, and not with no message at the job's limit.
#
# Keep the build limit low. This step is number 35 of 38 in a job that stops
# at 45 minutes, and about 30 minutes of that time is gone when the step
# starts. generate() runs three times, and each build can also retry, so a
# large limit lets the job stop first and report nothing. A limit of 420 s
# lets one hung build report itself in the time the job has left.
build_limit="${SWIFTQL_FIXTURE_BUILD_LIMIT:-420}"
run_limit="${SWIFTQL_FIXTURE_RUN_LIMIT:-180}"

# The number of extra attempts after the operating system kills a build or a
# run with SIGKILL (status 137). The macOS CI runner kills a process when its
# memory runs low. That kill comes from the runner, and not from the code
# under test, so the fixture proves nothing when it reports such a kill as a
# failure (#772). Every other failure fails the check at once.
sigkill_retries="${SWIFTQL_FIXTURE_SIGKILL_RETRIES:-1}"

build_log="$work/build.log"
run_log="$work/run.log"

# Tells if an exit status is a SIGKILL. A shell reports a signalled child as
# 128 plus the signal number, so SIGKILL is 137.
#
# A shell cannot tell a signalled child from a program that returns 137 by
# itself, so this test can accept a program that chooses that value. The risk
# here is small: fixture-manifest returns 0, 1, or 64 only, and swift build
# does not return 137.
#
# The value 265 is the same test for ksh, which returns 256 plus the signal
# number. It is defensive only. The first line of this file is #!/bin/sh, so
# ksh does not run this script on macOS or on Linux.
is_sigkill() {
    [ "$1" -eq 137 ] || [ "$1" -eq 265 ]
}

# Gives the word "time" for the value 1, and "times" for every other value.
times_word() {
    if [ "$1" -eq 1 ]; then
        echo "time"
    else
        echo "times"
    fi
}

# Reports a retry to the CI log, so that the flake stays visible and counted.
#
# It prints the output of the killed attempt here, and not later. A retry that
# then passes leaves no other record: the next generate() removes the kept
# file, and the scratch directory goes when this script ends. That output is
# the evidence that #772 needs, and this is the case that #772 describes.
#
# usage: report_retry NAME THIS_ATTEMPT TOTAL_ATTEMPTS KEPT_LOG
report_retry() {
    echo "note: the operating system killed '$1' with SIGKILL on attempt $2 of $3."
    echo "      The fixture starts it again (#772)."
    if [ -f "$4" ]; then
        echo "--- the output of the killed attempt ($4) ---"
        cat "$4"
        echo "--- end of the output of the killed attempt ---"
    fi
    if [ -n "${GITHUB_ACTIONS:-}" ]; then
        echo "::warning::DeclaredQueryRegistryFixture retried '$1' after a SIGKILL from the runner (#772)."
    fi
}

# Runs a command with a time limit. The output goes to $2. The exit status of
# the command is returned. A command that passes the limit is stopped, and
# $limit_reached is set to 1.
#
# generate() clears the errexit option before it calls this function, so that
# the function can read the exit status of a command that fails.
#
# usage: run_limited SECONDS LOG_PATH COMMAND...
run_limited() {
    limit="$1"
    log="$2"
    shift 2
    limit_reached=0
    rm -f "$work/limit-reached"
    : > "$work/running"
    # exec replaces the subshell, so $command_pid is the command itself and a
    # signal reaches the command and not a wrapper.
    ( trap - EXIT; exec "$@" > "$log" 2>&1 ) &
    command_pid=$!
    # The watchdog watches the $work/running file and not the process, because
    # a process that has stopped stays visible to kill -0 until its parent
    # collects it. Its own output goes to /dev/null, so that nothing it starts
    # holds the log of the calling step open.
    #
    # The signals reach the direct child only. A swift build that passes the
    # limit leaves its swift-frontend children alive, and the CI runner
    # collects them when the job ends. This is acceptable, because a build
    # that passes the limit fails the fixture at once.
    (
        trap - EXIT
        waited=0
        while [ -f "$work/running" ] && [ "$waited" -lt "$limit" ]; do
            sleep 1
            waited=$((waited + 1))
        done
        if [ -f "$work/running" ]; then
            : > "$work/limit-reached"
            kill -TERM "$command_pid" 2>/dev/null || true
            # Give the command 10 s to stop after SIGTERM, but stop waiting as
            # soon as it does stop.
            waited=0
            while [ -f "$work/running" ] && [ "$waited" -lt 10 ]; do
                sleep 1
                waited=$((waited + 1))
            done
            if [ -f "$work/running" ]; then
                kill -KILL "$command_pid" 2>/dev/null || true
            fi
        fi
    ) > /dev/null 2>&1 &
    watchdog_pid=$!
    wait "$command_pid"
    status=$?
    rm -f "$work/running"
    wait "$watchdog_pid" 2>/dev/null
    if [ -f "$work/limit-reached" ]; then
        limit_reached=1
    fi
    return "$status"
}

# Runs a command with a time limit, and retries it only when the operating
# system kills it with SIGKILL. See $sigkill_retries above.
#
# generate() clears the errexit option before it calls this function, so that
# the function can read the exit status of a command that fails.
#
# usage: run_retried NAME SECONDS LOG_PATH COMMAND...
run_retried() {
    name="$1"
    retry_log="$3"
    shift
    rm -f "$retry_log".[0-9]*
    attempt=0
    while :; do
        run_limited "$@"
        attempt_status=$?
        if [ "$limit_reached" -eq 1 ]; then
            return "$attempt_status"
        fi
        if ! is_sigkill "$attempt_status"; then
            return "$attempt_status"
        fi
        if [ "$attempt" -ge "$sigkill_retries" ]; then
            return "$attempt_status"
        fi
        # Keep the output of the killed attempt. It is the evidence for #772,
        # and the next attempt writes over $retry_log.
        if [ -f "$retry_log" ]; then
            cp "$retry_log" "$retry_log.$((attempt + 1))"
        fi
        report_retry "$name" "$((attempt + 1))" "$((sigkill_retries + 1))" \
            "$retry_log.$((attempt + 1))"
        attempt=$((attempt + 1))
        sleep 5
    done
}

# Prints the output of a step. It prints the output of each killed attempt
# first, because the scratch directory does not survive this script.
show_log() {
    for kept in "$1".[0-9]*; do
        if [ -f "$kept" ]; then
            echo "--- $kept ---"
            cat "$kept"
        fi
    done
    if [ -f "$1" ]; then
        echo "--- $1 ---"
        cat "$1"
    fi
}

# Builds fixture-manifest, and then runs it. The status of the run is
# returned, so a check reads the validator's verdict only. A build that
# fails, that passes its time limit, or that the operating system kills more
# often than the retry allows stops the fixture at once.
generate() {
    # Clear the errexit option for this function and for the helpers it calls,
    # so that each one can read the exit status of a command that fails. The
    # option is saved one time here and restored one time below, and no helper
    # touches it. Every other exit from this function ends the script.
    generate_errexit=0
    case "$-" in
        *e*) generate_errexit=1 ;;
    esac
    set +e

    attempts=$((sigkill_retries + 1))

    run_retried "swift build" "$build_limit" "$build_log" \
        swift build --package-path "$work" --jobs "$jobs" --product fixture-manifest
    build_status=$?
    if [ "$build_status" -ne 0 ]; then
        if [ "$limit_reached" -eq 1 ]; then
            echo "FAIL: the build of fixture-manifest passed its ${build_limit}s limit"
        elif is_sigkill "$build_status"; then
            echo "FAIL: the operating system killed the build of fixture-manifest with"
            echo "      SIGKILL $attempts $(times_word "$attempts"). The CI runner has too little memory."
        else
            echo "FAIL: the build of fixture-manifest failed with status $build_status"
        fi
        show_log "$build_log"
        exit 1
    fi

    run_retried "fixture-manifest" "$run_limit" "$run_log" \
        swift run --package-path "$work" --jobs "$jobs" --skip-build fixture-manifest "$work/out"
    run_status=$?
    if [ "$run_status" -ne 0 ]; then
        if [ "$limit_reached" -eq 1 ]; then
            echo "FAIL: fixture-manifest passed its ${run_limit}s limit"
            show_log "$run_log"
            exit 1
        fi
        if is_sigkill "$run_status"; then
            echo "FAIL: the operating system killed fixture-manifest with SIGKILL"
            echo "      $attempts $(times_word "$attempts"). The CI runner has too little memory."
            show_log "$run_log"
            exit 1
        fi
    fi

    if [ "$generate_errexit" -eq 1 ]; then
        set -e
    fi
    return "$run_status"
}

require_line() {
    if ! grep -qx "$1" "$run_log"; then
        echo "FAIL: expected the line '$1'"
        show_log "$run_log"
        exit 1
    fi
}

query_count() {
    grep -c '^query: ' "$run_log" || true
}

generator_fingerprint() {
    cat "$work/Package.swift" "$work/Sources/fixture-manifest/main.swift" | cksum
}

echo "== 1. The declared queries are in the manifest, and pass =="
if ! generate; then
    echo "FAIL: expected the first generation to pass"
    show_log "$run_log"
    exit 1
fi
require_line "query: GRDBDatabase.fixtureAuthor"
require_line "query: GRDBDatabase.fixtureAuthors"
require_line "verdict: passed"
if [ "$(query_count)" -ne 2 ]; then
    echo "FAIL: expected 2 queries"
    show_log "$run_log"
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
    show_log "$run_log"
    exit 1
fi
require_line "query: GRDBDatabase.fixtureAuthorsNamed"
require_line "verdict: passed"
if [ "$(query_count)" -ne 3 ]; then
    echo "FAIL: expected 3 queries"
    show_log "$run_log"
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
    show_log "$run_log"
    exit 1
fi
require_line "query: GRDBDatabase.fixtureMissingRows"
require_line "verdict: failed"
if ! grep -q '^diagnostic: GRDBDatabase.fixtureMissingRows: .*FixtureMissing' "$run_log"; then
    echo "FAIL: expected the validator's diagnostic for the missing table"
    show_log "$run_log"
    exit 1
fi

echo "OK: declared-query discovery validates an added query with no list to edit"
