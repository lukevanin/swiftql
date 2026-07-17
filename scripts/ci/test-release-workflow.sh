#!/bin/bash

set -euo pipefail

script_directory="$(cd "$(dirname "$0")" && pwd -P)"
check_ref="$script_directory/check-release-ref.sh"
check_readiness="$script_directory/check-release-readiness.sh"
check_changelog="$script_directory/check-release-changelog.sh"
prepare_assets="$script_directory/prepare-release-assets.sh"
publish_release="$script_directory/publish-release.sh"
archive_tool="$script_directory/release-archive.py"

fail() {
    printf 'error: release workflow self-test: %s\n' "$*" >&2
    exit 1
}

sha256_file() {
    if command -v sha256sum > /dev/null 2>&1; then
        sha256sum "$1" | awk '{ print $1 }'
    else
        shasum -a 256 "$1" | awk '{ print $1 }'
    fi
}

replace_state() {
    local replacement="$1"
    mv "$replacement" "$SWIFTQL_FAKE_RELEASE_STATE"
}

record_mutation() {
    printf '%s\n' "$1" >> "$SWIFTQL_FAKE_MUTATIONS"
}

fake_release_api() {
    local operation="$1"
    shift
    local state="$SWIFTQL_FAKE_RELEASE_STATE"
    local temporary
    local payload
    local release_id
    local asset_id
    local asset_path
    local asset_name
    local digest
    local size
    local immutable_reads

    case "$operation" in
        list-releases)
            jq '.releases' "$state"
            ;;
        create-release)
            payload="$1"
            release_id="$(jq -r '.next_release_id' "$state")"
            temporary="$(mktemp "${TMPDIR:-/tmp}/swiftql-fake-release.XXXXXX")"
            jq \
                --argjson release_id "$release_id" \
                --slurpfile payload "$payload" \
                '.next_release_id += 1 |
                 .releases += [($payload[0] + {
                     id: $release_id,
                     body: ($payload[0].body +
                         "\n\n## What\u0027s Changed\n\n- Fixture generated note"),
                     immutable: false,
                     assets: []
                 })]' \
                "$state" > "$temporary"
            replace_state "$temporary"
            record_mutation "create-release:$release_id"
            jq --argjson release_id "$release_id" \
                '.releases[] | select(.id == $release_id)' "$state"
            ;;
        list-assets)
            release_id="$1"
            jq --argjson release_id "$release_id" \
                '.releases[] | select(.id == $release_id) | .assets' "$state"
            ;;
        get-release)
            release_id="$1"
            immutable_reads="$(cat "$SWIFTQL_FAKE_IMMUTABLE_READS")"
            immutable_reads="$((immutable_reads + 1))"
            printf '%s\n' "$immutable_reads" > "$SWIFTQL_FAKE_IMMUTABLE_READS"
            if [[ "$SWIFTQL_FAKE_IMMUTABLE_MODE" == delayed &&
                  "$immutable_reads" -ge 2 ]]; then
                temporary="$(mktemp "${TMPDIR:-/tmp}/swiftql-fake-release.XXXXXX")"
                jq --argjson release_id "$release_id" \
                    '.releases |= map(
                        if .id == $release_id then .immutable = true else . end
                     )' "$state" > "$temporary"
                replace_state "$temporary"
            fi
            jq --argjson release_id "$release_id" \
                '.releases[] | select(.id == $release_id)' "$state"
            ;;
        delete-asset)
            asset_id="$1"
            temporary="$(mktemp "${TMPDIR:-/tmp}/swiftql-fake-release.XXXXXX")"
            jq --argjson asset_id "$asset_id" \
                '.releases |= map(.assets |= map(select(.id != $asset_id)))' \
                "$state" > "$temporary"
            replace_state "$temporary"
            rm -f "$SWIFTQL_FAKE_ASSETS/$asset_id"
            record_mutation "delete-asset:$asset_id"
            ;;
        upload-asset)
            release_id="$1"
            asset_path="$2"
            asset_name="$(basename "$asset_path")"
            if [[ "$(jq --argjson release_id "$release_id" \
                '[.releases[] | select(.id == $release_id)] | length' "$state")" -ne 1 ]]; then
                fail "fake upload could not find release ID $release_id"
            fi
            if [[ "$(jq --argjson release_id "$release_id" --arg name "$asset_name" \
                '[.releases[] | select(.id == $release_id) | .assets[] |
                  select(.name == $name)] | length' "$state")" -ne 0 ]]; then
                fail "fake upload received duplicate asset $asset_name"
            fi
            asset_id="$(jq -r '.next_asset_id' "$state")"
            digest="sha256:$(sha256_file "$asset_path")"
            size="$(wc -c < "$asset_path" | tr -d '[:space:]')"
            mkdir -p "$SWIFTQL_FAKE_ASSETS"
            cp "$asset_path" "$SWIFTQL_FAKE_ASSETS/$asset_id"
            temporary="$(mktemp "${TMPDIR:-/tmp}/swiftql-fake-release.XXXXXX")"
            jq \
                --argjson release_id "$release_id" \
                --arg name "$asset_name" \
                --arg digest "$digest" \
                --argjson asset_id "$asset_id" \
                --argjson size "$size" \
                '.next_asset_id += 1 |
                 .releases |= map(
                     if .id == $release_id then
                         .assets += [{
                             id: $asset_id,
                             name: $name,
                             state: "uploaded",
                             digest: $digest,
                             size: $size
                         }]
                     else . end
                 )' "$state" > "$temporary"
            replace_state "$temporary"
            record_mutation "upload-asset:$asset_name"
            jq --argjson asset_id "$asset_id" \
                '.releases[].assets[] | select(.id == $asset_id)' "$state"
            ;;
        update-release)
            release_id="$1"
            payload="$2"
            temporary="$(mktemp "${TMPDIR:-/tmp}/swiftql-fake-release.XXXXXX")"
            jq \
                --argjson release_id "$release_id" \
                --arg immutable_mode "$SWIFTQL_FAKE_IMMUTABLE_MODE" \
                --slurpfile payload "$payload" \
                '.releases |= map(
                    if .id == $release_id then
                        . + $payload[0] |
                        if $immutable_mode == "immediate" and .draft == false then
                            .immutable = true
                        else . end
                    else . end
                 )' "$state" > "$temporary"
            replace_state "$temporary"
            record_mutation "update-release:$release_id"
            jq --argjson release_id "$release_id" \
                '.releases[] | select(.id == $release_id)' "$state"
            ;;
        download-asset)
            asset_id="$1"
            cat "$SWIFTQL_FAKE_ASSETS/$asset_id"
            ;;
        *)
            fail "unknown fake API operation: $operation"
            ;;
    esac
}

case "${1:-}" in
    pre-publish-check)
        : "${SWIFTQL_FAKE_PRE_PUBLISH_CHECKS:?Set SWIFTQL_FAKE_PRE_PUBLISH_CHECKS}"
        printf '%s %s %s\n' "$2" "$3" "$4" >> "$SWIFTQL_FAKE_PRE_PUBLISH_CHECKS"
        if [[ "${SWIFTQL_FAKE_PRE_PUBLISH_FAILURE:-false}" == true ]]; then
            fail 'fake pre-publish ref moved'
        fi
        exit 0
        ;;
    list-releases|create-release|list-assets|get-release|delete-asset|upload-asset|update-release|download-asset)
        : "${SWIFTQL_FAKE_RELEASE_STATE:?Set SWIFTQL_FAKE_RELEASE_STATE}"
        : "${SWIFTQL_FAKE_MUTATIONS:?Set SWIFTQL_FAKE_MUTATIONS}"
        : "${SWIFTQL_FAKE_ASSETS:?Set SWIFTQL_FAKE_ASSETS}"
        : "${SWIFTQL_FAKE_IMMUTABLE_READS:?Set SWIFTQL_FAKE_IMMUTABLE_READS}"
        : "${SWIFTQL_FAKE_IMMUTABLE_MODE:?Set SWIFTQL_FAKE_IMMUTABLE_MODE}"
        fake_release_api "$@"
        exit 0
        ;;
esac

expect_failure() {
    if "$@" > /dev/null 2>&1; then
        fail "command unexpectedly succeeded: $*"
    fi
}

initialize_fake_api() {
    fake_root="$test_root/fake-$1"
    fake_state="$fake_root/state.json"
    fake_mutations="$fake_root/mutations.log"
    fake_assets="$fake_root/assets"
    fake_pre_publish_checks="$fake_root/pre-publish-checks.log"
    fake_immutable_reads="$fake_root/immutable-reads"
    fake_pre_publish_failure=false
    fake_immutable_mode=immediate
    mkdir -p "$fake_assets"
    printf '%s\n' \
        '{"next_release_id":100,"next_asset_id":1000,"releases":[]}' \
        > "$fake_state"
    : > "$fake_mutations"
    : > "$fake_pre_publish_checks"
    printf '0\n' > "$fake_immutable_reads"
}

run_publisher() {
    env \
        GITHUB_REPOSITORY=lukevanin/swiftql \
        GITHUB_SERVER_URL=https://github.com \
        SWIFTQL_RELEASE_API="$0" \
        SWIFTQL_FAKE_RELEASE_STATE="$fake_state" \
        SWIFTQL_FAKE_MUTATIONS="$fake_mutations" \
        SWIFTQL_FAKE_ASSETS="$fake_assets" \
        SWIFTQL_FAKE_PRE_PUBLISH_CHECKS="$fake_pre_publish_checks" \
        SWIFTQL_FAKE_PRE_PUBLISH_FAILURE="$fake_pre_publish_failure" \
        SWIFTQL_FAKE_IMMUTABLE_READS="$fake_immutable_reads" \
        SWIFTQL_FAKE_IMMUTABLE_MODE="$fake_immutable_mode" \
        SWIFTQL_PRE_PUBLISH_CHECK="$0" \
        SWIFTQL_IMMUTABLE_ATTEMPTS=3 \
        SWIFTQL_IMMUTABLE_INTERVAL_SECONDS=0 \
        "$publish_release" "$@"
}

fake_api_command() {
    env \
        SWIFTQL_FAKE_RELEASE_STATE="$fake_state" \
        SWIFTQL_FAKE_MUTATIONS="$fake_mutations" \
        SWIFTQL_FAKE_ASSETS="$fake_assets" \
        SWIFTQL_FAKE_IMMUTABLE_READS="$fake_immutable_reads" \
        SWIFTQL_FAKE_IMMUTABLE_MODE="$fake_immutable_mode" \
        "$0" "$@"
}

seed_release() {
    local tag="$1"
    local commit="$2"
    local draft="$3"
    local payload="$fake_root/seed-release.json"
    local marker="<!-- swiftql-release-sha: $commit -->"

    jq -n \
        --arg tag "$tag" \
        --arg commit "$commit" \
        --arg marker "$marker" \
        --argjson draft "$draft" \
        '{
            tag_name: $tag,
            target_commitish: $commit,
            name: $tag,
            body: ("Fixture release\n\n" + $marker),
            draft: $draft,
            prerelease: false,
            generate_release_notes: true
        }' > "$payload"
    fake_api_command create-release "$payload" > /dev/null
}

fake_asset_id() {
    local name="$1"
    jq -er --arg name "$name" \
        '.releases[0].assets[] | select(.name == $name) | .id' "$fake_state"
}

refresh_fake_asset_digest() {
    local asset_id="$1"
    local asset_path="$fake_assets/$asset_id"
    local digest="sha256:$(sha256_file "$asset_path")"
    local temporary

    temporary="$(mktemp "${TMPDIR:-/tmp}/swiftql-fake-digest.XXXXXX")"
    jq --argjson asset_id "$asset_id" --arg digest "$digest" \
        '.releases |= map(
            .assets |= map(
                if .id == $asset_id then
                    .digest = $digest | .size = 0
                else . end
            )
         )' "$fake_state" > "$temporary"
    mv "$temporary" "$fake_state"
}

make_fake_published_assets_self_consistent() {
    local docs_id
    local manifest_id
    local checksums_id
    local docs_digest
    local manifest_digest
    local temporary

    docs_id="$(fake_asset_id swiftql-docc-v1.1.0.tar.gz)"
    manifest_id="$(fake_asset_id swiftql-release-v1.1.0.json)"
    checksums_id="$(fake_asset_id SHA256SUMS)"
    docs_digest="$(sha256_file "$fake_assets/$docs_id")"
    temporary="$(mktemp "${TMPDIR:-/tmp}/swiftql-fake-manifest.XXXXXX")"
    jq --arg docs_digest "$docs_digest" \
        '.documentation_sha256 = $docs_digest' \
        "$fake_assets/$manifest_id" > "$temporary"
    mv "$temporary" "$fake_assets/$manifest_id"
    manifest_digest="$(sha256_file "$fake_assets/$manifest_id")"
    printf '%s  %s\n' "$docs_digest" swiftql-docc-v1.1.0.tar.gz \
        > "$fake_assets/$checksums_id"
    printf '%s  %s\n' "$manifest_digest" swiftql-release-v1.1.0.json \
        >> "$fake_assets/$checksums_id"
    refresh_fake_asset_digest "$docs_id"
    refresh_fake_asset_digest "$manifest_id"
    refresh_fake_asset_digest "$checksums_id"
}

assert_no_new_mutation() {
    local baseline="$1"
    local description="$2"
    local actual

    actual="$(wc -l < "$fake_mutations" | tr -d '[:space:]')"
    [[ "$actual" == "$baseline" ]] || fail "$description performed a mutation"
}

test_root="$(mktemp -d "${TMPDIR:-/tmp}/swiftql-release-tests.XXXXXX")"
cleanup_test_root() {
    local status="$?"
    if [[ "${SWIFTQL_KEEP_TEST_ROOT:-false}" == true ]]; then
        printf 'SWIFTQL_RELEASE_WORKFLOW_TEST_ROOT %s\n' "$test_root" >&2
    else
        rm -rf "$test_root"
    fi
    return "$status"
}
trap cleanup_test_root EXIT

# Exact ref and reachability checks use a real temporary Git graph.
git_root="$test_root/git"
mkdir -p "$git_root"
git -C "$git_root" init -q -b main
git -C "$git_root" config user.name SwiftQL-CI
git -C "$git_root" config user.email swiftql-ci@example.invalid
printf 'main\n' > "$git_root/state.txt"
git -C "$git_root" add state.txt
git -C "$git_root" commit -q -m main
main_sha="$(git -C "$git_root" rev-parse HEAD)"
git -C "$git_root" tag -a v1.1.0 -m 'SwiftQL v1.1.0'
git -C "$git_root" tag release-test/v1.1.999
git -C "$git_root" tag release-test/not-semver
git -C "$git_root" tag v1.0.9
(
    cd "$git_root"
    "$check_ref" v1.1.0 "$main_sha" refs/heads/main |
        grep -Fx 'mode=publish' > /dev/null
    "$check_ref" release-test/v1.1.999 "$main_sha" refs/heads/main |
        grep -Fx 'mode=dry-run' > /dev/null
    expect_failure "$check_ref" release-test/not-semver "$main_sha" refs/heads/main
    expect_failure "$check_ref" v1.0.9 "$main_sha" refs/heads/main
)
git -C "$git_root" switch -q -c unreachable
printf 'unreachable\n' >> "$git_root/state.txt"
git -C "$git_root" commit -qam unreachable
unreachable_sha="$(git -C "$git_root" rev-parse HEAD)"
git -C "$git_root" tag release-test/v1.1.998
(
    cd "$git_root"
    # The annotated production tag peels to main, not its tag object.
    expect_failure "$check_ref" v1.1.0 "$unreachable_sha" refs/heads/main
    # Even with the expected tag commit, an unrelated checkout is rejected.
    expect_failure "$check_ref" v1.1.0 "$main_sha" refs/heads/main
    expect_failure \
        "$check_ref" release-test/v1.1.998 "$unreachable_sha" refs/heads/main
)
git -C "$git_root" tag -a release-test/v1.1.997 "$main_sha" -m before-move
git -C "$git_root" tag -f -a release-test/v1.1.997 "$unreachable_sha" -m after-move
git -C "$git_root" switch -q main
(
    cd "$git_root"
    expect_failure \
        "$check_ref" release-test/v1.1.997 "$main_sha" refs/heads/main
)

# The one-time v1.1 milestone gate allows only the tracker and release issue.
printf '%s\n' \
    '[{"number":118,"title":"Tracker"},{"number":119,"title":"Release"}]' \
    > "$test_root/issues-ready.json"
printf '%s\n' \
    '[{"number":118},{"number":119},{"number":151,"title":"Still open"}]' \
    > "$test_root/issues-blocked.json"
"$check_readiness" v1.1.0 "$test_root/issues-ready.json" > /dev/null
expect_failure \
    "$check_readiness" v1.1.0 "$test_root/issues-blocked.json"
"$check_readiness" v1.1.1 "$test_root/does-not-exist.json" > /dev/null

# Production releases require a dated changelog heading; test tags skip it.
printf '## [1.1.0] - 2026-07-17\n' > "$test_root/changelog-ready.md"
printf '## [1.1.0] - Unreleased\n' > "$test_root/changelog-unreleased.md"
"$check_changelog" \
    v1.1.0 v1.1.0 "$test_root/changelog-ready.md" > /dev/null
expect_failure "$check_changelog" \
    v1.1.0 v1.1.0 "$test_root/changelog-unreleased.md"
expect_failure "$check_changelog" \
    v1.1.0 v1.1.0 "$test_root/does-not-exist.md"
"$check_changelog" \
    release-test/v1.1.0 v1.1.0 "$test_root/does-not-exist.md" > /dev/null

# Build a minimal real Pages tar and prove deterministic release packaging.
site="$test_root/site"
mkdir -p \
    "$site/documentation/swiftql/gettingstarted" \
    "$site/data/documentation/swiftql"
: > "$site/.nojekyll"
printf '<html>root</html>\n' > "$site/index.html"
mkdir -p "$site/documentation/swiftql"
printf '<html>SwiftQL</html>\n' > "$site/documentation/swiftql/index.html"
printf '<html>Getting started</html>\n' \
    > "$site/documentation/swiftql/gettingstarted/index.html"
printf '{"metadata":{"title":"SwiftQL"}}\n' \
    > "$site/data/documentation/swiftql.json"
printf '{"metadata":{"title":"Getting started"}}\n' \
    > "$site/data/documentation/swiftql/gettingstarted.json"
jq -n \
    --arg commit "$main_sha" \
    '{
        commit_sha: $commit,
        source_ref: "refs/tags/v1.1.0",
        source_ref_name: "v1.1.0",
        run_id: "12345",
        run_attempt: "1",
        repository: "lukevanin/swiftql",
        workflow_url: "https://github.com/lukevanin/swiftql/actions/runs/12345"
    }' > "$site/swiftql-pages-provenance.json"
pages_tar="$test_root/artifact.tar"
COPYFILE_DISABLE=1 tar -cf "$pages_tar" -C "$site" .
assets_a="$test_root/assets-a"
assets_b="$test_root/assets-b"
"$prepare_assets" \
    "$pages_tar" "$assets_a" v1.1.0 "$main_sha" \
    12345 1 lukevanin/swiftql v1.1.0 > /dev/null
"$prepare_assets" \
    "$pages_tar" "$assets_b" v1.1.0 "$main_sha" \
    12345 1 lukevanin/swiftql v1.1.0 > /dev/null
cmp "$assets_a/swiftql-docc-v1.1.0.tar.gz" \
    "$assets_b/swiftql-docc-v1.1.0.tar.gz"
cmp "$assets_a/swiftql-release-v1.1.0.json" \
    "$assets_b/swiftql-release-v1.1.0.json"
cmp "$assets_a/SHA256SUMS" "$assets_b/SHA256SUMS"

# Input archive order, ownership, mode, and mtime metadata do not affect the
# normalized release assets when the logical site bytes are identical.
metadata_site="$test_root/metadata-site"
cp -R "$site" "$metadata_site"
find "$metadata_site" -exec touch -t 203001020304 {} +
metadata_list="$test_root/metadata-files.txt"
(
    cd "$metadata_site"
    find . -type f -print | LC_ALL=C sort -r > "$metadata_list"
    COPYFILE_DISABLE=1 tar -cf "$test_root/metadata-artifact.tar" -T "$metadata_list"
)
assets_metadata="$test_root/assets-metadata"
"$prepare_assets" \
    "$test_root/metadata-artifact.tar" "$assets_metadata" \
    v1.1.0 "$main_sha" 12345 1 lukevanin/swiftql v1.1.0 > /dev/null
cmp "$assets_a/swiftql-docc-v1.1.0.tar.gz" \
    "$assets_metadata/swiftql-docc-v1.1.0.tar.gz"
cmp "$assets_a/swiftql-release-v1.1.0.json" \
    "$assets_metadata/swiftql-release-v1.1.0.json"
cmp "$assets_a/SHA256SUMS" "$assets_metadata/SHA256SUMS"

dry_site="$test_root/dry-site"
cp -R "$site" "$dry_site"
jq \
    '.source_ref = "refs/tags/release-test/v1.1.0" |
     .source_ref_name = "release-test/v1.1.0"' \
    "$dry_site/swiftql-pages-provenance.json" > "$test_root/dry-provenance.json"
mv "$test_root/dry-provenance.json" \
    "$dry_site/swiftql-pages-provenance.json"
dry_pages_tar="$test_root/dry-artifact.tar"
COPYFILE_DISABLE=1 tar -cf "$dry_pages_tar" -C "$dry_site" .
assets_dry="$test_root/assets-dry"
"$prepare_assets" \
    "$dry_pages_tar" "$assets_dry" v1.1.0 "$main_sha" \
    12345 1 lukevanin/swiftql release-test/v1.1.0 > /dev/null
expect_failure "$prepare_assets" \
    "$pages_tar" "$test_root/prod-as-dry-assets" v1.1.0 "$main_sha" \
    12345 1 lukevanin/swiftql release-test/v1.1.0
expect_failure "$prepare_assets" \
    "$dry_pages_tar" "$test_root/dry-as-prod-assets" v1.1.0 "$main_sha" \
    12345 1 lukevanin/swiftql v1.1.0
expect_failure "$prepare_assets" \
    "$pages_tar" "$test_root/non-normalizing-assets" v1.1.0 "$main_sha" \
    12345 1 lukevanin/swiftql release-test/v1.1.1

bad_site="$test_root/bad-site"
cp -R "$site" "$bad_site"
jq '.commit_sha = "0000000000000000000000000000000000000000"' \
    "$bad_site/swiftql-pages-provenance.json" > "$test_root/bad-provenance.json"
mv "$test_root/bad-provenance.json" \
    "$bad_site/swiftql-pages-provenance.json"
COPYFILE_DISABLE=1 tar -cf "$test_root/bad-artifact.tar" -C "$bad_site" .
expect_failure "$prepare_assets" \
    "$test_root/bad-artifact.tar" "$test_root/bad-assets" \
    v1.1.0 "$main_sha" 12345 1 lukevanin/swiftql v1.1.0

unsafe_site="$test_root/unsafe-site"
cp -R "$site" "$unsafe_site"
ln -s /tmp "$unsafe_site/unsafe-link"
COPYFILE_DISABLE=1 tar -cf "$test_root/unsafe-artifact.tar" -C "$unsafe_site" .
expect_failure "$prepare_assets" \
    "$test_root/unsafe-artifact.tar" "$test_root/unsafe-assets" \
    v1.1.0 "$main_sha" 12345 1 lukevanin/swiftql v1.1.0

# A dry run has no write-capable operation.
initialize_fake_api dry
run_publisher --dry-run release-test/v1.1.0 \
    v1.1.0 "$main_sha" "$assets_dry" > /dev/null
[[ ! -s "$fake_mutations" ]] || fail 'dry run mutated release state'
[[ "$(jq '.releases | length' "$fake_state")" -eq 0 ]] ||
    fail 'dry run created a release'

# Publisher mode and source-tag mismatches fail before the API can mutate.
initialize_fake_api wrong-mode
expect_failure run_publisher \
    release-test/v1.1.0 v1.1.0 "$main_sha" "$assets_dry"
expect_failure run_publisher --dry-run \
    v1.1.0 v1.1.0 "$main_sha" "$assets_a"
[[ ! -s "$fake_mutations" ]] ||
    fail 'wrong publisher mode/source tag performed a mutation'

# Dry runs inspect existing draft state without creating, uploading, deleting,
# or updating anything, including when an asset is missing or mismatched.
initialize_fake_api dry-partial
seed_release v1.1.0 "$main_sha" true
dry_partial_release_id="$(jq -r '.releases[0].id' "$fake_state")"
fake_api_command upload-asset "$dry_partial_release_id" \
    "$assets_dry/swiftql-docc-v1.1.0.tar.gz" > /dev/null
dry_partial_baseline="$(wc -l < "$fake_mutations" | tr -d '[:space:]')"
run_publisher --dry-run release-test/v1.1.0 \
    v1.1.0 "$main_sha" "$assets_dry" > "$test_root/dry-partial.log"
[[ "$(wc -l < "$fake_mutations" | tr -d '[:space:]')" == "$dry_partial_baseline" ]] ||
    fail 'partial-draft dry run performed a mutation'
grep -F 'DRY-RUN would upload' "$test_root/dry-partial.log" > /dev/null ||
    fail 'partial-draft dry run did not report its missing assets'

initialize_fake_api dry-mismatch
seed_release v1.1.0 "$main_sha" true
dry_mismatch_release_id="$(jq -r '.releases[0].id' "$fake_state")"
dry_wrong_directory="$test_root/dry-wrong"
mkdir -p "$dry_wrong_directory"
printf 'wrong dry-run documentation bytes\n' \
    > "$dry_wrong_directory/swiftql-docc-v1.1.0.tar.gz"
fake_api_command upload-asset "$dry_mismatch_release_id" \
    "$dry_wrong_directory/swiftql-docc-v1.1.0.tar.gz" > /dev/null
dry_mismatch_baseline="$(wc -l < "$fake_mutations" | tr -d '[:space:]')"
run_publisher --dry-run release-test/v1.1.0 \
    v1.1.0 "$main_sha" "$assets_dry" > "$test_root/dry-mismatch.log"
[[ "$(wc -l < "$fake_mutations" | tr -d '[:space:]')" == "$dry_mismatch_baseline" ]] ||
    fail 'mismatched-draft dry run performed a mutation'
grep -F 'DRY-RUN would replace' "$test_root/dry-mismatch.log" > /dev/null ||
    fail 'mismatched-draft dry run did not report its replacement plan'

# A resumed marker-only draft is rejected before any asset or release mutation.
initialize_fake_api missing-notes
seed_release v1.1.0 "$main_sha" true
missing_notes_state="$(mktemp "${TMPDIR:-/tmp}/swiftql-missing-notes.XXXXXX")"
jq --arg marker "<!-- swiftql-release-sha: $main_sha -->" \
    '.releases[0].body = $marker' "$fake_state" > "$missing_notes_state"
mv "$missing_notes_state" "$fake_state"
missing_notes_baseline="$(wc -l < "$fake_mutations" | tr -d '[:space:]')"
expect_failure run_publisher \
    v1.1.0 v1.1.0 "$main_sha" "$assets_a"
[[ "$(wc -l < "$fake_mutations" | tr -d '[:space:]')" == "$missing_notes_baseline" ]] ||
    fail 'marker-only draft was mutated'
[[ "$(jq '.releases[0].draft' "$fake_state")" == true ]] ||
    fail 'marker-only draft was published'

# The final pre-publish hook runs after exact asset verification. A moved ref
# fails that hook and prevents the draft PATCH.
initialize_fake_api moved-ref
seed_release v1.1.0 "$main_sha" true
moved_ref_release_id="$(jq -r '.releases[0].id' "$fake_state")"
for asset_path in \
    "$assets_a/swiftql-docc-v1.1.0.tar.gz" \
    "$assets_a/swiftql-release-v1.1.0.json" \
    "$assets_a/SHA256SUMS"; do
    fake_api_command upload-asset "$moved_ref_release_id" "$asset_path" > /dev/null
done
moved_ref_baseline="$(wc -l < "$fake_mutations" | tr -d '[:space:]')"
fake_pre_publish_failure=true
expect_failure run_publisher \
    v1.1.0 v1.1.0 "$main_sha" "$assets_a"
[[ "$(wc -l < "$fake_mutations" | tr -d '[:space:]')" == "$moved_ref_baseline" ]] ||
    fail 'moved-ref pre-publish failure performed a mutation'
[[ "$(jq '.releases[0].draft' "$fake_state")" == true ]] ||
    fail 'moved-ref pre-publish failure published the draft'
[[ "$(wc -l < "$fake_pre_publish_checks" | tr -d '[:space:]')" == 1 ]] ||
    fail 'moved-ref fixture did not reach the pre-publish hook exactly once'

# First publication creates one draft, uploads three assets, publishes it, and
# a rerun verifies that exact published state without another mutation.
initialize_fake_api publish
run_publisher v1.1.0 v1.1.0 "$main_sha" "$assets_a" > /dev/null
[[ "$(jq '.releases | length' "$fake_state")" -eq 1 ]] ||
    fail 'publisher did not create exactly one release'
[[ "$(jq '.releases[0].draft' "$fake_state")" == false ]] ||
    fail 'publisher did not publish its draft'
[[ "$(jq '.releases[0].immutable' "$fake_state")" == true ]] ||
    fail 'publisher did not require an immutable release'
[[ "$(jq '.releases[0].assets | length' "$fake_state")" -eq 3 ]] ||
    fail 'publisher did not upload exactly three assets'
mutation_count="$(wc -l < "$fake_mutations" | tr -d '[:space:]')"
run_publisher v1.1.0 v1.1.0 "$main_sha" "$assets_a" > /dev/null
[[ "$(wc -l < "$fake_mutations" | tr -d '[:space:]')" == "$mutation_count" ]] ||
    fail 'published rerun performed a mutation'

# Repository immutability may propagate after publication. The publisher polls
# the exact release to true, and never declares a mutable published release OK.
initialize_fake_api immutable-delayed
fake_immutable_mode=delayed
run_publisher v1.1.0 v1.1.0 "$main_sha" "$assets_a" > /dev/null
[[ "$(jq '.releases[0].immutable' "$fake_state")" == true ]] ||
    fail 'publisher did not observe delayed immutable state'
[[ "$(cat "$fake_immutable_reads")" -ge 2 ]] ||
    fail 'publisher did not poll delayed immutable state'

initialize_fake_api immutable-never
seed_release v1.1.0 "$main_sha" false
fake_immutable_mode=never
immutable_never_baseline="$(wc -l < "$fake_mutations" | tr -d '[:space:]')"
expect_failure run_publisher \
    v1.1.0 v1.1.0 "$main_sha" "$assets_a"
[[ "$(wc -l < "$fake_mutations" | tr -d '[:space:]')" == "$immutable_never_baseline" ]] ||
    fail 'mutable published release was mutated during verification'
[[ "$(jq '.releases[0].immutable' "$fake_state")" == false ]] ||
    fail 'never-immutable fixture unexpectedly became immutable'

# Published reruns fail closed without mutation when remote state is corrupt,
# even when the API digests, manifest, and checksums are forged consistently.
initialize_fake_api published-corrupt-archive
run_publisher v1.1.0 v1.1.0 "$main_sha" "$assets_a" > /dev/null
corrupt_docs_id="$(fake_asset_id swiftql-docc-v1.1.0.tar.gz)"
printf 'this is not a documentation archive\n' > "$fake_assets/$corrupt_docs_id"
make_fake_published_assets_self_consistent
published_baseline="$(wc -l < "$fake_mutations" | tr -d '[:space:]')"
expect_failure run_publisher v1.1.0 v1.1.0 "$main_sha" "$assets_a"
assert_no_new_mutation "$published_baseline" 'corrupt published archive check'

initialize_fake_api published-bad-provenance
run_publisher v1.1.0 v1.1.0 "$main_sha" "$assets_a" > /dev/null
provenance_docs_id="$(fake_asset_id swiftql-docc-v1.1.0.tar.gz)"
provenance_root="$test_root/tampered-provenance"
mkdir -p "$provenance_root/site"
gzip -dc "$fake_assets/$provenance_docs_id" > "$provenance_root/source.tar"
python3 "$archive_tool" extract \
    "$provenance_root/source.tar" "$provenance_root/site"
jq '.source_ref = "refs/tags/v9.9.9"' \
    "$provenance_root/site/swiftql-pages-provenance.json" \
    > "$provenance_root/bad-provenance.json"
mv "$provenance_root/bad-provenance.json" \
    "$provenance_root/site/swiftql-pages-provenance.json"
python3 "$archive_tool" create \
    "$provenance_root/site" "$provenance_root/tampered.tar"
gzip -n -c "$provenance_root/tampered.tar" > "$fake_assets/$provenance_docs_id"
make_fake_published_assets_self_consistent
published_baseline="$(wc -l < "$fake_mutations" | tr -d '[:space:]')"
expect_failure run_publisher v1.1.0 v1.1.0 "$main_sha" "$assets_a"
assert_no_new_mutation "$published_baseline" 'published provenance check'

initialize_fake_api published-bad-manifest
run_publisher v1.1.0 v1.1.0 "$main_sha" "$assets_a" > /dev/null
bad_manifest_id="$(fake_asset_id swiftql-release-v1.1.0.json)"
bad_manifest_temporary="$(mktemp "${TMPDIR:-/tmp}/swiftql-bad-manifest.XXXXXX")"
jq '.run_id = "99999" |
    .workflow_url = "https://github.com/lukevanin/swiftql/actions/runs/99999"' \
    "$fake_assets/$bad_manifest_id" > "$bad_manifest_temporary"
mv "$bad_manifest_temporary" "$fake_assets/$bad_manifest_id"
make_fake_published_assets_self_consistent
published_baseline="$(wc -l < "$fake_mutations" | tr -d '[:space:]')"
expect_failure run_publisher v1.1.0 v1.1.0 "$main_sha" "$assets_a"
assert_no_new_mutation "$published_baseline" 'published manifest check'

initialize_fake_api published-bad-checksums
run_publisher v1.1.0 v1.1.0 "$main_sha" "$assets_a" > /dev/null
bad_checksums_id="$(fake_asset_id SHA256SUMS)"
printf 'forged checksums\n' > "$fake_assets/$bad_checksums_id"
refresh_fake_asset_digest "$bad_checksums_id"
published_baseline="$(wc -l < "$fake_mutations" | tr -d '[:space:]')"
expect_failure run_publisher v1.1.0 v1.1.0 "$main_sha" "$assets_a"
assert_no_new_mutation "$published_baseline" 'published checksum check'

initialize_fake_api published-missing-notes
run_publisher v1.1.0 v1.1.0 "$main_sha" "$assets_a" > /dev/null
published_body_temporary="$(mktemp "${TMPDIR:-/tmp}/swiftql-bad-body.XXXXXX")"
jq --arg marker "<!-- swiftql-release-sha: $main_sha -->" \
    '.releases[0].body = $marker' "$fake_state" > "$published_body_temporary"
mv "$published_body_temporary" "$fake_state"
published_baseline="$(wc -l < "$fake_mutations" | tr -d '[:space:]')"
expect_failure run_publisher v1.1.0 v1.1.0 "$main_sha" "$assets_a"
assert_no_new_mutation "$published_baseline" 'published generated-notes check'

initialize_fake_api published-extra-asset
run_publisher v1.1.0 v1.1.0 "$main_sha" "$assets_a" > /dev/null
extra_state="$(mktemp "${TMPDIR:-/tmp}/swiftql-extra-asset.XXXXXX")"
jq '.releases[0].assets += [{
        id: 9999,
        name: "unexpected.txt",
        state: "uploaded",
        digest: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    }]' "$fake_state" > "$extra_state"
mv "$extra_state" "$fake_state"
published_baseline="$(wc -l < "$fake_mutations" | tr -d '[:space:]')"
expect_failure run_publisher v1.1.0 v1.1.0 "$main_sha" "$assets_a"
assert_no_new_mutation "$published_baseline" 'published extra-asset check'

initialize_fake_api published-missing-asset
run_publisher v1.1.0 v1.1.0 "$main_sha" "$assets_a" > /dev/null
missing_state="$(mktemp "${TMPDIR:-/tmp}/swiftql-missing-asset.XXXXXX")"
jq '.releases[0].assets |= map(select(.name != "SHA256SUMS"))' \
    "$fake_state" > "$missing_state"
mv "$missing_state" "$fake_state"
published_baseline="$(wc -l < "$fake_mutations" | tr -d '[:space:]')"
expect_failure run_publisher v1.1.0 v1.1.0 "$main_sha" "$assets_a"
assert_no_new_mutation "$published_baseline" 'published missing-asset check'

# A partial draft retains a matching asset, uploads only the missing assets,
# and publishes. A mismatched draft asset is replaced by exact ID.
initialize_fake_api partial
seed_release v1.1.0 "$main_sha" true
partial_release_id="$(jq -r '.releases[0].id' "$fake_state")"
fake_api_command upload-asset "$partial_release_id" \
    "$assets_a/swiftql-docc-v1.1.0.tar.gz" > /dev/null
partial_baseline="$(wc -l < "$fake_mutations" | tr -d '[:space:]')"
run_publisher v1.1.0 v1.1.0 "$main_sha" "$assets_a" > /dev/null
partial_added="$(tail -n "+$((partial_baseline + 1))" "$fake_mutations")"
[[ "$partial_added" != *'delete-asset:'* ]] ||
    fail 'publisher replaced a matching partial-draft asset'
[[ "$(jq '.releases[0].draft' "$fake_state")" == false ]] ||
    fail 'partial draft was not published'

initialize_fake_api mismatch
seed_release v1.1.0 "$main_sha" true
wrong_release_id="$(jq -r '.releases[0].id' "$fake_state")"
wrong_directory="$test_root/wrong"
mkdir -p "$wrong_directory"
printf 'wrong documentation bytes\n' \
    > "$wrong_directory/swiftql-docc-v1.1.0.tar.gz"
fake_api_command upload-asset "$wrong_release_id" \
    "$wrong_directory/swiftql-docc-v1.1.0.tar.gz" > /dev/null
run_publisher v1.1.0 v1.1.0 "$main_sha" "$assets_a" > /dev/null
grep -F 'delete-asset:' "$fake_mutations" > /dev/null ||
    fail 'publisher did not replace a mismatched draft asset'

# A draft with an unrelated asset fails before the publisher mutates it.
initialize_fake_api unexpected
seed_release v1.1.0 "$main_sha" true
unexpected_release_id="$(jq -r '.releases[0].id' "$fake_state")"
printf 'unexpected\n' > "$test_root/unexpected.txt"
fake_api_command upload-asset "$unexpected_release_id" \
    "$test_root/unexpected.txt" > /dev/null
unexpected_baseline="$(wc -l < "$fake_mutations" | tr -d '[:space:]')"
expect_failure run_publisher v1.1.0 v1.1.0 "$main_sha" "$assets_a"
[[ "$(wc -l < "$fake_mutations" | tr -d '[:space:]')" == "$unexpected_baseline" ]] ||
    fail 'publisher mutated a draft containing an unexpected asset'

# An unrelated release is preserved. A conflicting published release fails
# closed without a new mutation.
initialize_fake_api unrelated
seed_release v9.9.9 "$main_sha" true
unrelated_id="$(jq -r '.releases[0].id' "$fake_state")"
run_publisher v1.1.0 v1.1.0 "$main_sha" "$assets_a" > /dev/null
[[ "$(jq '.releases | length' "$fake_state")" -eq 2 ]] ||
    fail 'publisher removed or reused an unrelated release'
[[ "$(jq --argjson id "$unrelated_id" \
    '[.releases[] | select(.id == $id)] | length' "$fake_state")" -eq 1 ]] ||
    fail 'publisher mutated unrelated release identity'

initialize_fake_api conflict
seed_release v1.1.0 0000000000000000000000000000000000000000 false
conflict_baseline="$(wc -l < "$fake_mutations" | tr -d '[:space:]')"
expect_failure run_publisher v1.1.0 v1.1.0 "$main_sha" "$assets_a"
[[ "$(wc -l < "$fake_mutations" | tr -d '[:space:]')" == "$conflict_baseline" ]] ||
    fail 'conflicting published release was mutated'

printf 'SWIFTQL_RELEASE_WORKFLOW_TESTS ok\n'
