#!/bin/sh

set -eu

# Verifies the landing page that make-docs.sh installs over DocC's generated
# root index.html. The landing page is the first thing a visitor sees, so it is
# gated the same way the DocC output is: present, fully templated, and free of
# external subresources.

main() {
    if [ "$#" -ne 2 ]; then
        printf 'usage: %s OUTPUT_DIRECTORY HOSTING_BASE_PATH\n' "$0" >&2
        return 64
    fi

    output="$1"
    hosting_base_path="$2"

    if [ ! -d "$output" ]; then
        printf 'error: site output directory does not exist: %s\n' "$output" >&2
        return 1
    fi

    landing="$output/index.html"
    require_file "$landing"
    require_file "$output/swiftql-logo.png"

    # The landing page replaced DocC's root shell rather than sitting beside it.
    require_content "$landing" '<title>SwiftQL - SQL, as a first-class language in Swift</title>'

    # Every template token was substituted.
    if grep -q '__BASE_PATH__' "$landing"; then
        printf 'error: landing page still contains __BASE_PATH__: %s\n' \
            "$landing" >&2
        return 1
    fi

    # Substitution produced the real hosting paths.
    require_content "$landing" \
        "\"/$hosting_base_path/documentation/swiftql/\""
    require_content "$landing" "\"/$hosting_base_path/swiftql-logo.png\""
    require_content "$landing" "\"/$hosting_base_path/blog/\""

    # No external scripts, stylesheets, fonts, or images: the page must render
    # with the site alone.
    if grep -Eq '(src|href)="https?://[^"]*\.(js|css|png|jpg|jpeg|svg|woff2?)"' \
        "$landing"; then
        printf 'error: landing page references an external subresource: %s\n' \
            "$landing" >&2
        return 1
    fi
    if grep -q '<script' "$landing"; then
        printf 'error: landing page must not contain scripts: %s\n' \
            "$landing" >&2
        return 1
    fi

    # DocC still owns everything below the root.
    require_file "$output/documentation/swiftql/index.html"

    printf 'SWIFTQL_LANDING_PAGE ok %s\n' "$landing"
}

require_file() {
    if [ ! -s "$1" ]; then
        printf 'error: missing or empty site output: %s\n' "$1" >&2
        return 1
    fi
}

require_content() {
    if ! grep -qF "$2" "$1"; then
        printf 'error: expected %s to contain: %s\n' "$1" "$2" >&2
        return 1
    fi
}

main "$@"
