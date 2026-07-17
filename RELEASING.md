# Releasing SwiftQL

SwiftQL releases use `vMAJOR.MINOR.PATCH` tags beginning with `v1.1.0`. The
historical `1.0.0` tag and release are intentionally unchanged.

The [Verified release workflow](.github/workflows/release.yml) treats a tag as
an untrusted request. It publishes only after it has proved that the exact tag
commit is still reachable from `main`, run the complete Swift 5.9 and Swift 6.0
compatibility matrix, and built the exact commit's validated DocC artifact.

## Before a release

1. Merge every retained issue for the release. For `v1.1.0`, milestone 7 must
   have only tracking issue #118 and release issue #119 open. The workflow
   checks this before validation and again immediately before publication.
2. Confirm the latest `main` runs of **Swift compatibility** and
   **Documentation** pass. Verify the deployed documentation provenance names
   that `main` commit.
3. Run `scripts/ci/test-release-workflow.sh` locally. This exercises the tag,
   reachability, packaging, dry-run, partial-draft, rerun, and conflict paths
   without calling GitHub's write APIs.
4. Run the safe test tags below while the changelog still says `Unreleased`.
   After they pass, merge a final release-preparation change that replaces
   `## [X.Y.Z] - Unreleased` with exactly `## [X.Y.Z] - YYYY-MM-DD`. Production
   tags fail before the compiler matrix unless that dated heading is present.
5. In repository settings, enable immutable releases. Verify it out of band
   with an administrator token immediately before tagging; HTTP success alone
   is insufficient because the endpoint also returns 200 while disabled:

   ```sh
   gh api repos/lukevanin/swiftql/immutable-releases |
     jq -e '.enabled == true'
   ```

   The release workflow deliberately has no Administration permission and
   cannot perform this pre-publication settings check. It polls the published
   release and refuses to report success unless `immutable` becomes `true`.
6. Create the active repository tag ruleset
   `Protect v-prefixed release tags`. It must include `refs/tags/v*`, restrict
   updates and deletions, and have no bypass actors. Verify its full rule record
   out of band; the summary list alone does not show all conditions and rules:

   ```sh
   ruleset_id="$(gh api repos/lukevanin/swiftql/rulesets |
     jq -er '.[] | select(.name == "Protect v-prefixed release tags") | .id')"
   gh api "repos/lukevanin/swiftql/rulesets/$ruleset_id" |
     jq -e '
       .name == "Protect v-prefixed release tags" and
       .target == "tag" and .enforcement == "active" and
       .current_user_can_bypass == "never" and
       (.conditions.ref_name.include | index("refs/tags/v*")) != null and
       (.conditions.ref_name.exclude | length) == 0 and
       ([.rules[].type] | index("update")) != null and
       ([.rules[].type] | index("deletion")) != null and
       (.bypass_actors | length) == 0'
   ```

   This server-side rule closes the otherwise unavoidable network-sized race
   between the workflow's last tag check and release publication. Do not prove
   the rule with a disposable `v...` tag: the rule intentionally prevents that
   tag from being deleted. Its first end-to-end proof is the real `v1.1.0` tag.
7. Record the exact remote commit. Do not release from an unpushed local commit.

```sh
git fetch origin main --tags
release_sha="$(git rev-parse origin/main)"
git merge-base --is-ancestor "$release_sha" origin/main
```

## Safe test tags

Tags below `release-test/` run the real compiler and documentation workflows,
prepare the real release assets, and call the publisher with a read-only token.
They can never enter the write-capable publication job.

Run these one at a time after the release workflow has landed on `main`:

- `release-test/v1.1.999` at `origin/main` must pass through the dry-run job and
  create no GitHub Release.
- `release-test/not-semver` must fail tag validation before compiler or
  documentation jobs start.
- A valid test tag such as `release-test/v1.1.998` on a temporary commit that is
  not reachable from `main` must fail the reachability gate.

After recording the workflow URLs and confirming that no release was created,
delete only the temporary test tags and branch. Tag-deletion events are skipped
by the workflow. Never use a production `v...` tag for a dry run.

## Publishing

Create one annotated tag at the recorded `origin/main` commit and push only
that tag:

```sh
git tag -a v1.1.0 "$release_sha" -m "SwiftQL v1.1.0"
git push origin refs/tags/v1.1.0
```

The release workflow:

1. validates and peels the event SHA and tag ref;
2. proves the commit is reachable from current `origin/main`;
3. invokes the reusable four-lane compatibility workflow;
4. invokes the reusable documentation workflow without deploying Pages;
5. packages the Pages tar as `swiftql-docc-v1.1.0.tar.gz` and creates
   `swiftql-release-v1.1.0.json` plus `SHA256SUMS`;
6. creates a draft GitHub Release with generated notes and an exact commit/run
   marker;
7. uploads and verifies all three assets, then immediately refetches and
   revalidates the tag, `main` reachability, milestone, and changelog before the
   publication request;
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
- all four compatibility lanes and the documentation build passed;
- the tag still peels to that commit and remains reachable from `main`;
- the release is published, is not a prerelease, and its generated notes contain
  the exact commit marker;
- the release API reports `immutable: true`, and the production tag ruleset is
  still active;
- downloaded release assets pass GitHub's immutable-release attestation check
  (for example, `gh attestation verify ASSET --repo lukevanin/swiftql`);
- the release has exactly the DocC archive, manifest, and checksum assets;
- API asset digests match `SHA256SUMS`, and the manifest maps the tag to the
  exact commit and workflow run; and
- the historical `1.0.0` tag and release are unchanged.

For `v1.1.0`, post the evidence on #119 and close #119 first. Re-fetch it to
confirm closure, then close tracking issue #118. This order is part of the
release gate.

## Recovery

- **Invalid or unreachable tag, before a release exists:** delete only the bad
  tag, merge the correction to `main`, and create a fresh correct tag. Do not
  force-move a published release tag.
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
