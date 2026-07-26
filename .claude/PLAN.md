# Plan: Add CONTRIBUTING.md (issue #405)

## Phase 1 — Documentation

- [x] 1.1 Write `CONTRIBUTING.md` at the repo root, covering: local setup, build,
  test suite structure (`Tests/`, `CompileFail/`, and fixture targets),
  code style, branch/commit/PR conventions, and a pointer to `RELEASING.md`.
  tests: package still builds (`swift build`); existing test suite passes (`swift test`).
  validation: file exists at repo root; CI (docs-only change, no Swift changes).
