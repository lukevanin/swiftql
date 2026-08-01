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
# Explicit template so this works identically across BSD (macOS) and GNU
# mktemp implementations, which differ on bare invocations.
VALID_MANIFEST_BACKUP=$(mktemp "${TMPDIR:-/tmp}/swiftql-plugin-verify-xcode.XXXXXX")
cp "$MANIFEST" "$VALID_MANIFEST_BACKUP"
DERIVED_DATA=$(mktemp -d "${TMPDIR:-/tmp}/swiftql-plugin-verify-xcode-dd.XXXXXX")
trap 'cp "$VALID_MANIFEST_BACKUP" "$MANIFEST"; rm -f "$VALID_MANIFEST_BACKUP"; rm -rf "$DERIVED_DATA"' EXIT

PRODUCTS_DIR="$DERIVED_DATA/Build/Products/$CONFIGURATION"

xcode_build() {
    # `platform=macOS` matches the fixture's `platforms: [.macOS(.v13)]`.
    xcodebuild build \
        -scheme "$SCHEME" \
        -destination 'platform=macOS' \
        -configuration "$CONFIGURATION" \
        -derivedDataPath "$DERIVED_DATA" \
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
echo "OK"

echo
echo "All SwiftQLSQLiteBuildValidationPlugin Xcode build-system checks passed."
