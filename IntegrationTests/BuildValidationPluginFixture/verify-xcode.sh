#!/bin/sh
# Verifies SwiftQLSQLiteBuildValidationPlugin under *Xcode's* build system,
# which is a different build system from the one `verify.sh` exercises and
# which regressed independently of it (#492).
#
# Xcode names a package executable after its product, while a plugin's
# `context.tool(named:)` resolves the tool by target name. When the validator
# executable's target name and product name disagree, Xcode drops it from the
# adopting target's dependency graph and every plugin-adopting target fails
# with "Build input file cannot be found" before validation runs — on a valid
# manifest as much as an invalid one. `swift build` tolerates the mismatch, so
# verify.sh alone cannot catch this.
#
# Checks, in order:
#   1. A valid manifest builds, both opted-in targets report "passed", and no
#      target reports the #492 "Build input file cannot be found" error.
#   2. The validator executable is built at the exact path the plugin's tool
#      resolution expects, `Products/<config>/swiftql-build-validate` — the
#      target-name/product-name invariant #492 turned on.
#   3. An invalid manifest fails the Xcode build with the validator's own
#      diagnostic, not with a missing-input-file error.
#   4. Restoring the valid manifest builds successfully again.
#   5. An Xcode *application* target (XcodeApp/ValidatedApp.xcodeproj) adopts
#      the plugin through its XcodeBuildToolPlugin conformance (#666), builds,
#      and produces both a "passed" correctness report and a plan sidecar with
#      verified recommendations, because its opt-in file is a target member.
#   6. An invalid manifest in that application target fails its build with the
#      validator's own diagnostic.
#   7. Restoring the application's valid manifest builds successfully again.
set -eu
cd "$(dirname "$0")"

SCHEME="SwiftQLBuildValidationPluginFixture-Package"
CONFIGURATION="Debug"
VALIDATOR_EXECUTABLE="swiftql-build-validate"
MISSING_INPUT_ERROR="Build input file cannot be found"

if ! command -v xcodebuild > /dev/null 2>&1; then
    echo "SKIP: xcodebuild is not available; this script needs Xcode on macOS."
    echo "      Run verify.sh for the swift build path."
    exit 0
fi

MANIFEST="Sources/ValidatedLibrary/swiftql-build-validation-manifest.json"
APP_PROJECT="XcodeApp/ValidatedApp.xcodeproj"
APP_SCHEME="ValidatedApp"
APP_MANIFEST="XcodeApp/ValidatedApp/swiftql-build-validation-manifest.json"
# Explicit template so this works identically across BSD (macOS) and GNU
# mktemp implementations, which differ on bare invocations.
VALID_MANIFEST_BACKUP=$(mktemp "${TMPDIR:-/tmp}/swiftql-plugin-verify-xcode.XXXXXX")
cp "$MANIFEST" "$VALID_MANIFEST_BACKUP"
VALID_APP_MANIFEST_BACKUP=$(mktemp "${TMPDIR:-/tmp}/swiftql-plugin-verify-xcode-app.XXXXXX")
cp "$APP_MANIFEST" "$VALID_APP_MANIFEST_BACKUP"
DERIVED_DATA=$(mktemp -d "${TMPDIR:-/tmp}/swiftql-plugin-verify-xcode-dd.XXXXXX")
# A derived-data directory of its own, so the application's reports can never
# be counted by the package checks above them, or the reverse.
APP_DERIVED_DATA=$(mktemp -d "${TMPDIR:-/tmp}/swiftql-plugin-verify-xcode-app-dd.XXXXXX")
trap 'cp "$VALID_MANIFEST_BACKUP" "$MANIFEST"; cp "$VALID_APP_MANIFEST_BACKUP" "$APP_MANIFEST"; rm -f "$VALID_MANIFEST_BACKUP" "$VALID_APP_MANIFEST_BACKUP"; rm -rf "$DERIVED_DATA" "$APP_DERIVED_DATA"' EXIT

PRODUCTS_DIR="$DERIVED_DATA/Build/Products/$CONFIGURATION"
APP_PLUGIN_OUTPUTS="$APP_DERIVED_DATA/Build/Intermediates.noindex/BuildToolPluginIntermediates"

xcode_build() {
    # `platform=macOS` matches the fixture's `platforms: [.macOS(.v13)]`.
    xcodebuild build \
        -scheme "$SCHEME" \
        -destination 'platform=macOS' \
        -configuration "$CONFIGURATION" \
        -derivedDataPath "$DERIVED_DATA" \
        > "$1" 2>&1
}

xcode_app_build() {
    # The application target has no package scheme: it is a native target in
    # an .xcodeproj that depends on this repository as a local package, which
    # is the adoption path a SwiftPM target cannot exercise. No
    # -skipPackagePluginValidation flag, the same as xcode_build above.
    xcodebuild build \
        -project "$APP_PROJECT" \
        -scheme "$APP_SCHEME" \
        -destination 'platform=macOS' \
        -configuration "$CONFIGURATION" \
        -derivedDataPath "$APP_DERIVED_DATA" \
        > "$1" 2>&1
}

assert_no_missing_input_error() {
    if grep -q "$MISSING_INPUT_ERROR" "$1"; then
        echo "FAIL: #492 regressed — Xcode could not find the validator executable"
        grep "$MISSING_INPUT_ERROR" "$1"
        exit 1
    fi
}

assert_passed_report() {
    if ! grep -Eq '"overall_verdict"[[:space:]]*:[[:space:]]*"passed"' "$1"; then
        echo "FAIL: expected overall_verdict passed in $1"
        cat "$1"
        exit 1
    fi
}

assert_plan_sidecar_has_recommendations() {
    # `plutil` ships with macOS, which this script already requires. Extracting
    # the first element's DDL succeeds only when the array exists and is
    # non-empty. That holds on every `plutil` that reads JSON, unlike `raw`
    # output for a collection, which has differed between macOS releases.
    if ! FIRST_DDL=$(plutil -extract index_recommendations.recommendations.0.candidate.ddl raw -o - "$1" 2>/dev/null) \
        || [ -z "$FIRST_DDL" ]; then
        echo "FAIL: expected a non-empty index_recommendations.recommendations in $1"
        plutil -extract index_recommendations json -o - "$1" 2>/dev/null || true
        exit 1
    fi
}

echo "== 1. Valid manifest builds under Xcode and reports passed =="
if ! xcode_build /tmp/swiftql-plugin-verify-xcode-1.log; then
    echo "FAIL: expected the Xcode build to succeed with a valid manifest"
    assert_no_missing_input_error /tmp/swiftql-plugin-verify-xcode-1.log
    tail -50 /tmp/swiftql-plugin-verify-xcode-1.log
    exit 1
fi
assert_no_missing_input_error /tmp/swiftql-plugin-verify-xcode-1.log
# Scoped to the plugin's own declared-output directory: Xcode also copies each
# target's declared plugin outputs into that target's resource bundle, which
# would otherwise double-count these.
REPORTS=$(find "$DERIVED_DATA/Build/Intermediates.noindex/BuildToolPluginIntermediates" \
    -name swiftql-build-validation-report.json 2>/dev/null | sort)
# `grep -c` exits 1 when it counts zero matches, which would trip `set -e` and
# skip the explicit failure message below before it can print.
REPORT_COUNT=$(printf '%s\n' "$REPORTS" | grep -c . || true)
if [ "$REPORT_COUNT" -ne 2 ]; then
    echo "FAIL: expected 2 report files (one per opted-in target), found $REPORT_COUNT"
    printf '%s\n' "$REPORTS"
    exit 1
fi
# Split on newlines only. These paths sit under $DERIVED_DATA, hence under
# $TMPDIR, so the default IFS would break every check below the moment someone
# runs this with a temporary directory whose path contains a space. A
# `find ... | while read` pipeline would not do: its body runs in a subshell,
# where assert_passed_report's `exit 1` would end the subshell and let the
# script carry on reporting success.
OLD_IFS=$IFS
IFS='
'
for REPORT in $REPORTS; do
    assert_passed_report "$REPORT"
done
IFS=$OLD_IFS
echo "OK"

echo "== 1b. The opted-in target's plan sidecar carries verified recommendations =="
# Only SecondValidatedLibrary opts in. A present but empty recommendation set
# is what a verification pass whose every scratch copy failed produces, and
# before #647 that failure was invisible: it exited zero and warned nothing.
PLAN_REPORT=$(find "$DERIVED_DATA/Build/Intermediates.noindex/BuildToolPluginIntermediates" \
    -path '*SecondValidatedLibrary*' \
    -name swiftql-plan-analysis-report.json 2>/dev/null | sort | head -1)
if [ -z "$PLAN_REPORT" ]; then
    echo "FAIL: expected a plan sidecar for SecondValidatedLibrary"
    exit 1
fi
assert_plan_sidecar_has_recommendations "$PLAN_REPORT"
echo "OK (first recommendation: $FIRST_DDL)"

echo "== 2. Validator executable lands where the plugin's tool resolution expects =="
if [ ! -x "$PRODUCTS_DIR/$VALIDATOR_EXECUTABLE" ]; then
    echo "FAIL: expected an executable at $PRODUCTS_DIR/$VALIDATOR_EXECUTABLE"
    echo "      The validator's target name and product name must both be"
    echo "      '$VALIDATOR_EXECUTABLE' — see #492."
    ls "$PRODUCTS_DIR" || true
    exit 1
fi
echo "OK"

echo "== 3. Invalid manifest fails the Xcode build with the actionable diagnostic =="
cp Fixtures/invalid-manifest.json "$MANIFEST"
if xcode_build /tmp/swiftql-plugin-verify-xcode-3.log; then
    echo "FAIL: expected the Xcode build to fail with an invalid manifest"
    tail -50 /tmp/swiftql-plugin-verify-xcode-3.log
    exit 1
fi
assert_no_missing_input_error /tmp/swiftql-plugin-verify-xcode-3.log
if ! grep -q "no such table: totally_missing_table" /tmp/swiftql-plugin-verify-xcode-3.log; then
    echo "FAIL: expected the validator's diagnostic to be forwarded to build output"
    tail -50 /tmp/swiftql-plugin-verify-xcode-3.log
    exit 1
fi
echo "OK"

echo "== 4. Restoring the valid manifest builds successfully again =="
cp "$VALID_MANIFEST_BACKUP" "$MANIFEST"
if ! xcode_build /tmp/swiftql-plugin-verify-xcode-4.log; then
    echo "FAIL: expected the Xcode build to succeed again after restoring the valid manifest"
    assert_no_missing_input_error /tmp/swiftql-plugin-verify-xcode-4.log
    tail -50 /tmp/swiftql-plugin-verify-xcode-4.log
    exit 1
fi
assert_no_missing_input_error /tmp/swiftql-plugin-verify-xcode-4.log
# Check 3 left a failed report at ValidatedLibrary's path, so a build that
# succeeds without re-running the validator still fails here. Same IFS
# handling as check 1.
OLD_IFS=$IFS
IFS='
'
for REPORT in $REPORTS; do
    assert_passed_report "$REPORT"
done
IFS=$OLD_IFS
echo "OK"

echo "== 5. An Xcode application target adopts the plugin and produces both outputs =="
if ! xcode_app_build /tmp/swiftql-plugin-verify-xcode-5.log; then
    echo "FAIL: expected the application target to build with a valid manifest"
    assert_no_missing_input_error /tmp/swiftql-plugin-verify-xcode-5.log
    tail -50 /tmp/swiftql-plugin-verify-xcode-5.log
    exit 1
fi
assert_no_missing_input_error /tmp/swiftql-plugin-verify-xcode-5.log
# Scoped to the plugin's declared-output directory for the same reason as
# check 1: Xcode also copies declared outputs into the app bundle's Resources.
APP_REPORTS=$(find "$APP_PLUGIN_OUTPUTS" -path '*ValidatedApp*' \
    -name swiftql-build-validation-report.json 2>/dev/null | sort)
APP_REPORT_COUNT=$(printf '%s\n' "$APP_REPORTS" | grep -c . || true)
if [ "$APP_REPORT_COUNT" -ne 1 ]; then
    echo "FAIL: expected 1 correctness report for the application target, found $APP_REPORT_COUNT"
    echo "      Without it the plugin did not run: the target must list the plugin"
    echo "      and carry the manifest and snapshot as member files."
    printf '%s\n' "$APP_REPORTS"
    exit 1
fi
assert_passed_report "$APP_REPORTS"
APP_PLAN_REPORT=$(find "$APP_PLUGIN_OUTPUTS" -path '*ValidatedApp*' \
    -name swiftql-plan-analysis-report.json 2>/dev/null | sort | head -1)
if [ -z "$APP_PLAN_REPORT" ]; then
    echo "FAIL: expected a plan sidecar for the application target, whose"
    echo "      swiftql-plan-analysis.json opt-in is a member file"
    exit 1
fi
assert_plan_sidecar_has_recommendations "$APP_PLAN_REPORT"
echo "OK (first recommendation: $FIRST_DDL)"

echo "== 6. An invalid manifest fails the application target's build =="
cp Fixtures/invalid-manifest.json "$APP_MANIFEST"
if xcode_app_build /tmp/swiftql-plugin-verify-xcode-6.log; then
    echo "FAIL: expected the application target's build to fail with an invalid manifest"
    tail -50 /tmp/swiftql-plugin-verify-xcode-6.log
    exit 1
fi
assert_no_missing_input_error /tmp/swiftql-plugin-verify-xcode-6.log
if ! grep -q "no such table: totally_missing_table" /tmp/swiftql-plugin-verify-xcode-6.log; then
    echo "FAIL: expected the validator's diagnostic in the application target's build output"
    tail -50 /tmp/swiftql-plugin-verify-xcode-6.log
    exit 1
fi
echo "OK"

echo "== 7. Restoring the application's valid manifest builds successfully again =="
cp "$VALID_APP_MANIFEST_BACKUP" "$APP_MANIFEST"
if ! xcode_app_build /tmp/swiftql-plugin-verify-xcode-7.log; then
    echo "FAIL: expected the application target to build again after restoring its manifest"
    assert_no_missing_input_error /tmp/swiftql-plugin-verify-xcode-7.log
    tail -50 /tmp/swiftql-plugin-verify-xcode-7.log
    exit 1
fi
assert_no_missing_input_error /tmp/swiftql-plugin-verify-xcode-7.log
# Check 6 left a failed report at this path, so a build that succeeds without
# re-running the validator still fails here.
assert_passed_report "$APP_REPORTS"
echo "OK"

echo
echo "All SwiftQLSQLiteBuildValidationPlugin Xcode build-system checks passed."
