#!/bin/bash

set -euo pipefail

# Verifies the Getting Started playground has not rotted (#483).
#
# A playground is not compiled by `swift build` or exercised by `swift test`,
# so an API change can break it silently. This script closes that gap without
# needing Xcode's playground runner, which is not scriptable:
#
#   1. The companion example module builds.
#   2. Every page listed in contents.xcplayground exists on disk, and every
#      page on disk is listed. Both lists are compared as sets; this does not
#      check that the navigator's page order matches the on-disk listing.
#   3. Every page's Contents.swift compiles and runs against this checkout,
#      with no warnings and no hang.
#
# Step 3 works by copying each page to main.swift in a throwaway SwiftPM
# package that depends on this checkout by path. A page's top-level code is
# exactly what an executable target's main.swift holds, so the page runs
# unmodified. What this does not cover is Xcode's own playground REPL and its
# results sidebar.

fail() {
    printf 'error: playground check: %s\n' "$*" >&2
    exit 1
}

script_directory="$(cd "$(dirname "$0")" && pwd -P)"
repository_root="$(cd "$script_directory/../.." && pwd -P)"
playground="$repository_root/Examples/GettingStarted.playground"
manifest="$playground/contents.xcplayground"
pages_directory="$playground/Pages"

if [[ "$#" -gt 1 ]]; then
    printf 'usage: %s [OUTPUT_DIRECTORY]\n' "$0" >&2
    exit 64
fi

page_timeout="${SWIFTQL_PLAYGROUND_PAGE_TIMEOUT:-180}"
if [[ ! "$page_timeout" =~ ^[1-9][0-9]*$ ]]; then
    fail "SWIFTQL_PLAYGROUND_PAGE_TIMEOUT must be a positive integer"
fi

output_directory="${1:-}"
if [[ -n "$output_directory" ]]; then
    mkdir -p "$output_directory"
    output_directory="$(cd "$output_directory" && pwd -P)"
fi

test -f "$manifest" || fail "missing playground manifest: $manifest"
test -d "$pages_directory" || fail "missing playground pages: $pages_directory"

temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/swiftql-playground.XXXXXX")"
trap 'rm -rf "$temporary_root"' EXIT

# --- 1. The companion example module builds --------------------------------

printf '==> Building SwiftQLExamples\n'
(
    cd "$repository_root"
    swift build --target SwiftQLExamples
) || fail 'SwiftQLExamples does not build'

# --- 2. The manifest and the Pages directory agree -------------------------

manifest_pages="$temporary_root/manifest-pages.txt"
disk_pages="$temporary_root/disk-pages.txt"

sed -n "s/.*<page name='\([^']*\)'.*/\1/p" "$manifest" > "$manifest_pages"
if [[ ! -s "$manifest_pages" ]]; then
    fail "no <page name='...'/> entries found in $manifest"
fi

# Xcode orders pages by the manifest, so compare as sorted sets: order is the
# manifest's to decide, membership is what has to match.
find "$pages_directory" -maxdepth 1 -name '*.xcplaygroundpage' \
    -exec basename {} .xcplaygroundpage \; | sort > "$disk_pages"

sorted_manifest_pages="$temporary_root/manifest-pages-sorted.txt"
sort "$manifest_pages" > "$sorted_manifest_pages"

if ! diff -u "$sorted_manifest_pages" "$disk_pages" > "$temporary_root/pages.diff"; then
    cat "$temporary_root/pages.diff" >&2
    fail 'contents.xcplayground and the Pages directory disagree'
fi

page_count="$(wc -l < "$manifest_pages" | tr -d ' ')"
printf '==> %s pages listed and present\n' "$page_count"

# --- 3. Every page compiles and runs ---------------------------------------

harness="$temporary_root/PlaygroundPageHarness"
mkdir -p "$harness/Sources/PlaygroundPage"

cat > "$harness/Package.swift" <<EOF
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PlaygroundPageHarness",
    platforms: [.iOS(.v16), .macOS(.v13)],
    dependencies: [
        // Named explicitly rather than letting SwiftPM derive identity from
        // the checkout directory, which is what IntegrationTests/Swift5Client,
        // IntegrationTests/BuildValidationPluginFixture, and
        // Examples/TodoApp/TodoKit all do. A CI checkout directory does not
        // have to be called "swiftql", and a worktree never is.
        .package(name: "SwiftQL", path: "$repository_root")
    ],
    targets: [
        .executableTarget(
            name: "PlaygroundPage",
            dependencies: [
                .product(name: "SwiftQL", package: "SwiftQL"),
                .product(name: "SwiftQLExamples", package: "SwiftQL"),
            ]
        )
    ]
)
EOF

transcript="$temporary_root/transcript.txt"
: > "$transcript"

failures=0
while IFS= read -r page; do
    page_source="$pages_directory/$page.xcplaygroundpage/Contents.swift"
    if [[ ! -f "$page_source" ]]; then
        printf 'error: missing Contents.swift for page: %s\n' "$page" >&2
        failures=$((failures + 1))
        continue
    fi

    printf '==> %s\n' "$page"
    cp "$page_source" "$harness/Sources/PlaygroundPage/main.swift"

    build_log="$temporary_root/build-$failures.log"
    # The `|| true` on both excerpt pipelines is load-bearing under
    # `set -euo pipefail`. A build can fail without any line matching
    # `error:` (a linker or toolchain failure), which makes grep exit 1 and
    # pipefail abort the whole script before the failure is counted. `head`
    # closing the pipe early does the same thing by way of SIGPIPE. Either
    # way the script would exit mid-loop and report nothing.
    if ! (cd "$harness" && swift build --product PlaygroundPage) > "$build_log" 2>&1; then
        grep -E 'error:' "$build_log" | head -20 >&2 || true
        tail -5 "$build_log" >&2
        printf 'error: page does not compile: %s\n' "$page" >&2
        failures=$((failures + 1))
        continue
    fi
    if grep -q 'warning:' "$build_log"; then
        grep -E 'warning:' "$build_log" | head -20 >&2 || true
        printf 'error: page compiles with warnings: %s\n' "$page" >&2
        failures=$((failures + 1))
        continue
    fi

    # A page that waits on a live query can hang if the observation never
    # delivers, so run it under a watchdog rather than blocking the build.
    page_output="$temporary_root/output.txt"
    (cd "$harness" && swift run --skip-build PlaygroundPage) \
        > "$page_output" 2>&1 &
    page_pid=$!
    elapsed=0
    while kill -0 "$page_pid" 2>/dev/null && (( elapsed < page_timeout )); do
        sleep 1
        elapsed=$((elapsed + 1))
    done
    if kill -0 "$page_pid" 2>/dev/null; then
        kill -9 "$page_pid" 2>/dev/null || true
        wait "$page_pid" 2>/dev/null || true
        printf 'error: page did not finish within %ss: %s\n' \
            "$page_timeout" "$page" >&2
        failures=$((failures + 1))
        continue
    fi
    if ! wait "$page_pid"; then
        cat "$page_output" >&2
        printf 'error: page exited non-zero: %s\n' "$page" >&2
        failures=$((failures + 1))
        continue
    fi

    {
        printf '===== %s =====\n' "$page"
        cat "$page_output"
    } >> "$transcript"
    cat "$page_output"
done < "$manifest_pages"

if [[ -n "$output_directory" ]]; then
    cp "$transcript" "$output_directory/page-output.txt"
    {
        printf '## Getting Started playground\n\n'
        printf -- '- Source commit: `%s`\n' \
            "$(git -C "$repository_root" rev-parse HEAD)"
        printf -- '- Pages checked: %s\n' "$page_count"
        printf -- '- Failures: %s\n\n' "$failures"
        printf 'Each page was compiled and run against this checkout. '
        printf 'Xcode'"'"'s own playground runner is not scriptable and is not '
        printf 'covered.\n'
    } > "$output_directory/summary.md"
fi

if (( failures > 0 )); then
    fail "$failures of $page_count pages failed"
fi

printf '==> All %s pages compiled, ran, and exited cleanly\n' "$page_count"
