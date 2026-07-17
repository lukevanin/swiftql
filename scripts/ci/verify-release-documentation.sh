#!/bin/bash

set -euo pipefail

fail() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

sha256_file() {
    if command -v sha256sum > /dev/null 2>&1; then
        sha256sum "$1" | awk '{ print $1 }'
    else
        shasum -a 256 "$1" | awk '{ print $1 }'
    fi
}

require_file() {
    if [[ ! -f "$1" || -L "$1" ]]; then
        fail "missing or unsafe documentation file: $1"
    fi
}

require_nonempty_file() {
    require_file "$1"
    [[ -s "$1" ]] || fail "empty documentation file: $1"
}

if [[ "$#" -ne 6 ]]; then
    printf 'usage: %s DOCS_ARCHIVE MANIFEST RELEASE_TAG SOURCE_TAG COMMIT_SHA REPOSITORY\n' \
        "$0" >&2
    exit 64
fi

docs_archive="$1"
manifest="$2"
release_tag="$3"
source_tag="$4"
commit_sha="$5"
repository="$6"
script_directory="$(cd "$(dirname "$0")" && pwd -P)"
archive_tool="$script_directory/release-archive.py"

require_nonempty_file "$docs_archive"
require_nonempty_file "$manifest"
docs_name="$(basename "$docs_archive")"
[[ "$release_tag" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] ||
    fail "invalid release tag: $release_tag"
[[ "$source_tag" == "$release_tag" ||
   "$source_tag" == "release-test/$release_tag" ]] ||
    fail "source tag does not normalize to release tag: $source_tag"
[[ "$commit_sha" =~ ^[0-9a-f]{40}$ ]] ||
    fail "invalid release commit: $commit_sha"
[[ "$repository" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] ||
    fail "invalid repository: $repository"
[[ "$docs_name" == "swiftql-docc-$release_tag.tar.gz" ]] ||
    fail "unexpected documentation asset name: $docs_name"
docs_sha256="$(sha256_file "$docs_archive")"
server_url="${GITHUB_SERVER_URL:-https://github.com}"

if ! jq -e \
    --arg repository "$repository" \
    --arg tag "$release_tag" \
    --arg source_tag "$source_tag" \
    --arg commit_sha "$commit_sha" \
    --arg docs_name "$docs_name" \
    --arg docs_sha256 "$docs_sha256" \
    --arg server_url "$server_url" \
    '.schema_version == 1 and
     .repository == $repository and
     .tag == $tag and
     .source_tag == $source_tag and
     .commit_sha == $commit_sha and
     .documentation_asset == $docs_name and
     .documentation_sha256 == $docs_sha256 and
     (.run_id | type == "string" and test("^[0-9]+$")) and
     (.documentation_run_attempt | type == "string" and test("^[0-9]+$")) and
     (.publication_run_attempt | type == "string" and test("^[0-9]+$")) and
     .workflow_url == ($server_url + "/" + $repository + "/actions/runs/" + .run_id)' \
    "$manifest" > /dev/null; then
    fail 'release manifest metadata is incomplete or inconsistent'
fi

temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/swiftql-verify-docs.XXXXXX")"
trap 'rm -rf "$temporary_directory"' EXIT
docs_tar="$temporary_directory/documentation.tar"
site_directory="$temporary_directory/site"
gzip -t "$docs_archive"
gzip -dc "$docs_archive" > "$docs_tar"
python3 "$archive_tool" extract "$docs_tar" "$site_directory"

require_file "$site_directory/.nojekyll"
require_nonempty_file "$site_directory/index.html"
require_nonempty_file "$site_directory/documentation/swiftql/index.html"
require_nonempty_file \
    "$site_directory/documentation/swiftql/gettingstarted/index.html"
require_nonempty_file "$site_directory/data/documentation/swiftql.json"
require_nonempty_file \
    "$site_directory/data/documentation/swiftql/gettingstarted.json"

pages_provenance="$site_directory/swiftql-pages-provenance.json"
require_nonempty_file "$pages_provenance"
run_id="$(jq -r '.run_id' "$manifest")"
documentation_run_attempt="$(jq -r '.documentation_run_attempt' "$manifest")"
workflow_url="$(jq -r '.workflow_url' "$manifest")"
if ! jq -e \
    --arg commit_sha "$commit_sha" \
    --arg source_ref "refs/tags/$source_tag" \
    --arg source_tag "$source_tag" \
    --arg run_id "$run_id" \
    --arg run_attempt "$documentation_run_attempt" \
    --arg repository "$repository" \
    --arg workflow_url "$workflow_url" \
    '.commit_sha == $commit_sha and
     .source_ref == $source_ref and
     .source_ref_name == $source_tag and
     .run_id == $run_id and
     .run_attempt == $run_attempt and
     .repository == $repository and
     .workflow_url == $workflow_url' \
    "$pages_provenance" > /dev/null; then
    fail 'embedded Pages provenance does not match the release manifest'
fi

printf 'SWIFTQL_RELEASE_DOCUMENTATION ok %s %s %s\n' \
    "$source_tag" "$commit_sha" "$run_id"
