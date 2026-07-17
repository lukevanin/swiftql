#!/bin/bash

set -euo pipefail

script_directory="$(cd "$(dirname "$0")" && pwd -P)"
check_ref="$script_directory/check-release-ref.sh"
check_readiness="$script_directory/check-release-readiness.sh"
prepare_assets="$script_directory/prepare-release-assets.sh"
publish_release="$script_directory/publish-release.sh"

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
            jq --argjson release_id "$release_id" --slurpfile payload "$payload" \
                '.releases |= map(
                    if .id == $release_id then . + $payload[0] else . end
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
    list-releases|create-release|list-assets|delete-asset|upload-asset|update-release|download-asset)
        : "${SWIFTQL_FAKE_RELEASE_STATE:?Set SWIFTQL_FAKE_RELEASE_STATE}"
        : "${SWIFTQL_FAKE_MUTATIONS:?Set SWIFTQL_FAKE_MUTATIONS}"
        : "${SWIFTQL_FAKE_ASSETS:?Set SWIFTQL_FAKE_ASSETS}"
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
    mkdir -p "$fake_assets"
    printf '%s\n' \
        '{"next_release_id":100,"next_asset_id":1000,"releases":[]}' \
        > "$fake_state"
    : > "$fake_mutations"
}

run_publisher() {
    env \
        GITHUB_REPOSITORY=lukevanin/swiftql \
        GITHUB_SERVER_URL=https://github.com \
        SWIFTQL_RELEASE_API="$0" \
        SWIFTQL_FAKE_RELEASE_STATE="$fake_state" \
        SWIFTQL_FAKE_MUTATIONS="$fake_mutations" \
        SWIFTQL_FAKE_ASSETS="$fake_assets" \
        "$publish_release" "$@"
}

fake_api_command() {
    env \
        SWIFTQL_FAKE_RELEASE_STATE="$fake_state" \
        SWIFTQL_FAKE_MUTATIONS="$fake_mutations" \
        SWIFTQL_FAKE_ASSETS="$fake_assets" \
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

test_root="$(mktemp -d "${TMPDIR:-/tmp}/swiftql-release-tests.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT

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
git -C "$git_root" tag v1.1.0
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
    expect_failure \
        "$check_ref" release-test/v1.1.998 "$unreachable_sha" refs/heads/main
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
tar -cf "$pages_tar" -C "$site" .
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

dry_site="$test_root/dry-site"
cp -R "$site" "$dry_site"
jq \
    '.source_ref = "refs/tags/release-test/v1.1.0" |
     .source_ref_name = "release-test/v1.1.0"' \
    "$dry_site/swiftql-pages-provenance.json" > "$test_root/dry-provenance.json"
mv "$test_root/dry-provenance.json" \
    "$dry_site/swiftql-pages-provenance.json"
dry_pages_tar="$test_root/dry-artifact.tar"
tar -cf "$dry_pages_tar" -C "$dry_site" .
assets_dry="$test_root/assets-dry"
"$prepare_assets" \
    "$dry_pages_tar" "$assets_dry" v1.1.0 "$main_sha" \
    12345 1 lukevanin/swiftql release-test/v1.1.0 > /dev/null

bad_site="$test_root/bad-site"
cp -R "$site" "$bad_site"
jq '.commit_sha = "0000000000000000000000000000000000000000"' \
    "$bad_site/swiftql-pages-provenance.json" > "$test_root/bad-provenance.json"
mv "$test_root/bad-provenance.json" \
    "$bad_site/swiftql-pages-provenance.json"
tar -cf "$test_root/bad-artifact.tar" -C "$bad_site" .
expect_failure "$prepare_assets" \
    "$test_root/bad-artifact.tar" "$test_root/bad-assets" \
    v1.1.0 "$main_sha" 12345 1 lukevanin/swiftql v1.1.0

unsafe_site="$test_root/unsafe-site"
cp -R "$site" "$unsafe_site"
ln -s /tmp "$unsafe_site/unsafe-link"
tar -cf "$test_root/unsafe-artifact.tar" -C "$unsafe_site" .
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

# First publication creates one draft, uploads three assets, publishes it, and
# a rerun verifies that exact published state without another mutation.
initialize_fake_api publish
run_publisher v1.1.0 v1.1.0 "$main_sha" "$assets_a" > /dev/null
[[ "$(jq '.releases | length' "$fake_state")" -eq 1 ]] ||
    fail 'publisher did not create exactly one release'
[[ "$(jq '.releases[0].draft' "$fake_state")" == false ]] ||
    fail 'publisher did not publish its draft'
[[ "$(jq '.releases[0].assets | length' "$fake_state")" -eq 3 ]] ||
    fail 'publisher did not upload exactly three assets'
mutation_count="$(wc -l < "$fake_mutations" | tr -d '[:space:]')"
run_publisher v1.1.0 v1.1.0 "$main_sha" "$assets_a" > /dev/null
[[ "$(wc -l < "$fake_mutations" | tr -d '[:space:]')" == "$mutation_count" ]] ||
    fail 'published rerun performed a mutation'

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
