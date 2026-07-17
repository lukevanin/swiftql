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

    case "$hosting_base_path" in
        ""|.|..|*/*)
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
}

main "$@"
