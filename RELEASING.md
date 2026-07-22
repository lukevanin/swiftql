# Releasing SwiftQL

SwiftQL releases use `vMAJOR.MINOR.PATCH` tags beginning with `v1.1.0`. This
guide states the procedure once, version-neutrally. Read `vX.Y.Z` as the
version being released and substitute it everywhere; the shell snippets use
`$release_tag`, `$release_sha`, and `$milestone_title` so they can be pasted
without editing.

The historical `1.0.0` tag and release, and every already-published `v...`
release, are immutable. A new release never rewrites them.

The [Verified release workflow](.github/workflows/release.yml) treats a tag as
an untrusted request. It publishes only after it has proved that the exact tag
commit is still reachable from `main`, run the seven-cell Swift compatibility
matrix, and built the exact commit's validated DocC artifact.

## Before a release

1. Merge every retained issue for the version, complete that milestone's audit
   work, and close the milestone with no open issues. Verify the live
   milestone rather than a local planning file. Milestone titles are not
   mechanically derivable from the tag. A minor release is usually tracked by
   a `vX.Y` milestone, and a patch release by its own `vX.Y.Z` milestone, so
   name the milestone explicitly and resolve it by title:

   ```sh
   release_tag=vX.Y.Z
   # Set this to the milestone that actually tracks the release: vX.Y when
   # the line shares one milestone, vX.Y.Z when the patch has its own.
   milestone_title=MILESTONE_TITLE

   gh api --paginate \
     -H 'Accept: application/vnd.github+json' \
     -H 'X-GitHub-Api-Version: 2026-03-10' \
     'repos/lukevanin/swiftql/milestones?state=all&per_page=100' |
     jq -se --arg title "$milestone_title" '
       [.[][] | select(.title == $title)] as $matches |
       ($matches | length) == 1 and
       $matches[0].state == "closed" and
       $matches[0].open_issues == 0'
   ```

   `scripts/ci/check-release-readiness.sh` retains the historical one-time
   server-side gate for `v1.1.0` and deliberately skips every later version.
   It is not proof that any later milestone is ready; a maintainer with an
   authenticated token owns the live milestone check above. Preserve its
   output and the milestone audit evidence in the release issue.

   A release-readiness audit document under
   [`Documentation/ReleaseAudits/`](Documentation/ReleaseAudits) is required
   when the milestone's audit issue belongs to the version being released.
   That is the case for a minor or major release: `vX.Y.0` must produce a
   checked-in `Documentation/ReleaseAudits/vX.Y.md` recording the pre-tag
   verdict and evidence, as
   [`v1.2.md`](Documentation/ReleaseAudits/v1.2.md) and
   [`v1.3.md`](Documentation/ReleaseAudits/v1.3.md) do. A patch release inside
   a line whose audit issue is deliberately scheduled at the end of that line
   produces no audit document of its own. The v1.4 line schedules audit issue
   [#229](https://github.com/lukevanin/swiftql/issues/229) in the `v1.4.6`
   milestone, so `v1.4.1` through `v1.4.5` have none. The live milestone check
   and the per-release evidence recorded in the release issue are still
   required in that case; only the checked-in audit document is deferred.
2. Confirm the latest `main` runs of **Swift compatibility** and
   **Documentation** pass. The compatibility run must contain all seven
   release-blocking compiler cells: committed and clean resolution for each of
   the pinned Swift 5.9 and Swift 6.0 support points, plus clean resolution for
   Swift 6.1, 6.2, and 6.3. Verify the deployed documentation provenance names
   that `main` commit.
3. Run `scripts/ci/test-release-workflow.sh` locally. This exercises the tag,
   reachability, packaging, dry-run, partial-draft, rerun, and conflict paths
   without calling GitHub's write APIs.
4. Run the safe test tags below while the changelog still says `Unreleased`.
   `scripts/ci/check-release-changelog.sh` skips `release-test/` tags outright,
   so the dry runs neither need nor exercise the dated heading.

   After they pass, date the heading for the version, replacing
   `## [X.Y.Z] - Unreleased` with exactly `## [X.Y.Z] - YYYY-MM-DD`. Production
   tags fail before the compiler matrix unless that heading is present on the
   *tagged* commit, which the script reads directly rather than reading
   `main`'s tip. When the release commit is `main`'s tip, merge that
   release-preparation change to `main` and tag the tip. When it is not, put
   the dated heading on the preparation branch instead and follow "Releasing a
   commit that is not at `main`'s tip" below.
5. In repository settings, enable immutable releases. Verify it out of band
   with an administrator token immediately before tagging; HTTP success alone
   is insufficient because the endpoint also returns 200 while disabled:

   ```sh
   gh api \
     -H 'Accept: application/vnd.github+json' \
     -H 'X-GitHub-Api-Version: 2026-03-10' \
     repos/lukevanin/swiftql/immutable-releases |
     jq -e '.enabled == true'
   ```

   The release workflow deliberately has no Administration permission and
   cannot perform this pre-publication settings check. It polls the published
   release and refuses to report success unless `immutable` becomes `true`.
6. Create the active repository tag ruleset
   `Protect v-prefixed release tags`. It must include `refs/tags/v*`, restrict
   updates and deletions, and have no bypass actors. Verify its full rule record
   out of band; the summary list alone does not show all conditions and rules.

   Its exact REST representation is:

   ```json
   {
     "name": "Protect v-prefixed release tags",
     "target": "tag",
     "enforcement": "active",
     "bypass_actors": [],
     "conditions": {
       "ref_name": {
         "include": ["refs/tags/v*"],
         "exclude": []
       }
     },
     "rules": [
       {"type": "deletion"},
       {"type": "update"}
     ]
   }
   ```

   Require exactly one repository-owned match and exactly those two rules:

   ```sh
   rulesets="$(gh api \
     -H 'Accept: application/vnd.github+json' \
     -H 'X-GitHub-Api-Version: 2026-03-10' \
     repos/lukevanin/swiftql/rulesets)"
   test "$(jq '[.[] | select(
     .name == "Protect v-prefixed release tags" and
     .source == "lukevanin/swiftql"
   )] | length' <<< "$rulesets")" -eq 1
   ruleset_id="$(jq -er '.[] | select(
     .name == "Protect v-prefixed release tags" and
     .source == "lukevanin/swiftql"
   ) | .id' <<< "$rulesets")"
   gh api \
     -H 'Accept: application/vnd.github+json' \
     -H 'X-GitHub-Api-Version: 2026-03-10' \
     "repos/lukevanin/swiftql/rulesets/$ruleset_id" |
     jq -e '
       .name == "Protect v-prefixed release tags" and
       .source == "lukevanin/swiftql" and
       .target == "tag" and .enforcement == "active" and
       .current_user_can_bypass == "never" and
       (.conditions.ref_name.include == ["refs/tags/v*"]) and
       (.conditions.ref_name.exclude == []) and
       ([.rules[].type] | sort) == ["deletion", "update"] and
       (.bypass_actors | length) == 0'
   ```

   The ruleset is recorded with id `19095830`. This server-side rule closes the
   otherwise unavoidable network-sized race between the workflow's last tag
   check and release publication. Do not prove the rule with a disposable `v...`
   tag: the rule intentionally prevents that tag from being deleted. Its first
   end-to-end proof was the historical `v1.1.0` tag; verify that the same rule
   remains active before every later release.
7. Record the exact remote commit. Do not release from an unpushed local commit.

```sh
git fetch origin main --tags
release_sha="$(git rev-parse origin/main)"
git merge-base --is-ancestor "$release_sha" origin/main
```

## Releasing a commit that is not at `main`'s tip

The changelog gate requires the *tagged commit* to carry a dated
`## [X.Y.Z] - YYYY-MM-DD` heading. By the time a patch release is prepared,
`main` may already carry later work that does not belong to that version, so
tagging `main`'s tip would ship more than the version claims.

`scripts/ci/check-release-ref.sh` does not require the tag to be `main`'s tip.
It requires only `git merge-base --is-ancestor "$tag_commit" "$main_commit"`,
so any commit still reachable from `main` qualifies. Use that:

1. Branch from the last commit belonging to that version's milestone.
2. On that branch, add the dated `## [X.Y.Z] - YYYY-MM-DD` changelog section.
3. Merge the branch into `main` **with a merge commit**.
4. Record that branch commit as `$release_sha` and tag it.

```sh
git fetch origin main --tags
release_tag=vX.Y.Z

# While the preparation branch still exists. Fetch it explicitly: the fetch
# above updates only origin/main and the tags.
git fetch origin release/vX.Y.Z-changelog
release_sha="$(git rev-parse origin/release/vX.Y.Z-changelog)"

# Or, once it has been deleted, from the preparation PR's merge commit. The
# second parent of a merge commit is the tip of the branch that was merged:
merge_sha=MERGE_COMMIT_SHA
release_sha="$(git rev-parse "$merge_sha^2")"

git merge-base --is-ancestor "$release_sha" origin/main
```

Deleting the preparation branch after the merge is safe. The commit stays
reachable from `main` through the merge commit, so the reachability gate still
passes; only the branch ref goes away, which is why the second form above
recovers the SHA from the merge commit instead.

A merge commit is mandatory. A squash merge or a rebase merge rewrites the
branch's commits into new objects on `main` and orphans the commit the tag
points at. The orphaned commit is no longer reachable from `main`, so
`check-release-ref.sh` fails the reachability gate and the release cannot be
published. Confirm the merge method before merging the preparation PR.

`v1.4.1` is the worked precedent. PR
[#333](https://github.com/lukevanin/swiftql/pull/333) branches
`release/v1.4.1-changelog` from the last v1.4.1 milestone commit and adds only
the dated changelog section. Merging it into `main` with a merge commit keeps
that branch commit reachable, so `v1.4.1` can be tagged there while `main`
already carries later work.

## Safe test tags

Tags below `release-test/` run the real compiler and documentation workflows,
prepare the real release assets, and call the publisher with a read-only token.
They can never enter the write-capable publication job.

Run these one at a time after the release workflow has landed on `main`:

- `release-test/vX.Y.999` at the recorded release commit must pass through the
  dry-run job and create no GitHub Release.
- `release-test/not-semver` must fail tag validation before compiler or
  documentation jobs start.
- A valid test tag such as `release-test/vX.Y.998` on a temporary commit that is
  not reachable from `main` must fail the reachability gate.

After recording the workflow URLs and confirming that no release was created,
delete only the temporary test tags and branch. Tag-deletion events are skipped
by the workflow. Never use a production `v...` tag for a dry run.

## Publishing

Create one annotated tag at the recorded release commit and push only that tag:

```sh
git tag -a "$release_tag" "$release_sha" -m "SwiftQL $release_tag"
git push origin "refs/tags/$release_tag"
```

The release workflow:

1. validates and peels the event SHA and tag ref;
2. proves the commit is reachable from current `origin/main`;
3. invokes the reusable compatibility workflow and requires all seven compiler
   cells;
4. invokes the reusable documentation workflow without deploying Pages;
5. packages the Pages tar as `swiftql-docc-$release_tag.tar.gz` and creates
   `swiftql-release-$release_tag.json` plus `SHA256SUMS`;
6. creates a draft GitHub Release with generated notes and an exact commit/run
   marker;
7. uploads and verifies all three assets, then immediately refetches and
   revalidates the exact tag and `main` reachability before publication; the
   dated changelog was validated from that same exact tag commit in the initial
   validation job; the release issue owns the separate authenticated live
   milestone check, because the retained readiness script is intentionally
   v1.1-only and skips every later version;
8. publishes only a draft that already contains generated notes, polls until
   GitHub reports the release immutable, and reopens the DocC archive to verify
   its catalog pages and embedded provenance; and
9. rechecks the tag ref after publication.

The publisher looks up only the exact tag. A rerun resumes its draft, preserves
matching assets, replaces a mismatched asset only while the release is a draft,
and treats a matching published release as a read-only success. It never uses a
blind `--clobber`, edits another tag's release, or rewrites a published release.

## Verification and issue closure

Do not close the release issue when its workflow PR merges. After the tag run
succeeds, independently verify:

- the run event, ref, and head SHA match the release tag and recorded commit;
- all seven compatibility cells and the documentation build passed;
- the tag still peels to that commit and remains reachable from `main`;
- the release is published, is not a prerelease, and its generated notes contain
  the exact commit marker;
- the release API reports `immutable: true`, and the production tag ruleset is
  still active;
- GitHub verifies the immutable release attestation with
  `gh release verify "$release_tag" --repo lukevanin/swiftql`, and each
  downloaded asset passes
  `gh release verify-asset "$release_tag" PATH --repo lukevanin/swiftql`;
- the release has exactly the DocC archive, manifest, and checksum assets;
- API asset digests match `SHA256SUMS`, and the manifest maps the tag to the
  exact commit and workflow run; and
- the historical `1.0.0` tag and release and every previously published `v...`
  release are unchanged.

A milestone audit issue is pre-tag evidence, not proof that a release was
published. Before tagging, create or identify one dedicated release issue for
`vX.Y.Z` outside the closed milestone. Post the tag-run, release, asset,
attestation, and ruleset evidence there; close it only after every check above
passes. Re-fetch the issue to confirm closure. Do not reopen the audit issue or
the closed milestone merely to store post-tag evidence.

## Recovery

- **Invalid or unreachable test tag, before a release exists:** delete only the
  bad `release-test/...` tag, merge the correction to `main`, and create a fresh
  test tag. Test tags are outside the production tag ruleset.
- **Invalid or unreachable production tag, before a release exists:** never
  force-move the `v...` tag. Prefer abandoning that version and preparing a new
  version. If the exact version must be recovered, treat it as an audited admin
  incident: first prove that no release exists, temporarily alter or disable
  only the production tag ruleset, delete only that exact unpublished tag,
  immediately restore the ruleset, and repeat every ruleset verification in
  the preflight section before creating the corrected annotated tag. Record the
  incident and each verification result. Do not create the corrected tag while
  the ruleset is relaxed.
- **Draft creation or asset upload failed:** choose **Re-run all jobs** on the
  original tag run. GitHub retains that run's original ref and SHA, and the
  publisher resumes the exact draft. Re-running all jobs also regenerates an
  expired Pages artifact.
- **Publication completed but final verification timed out:** rerun the failed
  jobs. A complete published release is verified without mutation.
- **Published metadata or assets conflict:** the workflow fails closed. Do not
  delete, replace, or clobber them automatically. Review the release manually;
  if immutable releases are enabled, publish a corrected patch version instead.
- **Tag moved while validation was running:** the required tag ruleset should
  reject the move. The workflow also checks immediately before and after
  publication. If the ruleset was disabled or bypassed, a move in the residual
  network window can leave a release published even though the final job fails;
  stop and audit the tag and immutable release rather than force-moving either.
- **Release does not become immutable:** treat the run as failed even if GitHub
  already made the draft public. Do not mutate it. Verify the repository setting
  out of band, preserve the evidence, and use a corrected patch version if the
  release cannot be made trustworthy without rewriting published state.

Immutable releases and the production tag ruleset are mandatory prerequisites,
not optional hardening. The draft-first sequence lets GitHub lock the tag and
assets only after every asset has been uploaded and verified. The workflow
performs a bounded post-publication poll for immutable state; enabling the
setting affects only future releases and does not alter the historical `1.0.0`
tag or release.
