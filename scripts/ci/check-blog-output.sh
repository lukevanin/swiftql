#!/bin/sh

set -eu

# Verifies the Hugo blog that make-docs.sh builds from Website/blog into
# $output/blog. Gated the same way the landing page is: present, fully
# templated, and free of external subresources.

main() {
    if [ "$#" -ne 2 ]; then
        printf 'usage: %s OUTPUT_DIRECTORY HOSTING_BASE_PATH\n' "$0" >&2
        return 64
    fi

    output="$1"
    hosting_base_path="$2"
    blog="$output/blog"

    if [ ! -d "$blog" ]; then
        printf 'error: blog output directory does not exist: %s\n' "$blog" >&2
        return 1
    fi

    require_file "$blog/index.html"
    require_file "$blog/style.css"
    require_file "$blog/swiftql-logo.png"
    require_content "$blog/index.html" '<title>SwiftQL Blog</title>'

    for post in \
        posts/why-i-taught-the-swift-compiler-to-read-sql/index.html \
        posts/porting-sql-to-swiftql/index.html \
        posts/whats-new-in-1-0-0/index.html \
        posts/whats-new-in-1-1-0/index.html \
        posts/whats-new-in-1-2-0/index.html \
        posts/whats-new-in-1-3-0/index.html \
        posts/whats-new-in-1-4-1/index.html \
        posts/whats-new-in-1-4-2/index.html \
        posts/whats-new-in-1-4-3/index.html \
        posts/whats-new-in-1-4-4/index.html \
        posts/whats-new-in-1-4-5/index.html \
        posts/whats-new-in-1-4-6/index.html \
        posts/whats-new-in-1-5-1/index.html \
        posts/whats-new-in-1-5-2/index.html \
        posts/whats-new-in-1-5-3/index.html \
        posts/whats-new-in-1-5-4/index.html \
        posts/whats-new-in-1-5-5/index.html \
        posts/whats-new-in-1-6-0/index.html \
        posts/whats-new-in-1-7-0/index.html
    do
        require_file "$blog/$post"
        # Every template token was substituted, in every page Hugo generated.
        if grep -q '__BASE_PATH__' "$blog/$post"; then
            printf 'error: blog post still contains __BASE_PATH__: %s\n' \
                "$blog/$post" >&2
            return 1
        fi
        require_content "$blog/$post" \
            "href=\"/$hosting_base_path/documentation/swiftql/\""
    done

    if grep -q '__BASE_PATH__' "$blog/index.html"; then
        printf 'error: blog index still contains __BASE_PATH__: %s\n' \
            "$blog/index.html" >&2
        return 1
    fi
    require_content "$blog/index.html" \
        "href=\"/$hosting_base_path/documentation/swiftql/\""

    # No external scripts, stylesheets, fonts, or images: the blog must
    # render with the site alone, matching the landing page's own rule.
    if grep -rEq '(src|href)="https?://[^"]*\.(js|css|png|jpg|jpeg|svg|woff2?)"' \
        "$blog"/index.html "$blog"/posts/*/index.html; then
        printf 'error: blog references an external subresource under: %s\n' \
            "$blog" >&2
        return 1
    fi
    if grep -rq '<script' "$blog"/index.html "$blog"/posts/*/index.html; then
        printf 'error: blog pages must not contain scripts: %s\n' "$blog" >&2
        return 1
    fi

    # The landing page links back to the blog, and the blog links back out.
    require_content "$output/index.html" "\"/$hosting_base_path/blog/\""

    printf 'SWIFTQL_BLOG ok %s\n' "$blog"
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
