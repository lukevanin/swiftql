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

All GitHub work goes through the MCP servers — **no `gh` CLI needed**. Two
servers cover everything: the official server (issues, branches, PRs) and the
`github-mcp` server (milestones, Projects v2, releases, issue dependencies).
Local git (status/diff/log/branch/commit/push) still uses `git` via Bash.

| Action | Tool |
|---|---|
| Find / create / update an issue | `search_issues` / `issue_write` / `issue_read` |
| Create / list a milestone | `github-mcp` `create_milestone` / `list_milestones` |
| Add an issue to Project #9 (returns `itemId`) | `github-mcp` `add_project_item` |
| Set a project field (Size, Priority, Status…) | `github-mcp` `set_project_field` |
| Inspect project fields/options/items | `github-mcp` `get_project` |
| Mark an issue blocked by another | `github-mcp` `add_blocked_by` |
| Read dependencies | `github-mcp` `list_blocked_by` / `list_blocking` |
| Create a branch | `create_branch` (`from_branch: main`) |
| Open a PR | `create_pull_request` |

`set_project_field` and `add_blocked_by` take plain human values / issue numbers
and resolve the underlying ids themselves — never look up option or node ids by
hand. Field names and options are discoverable via `get_project` (number 9,
owner `lukevanin`).

### Step 1 — Milestone

A **milestone** is one app-version release **or** one experiment/spike.

- List existing milestones (`list_milestones`, `state: all`) and reuse one if it
  fits — many versions (v1.4.4–v1.4.6, v1.5–v1.7, v2, v2.1–v2.8) already exist.
- Otherwise `create_milestone` with a version title (`vX.Y.Z`) for a release, or
  a descriptive title for an experiment/spike.

### Step 2 — Break the milestone into issues

One **cohesive, self-contained** task per issue. Don't split a single feature
across multiple issues, and don't bundle multiple features into one — this is a
judgement call, not a precise rule.

- `search_issues` first to avoid creating a duplicate.
- `issue_write` (`method: create`) with: the **milestone number**, a **priority
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
Reserve `sub_issue_write` for genuine *decomposition* (a task that breaks into
children) — it is a hierarchy tool, not an ordering mechanism.

### Step 4 — Base branch for the milestone

Create the milestone's base branch from `main` with `create_branch`
(`from_branch: main`), named `version/x.y.z` (e.g. `version/1.4.5`). For an
experiment/spike, use a descriptive `experiment/<name>` branch instead.

### Step 5 — One PR per issue, then hand off

When a milestone contains multiple issues, deliver **one PR per issue**, each
**targeting the milestone base branch** (`version/x.y.z`), not `main`.

**Scaffolding stops here.** Implementing the issues and opening their PRs happens
in separate delivery sessions. Those sessions follow the repo's existing Copilot
review loop: open the PR, request a Copilot review, address every actionable
comment (fix or explain why not), push, and re-request until Copilot has no
further useful feedback.

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
