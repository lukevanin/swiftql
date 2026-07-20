#!/bin/bash

set -euo pipefail

: "${EXPECTED_SWIFT_SERIES:?Set EXPECTED_SWIFT_SERIES}"

expected_platform="${EXPECTED_PLATFORM:-macos}"
expected_swift_command_mode="${EXPECTED_SWIFT_COMMAND_MODE:-xcrun}"

fail() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repository_root"

case "$expected_swift_command_mode" in
    xcrun)
        swift_output="$(xcrun swift --version 2>&1)"
        swift_executable="$(xcrun --find swift)"
        ;;
    path)
        swift_output="$(swift --version 2>&1)"
        swift_executable="$(command -v swift)"
        [[ "$expected_platform" != "macos" || "$swift_executable" != "/usr/bin/swift" ]] ||
            fail "PATH Swift unexpectedly resolved to the Xcode dispatcher"
        ;;
    *)
        fail "unsupported EXPECTED_SWIFT_COMMAND_MODE: $expected_swift_command_mode"
        ;;
esac
tools_version="$(swift package tools-version)"
target_info="$(swiftc -print-target-info)"

printf '%s\n' "$swift_output"
printf 'Swift package tools version: %s\n' "$tools_version"
printf 'Swift executable: %s\n' "$swift_executable"
printf 'Swift command mode: %s\n' "$expected_swift_command_mode"
printf 'Compatibility platform: %s\n' "$expected_platform"
printf 'Swift target information:\n'
printf '%s\n' "$target_info"
printf 'Architecture: %s\n' "$(uname -m)"
printf 'Runner ImageOS: %s\n' "${ImageOS:-<not reported>}"
printf 'Runner ImageVersion: %s\n' "${ImageVersion:-<not reported>}"

case "$expected_platform" in
    macos)
        : "${EXPECTED_XCODE_VERSION:?Set EXPECTED_XCODE_VERSION}"
        : "${EXPECTED_XCODE_BUILD:?Set EXPECTED_XCODE_BUILD}"
        : "${EXPECTED_SDK_VERSION:?Set EXPECTED_SDK_VERSION}"
        : "${EXPECTED_DEVELOPER_DIR:?Set EXPECTED_DEVELOPER_DIR}"

        xcode_output="$(xcodebuild -version)"
        xcode_version="$(printf '%s\n' "$xcode_output" | sed -n '1s/^Xcode //p')"
        xcode_build="$(printf '%s\n' "$xcode_output" | sed -n '2s/^Build version //p')"
        sdk_version="$(xcrun --sdk macosx --show-sdk-version)"

        printf '%s\n' "Selected developer directory: ${DEVELOPER_DIR:-<unset>}"
        printf '%s\n' "$xcode_output"
        printf 'macOS SDK: %s\n' "$sdk_version"
        printf 'macOS SDK path: %s\n' "$(xcrun --sdk macosx --show-sdk-path)"
        printf 'System xcode-select path: %s\n' "$(xcode-select -p)"
        sw_vers

        [[ "${DEVELOPER_DIR:-}" == "$EXPECTED_DEVELOPER_DIR" ]] ||
            fail "DEVELOPER_DIR is '${DEVELOPER_DIR:-<unset>}'; expected '$EXPECTED_DEVELOPER_DIR'"
        [[ -d "$EXPECTED_DEVELOPER_DIR" ]] ||
            fail "expected Xcode developer directory does not exist: $EXPECTED_DEVELOPER_DIR"
        if [[ "$expected_swift_command_mode" == "xcrun" ]]; then
            [[ "$swift_executable" == "$EXPECTED_DEVELOPER_DIR"/Toolchains/*/usr/bin/swift ]] ||
                fail "xcrun selected Swift outside the expected Xcode: $swift_executable"
        fi
        [[ "$xcode_version" == "$EXPECTED_XCODE_VERSION" ]] ||
            fail "Xcode version is '$xcode_version'; expected '$EXPECTED_XCODE_VERSION'"
        [[ "$xcode_build" == "$EXPECTED_XCODE_BUILD" ]] ||
            fail "Xcode build is '$xcode_build'; expected '$EXPECTED_XCODE_BUILD'"
        [[ "$sdk_version" == "$EXPECTED_SDK_VERSION" ]] ||
            fail "macOS SDK is '$sdk_version'; expected '$EXPECTED_SDK_VERSION'"
        ;;
    linux)
        : "${EXPECTED_OS_ID:?Set EXPECTED_OS_ID}"
        : "${EXPECTED_OS_VERSION_ID:?Set EXPECTED_OS_VERSION_ID}"
        os_release_file="${EXPECTED_OS_RELEASE_FILE:-/etc/os-release}"
        [[ -r "$os_release_file" ]] || fail "$os_release_file is not readable"
        # shellcheck source=/dev/null
        source "$os_release_file"
        printf 'Linux distribution: %s %s\n' "${ID:-<unset>}" "${VERSION_ID:-<unset>}"
        [[ "${ID:-}" == "$EXPECTED_OS_ID" ]] ||
            fail "Linux ID is '${ID:-<unset>}'; expected '$EXPECTED_OS_ID'"
        [[ "${VERSION_ID:-}" == "$EXPECTED_OS_VERSION_ID" ]] ||
            fail "Linux VERSION_ID is '${VERSION_ID:-<unset>}'; expected '$EXPECTED_OS_VERSION_ID'"
        ;;
    *)
        fail "unsupported EXPECTED_PLATFORM: $expected_platform"
        ;;
esac

[[ "$swift_output" == *"Apple Swift version $EXPECTED_SWIFT_SERIES"* ]] ||
    [[ "$swift_output" == *"Swift version $EXPECTED_SWIFT_SERIES"* ]] ||
    fail "Swift compiler is not in the expected $EXPECTED_SWIFT_SERIES series"
if [[ -n "${EXPECTED_SWIFT_VERSION:-}" ]]; then
    [[ "$swift_output" == *"Swift version $EXPECTED_SWIFT_VERSION"* ]] ||
        fail "Swift compiler is not exactly version $EXPECTED_SWIFT_VERSION"
fi
[[ "$tools_version" == "5.9.0" ]] ||
    fail "package tools version is '$tools_version'; expected '5.9.0'"
if [[ -n "${EXPECTED_TARGET_TRIPLE:-}" ]]; then
    [[ "$target_info" == *"\"triple\" : \"$EXPECTED_TARGET_TRIPLE\""* ]] ||
        [[ "$target_info" == *"\"triple\": \"$EXPECTED_TARGET_TRIPLE\""* ]] ||
        [[ "$target_info" == *"\"triple\":\"$EXPECTED_TARGET_TRIPLE\""* ]] ||
        fail "Swift target triple is not '$EXPECTED_TARGET_TRIPLE'"
fi
if [[ -n "${EXPECTED_IMAGE_OS:-}" ]]; then
    [[ "${ImageOS:-}" == "$EXPECTED_IMAGE_OS" ]] ||
        fail "ImageOS is '${ImageOS:-<unset>}'; expected '$EXPECTED_IMAGE_OS'"
fi
if [[ -n "${EXPECTED_ARCHITECTURE:-}" ]]; then
    [[ "$(uname -m)" == "$EXPECTED_ARCHITECTURE" ]] ||
        fail "architecture is '$(uname -m)'; expected '$EXPECTED_ARCHITECTURE'"
fi
