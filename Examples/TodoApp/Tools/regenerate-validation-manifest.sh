#!/bin/bash
#
# Regenerates the demo's build-validation artifacts:
#
#   TodoKit/Sources/TodoKitBuildValidation/swiftql-build-validation-snapshot.sqlite
#   TodoKit/Sources/TodoKitBuildValidation/swiftql-build-validation-manifest.json
#
# Run this after changing the demo's schema or any declared query. The
# generator refuses to write artifacts the validator would reject, so a
# successful run means the plugin will pass.
#
# Pass a directory to write somewhere else than the checked-in target.
# scripts/ci/check-todo-demo.sh does that so it can compare a fresh
# regeneration against the checked-in one without touching the working tree.
#
# usage: regenerate-validation-manifest.sh [OUTPUT_DIRECTORY]

set -euo pipefail

example_root="$(cd "$(dirname "$0")/.." && pwd -P)"
package_root="$example_root/TodoKit"
output_directory="${1:-$package_root/Sources/TodoKitBuildValidation}"

mkdir -p "$output_directory"

swift run \
    --package-path "$package_root" \
    todo-validation-manifest \
    "$output_directory"
