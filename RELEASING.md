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
   # the line shares one milestone, vX.Y.Z when the patch has its own. Keep
   # the quotes; a milestone title may contain spaces.
   milestone_title="MILESTONE_TITLE"

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

Complete "Documentation currency" and "Release notes" below before recording the
release commit. Both produce changes that must be present on the tagged commit,
and neither can be applied to a published release afterwards.

## Documentation currency

A published release is immutable, and the documentation that ships with it is
whatever the tagged commit contains. A README describing the previous release's
capabilities cannot be corrected in place; it can only be superseded by another
release. Documentation currency is therefore a pre-tag gate, completed before
step 7 records the release commit.

### Reader-facing documents

Required for every minor and major release, and for any patch that changes
documented behavior.

Re-read [README.md](README.md) and
[Documentation/PortingFromSQL.md](Documentation/PortingFromSQL.md) against what
the milestone actually shipped, and correct:

- **Capability claims.** The README's "What becomes first-class" list, and any
  statement about what SwiftQL supports.
- **The comparison table.** SwiftQL's own row when its shape or coverage
  changed, and any other row whose facts have changed. A comparison against
  another library is a factual claim about that library, so re-verify it against
  that project's current documentation rather than against memory.
- **"Choose something else when".** A caveat the milestone has resolved must be
  removed. This section ages faster than the rest of the README because it is a
  list of current limitations.
- **The clause mapping in PortingFromSQL.** New clauses, statements, functions,
  or syntax forms get rows. A mapping table that omits shipped syntax is worse
  than no table, because readers treat it as exhaustive.
- **"Where the correspondence is not exact" in PortingFromSQL.** This restates
  the conformance inventory's gaps and must agree with it exactly. Update it
  from the inventory, not from recollection.
- **Version numbers** in the installation instructions.

The landing page at [Website/index.html](Website/index.html) restates the
tagline, the comparison table, the "Choose something else when" list, and the
Swift Package Manager version. It is the first page a visitor sees, so it is
part of this gate rather than an afterthought: whatever changed in the README
above almost certainly changed here too. It carries no generated content, so
nothing warns you when it drifts.

Review [Documentation/DESIGN.md](Documentation/DESIGN.md) as well when the
release changes a decision it records, such as retiring the chaining syntax or
replacing the `sql { }` and `sqlResult { }` builders with a function macro. Its
"What is still wrong" section is a list of open problems and should shrink as
they are fixed.

Record in the release issue which documents were reviewed and what changed, or
state explicitly that no change was required. Silence is not evidence of review.

### Conformance inventory

The
[inventory](Tests/SwiftQLSQLiteConformanceFixtures/SQLiteConformanceInventory.json)
is the source of truth for what SwiftQL supports. The
[report](Conformance/SQLite/REPORT.md) is its generated view, and
[COMPATIBILITY.md](COMPATIBILITY.md#sqlite-conformance-inventory), the README,
and PortingFromSQL restate its totals. All of them must agree on the tagged
commit.

For any release that adds or changes SQLite surface:

1. Add or adjust feature records and their evidence for what shipped, and move
   features out of `unimplemented` as they land. A feature counts as supported
   only when it links to successful preparation by a real SQLite engine whose
   version and source ID are recorded. Unit tests alone do not promote a
   feature.
2. Bump `INVENTORY_VERSION` in
   [`scripts/ci/sqlite-conformance-inventory.py`](scripts/ci/sqlite-conformance-inventory.py)
   when the inventory's contents change with the release line. The constant is
   in the script, not in the JSON, and is easy to leave behind.
3. Regenerate and verify:

   ```sh
   python3 scripts/ci/sqlite-conformance-inventory.py write
   python3 scripts/ci/sqlite-conformance-inventory.py check
   ```

4. Update the totals restated in COMPATIBILITY.md, the README, and
   PortingFromSQL to match the regenerated report.

**Check for drift before starting.** When the inventory version trails the
release line, features shipped in between are missing from it. Confirm that every
closed issue in the milestone that changed SQL surface has a corresponding
inventory record, and treat an unexplained gap as unfinished release work rather
than as a documentation nicety. An inventory that understates the library is
still wrong, and it is the number readers quote.

## Release notes

The published release body is the project's most widely read artifact. Swift
Package Index surfaces it, watchers receive it by email, and every
announcement links to it. It is read by people deciding whether SwiftQL is
worth their attention, not only by maintainers upgrading a pinned version.

An auto-generated pull-request list does not serve that reader. Every minor and
major release therefore carries a hand-written summary at the top of the body,
authored in `Documentation/ReleaseNotes/vX.Y.Z.md`.

### Authoring the summary

Write the summary on the release-preparation commit - the same commit that
carries the dated changelog heading. `publish-release.sh` reads the file from
the checked-out tag, so the summary is covered by the same exact-commit and
immutability guarantees as every other release artifact. A summary added after
publication cannot be applied: published releases are immutable by design.

The file is required for `vX.Y.0` and any major release, and optional for a
patch. When it is absent the body falls back to the provenance block and
generated notes alone, which is the correct shape for a patch that carries no
narrative.

Keep it to four elements, in this order:

1. **One sentence naming the theme.** Not "this release contains 14 pull
   requests" - what changed, in the reader's terms. A release is worth
   announcing precisely when this sentence is easy to write.
2. **Two or three sentences of detail**, each tied to something a reader might
   want. Name the capability, not the issue number.
3. **A short code example** when the release changes what user code looks
   like. This is the single highest-value element for a reader who has never
   used SwiftQL, and the part most likely to be quoted elsewhere.
4. **Upgrade impact** - deprecations, behavior changes, and platform or
   compiler requirements. State plainly when there are none.

Link to the changelog for the exhaustive list rather than reproducing it. The
changelog is the complete record for someone upgrading; the summary is the
argument for someone deciding.

`Documentation/ReleaseNotes/v1.5.4.md` is the worked example.

### What the published body contains

The publisher composes the body in this order:

1. the hand-written summary, when the file exists;
2. the provenance block - verified commit, validation run, and the exact
   commit marker; and
3. GitHub's generated notes, appended by the release API.

The marker and generated-notes checks in `validate_release_record` are
unchanged, so the existing verification gates still apply to the composed body.

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

- `release-test/vX.Y.999` at `origin/main`, or at any other commit reachable
  from `main`, must pass through the dry-run job and create no GitHub Release.
  These run before step 7 records `$release_sha`, and the release commit need
  not exist yet.
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

## Announcing a release

Publication makes a release *available*. Announcement makes it *known*. A
release that nobody is told about reaches only the people already watching the
repository, which is the audience that needs it least.

Announce after the verification checks above pass, never before - an
announcement that links to a release still under audit cannot be retracted.

### What gets announced

**Minor and major versions are announced. Patches ship silently.** SwiftQL
frequently publishes several patches in a week; announcing at that cadence
exhausts every channel that matters and trains readers to ignore the project.
Batching to minor versions also forces each announcement to carry a theme,
which is the same discipline the summary above requires.

A patch that fixes a security issue or a data-correctness bug is the exception
and is announced immediately, regardless of cadence.

### Where

Repeatable channels, used for every announced release:

- **The GitHub release itself.** Already done by the time you reach this
  section, provided the summary file existed at tag time.
- **The project blog.** A "What's new in vX.Y" post, for every announced
  release. See "The what's-new post" below.
- **Social - Mastodon and Bluesky.** Lead with the problem the release solves
  and a code screenshot. The release link belongs in a reply, not the opening
  post.
- **The [Swift Forums showcase thread](https://forums.swift.org/t/swiftql/82441).**
  Reply for releases that carry a substantial theme, not for every minor.
  Roughly every second or third is the right frequency.

Channels reserved for a major version, and deliberately not spent on a minor:
a new Swift Forums thread, Hacker News, iOS Dev Weekly, and Reddit. Each is
effectively one-shot; using one on a point release forfeits it for the release
that needed it.

### The what's-new post

Write "What's new in vX.Y" as a new post under
[`Website/blog/content/posts/`](Website/blog/content/posts), on the same
release-preparation commit as the changelog and the release-notes summary.
Match the front matter and tone of the existing posts -
[`why-i-taught-the-swift-compiler-to-read-sql.md`](Website/blog/content/posts/why-i-taught-the-swift-compiler-to-read-sql.md)
and
[`porting-sql-to-swiftql.md`](Website/blog/content/posts/porting-sql-to-swiftql.md).
It expands on the release-notes summary rather than duplicating it: the
summary is the pitch, the blog post is the walkthrough.

Include, wherever the release makes them relevant:

- **Code examples.** Before/after snippets for anything the release changes
  about what user code looks like - the same bar as the release-notes
  summary's code example, but with more of them and more context.
- **Data tables.** Benchmark numbers, conformance-inventory totals, or other
  measurable claims. Pull figures from the sources this document already
  treats as ground truth - the conformance inventory,
  `Documentation/ReleaseAudits/` - rather than restating them from memory.
- **Graphs**, when a trend or comparison reads better as a chart than a table,
  such as a before/after benchmark. The blog ships with no external
  subresources - [`check-blog-output.sh`](scripts/ci/check-blog-output.sh)
  fails the build if a post pulls one in - so a graph must be a static image
  under `Website/blog/static/` or an inline SVG, never a CDN chart library.

A new post is invisible to CI until it is registered in the two places that
hardcode the post list, so add it to both:

- the post list in [`check-blog-output.sh`](scripts/ci/check-blog-output.sh);
- the deployed-post link check in
  [`documentation.yml`](.github/workflows/documentation.yml).

Then confirm `make-docs.sh`'s Hugo build and `check-blog-output.sh` both pass
on the new post before merging it.

### Recording it

Add the announcement links to the release issue before closing it, in the same
way the tag-run and asset evidence is recorded. An unannounced minor release is
a process failure, not merely a missed opportunity, and the release issue is
where that is visible.

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
