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
4. Record the exact remote commit. Do not release from an unpushed local commit.

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
7. uploads and verifies all three assets before publishing the draft; and
8. rechecks the tag ref after publication.

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
- **Tag moved while validation was running:** publication fails its second ref
  check. Restore or replace the tag only if no release was published, then start
  a new run.

Enabling GitHub immutable releases is recommended. The workflow already follows
the required draft-first sequence, so publication can lock the tag and assets
only after every asset has been uploaded and verified.
