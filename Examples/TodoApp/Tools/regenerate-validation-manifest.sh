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
# Nothing runs this automatically yet. #475 adds the CI job for the demo, and
# the intent there is to run this and then check the working tree is clean, so
# a stale manifest fails the build rather than drifting quietly.

set -euo pipefail

example_root="$(cd "$(dirname "$0")/.." && pwd -P)"
package_root="$example_root/TodoKit"

swift run \
    --package-path "$package_root" \
    todo-validation-manifest \
    "$package_root/Sources/TodoKitBuildValidation"
