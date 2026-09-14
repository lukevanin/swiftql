#!/bin/sh

# Installs the exact Hugo release pinned in scripts/ci/hugo-version.sh into
# INSTALL_DIRECTORY (#611).
#
# `brew install hugo` installs whatever version Homebrew currently ships. Twice
# that drifted away from make-docs.sh's exact-version gate, and every
# documentation build failed until the pin was bumped by hand, including the
# build the verified release workflow depends on. This script downloads the
# pinned release asset instead, refuses it unless its SHA-256 matches the pin,
# and checks that the binary reports the pinned version before installing it.
#
# On GitHub Actions it also prepends INSTALL_DIRECTORY to GITHUB_PATH, so every
# later step resolves this hugo ahead of any copy on the runner image.

set -eu

main() {
    if [ "$#" -ne 1 ] || [ -z "$1" ]; then
        printf 'usage: %s INSTALL_DIRECTORY\n' "$0" >&2
        return 64
    fi
    install_directory="$1"

    script_directory="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
    . "$script_directory/hugo-version.sh"

    platform="$(uname -s)"
    case "$platform" in
        Darwin)
            asset="hugo_extended_withdeploy_${SWIFTQL_HUGO_VERSION}_darwin-universal.pkg"
            expected_sha256="$SWIFTQL_HUGO_DARWIN_UNIVERSAL_SHA256"
            ;;
        *)
            printf 'error: no pinned Hugo release for %s; the documentation build runs on macOS\n' \
                "$platform" >&2
            return 69
            ;;
    esac

    work_directory="$(mktemp -d)"
    trap 'rm -rf "$work_directory"' EXIT
    package="$work_directory/$asset"

    curl --fail --silent --show-error --location --retry 3 \
        --output "$package" \
        "https://github.com/gohugoio/hugo/releases/download/v$SWIFTQL_HUGO_VERSION/$asset"

    actual_sha256="$(shasum -a 256 "$package" | cut -d ' ' -f 1)"
    if [ "$actual_sha256" != "$expected_sha256" ]; then
        printf 'error: %s has SHA-256 %s, expected %s\n' \
            "$asset" "$actual_sha256" "$expected_sha256" >&2
        return 1
    fi

    # Hugo publishes its macOS builds only as installer packages. Expanding the
    # package reads its payload without running installer scripts or needing
    # administrator rights.
    pkgutil --expand-full "$package" "$work_directory/expanded"
    find "$work_directory/expanded" -type f -name hugo > "$work_directory/binaries"
    if [ "$(wc -l < "$work_directory/binaries" | tr -d ' ')" != 1 ]; then
        printf 'error: expected one hugo binary in %s, found:\n' "$asset" >&2
        cat "$work_directory/binaries" >&2
        return 1
    fi

    # Check the extracted binary before it reaches INSTALL_DIRECTORY, so a
    # failed check never leaves a wrong hugo where PATH can find it.
    binary="$(cat "$work_directory/binaries")"
    chmod 755 "$binary"
    binary_version="$("$binary" version)"
    case "$binary_version" in
        "hugo v$SWIFTQL_HUGO_VERSION"[!0-9.]*) ;;
        *)
            printf 'error: expected hugo v%s from %s, found: %s\n' \
                "$SWIFTQL_HUGO_VERSION" "$asset" "$binary_version" >&2
            return 1
            ;;
    esac

    mkdir -p "$install_directory"
    install_directory="$(CDPATH= cd -- "$install_directory" && pwd -P)"
    cp "$binary" "$install_directory/hugo"
    chmod 755 "$install_directory/hugo"
    printf '%s\n' "$binary_version"

    if [ -n "${GITHUB_PATH:-}" ]; then
        printf '%s\n' "$install_directory" >> "$GITHUB_PATH"
    fi
}

main "$@"
