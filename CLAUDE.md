# SwiftQL — working guide for Claude

## Milestone & issue workflow

Use this workflow when planning large or complex work on SwiftQL. It **scaffolds**
the work on GitHub — milestone → issues → project/size/dependencies → base
branch — and then hands off. Implementing each issue happens in a **separate**
session (chips / `/flow` / a fresh delivery session); this workflow deliberately
stops before writing code.

Repo: `lukevanin/swiftql`. Project board: **#9 "SwiftQL Project Plan"** (owner
`lukevanin`), already linked to the repo.

### Tools

Which GitHub tools a session has depends on how it was started, so check what
is available before picking one. The routes, in order of preference:

- **`github-mcp`**, where it is configured. It runs under a personal access
  token and is the only server with the project and dependency tools in the
  table below (`add_project_item`, `set_project_field`, `add_blocked_by`, and
  so on). Prefer it for issue and milestone writes too.
- **The official GitHub connector.** What it may write depends on the
  session. In some sessions every write returns
  `403 Resource not accessible by integration`. In the Claude Code cloud
  sessions that delivered #800 and #801 it opened and edited PRs
  (`create_pull_request`, `update_pull_request`) and posted and edited PR
  conversation comments (`add_issue_comment`, `update_issue_comment`), but
  every inline review write still returned 403. Try a write once; on a 403,
  do not retry it, take the next route.
- **The GitHub REST API** through `curl`, with the session's token
  (`$GH_TOKEN` in those cloud sessions), for a write no connected server
  offers. For example, #800's session removed an issue dependency with
  `DELETE /repos/lukevanin/swiftql/issues/{number}/dependencies/blocked_by/{id}`,
  where `{id}` is the blocking issue's `id`, not its number.
- **`gh`**, where it is installed. Those cloud sessions did not have it.

Branches are always created with `git`. Releases are written by none of
these; the tag-triggered workflow owns them (Step 6). Local git
(status/diff/log/branch/commit/push) uses `git` via Bash.

| Action | Tool |
|---|---|
| Find / read / list an issue (read-only) | `search_issues` / `issue_read` / `github-mcp` `list_issues` |
| Create / update an issue | `github-mcp` `create_issue` / `edit_issue` |
| Create / list a milestone | `github-mcp` `create_milestone` / `list_milestones` |
| Add an issue to Project #9 (returns `itemId`) | `github-mcp` `add_project_item` |
| Set a project field (Size, Priority, Status…) | `github-mcp` `set_project_field` |
| Inspect project fields/options/items | `github-mcp` `get_project` |
| Mark an issue blocked by another | `github-mcp` `add_blocked_by` |
| Read dependencies | `github-mcp` `list_blocked_by` / `list_blocking` |
| Decompose an issue into sub-issues | `github-mcp` `add_sub_issue` / `list_sub_issues` |
| Create a branch | `git branch` + `git push -u origin <name>` |
| Open a PR | `gh pr create`, or the connector's `create_pull_request` where it can write |

**Never create a branch with the connector's `create_branch`**: use `git`, so
the branch starts from the fetched base (Step 4). Where the connector is
read-only, its `issue_write`, `sub_issue_write`, and `create_pull_request` fail
with 403; the table above gives the working equivalent for each.

`set_project_field` and `add_blocked_by` take plain human values / issue numbers
and resolve the underlying ids themselves — never look up option or node ids by
hand. Field names and options are discoverable via `get_project` (number 9,
owner `lukevanin`).

### Step 1 — Milestone

A **milestone** is one app-version release **or** one experiment/spike.

- List existing milestones (`list_milestones`, `state: all`) and reuse one if it
  fits — many versions already exist (v1.9.1, the PostgreSQL rendering spike,
  and v2.0–v2.10 are open).
- Otherwise `create_milestone` with a version title (`vX.Y.Z`) for a release, or
  a descriptive title for an experiment/spike.

### Step 2 — Break the milestone into issues

One **cohesive, self-contained** task per issue. Don't split a single feature
across multiple issues, and don't bundle multiple features into one — this is a
judgement call, not a precise rule.

- `search_issues` first to avoid creating a duplicate.
- `github-mcp` `create_issue` with: the **milestone number**, a **priority
  label** (`P1`–`P4`), and any relevant **type label** (`bug`, `enhancement`,
  `tests`, `ci`, `macro`, `security`, `documentation`). Size is **not** a label —
  it lives on the project (Step 3).

### Step 3 — Project, size, and dependencies

For each issue:

1. `add_project_item` (project number `9`, the issue number) → capture the
   returned `itemId`.
2. `set_project_field` on that `itemId` for **Size** (`XS`/`S`/`M`/`L`/`XL`) and
   **Priority** (`P2`/`P3`/`P4`). Size drives the board's Estimate/timeline, so
   set it for every issue.
3. `add_blocked_by` to record **ordering** dependencies — mark an issue as
   blocked by whatever must land before it, so the milestone can be implemented
   in the correct order. Verify with `list_blocked_by` / `list_blocking`.

Use `add_blocked_by` for *ordering* ("this can't start until that lands").
Reserve `github-mcp` `add_sub_issue` for genuine *decomposition* (a task that
breaks into children) — it is a hierarchy tool, not an ordering mechanism.

### Step 4 — Base branch for the milestone

Create the milestone's base branch from the fetched `origin/main` with `git`,
named `version/x.y.z`
(e.g. `version/1.4.5`):

```sh
git fetch origin
git branch version/x.y.z origin/main
git push -u origin version/x.y.z
```

For an experiment/spike, use a descriptive `experiment/<name>` branch instead.

### Step 5 — One PR per issue, then hand off

When a milestone contains multiple issues, deliver **one PR per issue**, each
**targeting the milestone base branch** (`version/x.y.z`), not `main`.

**Scaffolding stops here.** Implementing the issues and opening their PRs happens
in separate delivery sessions, which review each PR as described in
[Pull request review](#pull-request-review) below.

### Step 6 — Completion and release (defer)

- When **every** issue's PR is merged into the base branch, **notify the user for
  testing** — do not proceed to release unprompted.
- Once the user approves, the release (merge base branch → `main`, tag, publish)
  is performed **strictly per [RELEASING.md](RELEASING.md)**. That process is a
  hardened, audited pipeline; follow it exactly rather than duplicating or
  improvising its steps here.
- **Do not** use `github-mcp` `create_release` / `publish_release` for SwiftQL.
  Publication is owned by the tag-triggered verified workflow
  (`.github/workflows/release.yml`), which enforces the Swift compatibility
  matrix, DocC provenance, the immutable-release check, and the protected tag
  ruleset — all of which a direct release-API call would bypass.

## Pull request review

**Copilot review is not available for this repo. Do not request it.** Every PR
is reviewed with Claude, following the loop in
[CONTRIBUTING.md](CONTRIBUTING.md#pull-request-process), which holds all of its
rules, including what to do when review comments cannot be posted. A Claude
session runs that loop itself, and adds two things:

- **Posting a round.** Which comment tool can write to the PR depends on the
  session's GitHub setup; use one that accepts the write (see [Tools](#tools)).
- **Tell the user.** When the loop ends, give the user the open items from
  the closing comment. If no PR comment could be posted at all, give the
  user every round and the closing summary instead, and say that none of it
  is on the PR.
