#!/bin/sh

set -eu

main() {
    if [ "$#" -gt 1 ]; then
        printf 'usage: %s [OUTPUT_DIRECTORY]\n' "$0" >&2
        return 64
    fi

    source_root="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
    output_argument="${1-docs}"
    hosting_base_path="${SWIFTQL_DOCC_HOSTING_BASE_PATH:-swiftql}"

    while [ "${output_argument%/}" != "$output_argument" ]; do
        output_argument="${output_argument%/}"
    done
    if [ -z "$output_argument" ]; then
        printf 'error: unsafe documentation output: %s\n' "${1:-}" >&2
        return 64
    fi

    # Restricted to the characters GitHub allows in a repository name, so the
    # value can be substituted into the landing page without quoting concerns.
    case "$hosting_base_path" in
        ""|.|..|*[!A-Za-z0-9._-]*)
            printf 'error: invalid DocC hosting base path: %s\n' \
                "$hosting_base_path" >&2
            return 64
            ;;
    esac

    cd "$source_root"
    output_parent="$(dirname -- "$output_argument")"
    output_name="$(basename -- "$output_argument")"
    case "$output_name" in
        ""|/|.|..)
            printf 'error: unsafe documentation output: %s\n' \
                "$output_argument" >&2
            return 64
            ;;
    esac
    if [ ! -d "$output_parent" ]; then
        printf 'error: documentation output parent does not exist: %s\n' \
            "$output_parent" >&2
        return 64
    fi
    output_parent="$(CDPATH= cd -- "$output_parent" && pwd -P)"
    output="$output_parent/$output_name"

    if [ -L "$output" ]; then
        printf 'error: documentation output must not be a symbolic link: %s\n' \
            "$output" >&2
        return 64
    fi
    if [ -e "$output" ] && [ ! -d "$output" ]; then
        printf 'error: documentation output is not a directory: %s\n' \
            "$output" >&2
        return 64
    fi
    if [ -d "$output" ]; then
        output="$(CDPATH= cd -- "$output" && pwd -P)"
    fi
    case "$output" in
        /|"$source_root")
            printf 'error: unsafe documentation output: %s\n' "$output" >&2
            return 64
            ;;
        "$source_root"/*)
            if [ "$output" != "$source_root/docs" ]; then
                printf 'error: in-repository documentation output must be docs/: %s\n' \
                    "$output" >&2
                return 64
            fi
            ;;
    esac
    case "$source_root/" in
        "$output/"*)
            printf 'error: documentation output must not contain the repository: %s\n' \
                "$output" >&2
            return 64
            ;;
    esac

    # See https://swiftlang.github.io/swift-docc-plugin/documentation/swiftdoccplugin/publishing-to-github-pages
    swift package --allow-writing-to-directory "$output" \
        generate-documentation --target SwiftQL \
        --warnings-as-errors \
        --disable-indexing \
        --transform-for-static-hosting \
        --hosting-base-path "$hosting_base_path" \
        --output-path "$output"

    touch "$output/.nojekyll"
    "$source_root/scripts/ci/check-docc-output.sh" "$output"

    install_landing_page "$source_root" "$output" "$hosting_base_path"
    "$source_root/scripts/ci/check-landing-page.sh" "$output" "$hosting_base_path"
}

# Replaces DocC's generated root shell with the hand-written landing page from
# Website/. DocC's own pages live under documentation/ and keep their own
# index.html files, so only the site root changes.
install_landing_page() {
    landing_source_root="$1"
    landing_output="$2"
    landing_base_path="$3"
    landing_website="$landing_source_root/Website"

    for landing_asset in index.html swiftql-logo.png; do
        if [ ! -s "$landing_website/$landing_asset" ]; then
            printf 'error: missing landing page source: %s\n' \
                "$landing_website/$landing_asset" >&2
            return 1
        fi
    done

    cp "$landing_website/swiftql-logo.png" "$landing_output/swiftql-logo.png"
    sed -e "s|__BASE_PATH__|$landing_base_path|g" \
        "$landing_website/index.html" > "$landing_output/index.html"
}

main "$@"
