#!/usr/bin/env python3

"""Fail when a tracked Swift source sits outside the configured coverage roots.

The source coverage job runs only after a merge, so a new production target
used to turn main red one merge too late. This check needs only `git ls-files`
and `scripts/ci/source-coverage-config.json`, which lets the Linux
release-tooling job run it on every pull request.

Every tracked `.swift` file under `Sources/` (outside a `.docc` catalog) must
sit inside a coverage target's `source_root` or inside one of the config's
`excluded_source_roots`. An excluded root names a directory whose code the
coverage test binary never links, such as an executable target, and records
why.
"""

from __future__ import annotations

import argparse
import importlib.util
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, List, Mapping, Optional, Sequence


REPORT_SCRIPT = Path(__file__).with_name("source-coverage-report.py")


def load_report_module() -> Any:
    specification = importlib.util.spec_from_file_location(
        "source_coverage_report", REPORT_SCRIPT
    )
    if specification is None or specification.loader is None:
        raise RuntimeError(f"could not load {REPORT_SCRIPT}")
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    return module


report = load_report_module()
CoverageError = report.CoverageError


def load_excluded_roots(
    config: Mapping[str, Any], target_roots: Sequence[str]
) -> List[Dict[str, str]]:
    raw_excluded = config.get("excluded_source_roots", [])
    if not isinstance(raw_excluded, list):
        raise CoverageError("excluded_source_roots must be an array")
    excluded: List[Dict[str, str]] = []
    seen = set(target_roots)
    for raw_entry in raw_excluded:
        if not isinstance(raw_entry, dict):
            raise CoverageError("every excluded source root must be an object")
        source_root = report.relative_config_path(
            raw_entry.get("source_root"), "excluded_source_roots.source_root"
        )
        if not source_root.startswith("Sources/"):
            raise CoverageError(
                f"excluded source root must identify a Sources directory: {source_root}"
            )
        reason = raw_entry.get("reason")
        if not isinstance(reason, str) or not reason.strip():
            raise CoverageError(f"excluded source root needs a reason: {source_root}")
        for other in seen:
            if (
                source_root == other
                or source_root.startswith(other + "/")
                or other.startswith(source_root + "/")
            ):
                raise CoverageError(
                    f"excluded source root overlaps a configured root: {source_root}"
                )
        seen.add(source_root)
        excluded.append({"source_root": source_root, "reason": reason})
    return sorted(excluded, key=lambda entry: entry["source_root"])


def tracked_swift_sources(repository_root: Path) -> List[str]:
    try:
        result = subprocess.run(
            ["git", "-C", str(repository_root), "ls-files", "-z", "--", "Sources"],
            check=False,
            capture_output=True,
        )
    except OSError as error:
        raise CoverageError(f"could not enumerate tracked sources: {error}") from error
    if result.returncode != 0:
        detail = result.stderr.decode("utf-8", errors="replace").strip()
        raise CoverageError(f"could not enumerate tracked sources: {detail}")
    try:
        tracked_paths = result.stdout.decode("utf-8").split("\0")
    except UnicodeDecodeError as error:
        raise CoverageError("tracked source paths are not valid UTF-8") from error
    return sorted(
        path
        for path in tracked_paths
        if path.endswith(".swift") and not report.in_documentation_catalog(path)
    )


def inside(path: str, root: str) -> bool:
    return path.startswith(root + "/")


def check_membership(repository_root: Path, config_path: Path) -> List[str]:
    targets = report.load_config(config_path)
    target_roots = [target["source_root"] for target in targets]
    excluded = load_excluded_roots(report.load_json(config_path), target_roots)
    excluded_roots = [entry["source_root"] for entry in excluded]
    sources = tracked_swift_sources(repository_root)

    outside = [
        source
        for source in sources
        if not any(inside(source, root) for root in target_roots + excluded_roots)
    ]
    if outside:
        raise CoverageError(
            "tracked Swift sources are outside the configured target roots in "
            "scripts/ci/source-coverage-config.json (add a coverage target or an "
            "excluded_source_roots entry): "
            + ", ".join(outside)
        )
    stale = [
        root
        for root in excluded_roots
        if not any(inside(source, root) for source in sources)
    ]
    if stale:
        raise CoverageError(
            "excluded source roots have no tracked Swift sources: " + ", ".join(stale)
        )
    return sources


def parse_arguments(argv: Optional[Sequence[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--repository-root",
        type=Path,
        default=Path(__file__).resolve().parents[2],
    )
    parser.add_argument("--config", type=Path, default=None)
    return parser.parse_args(argv)


def main(argv: Optional[Sequence[str]] = None) -> int:
    arguments = parse_arguments(argv)
    repository_root = arguments.repository_root.resolve()
    config_path = arguments.config or (
        repository_root / "scripts/ci/source-coverage-config.json"
    )
    try:
        sources = check_membership(repository_root, config_path)
    except CoverageError as error:
        print(f"error: source target membership: {error}", file=sys.stderr)
        return 1
    print(
        f"source target membership: {len(sources)} tracked Swift sources are "
        "inside the configured target roots"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
