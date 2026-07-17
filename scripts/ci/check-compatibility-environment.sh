#!/bin/bash

set -euo pipefail

: "${EXPECTED_XCODE_VERSION:?Set EXPECTED_XCODE_VERSION}"
: "${EXPECTED_XCODE_BUILD:?Set EXPECTED_XCODE_BUILD}"
: "${EXPECTED_SWIFT_SERIES:?Set EXPECTED_SWIFT_SERIES}"
: "${EXPECTED_SDK_VERSION:?Set EXPECTED_SDK_VERSION}"
: "${EXPECTED_DEVELOPER_DIR:?Set EXPECTED_DEVELOPER_DIR}"

fail() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repository_root"

xcode_output="$(xcodebuild -version)"
xcode_version="$(printf '%s\n' "$xcode_output" | sed -n '1s/^Xcode //p')"
xcode_build="$(printf '%s\n' "$xcode_output" | sed -n '2s/^Build version //p')"
swift_output="$(xcrun swift --version 2>&1)"
sdk_version="$(xcrun --sdk macosx --show-sdk-version)"
tools_version="$(xcrun swift package tools-version)"

printf '%s\n' "Selected developer directory: ${DEVELOPER_DIR:-<unset>}"
printf '%s\n' "$xcode_output"
printf '%s\n' "$swift_output"
printf 'macOS SDK: %s\n' "$sdk_version"
printf 'macOS SDK path: %s\n' "$(xcrun --sdk macosx --show-sdk-path)"
printf 'Swift package tools version: %s\n' "$tools_version"
swift_executable="$(xcrun --find swift)"
printf 'Swift executable: %s\n' "$swift_executable"
printf 'System xcode-select path: %s\n' "$(xcode-select -p)"
printf 'Architecture: %s\n' "$(uname -m)"
printf 'Runner ImageOS: %s\n' "${ImageOS:-<not reported>}"
printf 'Runner ImageVersion: %s\n' "${ImageVersion:-<not reported>}"
sw_vers

[[ "${DEVELOPER_DIR:-}" == "$EXPECTED_DEVELOPER_DIR" ]] ||
    fail "DEVELOPER_DIR is '${DEVELOPER_DIR:-<unset>}'; expected '$EXPECTED_DEVELOPER_DIR'"
[[ -d "$EXPECTED_DEVELOPER_DIR" ]] ||
    fail "expected Xcode developer directory does not exist: $EXPECTED_DEVELOPER_DIR"
[[ "$swift_executable" == "$EXPECTED_DEVELOPER_DIR"/Toolchains/*/usr/bin/swift ]] ||
    fail "xcrun selected Swift outside the expected Xcode: $swift_executable"
[[ "$xcode_version" == "$EXPECTED_XCODE_VERSION" ]] ||
    fail "Xcode version is '$xcode_version'; expected '$EXPECTED_XCODE_VERSION'"
[[ "$xcode_build" == "$EXPECTED_XCODE_BUILD" ]] ||
    fail "Xcode build is '$xcode_build'; expected '$EXPECTED_XCODE_BUILD'"
[[ "$swift_output" == *"Apple Swift version $EXPECTED_SWIFT_SERIES"* ]] ||
    fail "Swift compiler is not in the expected $EXPECTED_SWIFT_SERIES series"
[[ "$sdk_version" == "$EXPECTED_SDK_VERSION" ]] ||
    fail "macOS SDK is '$sdk_version'; expected '$EXPECTED_SDK_VERSION'"
[[ "$tools_version" == "5.9.0" ]] ||
    fail "package tools version is '$tools_version'; expected '5.9.0'"
