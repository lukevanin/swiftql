#!/bin/bash

set -euo pipefail

: "${EXPECTED_SWIFT_VERSION:?Set EXPECTED_SWIFT_VERSION}"
: "${EXPECTED_SWIFT_TARGET:?Set EXPECTED_SWIFT_TARGET}"

fail() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repository_root"

swift_output="$(swift --version 2>&1)"
swift_target="$(printf '%s\n' "$swift_output" | sed -n 's/^Target: //p')"
tools_version="$(swift package tools-version)"

printf '%s\n' "$swift_output"
printf 'Swift executable: %s\n' "$(command -v swift)"
printf 'Swift package tools version: %s\n' "$tools_version"
printf 'Operating system: %s\n' "$(uname -a)"
printf 'Architecture: %s\n' "$(uname -m)"
if [[ -r /etc/os-release ]]; then
    cat /etc/os-release
fi

[[ "$swift_output" == *"Swift version $EXPECTED_SWIFT_VERSION "* ]] ||
    fail "Swift compiler is not exactly version $EXPECTED_SWIFT_VERSION"
[[ "$swift_target" == "$EXPECTED_SWIFT_TARGET" ]] ||
    fail "Swift target is '$swift_target'; expected '$EXPECTED_SWIFT_TARGET'"
[[ "$tools_version" == "5.9.0" ]] ||
    fail "package tools version is '$tools_version'; expected '5.9.0'"
