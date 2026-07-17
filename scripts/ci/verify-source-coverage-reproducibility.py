#!/usr/bin/env python3

"""Verify two first-party coverage captures came from the same clean source."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sys
from pathlib import Path
from typing import Any, Dict, Mapping, Optional, Sequence, Tuple


class ReproducibilityError(RuntimeError):
    """Raised when two coverage captures are not reproducible peers."""


def load_json(path: Path) -> Mapping[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ReproducibilityError(f"could not read {path}: {error}") from error
    if not isinstance(value, dict):
        raise ReproducibilityError(f"expected a JSON object in {path}")
    return value


def load_manifest(path: Path) -> Tuple[bytes, int, str]:
    try:
        contents = path.read_bytes()
    except OSError as error:
        raise ReproducibilityError(f"could not read {path}: {error}") from error
    if not contents or not contents.endswith(b"\n"):
        raise ReproducibilityError(f"manifest must be non-empty and newline-terminated: {path}")
    try:
        lines = contents.decode("utf-8").splitlines()
    except UnicodeDecodeError as error:
        raise ReproducibilityError(f"manifest is not UTF-8: {path}") from error
    if lines != sorted(set(lines)):
        raise ReproducibilityError(f"manifest is not sorted and unique: {path}")
    return contents, len(lines), hashlib.sha256(contents).hexdigest()


def require_clean_report(report: Mapping[str, Any], path: Path) -> None:
    if report.get("schema_version") != 1:
        raise ReproducibilityError(f"unsupported report schema in {path}")
    if report.get("source_tree_state") != "clean":
        raise ReproducibilityError(f"coverage report did not capture a clean tree: {path}")
    for field in (
        "source_commit",
        "coverage_command",
        "package_resolved_sha256",
        "toolchain",
        "filtering",
        "targets",
        "overall",
    ):
        if field not in report:
            raise ReproducibilityError(f"coverage report is missing {field}: {path}")


def verify_run(directory: Path) -> Tuple[Mapping[str, Any], bytes, bytes, int, str]:
    report_path = directory / "first-party-coverage.json"
    report = load_json(report_path)
    require_clean_report(report, report_path)
    included, source_count, source_sha256 = load_manifest(
        directory / "included-sources.txt"
    )
    try:
        allowed = (directory / "allowed-uninstrumented-sources.txt").read_bytes()
    except OSError as error:
        raise ReproducibilityError(
            f"could not read allowed-source manifest in {directory}: {error}"
        ) from error
    filtering = report["filtering"]
    if not isinstance(filtering, dict):
        raise ReproducibilityError(f"coverage filtering block is invalid: {report_path}")
    if filtering.get("included_source_files") != source_count:
        raise ReproducibilityError(
            f"included-source count does not match manifest: {report_path}"
        )
    if filtering.get("included_sources_sha256") != source_sha256:
        raise ReproducibilityError(
            f"included-source digest does not match manifest: {report_path}"
        )
    try:
        allowed_lines = allowed.decode("utf-8").splitlines()
    except UnicodeDecodeError as error:
        raise ReproducibilityError(
            f"allowed-source manifest is not UTF-8: {directory}"
        ) from error
    if allowed and not allowed.endswith(b"\n"):
        raise ReproducibilityError(
            f"allowed-source manifest is not newline-terminated: {directory}"
        )
    if allowed_lines != sorted(set(allowed_lines)):
        raise ReproducibilityError(
            f"allowed-source manifest is not sorted and unique: {directory}"
        )
    allowed_count = len(allowed_lines)
    if filtering.get("allowed_uninstrumented_source_files") != allowed_count:
        raise ReproducibilityError(
            f"allowed-source count does not match manifest: {report_path}"
        )
    return report, included, allowed, source_count, source_sha256


def differing_top_level_keys(
    first: Mapping[str, Any], second: Mapping[str, Any]
) -> Sequence[str]:
    return sorted(
        key
        for key in set(first) | set(second)
        if first.get(key) != second.get(key)
    )


def run(first_directory: Path, second_directory: Path, output_json: Path) -> None:
    first = verify_run(first_directory)
    second = verify_run(second_directory)
    first_report, first_included, first_allowed, source_count, source_sha256 = first
    second_report, second_included, second_allowed, _, _ = second

    if first_included != second_included:
        raise ReproducibilityError("included source manifests differ between clean runs")
    if first_allowed != second_allowed:
        raise ReproducibilityError(
            "allowed-uninstrumented source manifests differ between clean runs"
        )
    if first_report != second_report:
        keys = ", ".join(differing_top_level_keys(first_report, second_report))
        raise ReproducibilityError(
            f"normalized coverage reports differ between clean runs: {keys}"
        )

    evidence: Dict[str, Any] = {
        "schema_version": 1,
        "clean_runs_compared": 2,
        "source_commit": first_report["source_commit"],
        "source_tree_state": "clean",
        "package_resolved_sha256": first_report["package_resolved_sha256"],
        "coverage_command": first_report["coverage_command"],
        "toolchain": first_report["toolchain"],
        "included_source_sets_match": True,
        "allowed_uninstrumented_source_sets_match": True,
        "normalized_reports_match": True,
        "included_source_files": source_count,
        "included_sources_sha256": source_sha256,
    }
    output_json.parent.mkdir(parents=True, exist_ok=True)
    output_json.write_text(
        json.dumps(evidence, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    shutil.copyfile(
        second_directory / "included-sources.txt",
        output_json.parent / "repeated-included-sources.txt",
    )
    print(f"SWIFTQL_SOURCE_COVERAGE_REPRODUCIBLE {source_sha256}")


def parse_arguments(argv: Optional[Sequence[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("first_run", type=Path)
    parser.add_argument("second_run", type=Path)
    parser.add_argument("output_json", type=Path)
    return parser.parse_args(argv)


def main(argv: Optional[Sequence[str]] = None) -> int:
    arguments = parse_arguments(argv)
    try:
        run(arguments.first_run, arguments.second_run, arguments.output_json)
    except ReproducibilityError as error:
        print(f"error: source coverage reproducibility: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
