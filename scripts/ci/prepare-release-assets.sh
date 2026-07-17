#!/bin/bash

set -euo pipefail

fail() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

sha256_file() {
    local file="$1"

    if command -v sha256sum > /dev/null 2>&1; then
        sha256sum "$file" | awk '{ print $1 }'
    else
        shasum -a 256 "$file" | awk '{ print $1 }'
    fi
}

require_nonempty_file() {
    if [[ ! -f "$1" || -L "$1" || ! -s "$1" ]]; then
        fail "missing or empty documentation output: $1"
    fi
}

if [[ "$#" -ne 8 ]]; then
    printf 'usage: %s PAGES_TAR OUTPUT_DIRECTORY RELEASE_TAG COMMIT_SHA RUN_ID RUN_ATTEMPT REPOSITORY SOURCE_TAG\n' \
        "$0" >&2
    exit 64
fi

pages_tar="$1"
output_directory="$2"
release_tag="$3"
commit_sha="$4"
run_id="$5"
run_attempt="$6"
repository="$7"
source_tag="$8"

if [[ ! "$release_tag" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    fail "invalid release tag: $release_tag"
fi
if [[ ! "$commit_sha" =~ ^[0-9a-f]{40}$ ]]; then
    fail "commit SHA is not a lowercase full object ID: $commit_sha"
fi
if [[ ! "$run_id" =~ ^[0-9]+$ || ! "$run_attempt" =~ ^[0-9]+$ ]]; then
    fail 'run ID and attempt must be decimal integers'
fi
if [[ ! "$repository" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
    fail "invalid repository name: $repository"
fi
if [[ "$source_tag" != "$release_tag" &&
      "$source_tag" != "release-test/$release_tag" ]]; then
    fail "source tag does not normalize to release tag: $source_tag"
fi
if [[ ! -f "$pages_tar" || -L "$pages_tar" ]]; then
    fail "Pages artifact tar is missing or unsafe: $pages_tar"
fi
if [[ -L "$output_directory" ]]; then
    fail "release output directory must not be a symbolic link: $output_directory"
fi
mkdir -p "$output_directory"
if [[ ! -d "$output_directory" ]]; then
    fail "release output is not a directory: $output_directory"
fi

while IFS= read -r archive_path; do
    case "$archive_path" in
        /*|..|../*|*/..|*/../*)
            fail "Pages artifact contains an unsafe path: $archive_path"
            ;;
    esac
done < <(tar -tf "$pages_tar")

temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/swiftql-release-pages.XXXXXX")"
trap 'rm -rf "$temporary_directory"' EXIT
tar -xf "$pages_tar" -C "$temporary_directory"

unsafe_entries="$(find "$temporary_directory" ! -type d ! -type f -print)"
if [[ -n "$unsafe_entries" ]]; then
    fail "Pages artifact contains non-regular entries: $unsafe_entries"
fi
if [[ ! -f "$temporary_directory/.nojekyll" ||
      -L "$temporary_directory/.nojekyll" ]]; then
    fail 'Pages artifact is missing .nojekyll'
fi
require_nonempty_file "$temporary_directory/index.html"
require_nonempty_file "$temporary_directory/documentation/swiftql/index.html"
require_nonempty_file "$temporary_directory/documentation/swiftql/gettingstarted/index.html"
require_nonempty_file "$temporary_directory/data/documentation/swiftql.json"
require_nonempty_file \
    "$temporary_directory/data/documentation/swiftql/gettingstarted.json"

pages_provenance="$temporary_directory/swiftql-pages-provenance.json"
require_nonempty_file "$pages_provenance"
if ! jq -e \
    --arg commit_sha "$commit_sha" \
    --arg run_id "$run_id" \
    --arg repository "$repository" \
    --arg source_ref "refs/tags/$source_tag" \
    --arg source_tag "$source_tag" \
    '.commit_sha == $commit_sha and
     .source_ref == $source_ref and
     .source_ref_name == $source_tag and
     .run_id == $run_id and
     (.run_attempt | type == "string" and test("^[0-9]+$")) and
     .repository == $repository' \
    "$pages_provenance" > /dev/null; then
    fail 'Pages provenance does not match the release run'
fi
documentation_run_attempt="$(jq -r '.run_attempt' "$pages_provenance")"

docs_name="swiftql-docc-$release_tag.tar.gz"
manifest_name="swiftql-release-$release_tag.json"
checksums_name='SHA256SUMS'
docs_path="$output_directory/$docs_name"
manifest_path="$output_directory/$manifest_name"
checksums_path="$output_directory/$checksums_name"

for output_path in "$docs_path" "$manifest_path" "$checksums_path"; do
    if [[ -L "$output_path" ]]; then
        fail "release output must not be a symbolic link: $output_path"
    fi
done

gzip -n -c "$pages_tar" > "$docs_path"
docs_sha256="$(sha256_file "$docs_path")"
workflow_url="${GITHUB_SERVER_URL:-https://github.com}/$repository/actions/runs/$run_id"

jq -n \
    --arg repository "$repository" \
    --arg tag "$release_tag" \
    --arg source_tag "$source_tag" \
    --arg commit_sha "$commit_sha" \
    --arg run_id "$run_id" \
    --arg documentation_run_attempt "$documentation_run_attempt" \
    --arg publication_run_attempt "$run_attempt" \
    --arg workflow_url "$workflow_url" \
    --arg documentation_asset "$docs_name" \
    --arg documentation_sha256 "$docs_sha256" \
    '{
        schema_version: 1,
        repository: $repository,
        tag: $tag,
        source_tag: $source_tag,
        commit_sha: $commit_sha,
        run_id: $run_id,
        documentation_run_attempt: $documentation_run_attempt,
        publication_run_attempt: $publication_run_attempt,
        workflow_url: $workflow_url,
        documentation_asset: $documentation_asset,
        documentation_sha256: $documentation_sha256
    }' > "$manifest_path"

manifest_sha256="$(sha256_file "$manifest_path")"
printf '%s  %s\n' "$docs_sha256" "$docs_name" > "$checksums_path"
printf '%s  %s\n' "$manifest_sha256" "$manifest_name" >> "$checksums_path"

printf 'SWIFTQL_RELEASE_ASSETS ok %s %s\n' "$release_tag" "$commit_sha"
printf 'documentation_asset=%s\n' "$docs_name"
printf 'manifest_asset=%s\n' "$manifest_name"
printf 'checksums_asset=%s\n' "$checksums_name"
