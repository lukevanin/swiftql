#!/bin/bash

set -euo pipefail

fail() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repository_root"

[[ -f Package.resolved ]] || fail "Package.resolved was not produced"

swift_package=(xcrun swift package)
if [[ -n "${SWIFTQL_SCRATCH_PATH:-}" ]]; then
    swift_package+=(--scratch-path "$SWIFTQL_SCRATCH_PATH")
fi

dependencies="$("${swift_package[@]}" show-dependencies --format text)"
grdb="$(printf '%s\n' "$dependencies" | grep -i 'grdb\.swift.*@' | head -n 1 || true)"
swift_syntax="$(printf '%s\n' "$dependencies" | grep -i 'swift-syntax.*@' | head -n 1 || true)"

[[ -n "$grdb" ]] || fail "resolved GRDB version was not reported"
[[ -n "$swift_syntax" ]] || fail "resolved SwiftSyntax version was not reported"

printf '%s\n' "Resolved dependency graph:"
printf '%s\n' "$dependencies"
printf 'Resolved GRDB: %s\n' "$grdb"
printf 'Resolved SwiftSyntax: %s\n' "$swift_syntax"
