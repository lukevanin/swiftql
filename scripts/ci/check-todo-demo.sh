#!/bin/bash
#
# Builds and tests the to-do demo (Examples/TodoApp) against the working tree
# of SwiftQL, so a library change that breaks the demo fails loudly here
# rather than being discovered by someone cloning it later.
#
# Checks, in the order the script prints them:
#   1. The demo package builds from clean. This is also what runs SwiftQL's
#      build-time query validator over every query the demo declares.
#   2. Its tests pass.
#   3. The demo package built without warnings.
#   4. Regenerating the validation manifest and schema snapshot produces no
#      diff, so a query edited without regenerating fails rather than
#      validating the old shape.
#   5. The Xcode project's warnings-as-errors settings are still in force.
#   6. The app builds for macOS.
#   7. The app builds for an iOS simulator destination.
#
# Warnings are errors on both sides of the demo, by two different mechanisms.
# The Xcode project sets SWIFT_TREAT_WARNINGS_AS_ERRORS and
# GCC_TREAT_WARNINGS_AS_ERRORS, and step 5 verifies those are still YES rather
# than trusting them. The SwiftPM build does not inherit those settings, and
# passing -warnings-as-errors there would fail on the dependencies' warnings
# rather than the demo's, so step 3 instead rejects any warning whose source
# path is inside the demo.

set -euo pipefail

main() {
    local source_root
    local demo_root
    local package_root
    local derived_data
    local log_directory
    local ios_destination

    source_root="$(cd "$(dirname "$0")/../.." && pwd -P)"
    demo_root="$source_root/Examples/TodoApp"
    package_root="$demo_root/TodoKit"
    derived_data="${SWIFTQL_DEMO_DERIVED_DATA:-${TMPDIR:-/tmp}/swiftql-todo-demo-dd}"
    log_directory="${1:-${TMPDIR:-/tmp}}"
    ios_destination="${SWIFTQL_DEMO_IOS_DESTINATION:-generic/platform=iOS Simulator}"

    mkdir -p "$log_directory"
    test -d "$demo_root"
    test -f "$demo_root/TodoApp.xcodeproj/project.pbxproj"
    test -f "$package_root/Package.swift"

    echo "== 1. Demo package builds, and the query validator runs =="
    # Clean first: SwiftPM skips the validation command on an incremental
    # build whose inputs have not changed, and "the validator ran" is only
    # evidence if it had to.
    xcrun swift package --package-path "$package_root" clean
    xcrun swift build --package-path "$package_root" 2>&1 \
        | tee "$log_directory/swiftql-todo-demo-build.log"
    if ! grep -q "SwiftQL SQLite build validation" \
        "$log_directory/swiftql-todo-demo-build.log"; then
        echo "error: the build-time query validator did not run" >&2
        return 1
    fi

    echo "== 2. Demo tests pass =="
    xcrun swift test --package-path "$package_root" 2>&1 \
        | tee "$log_directory/swiftql-todo-demo-test.log"

    echo "== 3. The demo package built without warnings =="
    require_no_demo_warnings \
        "$log_directory/swiftql-todo-demo-build.log" \
        "$log_directory/swiftql-todo-demo-test.log"

    echo "== 4. The checked-in validation manifest is current =="
    "$demo_root/Tools/regenerate-validation-manifest.sh" \
        > "$log_directory/swiftql-todo-demo-manifest.log" 2>&1
    if ! git -C "$source_root" diff --exit-code -- \
        "Examples/TodoApp/TodoKit/Sources/TodoKitBuildValidation"; then
        echo "error: the validation manifest or snapshot is stale." >&2
        echo "Run Examples/TodoApp/Tools/regenerate-validation-manifest.sh and commit the result." >&2
        return 1
    fi

    echo "== 5. Warnings are still errors =="
    require_warning_setting "$demo_root" SWIFT_TREAT_WARNINGS_AS_ERRORS
    require_warning_setting "$demo_root" GCC_TREAT_WARNINGS_AS_ERRORS

    echo "== 6. The app builds for macOS =="
    build_app "$demo_root" "$derived_data-macos" "platform=macOS" \
        "$log_directory/swiftql-todo-demo-macos.log"

    echo "== 7. The app builds for an iOS simulator =="
    build_app "$demo_root" "$derived_data-ios" "$ios_destination" \
        "$log_directory/swiftql-todo-demo-ios.log"

    echo "OK: the to-do demo builds and tests cleanly on both platforms"
}

# Rejects any compiler warning originating in the demo's own sources.
#
# SwiftPM compiles the dependencies too, and their warnings are not this
# gate's business -- matching on the demo's path is what keeps the gate about
# the demo without silencing it.
require_no_demo_warnings() {
    local warnings

    warnings="$(
        grep -hE '^/.*Examples/TodoApp/.*: warning: ' "$@" | sort -u || true
    )"
    if [[ -n "$warnings" ]]; then
        echo "error: the demo package emitted warnings:" >&2
        printf '%s\n' "$warnings" >&2
        return 1
    fi
}

require_warning_setting() {
    local demo_root="$1"
    local setting="$2"
    local value

    value="$(
        xcodebuild -project "$demo_root/TodoApp.xcodeproj" \
            -scheme TodoApp \
            -destination 'platform=macOS' \
            -showBuildSettings 2>/dev/null \
            | awk -v key="$setting" '$1 == key { print $3; exit }'
    )"
    if [[ "$value" != "YES" ]]; then
        printf 'error: %s is %s, expected YES\n' "$setting" "${value:-unset}" >&2
        return 1
    fi
}

build_app() {
    local demo_root="$1"
    local derived_data="$2"
    local destination="$3"
    local log="$4"

    rm -rf "$derived_data"
    xcodebuild build \
        -project "$demo_root/TodoApp.xcodeproj" \
        -scheme TodoApp \
        -destination "$destination" \
        -derivedDataPath "$derived_data" \
        CODE_SIGNING_ALLOWED=NO \
        2>&1 | tee "$log" | grep -E '^(\*\*|.*(error|warning):)' || true

    if ! grep -q "BUILD SUCCEEDED" "$log"; then
        echo "error: the demo failed to build for $destination" >&2
        tail -50 "$log" >&2
        return 1
    fi
}

main "$@"
