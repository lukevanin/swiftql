# Scratch

## Goal
Stage 1.1 — Write CONTRIBUTING.md at the repo root

## Done
- Wrote CONTRIBUTING.md at repo root.
- `swift build` passed (Build complete).
- `swift test` passed (All tests passed).

## Next
Open PR from `agent/issue-405` → `main`.

## Decisions/gotchas
- Documentation-only change; no Swift source modifications.
- Tests/ contains both test targets and test-only library targets (fixtures, combinatorial support).
- CompileFail/ holds negative-compilation tests.
- Branch naming follows `agent/issue-NNN` for agent-driven work, `claude/<kebab-name>` for Claude-driven features, `version/x.y.z` for milestone bases.
- Commit messages are imperative-style, issue references in parentheses at the end.
- PRs target `main` for patch/docs changes; feature PRs may target a `version/x.y.z` base.
