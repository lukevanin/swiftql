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
builtinfunctions|Built-in Functions
customfunctions|Custom Functions
customtypes|Custom Types
enums|Enum Values
expressions|Expressions
functionalsyntax|Functional Syntax
generictableparameters|Generic Table Parameters
gettingstarted|Getting started
livequeries|Live Queries
queries|Select Queries
realvalues|Real Values
staticqueries|Static queries
ARTICLES

    printf 'SWIFTQL_DOCC_OUTPUT ok %s\n' "$output"
}

require_file() {
    if [ ! -s "$1" ]; then
        printf 'error: missing or empty DocC output: %s\n' "$1" >&2
        return 1
    fi
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
