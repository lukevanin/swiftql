#!/bin/bash

set -euo pipefail

script_directory="$(cd "$(dirname "$0")" && pwd -P)"
verify_documentation="$script_directory/verify-release-documentation.sh"

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

github_release_api() {
    local operation="$1"
    shift
    local gh_bin="${SWIFTQL_GH_BIN:-gh}"
    local api_version='X-GitHub-Api-Version: 2026-03-10'

    case "$operation" in
        list-releases)
            "$gh_bin" api \
                --paginate \
                -H 'Accept: application/vnd.github+json' \
                -H "$api_version" \
                "repos/$repository/releases?per_page=100" |
                jq -s 'add // []'
            ;;
        create-release)
            "$gh_bin" api \
                --method POST \
                -H 'Accept: application/vnd.github+json' \
                -H "$api_version" \
                "repos/$repository/releases" \
                --input "$1"
            ;;
        list-assets)
            "$gh_bin" api \
                --paginate \
                -H 'Accept: application/vnd.github+json' \
                -H "$api_version" \
                "repos/$repository/releases/$1/assets?per_page=100" |
                jq -s 'add // []'
            ;;
        get-release)
            "$gh_bin" api \
                -H 'Accept: application/vnd.github+json' \
                -H "$api_version" \
                "repos/$repository/releases/$1"
            ;;
        delete-asset)
            "$gh_bin" api \
                --method DELETE \
                -H 'Accept: application/vnd.github+json' \
                -H "$api_version" \
                "repos/$repository/releases/assets/$1"
            ;;
        upload-asset)
            local release_id="$1"
            local asset_path="$2"
            local encoded_name
            local token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"

            [[ -n "$token" ]] || fail 'GH_TOKEN or GITHUB_TOKEN is required to upload assets'
            encoded_name="$(jq -rn --arg value "$(basename "$asset_path")" \
                '$value | @uri')"
            curl \
                --fail-with-body \
                --silent \
                --show-error \
                --request POST \
                --header 'Accept: application/vnd.github+json' \
                --header 'Content-Type: application/octet-stream' \
                --header "Authorization: Bearer $token" \
                --header "$api_version" \
                --data-binary "@$asset_path" \
                "https://uploads.github.com/repos/$repository/releases/$release_id/assets?name=$encoded_name"
            ;;
        update-release)
            "$gh_bin" api \
                --method PATCH \
                -H 'Accept: application/vnd.github+json' \
                -H "$api_version" \
                "repos/$repository/releases/$1" \
                --input "$2"
            ;;
        download-asset)
            "$gh_bin" api \
                --method GET \
                -H 'Accept: application/octet-stream' \
                -H "$api_version" \
                "repos/$repository/releases/assets/$1"
            ;;
        *)
            fail "unknown release API operation: $operation"
            ;;
    esac
}

release_api() {
    if [[ -n "${SWIFTQL_RELEASE_API:-}" ]]; then
        "$SWIFTQL_RELEASE_API" "$@"
    else
        github_release_api "$@"
    fi
}

asset_record() {
    local assets_json="$1"
    local asset_name="$2"
    local count

    count="$(jq --arg name "$asset_name" \
        '[.[] | select(.name == $name)] | length' <<< "$assets_json")"
    if [[ "$count" -ne 1 ]]; then
        fail "expected exactly one release asset named $asset_name; found $count"
    fi
    jq -c --arg name "$asset_name" \
        '.[] | select(.name == $name)' <<< "$assets_json"
}

verify_local_assets() {
    local docs_sha256
    local manifest_sha256
    local expected_checksums

    for asset_path in "$docs_path" "$manifest_path" "$checksums_path"; do
        if [[ ! -s "$asset_path" || -L "$asset_path" ]]; then
            fail "release asset is missing, empty, or unsafe: $asset_path"
        fi
    done

    docs_sha256="$(sha256_file "$docs_path")"
    manifest_sha256="$(sha256_file "$manifest_path")"
    "$verify_documentation" \
        "$docs_path" "$manifest_path" "$release_tag" \
        "$source_tag" "$commit_sha" "$repository" > /dev/null

    expected_checksums="$(
        printf '%s  %s\n' "$docs_sha256" "$docs_name"
        printf '%s  %s\n' "$manifest_sha256" "$manifest_name"
    )"
    if [[ "$(cat "$checksums_path")" != "$expected_checksums" ]]; then
        fail 'SHA256SUMS does not match the local release assets'
    fi
}

validate_release_record() {
    local release_json="$1"
    local actual_tag
    local prerelease
    local body

    release_id="$(jq -er '.id | select(type == "number")' <<< "$release_json")" ||
        fail 'release response has no numeric ID'
    actual_tag="$(jq -er '.tag_name | select(type == "string")' <<< "$release_json")" ||
        fail 'release response has no tag name'
    if ! jq -e \
        'has("prerelease") and (.prerelease | type == "boolean") and
         has("draft") and (.draft | type == "boolean")' \
        <<< "$release_json" > /dev/null; then
        fail 'release response has no boolean prerelease/draft state'
    fi
    prerelease="$(jq -r '.prerelease' <<< "$release_json")"
    release_draft="$(jq -r '.draft' <<< "$release_json")"
    body="$(jq -er '.body | select(type == "string")' <<< "$release_json")" ||
        fail 'release response has no body'

    if [[ "$actual_tag" != "$release_tag" ]]; then
        fail "release API returned unrelated tag $actual_tag for $release_tag"
    fi
    if [[ "$prerelease" != false ]]; then
        fail "release $release_tag is unexpectedly a prerelease"
    fi
    if [[ "$body" != *"$release_marker"* ]]; then
        fail "release $release_tag does not contain the exact commit marker"
    fi
    if [[ "$body" != *"## What's Changed"* &&
          "$body" != *"**Full Changelog**"* ]]; then
        fail "release $release_tag does not contain generated release notes"
    fi
}

wait_for_immutable_release() {
    local release_json="$1"
    local expected_release_id="$release_id"
    local attempts="${SWIFTQL_IMMUTABLE_ATTEMPTS:-12}"
    local interval="${SWIFTQL_IMMUTABLE_INTERVAL_SECONDS:-5}"
    local attempt

    [[ "$attempts" =~ ^[1-9][0-9]*$ ]] || fail 'immutable poll attempts must be positive'
    [[ "$interval" =~ ^[0-9]+$ ]] || fail 'immutable poll interval must be nonnegative'
    for ((attempt = 1; attempt <= attempts; attempt += 1)); do
        validate_release_record "$release_json"
        [[ "$release_id" == "$expected_release_id" ]] ||
            fail "immutable poll returned unrelated release ID $release_id"
        if [[ "$release_draft" == false &&
              "$(jq -r '.immutable // false' <<< "$release_json")" == true ]]; then
            printf '%s\n' "$release_json"
            return 0
        fi
        if [[ "$attempt" -lt "$attempts" ]]; then
            sleep "$interval"
            release_json="$(release_api get-release "$expected_release_id")"
        fi
    done
    fail "published release $release_tag did not become immutable"
}

run_pre_publish_check() {
    if [[ -n "${SWIFTQL_PRE_PUBLISH_CHECK:-}" ]]; then
        "$SWIFTQL_PRE_PUBLISH_CHECK" pre-publish-check \
            "$source_tag" "$release_tag" "$commit_sha"
    else
        "$script_directory/pre-publish-release-check.sh" \
            "$source_tag" "$release_tag" "$commit_sha"
    fi
}

verify_remote_published_assets() {
    local release_json="$1"
    local assets_json
    local actual_names
    local expected_names
    local docs_record
    local manifest_record
    local checksums_record
    local remote_manifest
    local remote_checksums
    local remote_docs
    local docs_digest
    local manifest_digest
    local checksums_digest
    local expected_checksums
    local body

    assets_json="$(release_api list-assets "$release_id")"
    if ! jq -e 'type == "array"' <<< "$assets_json" > /dev/null; then
        fail 'release asset response is not an array'
    fi
    actual_names="$(jq -c '[.[].name] | sort' <<< "$assets_json")"
    expected_names="$(jq -cn \
        --arg docs "$docs_name" \
        --arg manifest "$manifest_name" \
        --arg checksums "$checksums_name" \
        '[$docs, $manifest, $checksums] | sort')"
    if [[ "$actual_names" != "$expected_names" ]]; then
        fail "published release has an unexpected asset set: $actual_names"
    fi

    docs_record="$(asset_record "$assets_json" "$docs_name")"
    manifest_record="$(asset_record "$assets_json" "$manifest_name")"
    checksums_record="$(asset_record "$assets_json" "$checksums_name")"
    for record in "$docs_record" "$manifest_record" "$checksums_record"; do
        if ! jq -e \
            '.state == "uploaded" and
             (.digest | type == "string" and test("^sha256:[0-9a-f]{64}$"))' \
            <<< "$record" > /dev/null; then
            fail 'published release contains an incomplete asset or invalid digest'
        fi
    done

    remote_manifest="$temporary_directory/remote-manifest.json"
    remote_checksums="$temporary_directory/remote-SHA256SUMS"
    remote_docs="$temporary_directory/$docs_name"
    release_api download-asset "$(jq -r '.id' <<< "$docs_record")" > "$remote_docs"
    release_api download-asset "$(jq -r '.id' <<< "$manifest_record")" > "$remote_manifest"
    release_api download-asset "$(jq -r '.id' <<< "$checksums_record")" > "$remote_checksums"
    if [[ ! -s "$remote_docs" || ! -s "$remote_manifest" ||
          ! -s "$remote_checksums" ]]; then
        fail 'published provenance assets could not be downloaded'
    fi

    docs_digest="$(jq -r '.digest' <<< "$docs_record")"
    manifest_digest="$(jq -r '.digest' <<< "$manifest_record")"
    checksums_digest="$(jq -r '.digest' <<< "$checksums_record")"
    docs_digest="${docs_digest#sha256:}"
    manifest_digest="${manifest_digest#sha256:}"
    checksums_digest="${checksums_digest#sha256:}"
    if [[ "$(sha256_file "$remote_docs")" != "$docs_digest" ]]; then
        fail 'published documentation bytes do not match the API digest'
    fi
    if [[ "$(sha256_file "$remote_manifest")" != "$manifest_digest" ]]; then
        fail 'published manifest bytes do not match the API digest'
    fi
    if [[ "$(sha256_file "$remote_checksums")" != "$checksums_digest" ]]; then
        fail 'published SHA256SUMS bytes do not match the API digest'
    fi
    "$verify_documentation" \
        "$remote_docs" "$remote_manifest" "$release_tag" \
        "$release_tag" "$commit_sha" "$repository" > /dev/null
    expected_checksums="$(
        printf '%s  %s\n' "$docs_digest" "$docs_name"
        printf '%s  %s\n' "$manifest_digest" "$manifest_name"
    )"
    if [[ "$(cat "$remote_checksums")" != "$expected_checksums" ]]; then
        fail 'published SHA256SUMS does not match the published asset digests'
    fi

    body="$(jq -r '.body' <<< "$release_json")"
    [[ "$body" == *"$release_marker"* ]] ||
        fail 'published release body lost its exact commit marker'
}

plan_or_sync_draft_assets() {
    local assets_json
    local unexpected_names
    local asset_path
    local asset_name
    local matches
    local count
    local record
    local local_digest
    local remote_digest
    local asset_id

    assets_json="$(release_api list-assets "$release_id")"
    if ! jq -e 'type == "array"' <<< "$assets_json" > /dev/null; then
        fail 'draft release asset response is not an array'
    fi
    unexpected_names="$(jq -c \
        --arg docs "$docs_name" \
        --arg manifest "$manifest_name" \
        --arg checksums "$checksums_name" \
        '[.[].name | select(. != $docs and . != $manifest and . != $checksums)] |
         unique | sort' <<< "$assets_json")"
    if [[ "$unexpected_names" != '[]' ]]; then
        fail "draft release has unexpected assets: $unexpected_names"
    fi

    for asset_path in "$docs_path" "$manifest_path" "$checksums_path"; do
        asset_name="$(basename "$asset_path")"
        local_digest="sha256:$(sha256_file "$asset_path")"
        matches="$(jq -c --arg name "$asset_name" \
            '[.[] | select(.name == $name)]' <<< "$assets_json")"
        count="$(jq 'length' <<< "$matches")"
        if [[ "$count" -gt 1 ]]; then
            fail "draft release contains duplicate assets named $asset_name"
        fi
        if [[ "$count" -eq 0 ]]; then
            if [[ "$dry_run" == true ]]; then
                printf 'DRY-RUN would upload %s\n' "$asset_name"
            else
                release_api upload-asset "$release_id" "$asset_path"
            fi
            continue
        fi

        record="$(jq -c '.[0]' <<< "$matches")"
        remote_digest="$(jq -r '.digest // ""' <<< "$record")"
        if [[ "$(jq -r '.state // ""' <<< "$record")" == uploaded &&
              "$remote_digest" == "$local_digest" ]]; then
            printf 'Keeping matching draft asset %s\n' "$asset_name"
            continue
        fi

        asset_id="$(jq -er '.id | select(type == "number")' <<< "$record")" ||
            fail "draft asset has no numeric ID: $asset_name"
        if [[ "$dry_run" == true ]]; then
            printf 'DRY-RUN would replace %s (asset %s)\n' "$asset_name" "$asset_id"
        else
            release_api delete-asset "$asset_id"
            release_api upload-asset "$release_id" "$asset_path"
        fi
    done

    if [[ "$dry_run" == false ]]; then
        assets_json="$(release_api list-assets "$release_id")"
        for asset_path in "$docs_path" "$manifest_path" "$checksums_path"; do
            asset_name="$(basename "$asset_path")"
            record="$(asset_record "$assets_json" "$asset_name")"
            local_digest="sha256:$(sha256_file "$asset_path")"
            if ! jq -e --arg digest "$local_digest" \
                '.state == "uploaded" and .digest == $digest' \
                <<< "$record" > /dev/null; then
                fail "uploaded draft asset does not match local bytes: $asset_name"
            fi
        done
    fi
}

dry_run=false
if [[ "${1:-}" == --dry-run ]]; then
    dry_run=true
    shift
fi
if [[ "$#" -ne 4 ]]; then
    printf 'usage: %s [--dry-run] SOURCE_TAG RELEASE_TAG COMMIT_SHA ASSET_DIRECTORY\n' "$0" >&2
    exit 64
fi

source_tag="$1"
release_tag="$2"
commit_sha="$3"
asset_directory="$4"
repository="${GITHUB_REPOSITORY:?Set GITHUB_REPOSITORY}"

if [[ ! "$release_tag" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    fail "invalid release tag: $release_tag"
fi
if [[ "$dry_run" == true ]]; then
    [[ "$source_tag" == "release-test/$release_tag" ]] ||
        fail "dry-run source tag does not match release tag: $source_tag"
elif [[ "$source_tag" != "$release_tag" ]]; then
    fail "publication source tag does not match release tag: $source_tag"
fi
if [[ ! "$commit_sha" =~ ^[0-9a-f]{40}$ ]]; then
    fail "commit SHA is not a lowercase full object ID: $commit_sha"
fi
if [[ ! "$repository" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
    fail "invalid repository name: $repository"
fi

docs_name="swiftql-docc-$release_tag.tar.gz"
manifest_name="swiftql-release-$release_tag.json"
checksums_name='SHA256SUMS'
docs_path="$asset_directory/$docs_name"
manifest_path="$asset_directory/$manifest_name"
checksums_path="$asset_directory/$checksums_name"
release_marker="<!-- swiftql-release-sha: $commit_sha -->"
temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/swiftql-publish-release.XXXXXX")"
trap 'rm -rf "$temporary_directory"' EXIT

verify_local_assets
run_id="$(jq -er '.run_id | select(type == "string")' "$manifest_path")" ||
    fail 'release manifest has no run ID'
server_url="${GITHUB_SERVER_URL:-https://github.com}"
release_body_prefix="$(printf \
    'Verified commit: [`%s`](%s/%s/commit/%s)\n\nValidation run: [%s](%s/%s/actions/runs/%s)\n\n%s\n' \
    "$commit_sha" "$server_url" "$repository" "$commit_sha" \
    "$run_id" "$server_url" "$repository" "$run_id" "$release_marker")"

releases_json="$(release_api list-releases)"
if ! jq -e 'type == "array"' <<< "$releases_json" > /dev/null; then
    fail 'release API response is not an array'
fi
matching_releases="$(jq -c --arg tag "$release_tag" \
    '[.[] | select(.tag_name == $tag)]' <<< "$releases_json")"
release_count="$(jq 'length' <<< "$matching_releases")"
if [[ "$release_count" -gt 1 ]]; then
    fail "multiple releases unexpectedly use tag $release_tag"
fi

if [[ "$release_count" -eq 0 ]]; then
    if [[ "$dry_run" == true ]]; then
        printf 'DRY-RUN would create draft release %s at %s\n' \
            "$release_tag" "$commit_sha"
        printf 'DRY-RUN would upload %s, %s, and %s\n' \
            "$docs_name" "$manifest_name" "$checksums_name"
        printf 'DRY-RUN would publish and verify %s\n' "$release_tag"
        printf 'SWIFTQL_RELEASE_DRY_RUN ok %s %s\n' "$release_tag" "$commit_sha"
        exit 0
    fi

    create_payload="$temporary_directory/create-release.json"
    jq -n \
        --arg tag_name "$release_tag" \
        --arg target_commitish "$commit_sha" \
        --arg name "$release_tag" \
        --arg body "$release_body_prefix" \
        '{
            tag_name: $tag_name,
            target_commitish: $target_commitish,
            name: $name,
            body: $body,
            draft: true,
            prerelease: false,
            generate_release_notes: true
        }' > "$create_payload"
    release_json="$(release_api create-release "$create_payload")"
else
    release_json="$(jq -c '.[0]' <<< "$matching_releases")"
fi

validate_release_record "$release_json"
if [[ "$release_draft" == false ]]; then
    release_json="$(wait_for_immutable_release "$release_json")"
    verify_remote_published_assets "$release_json"
    printf 'SWIFTQL_RELEASE_PUBLISHED ok %s %s release=%s\n' \
        "$release_tag" "$commit_sha" "$release_id"
    exit 0
fi
if [[ "$(jq -r '.immutable // false' <<< "$release_json")" == true ]]; then
    fail "draft release $release_tag is unexpectedly immutable"
fi

plan_or_sync_draft_assets
if [[ "$dry_run" == true ]]; then
    printf 'DRY-RUN would publish and verify draft release %s\n' "$release_tag"
    printf 'SWIFTQL_RELEASE_DRY_RUN ok %s %s\n' "$release_tag" "$commit_sha"
    exit 0
fi

update_payload="$temporary_directory/publish-release.json"
jq -n '{draft: false, prerelease: false, make_latest: "legacy"}' > "$update_payload"
run_pre_publish_check
release_json="$(release_api update-release "$release_id" "$update_payload")"
validate_release_record "$release_json"
if [[ "$release_draft" != false ]]; then
    fail "release $release_tag remained a draft after publication"
fi
release_json="$(wait_for_immutable_release "$release_json")"
verify_remote_published_assets "$release_json"

printf 'SWIFTQL_RELEASE_PUBLISHED ok %s %s release=%s\n' \
    "$release_tag" "$commit_sha" "$release_id"
