#!/bin/sh
# Verifies SwiftQLSQLiteBuildValidationPlugin's exact invocation contract by
# actually running `swift build` against this fixture package (a build-tool
# plugin's createBuildCommands cannot be unit-tested in isolation without a
# live PluginContext, so this is the practical, reproducible verification).
#
# Checks, in order:
#   1. A valid manifest builds successfully and produces a "passed" report.
#   1b. A second target adopting the plugin produces its own report at a
#       distinct path, proving reports don't collide across targets.
#   2. An invalid manifest fails the build and forwards the validator's
#      actionable diagnostic to stderr.
#   3. Restoring the valid manifest builds successfully again.
#   4. Rebuilding with no changes does not re-run validation (incremental
#      reuse).
#   5. Touching the manifest (content unchanged) does re-run validation, and
#      the resulting report is byte-identical to the prior run.
set -eu
cd "$(dirname "$0")"

MANIFEST="Sources/ValidatedLibrary/swiftql-build-validation-manifest.json"
VALID_MANIFEST_BACKUP=$(mktemp)
cp "$MANIFEST" "$VALID_MANIFEST_BACKUP"
trap 'cp "$VALID_MANIFEST_BACKUP" "$MANIFEST"; rm -f "$VALID_MANIFEST_BACKUP"' EXIT

report_paths() {
    # Scoped to the plugin's own declared-output directory: SwiftPM also
    # copies each target's declared plugin outputs into that target's
    # resource bundle, which would otherwise double-count these.
    find .build/plugins/outputs -name swiftql-build-validation-report.json 2>/dev/null | sort
}

assert_passed_report() {
    if ! grep -Eq '"overall_verdict"[[:space:]]*:[[:space:]]*"passed"' "$1"; then
        echo "FAIL: expected overall_verdict passed in $1"
        cat "$1"
        exit 1
    fi
}

echo "== 1. Valid manifest builds and reports passed =="
rm -rf .build
if ! swift build > /tmp/swiftql-plugin-verify-1.log 2>&1; then
    echo "FAIL: expected build to succeed with a valid manifest"
    cat /tmp/swiftql-plugin-verify-1.log
    exit 1
fi
REPORTS=$(report_paths)
REPORT_COUNT=$(printf '%s\n' "$REPORTS" | grep -c .)
if [ "$REPORT_COUNT" -ne 2 ]; then
    echo "FAIL: expected 2 report files (one per opted-in target), found $REPORT_COUNT"
    printf '%s\n' "$REPORTS"
    exit 1
fi
REPORT=$(printf '%s\n' "$REPORTS" | grep ValidatedLibrary | grep -v Second | head -1)
SECOND_REPORT=$(printf '%s\n' "$REPORTS" | grep SecondValidatedLibrary | head -1)
if [ -z "$REPORT" ] || [ -z "$SECOND_REPORT" ] || [ "$REPORT" = "$SECOND_REPORT" ]; then
    echo "FAIL: expected two distinct, target-namespaced report paths"
    printf '%s\n' "$REPORTS"
    exit 1
fi
assert_passed_report "$REPORT"
assert_passed_report "$SECOND_REPORT"
echo "OK"

echo "== 2. Invalid manifest fails the build with the actionable diagnostic =="
cp Fixtures/invalid-manifest.json "$MANIFEST"
if swift build > /tmp/swiftql-plugin-verify-2.log 2>&1; then
    echo "FAIL: expected build to fail with an invalid manifest"
    cat /tmp/swiftql-plugin-verify-2.log
    exit 1
fi
if ! grep -q "no such table: totally_missing_table" /tmp/swiftql-plugin-verify-2.log; then
    echo "FAIL: expected the validator's diagnostic to be forwarded to build output"
    cat /tmp/swiftql-plugin-verify-2.log
    exit 1
fi
echo "OK"

echo "== 3. Restoring the valid manifest builds successfully again =="
cp "$VALID_MANIFEST_BACKUP" "$MANIFEST"
if ! swift build > /tmp/swiftql-plugin-verify-3.log 2>&1; then
    echo "FAIL: expected build to succeed again after restoring the valid manifest"
    cat /tmp/swiftql-plugin-verify-3.log
    exit 1
fi
FIRST_HASH=$(shasum -a 256 "$REPORT" | awk '{print $1}')
echo "OK"

echo "== 4. Unchanged rebuild does not re-run validation =="
if ! swift build > /tmp/swiftql-plugin-verify-4.log 2>&1; then
    echo "FAIL: expected unchanged rebuild to succeed"
    exit 1
fi
if grep -q "SwiftQL SQLite build validation" /tmp/swiftql-plugin-verify-4.log; then
    echo "FAIL: expected validation to be skipped on an unchanged rebuild"
    cat /tmp/swiftql-plugin-verify-4.log
    exit 1
fi
echo "OK"

echo "== 5. Touching the manifest re-runs validation with a byte-identical report =="
touch "$MANIFEST"
if ! swift build > /tmp/swiftql-plugin-verify-5.log 2>&1; then
    echo "FAIL: expected rebuild after touch to succeed"
    exit 1
fi
if ! grep -q "SwiftQL SQLite build validation" /tmp/swiftql-plugin-verify-5.log; then
    echo "FAIL: expected validation to re-run after the manifest's mtime changed"
    cat /tmp/swiftql-plugin-verify-5.log
    exit 1
fi
SECOND_HASH=$(shasum -a 256 "$REPORT" | awk '{print $1}')
if [ "$FIRST_HASH" != "$SECOND_HASH" ]; then
    echo "FAIL: expected byte-identical reports across the rerun ($FIRST_HASH != $SECOND_HASH)"
    exit 1
fi
echo "OK"

echo
echo "All SwiftQLSQLiteBuildValidationPlugin invocation-contract checks passed."
