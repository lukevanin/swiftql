#!/bin/sh

set -eu

main() {
    if [ "$#" -ne 1 ]; then
        printf 'usage: %s OUTPUT_DIRECTORY\n' "$0" >&2
        return 64
    fi

    output="$1"
    if [ ! -d "$output" ]; then
        printf 'error: DocC output directory does not exist: %s\n' "$output" >&2
        return 1
    fi
    if [ ! -f "$output/.nojekyll" ]; then
        printf 'error: DocC output is missing .nojekyll: %s\n' "$output" >&2
        return 1
    fi
    require_file "$output/index.html"
    require_file "$output/documentation/swiftql/index.html"
    require_page "$output/data/documentation/swiftql.json" "SwiftQL"

    while IFS='|' read -r slug title; do
        require_page "$output/data/documentation/swiftql/$slug.json" "$title"
        require_file "$output/documentation/swiftql/$slug/index.html"
    done <<'ARTICLES'
advancedusage|Advanced usage
builtinfunctions|Built-in Functions
customfunctions|Custom Functions
customtypes|Custom Types
declaredqueries|Declared queries
enums|Enum Values
expressions|Expressions
functionalsyntax|Functional Syntax
generictableparameters|Generic Table Parameters
gettingstarted|Getting started
livequeries|Live Queries
numericdatecodecs|Numeric Date Codecs
queries|Select Queries
realvalues|Real Values
staticqueries|Static queries
ARTICLES

    check_tutorials "$output"

    printf 'SWIFTQL_DOCC_OUTPUT ok %s\n' "$output"
}

# Tutorials live on their own /tutorials route and pull their code from
# `@Code(file:)` resources rather than from the page itself, so neither the
# route nor the resources are covered by the article checks above. Both the
# routes and every resource named by the catalog source are checked here, with
# exact case, because a case-only rename survives a macOS build and 404s once
# the site is served from GitHub Pages.
check_tutorials() {
    tutorial_output="$1"
    tutorial_catalog="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)"
    tutorial_catalog="$tutorial_catalog/Sources/SwiftQL/SwiftQL.docc"
    tutorial_overview_page="$tutorial_output/data/tutorials/swiftql.json"
    tutorial_page="$tutorial_output/data/tutorials/swiftql/endtoendquery.json"

    require_exact_file "$tutorial_output" "tutorials/swiftql/index.html"
    require_exact_file "$tutorial_output" "data/tutorials/swiftql.json"
    require_page "$tutorial_overview_page" "Build a query with SwiftQL"
    require_exact_file "$tutorial_output" "tutorials/swiftql/endtoendquery/index.html"
    require_exact_file "$tutorial_output" "data/tutorials/swiftql/endtoendquery.json"
    require_page "$tutorial_page" "Query a SQLite database end to end"

    if ! grep -Fq '"doc://SwiftQL/tutorials/SwiftQL"' \
        "$tutorial_output/data/documentation/swiftql.json"; then
        printf 'error: the SwiftQL landing page no longer links the tutorial\n' >&2
        return 1
    fi

    tutorial_code_resources=0
    while IFS= read -r tutorial_resource; do
        [ -n "$tutorial_resource" ] || continue
        tutorial_code_resources=$((tutorial_code_resources + 1))
        if ! grep -Fq "\"$tutorial_resource\"" "$tutorial_page"; then
            printf 'error: built tutorial does not reference code snapshot: %s\n' \
                "$tutorial_resource" >&2
            return 1
        fi
    done <<EOF
$(list_directive_values '@Code' "$tutorial_catalog")
EOF
    if [ "$tutorial_code_resources" -eq 0 ]; then
        printf 'error: no @Code resources found in %s\n' "$tutorial_catalog" >&2
        return 1
    fi

    while IFS= read -r tutorial_resource; do
        [ -n "$tutorial_resource" ] || continue
        require_exact_file "$tutorial_output" "images/SwiftQL/$tutorial_resource"
    done <<EOF
$(list_directive_values '@Image' "$tutorial_catalog")
EOF
}

# Prints the resource file name from every `@Code(name:file:)` or
# `@Image(source:alt:)` directive in the catalog's tutorial sources. `find
# -exec ... +` rather than `xargs`, because GNU xargs runs its command once
# with no arguments when the input is empty, and `cat` with no arguments would
# then block on this script's stdin instead of reporting no tutorials.
list_directive_values() {
    directive_name="$1"
    directive_catalog="$2"
    case "$directive_name" in
        '@Code')
            find "$directive_catalog" -name '*.tutorial' -exec cat {} + | sed -n \
                's/.*@Code(name: "[^"]*", file: \([^)]*\)).*/\1/p'
            ;;
        '@Image')
            find "$directive_catalog" -name '*.tutorial' -exec cat {} + | sed -n \
                's/.*@Image(source: \([^,]*\),.*/\1/p'
            ;;
    esac
}

require_file() {
    if [ ! -s "$1" ]; then
        printf 'error: missing or empty DocC output: %s\n' "$1" >&2
        return 1
    fi
}

# `[ -f ... ]` matches case-insensitively on the macOS runners that build the
# site, so each path component is matched against the real directory listing.
require_exact_file() {
    exact_root="$1"
    exact_remaining="$2"
    exact_current="$exact_root"
    while [ -n "$exact_remaining" ]; do
        exact_component="${exact_remaining%%/*}"
        case "$exact_remaining" in
            */*) exact_remaining="${exact_remaining#*/}" ;;
            *) exact_remaining="" ;;
        esac
        if ! ls -1 -- "$exact_current" 2>/dev/null \
            | grep -Fxq -- "$exact_component"; then
            printf 'error: DocC output is missing %s (exact case) in %s\n' \
                "$exact_component" "$exact_current" >&2
            return 1
        fi
        exact_current="$exact_current/$exact_component"
    done
    require_file "$exact_current"
}

require_page() {
    file="$1"
    title="$2"
    require_file "$file"
    actual_title="$(/usr/bin/plutil -extract metadata.title raw -o - "$file")"
    normalized_actual_title="$(printf '%s' "$actual_title" | tr '[:upper:]' '[:lower:]')"
    normalized_title="$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]')"
    if [ "$normalized_actual_title" != "$normalized_title" ]; then
        printf 'error: expected DocC page title %s but found %s: %s\n' \
            "$title" "$actual_title" "$file" >&2
        return 1
    fi
}

main "$@"
