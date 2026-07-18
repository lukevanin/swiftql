#!/usr/bin/env python3

"""Verify two first-party coverage captures came from the same clean source."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import sys
from pathlib import Path, PurePosixPath
from typing import Any, Dict, Iterable, List, Mapping, Optional, Sequence, Tuple


METRIC_NAMES = ("lines", "functions", "regions")
METRIC_FIELDS = {"count", "covered", "uncovered", "percent"}
REPORT_FIELDS = {
    "schema_version",
    "source_commit",
    "source_tree_state",
    "toolchain",
    "coverage_command",
    "package_resolved_sha256",
    "raw_llvm_report",
    "filtering",
    "targets",
    "overall",
    "largest_uncovered_files",
}
TOOLCHAIN_FIELDS = {
    "xcode",
    "swift",
    "sdk",
    "llvm_cov",
    "llvm_profdata",
    "platform",
    "architecture",
    "runner_image",
}
RAW_REPORT_FIELDS = {"type", "version", "file_entries"}
FILTERING_FIELDS = {
    "rule",
    "included_source_files",
    "included_sources_sha256",
    "allowed_uninstrumented_source_files",
    "excluded_raw_file_entries",
    "excluded_raw_file_entries_by_category",
}
FILTERING_CATEGORIES = {
    "outside_repository",
    "build_or_dependency",
    "tests_or_fixtures",
    "benchmarks",
    "generated",
    "other_repository_sources",
}
TARGET_FIELDS = {
    "source_root",
    "source_files",
    "instrumented_source_files",
    "allowed_uninstrumented_source_files",
    "totals",
    "files",
}
FILE_FIELDS = {"path", *METRIC_NAMES}


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


def require_mapping(value: Any, context: str) -> Mapping[str, Any]:
    if not isinstance(value, dict):
        raise ReproducibilityError(f"{context} must be a JSON object")
    return value


def require_list(value: Any, context: str) -> List[Any]:
    if not isinstance(value, list):
        raise ReproducibilityError(f"{context} must be a JSON array")
    return value


def require_nonnegative_integer(value: Any, context: str) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value < 0:
        raise ReproducibilityError(f"{context} must be a nonnegative integer")
    return value


def require_nonempty_string(value: Any, context: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ReproducibilityError(f"{context} must be a non-empty string")
    return value


def require_exact_fields(
    value: Mapping[str, Any], expected: Iterable[str], context: str
) -> None:
    expected_fields = set(expected)
    actual_fields = set(value)
    if actual_fields == expected_fields:
        return
    details = []
    missing = sorted(expected_fields - actual_fields)
    unexpected = sorted(actual_fields - expected_fields)
    if missing:
        details.append("missing " + ", ".join(missing))
    if unexpected:
        details.append("unexpected " + ", ".join(unexpected))
    raise ReproducibilityError(f"{context} has invalid fields: {'; '.join(details)}")


def require_sha256(value: Any, context: str) -> str:
    digest = require_nonempty_string(value, context)
    if re.fullmatch(r"[0-9a-f]{64}", digest) is None:
        raise ReproducibilityError(f"{context} must be a lowercase SHA-256 digest")
    return digest


def require_source_path(value: Any, context: str, *, swift_file: bool) -> str:
    source = require_nonempty_string(value, context)
    path = PurePosixPath(source)
    if (
        path.is_absolute()
        or source != path.as_posix()
        or ".." in path.parts
        or not source.startswith("Sources/")
        or (swift_file and not source.endswith(".swift"))
    ):
        kind = "source file" if swift_file else "source root"
        raise ReproducibilityError(
            f"{context} must be a normalized repository-relative {kind} path"
        )
    return source


def require_clean_report(report: Mapping[str, Any], path: Path) -> None:
    require_exact_fields(report, REPORT_FIELDS, f"coverage report {path}")
    if report.get("schema_version") != 1:
        raise ReproducibilityError(f"unsupported report schema in {path}")
    if report.get("source_tree_state") != "clean":
        raise ReproducibilityError(f"coverage report did not capture a clean tree: {path}")


def require_sorted_unique_strings(value: Any, context: str) -> List[str]:
    items = require_list(value, context)
    if not all(isinstance(item, str) and item for item in items):
        raise ReproducibilityError(f"{context} must contain non-empty strings")
    if items != sorted(set(items)):
        raise ReproducibilityError(f"{context} must be sorted and unique")
    return items


def static_metric_identity(value: Any, context: str) -> Mapping[str, int]:
    metric = require_mapping(value, context)
    if set(metric) != METRIC_FIELDS:
        raise ReproducibilityError(
            f"{context} must contain exactly count, covered, uncovered, and percent"
        )
    count = require_nonnegative_integer(metric["count"], f"{context}.count")
    covered = require_nonnegative_integer(metric["covered"], f"{context}.covered")
    uncovered = require_nonnegative_integer(
        metric["uncovered"], f"{context}.uncovered"
    )
    percent = metric["percent"]
    if not isinstance(percent, (int, float)) or isinstance(percent, bool):
        raise ReproducibilityError(f"{context}.percent must be numeric")
    if covered > count or uncovered != count - covered:
        raise ReproducibilityError(f"{context} contains inconsistent counters")
    expected_percent = 0.0 if count == 0 else round((covered * 100.0) / count, 2)
    if percent != expected_percent:
        raise ReproducibilityError(f"{context}.percent is inconsistent with counters")
    return {"count": count}


def static_metrics_identity(value: Any, context: str) -> Mapping[str, Any]:
    metrics = require_mapping(value, context)
    if set(metrics) != set(METRIC_NAMES):
        raise ReproducibilityError(
            f"{context} must contain exactly lines, functions, and regions"
        )
    return {
        name: static_metric_identity(metrics[name], f"{context}.{name}")
        for name in METRIC_NAMES
    }


def file_identity(value: Any, context: str) -> Mapping[str, Any]:
    file_report = require_mapping(value, context)
    require_exact_fields(file_report, FILE_FIELDS, context)
    path = require_source_path(
        file_report.get("path"), f"{context}.path", swift_file=True
    )
    return {
        "path": path,
        **{
            name: static_metric_identity(file_report.get(name), f"{context}.{name}")
            for name in METRIC_NAMES
        },
    }


def target_identity(value: Any, context: str) -> Mapping[str, Any]:
    target = require_mapping(value, context)
    require_exact_fields(target, TARGET_FIELDS, context)
    source_root = require_source_path(
        target.get("source_root"), f"{context}.source_root", swift_file=False
    )
    source_files = require_nonnegative_integer(
        target.get("source_files"), f"{context}.source_files"
    )
    instrumented_source_files = require_nonnegative_integer(
        target.get("instrumented_source_files"),
        f"{context}.instrumented_source_files",
    )
    allowed_values = require_sorted_unique_strings(
        target.get("allowed_uninstrumented_source_files"),
        f"{context}.allowed_uninstrumented_source_files",
    )
    allowed = [
        require_source_path(
            source,
            f"{context}.allowed_uninstrumented_source_files[{index}]",
            swift_file=True,
        )
        for index, source in enumerate(allowed_values)
    ]
    if instrumented_source_files + len(allowed) != source_files:
        raise ReproducibilityError(
            f"{context} source membership counts are inconsistent"
        )
    files = require_list(target.get("files"), f"{context}.files")
    if len(files) != instrumented_source_files:
        raise ReproducibilityError(
            f"{context}.files does not match instrumented_source_files"
        )
    file_identities = [
        file_identity(file_report, f"{context}.files[{index}]")
        for index, file_report in enumerate(files)
    ]
    paths = [file_report["path"] for file_report in file_identities]
    if paths != sorted(set(paths)):
        raise ReproducibilityError(f"{context}.files must be sorted and unique by path")
    for path in paths + allowed:
        if not path.startswith(source_root + "/"):
            raise ReproducibilityError(
                f"{context} source is outside its source_root: {path}"
            )
    overlap = sorted(set(paths) & set(allowed))
    if overlap:
        raise ReproducibilityError(
            f"{context} sources cannot be both instrumented and allowed: "
            + ", ".join(overlap)
        )
    totals = static_metrics_identity(
        target.get("totals"), f"{context}.totals"
    )
    for name in METRIC_NAMES:
        file_total = sum(file_report[name]["count"] for file_report in file_identities)
        if totals[name]["count"] != file_total:
            raise ReproducibilityError(
                f"{context}.totals.{name}.count does not match its files"
            )
    return {
        "source_root": source_root,
        "source_files": source_files,
        "instrumented_source_files": instrumented_source_files,
        "allowed_uninstrumented_source_files": allowed,
        "totals": totals,
        "files": file_identities,
    }


def toolchain_identity(value: Any, context: str) -> Mapping[str, str]:
    toolchain = require_mapping(value, context)
    require_exact_fields(toolchain, TOOLCHAIN_FIELDS, context)
    return {
        name: require_nonempty_string(toolchain.get(name), f"{context}.{name}")
        for name in sorted(TOOLCHAIN_FIELDS)
    }


def raw_report_identity(value: Any, context: str) -> Mapping[str, Any]:
    raw_report = require_mapping(value, context)
    require_exact_fields(raw_report, RAW_REPORT_FIELDS, context)
    if raw_report.get("type") != "llvm.coverage.json.export":
        raise ReproducibilityError(
            f"{context}.type must be llvm.coverage.json.export"
        )
    return {
        "type": raw_report["type"],
        "version": require_nonempty_string(
            raw_report.get("version"), f"{context}.version"
        ),
        "file_entries": require_nonnegative_integer(
            raw_report.get("file_entries"), f"{context}.file_entries"
        ),
    }


def filtering_identity(value: Any, context: str) -> Mapping[str, Any]:
    filtering = require_mapping(value, context)
    require_exact_fields(filtering, FILTERING_FIELDS, context)
    categories = require_mapping(
        filtering.get("excluded_raw_file_entries_by_category"),
        f"{context}.excluded_raw_file_entries_by_category",
    )
    unknown_categories = sorted(set(categories) - FILTERING_CATEGORIES)
    if unknown_categories:
        raise ReproducibilityError(
            f"{context}.excluded_raw_file_entries_by_category has unknown categories: "
            + ", ".join(unknown_categories)
        )
    category_counts = {
        name: require_nonnegative_integer(
            count,
            f"{context}.excluded_raw_file_entries_by_category.{name}",
        )
        for name, count in categories.items()
    }
    excluded_entries = require_nonnegative_integer(
        filtering.get("excluded_raw_file_entries"),
        f"{context}.excluded_raw_file_entries",
    )
    if sum(category_counts.values()) != excluded_entries:
        raise ReproducibilityError(
            f"{context}.excluded_raw_file_entries does not match its categories"
        )
    return {
        "rule": require_nonempty_string(filtering.get("rule"), f"{context}.rule"),
        "included_source_files": require_nonnegative_integer(
            filtering.get("included_source_files"),
            f"{context}.included_source_files",
        ),
        "included_sources_sha256": require_sha256(
            filtering.get("included_sources_sha256"),
            f"{context}.included_sources_sha256",
        ),
        "allowed_uninstrumented_source_files": require_nonnegative_integer(
            filtering.get("allowed_uninstrumented_source_files"),
            f"{context}.allowed_uninstrumented_source_files",
        ),
        "excluded_raw_file_entries": excluded_entries,
        "excluded_raw_file_entries_by_category": dict(sorted(category_counts.items())),
    }


def reproducibility_identity(
    report: Mapping[str, Any], path: Path
) -> Mapping[str, Any]:
    source_commit = require_nonempty_string(
        report.get("source_commit"), f"{path}: source_commit"
    )
    if re.fullmatch(r"[0-9a-f]{40}", source_commit) is None:
        raise ReproducibilityError(
            f"{path}: source_commit must be a full lowercase Git SHA"
        )
    coverage_command = require_nonempty_string(
        report.get("coverage_command"), f"{path}: coverage_command"
    )
    package_resolved_sha256 = require_sha256(
        report.get("package_resolved_sha256"),
        f"{path}: package_resolved_sha256",
    )
    toolchain = toolchain_identity(report.get("toolchain"), f"{path}: toolchain")
    raw_report = raw_report_identity(
        report.get("raw_llvm_report"), f"{path}: raw_llvm_report"
    )
    filtering = filtering_identity(report.get("filtering"), f"{path}: filtering")
    if raw_report["file_entries"] != (
        filtering["included_source_files"]
        + filtering["excluded_raw_file_entries"]
    ):
        raise ReproducibilityError(
            f"{path}: raw_llvm_report.file_entries does not match filtering counts"
        )
    targets = require_mapping(report.get("targets"), f"{path}: targets")
    if not targets:
        raise ReproducibilityError(f"{path}: targets must not be empty")
    largest_uncovered_files = require_list(
        report.get("largest_uncovered_files"),
        f"{path}: largest_uncovered_files",
    )
    for index, file_report in enumerate(largest_uncovered_files):
        file_identity(
            file_report,
            f"{path}: largest_uncovered_files[{index}]",
        )
    target_identities: Dict[str, Any] = {}
    source_roots = set()
    owned_sources = set()
    for name, target in targets.items():
        require_nonempty_string(name, f"{path}: target name")
        target_report = target_identity(target, f"{path}: targets.{name}")
        source_root = target_report["source_root"]
        if source_root in source_roots:
            raise ReproducibilityError(
                f"{path}: duplicate target source_root: {source_root}"
            )
        source_roots.add(source_root)
        target_sources = {
            file_report["path"] for file_report in target_report["files"]
        } | set(target_report["allowed_uninstrumented_source_files"])
        duplicate_sources = sorted(owned_sources & target_sources)
        if duplicate_sources:
            raise ReproducibilityError(
                f"{path}: sources belong to multiple targets: "
                + ", ".join(duplicate_sources)
            )
        owned_sources.update(target_sources)
        target_identities[name] = target_report

    overall = static_metrics_identity(
        report.get("overall"), f"{path}: overall"
    )
    for name in METRIC_NAMES:
        target_total = sum(
            target["totals"][name]["count"] for target in target_identities.values()
        )
        if overall[name]["count"] != target_total:
            raise ReproducibilityError(
                f"{path}: overall.{name}.count does not match its targets"
            )
    return {
        "schema_version": 1,
        "source_commit": source_commit,
        "source_tree_state": "clean",
        "toolchain": dict(toolchain),
        "coverage_command": coverage_command,
        "package_resolved_sha256": package_resolved_sha256,
        "raw_llvm_report": dict(raw_report),
        "filtering": dict(filtering),
        "targets": target_identities,
        "overall": overall,
    }


def canonical_manifests(identity: Mapping[str, Any]) -> Tuple[bytes, bytes]:
    included_lines = []
    allowed_lines = []
    targets = identity["targets"]
    for name in sorted(targets):
        target = targets[name]
        included_lines.extend(
            f"{name}\t{file_report['path']}" for file_report in target["files"]
        )
        allowed_lines.extend(
            f"{name}\t{source}"
            for source in target["allowed_uninstrumented_source_files"]
        )
    included = "".join(line + "\n" for line in included_lines).encode("utf-8")
    allowed = "".join(line + "\n" for line in allowed_lines).encode("utf-8")
    return included, allowed


def verify_run(
    directory: Path,
) -> Tuple[Mapping[str, Any], Mapping[str, Any], bytes, bytes, int, str]:
    report_path = directory / "first-party-coverage.json"
    report = load_json(report_path)
    require_clean_report(report, report_path)
    identity = reproducibility_identity(report, report_path)
    expected_included, expected_allowed = canonical_manifests(identity)
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
    if included != expected_included:
        raise ReproducibilityError(
            "included-source manifest does not match report target topology: "
            f"{report_path}"
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
    if allowed != expected_allowed:
        raise ReproducibilityError(
            "allowed-source manifest does not match report target topology: "
            f"{report_path}"
        )
    return report, identity, included, allowed, source_count, source_sha256


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
    (
        first_report,
        first_identity,
        first_included,
        first_allowed,
        source_count,
        source_sha256,
    ) = first
    second_report, second_identity, second_included, second_allowed, _, _ = second

    if first_included != second_included:
        raise ReproducibilityError("included source manifests differ between clean runs")
    if first_allowed != second_allowed:
        raise ReproducibilityError(
            "allowed-uninstrumented source manifests differ between clean runs"
        )
    if first_identity != second_identity:
        keys = ", ".join(differing_top_level_keys(first_identity, second_identity))
        raise ReproducibilityError(
            f"coverage reproducibility identities differ between clean runs: {keys}"
        )

    normalized_reports_match = first_report == second_report

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
        "reproducibility_identity_matches": True,
        "normalized_reports_match": normalized_reports_match,
        "dynamic_coverage_metrics_match": normalized_reports_match,
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
