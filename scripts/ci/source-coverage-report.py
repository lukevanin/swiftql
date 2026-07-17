#!/usr/bin/env python3

"""Extract deterministic first-party coverage from SwiftPM's LLVM JSON export."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from collections import Counter
from pathlib import Path, PurePosixPath
from typing import Any, Dict, Iterable, List, Mapping, Optional, Sequence, Tuple


METRICS = ("lines", "functions", "regions")


class CoverageError(RuntimeError):
    """Raised when coverage inputs violate the reporting contract."""


def load_json(path: Path) -> Mapping[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise CoverageError(f"could not read JSON {path}: {error}") from error
    if not isinstance(value, dict):
        raise CoverageError(f"expected a JSON object in {path}")
    return value


def relative_config_path(value: Any, field: str) -> str:
    if not isinstance(value, str) or not value:
        raise CoverageError(f"{field} must be a non-empty relative path")
    path = PurePosixPath(value)
    if path.is_absolute() or ".." in path.parts or "." in path.parts:
        raise CoverageError(f"{field} must stay within the repository: {value}")
    return path.as_posix()


def load_config(path: Path) -> List[Dict[str, Any]]:
    config = load_json(path)
    if config.get("schema_version") != 1:
        raise CoverageError("coverage config schema_version must be 1")
    raw_targets = config.get("targets")
    if not isinstance(raw_targets, list) or not raw_targets:
        raise CoverageError("coverage config must define at least one target")

    targets: List[Dict[str, Any]] = []
    seen_names = set()
    seen_roots = set()
    for raw_target in raw_targets:
        if not isinstance(raw_target, dict):
            raise CoverageError("every coverage target must be an object")
        name = raw_target.get("name")
        if not isinstance(name, str) or not name:
            raise CoverageError("every coverage target needs a non-empty name")
        if name in seen_names:
            raise CoverageError(f"duplicate coverage target name: {name}")
        source_root = relative_config_path(
            raw_target.get("source_root"), f"{name}.source_root"
        )
        if not source_root.startswith("Sources/"):
            raise CoverageError(
                f"{name}.source_root must identify a first-party Sources directory"
            )
        if source_root in seen_roots:
            raise CoverageError(f"duplicate coverage source root: {source_root}")

        raw_allowed = raw_target.get("allowed_uninstrumented_sources", [])
        if not isinstance(raw_allowed, list):
            raise CoverageError(
                f"{name}.allowed_uninstrumented_sources must be an array"
            )
        allowed = sorted(
            relative_config_path(value, f"{name}.allowed_uninstrumented_sources")
            for value in raw_allowed
        )
        if len(allowed) != len(set(allowed)):
            raise CoverageError(f"duplicate uninstrumented source allowance in {name}")
        for allowed_path in allowed:
            if not (
                allowed_path == source_root
                or allowed_path.startswith(source_root + "/")
            ):
                raise CoverageError(
                    f"allowed source is outside {name}'s root: {allowed_path}"
                )

        seen_names.add(name)
        seen_roots.add(source_root)
        targets.append(
            {
                "name": name,
                "source_root": source_root,
                "allowed_uninstrumented_sources": allowed,
            }
        )
    return sorted(targets, key=lambda target: target["name"])


def repository_relative_path(filename: str, repository_root: Path) -> Optional[str]:
    path = Path(filename)
    if not path.is_absolute():
        path = repository_root / path
    try:
        relative = path.resolve().relative_to(repository_root)
    except ValueError:
        return None
    return relative.as_posix()


def raw_coverage_files(report: Mapping[str, Any]) -> List[Mapping[str, Any]]:
    if report.get("type") != "llvm.coverage.json.export":
        raise CoverageError("input is not an LLVM coverage JSON export")
    if not isinstance(report.get("version"), str) or not report["version"].strip():
        raise CoverageError("LLVM coverage report has no non-empty string version")
    data = report.get("data")
    if not isinstance(data, list) or not data:
        raise CoverageError("LLVM coverage report has no data entries")
    if len(data) != 1:
        raise CoverageError(
            "SwiftPM coverage export must contain exactly one data entry"
        )
    files: List[Mapping[str, Any]] = []
    for entry in data:
        if not isinstance(entry, dict) or not isinstance(entry.get("files"), list):
            raise CoverageError("LLVM coverage data entry has no files array")
        for file_entry in entry["files"]:
            if not isinstance(file_entry, dict):
                raise CoverageError("LLVM coverage file entry must be an object")
            if not isinstance(file_entry.get("filename"), str):
                raise CoverageError("LLVM coverage file entry has no filename")
            files.append(file_entry)
    return files


def metric(summary: Mapping[str, Any], metric_name: str) -> Dict[str, Any]:
    raw_metric = summary.get(metric_name)
    if not isinstance(raw_metric, dict):
        raise CoverageError(f"coverage file is missing {metric_name} summary")
    count = raw_metric.get("count")
    covered = raw_metric.get("covered")
    if (
        not isinstance(count, int)
        or isinstance(count, bool)
        or not isinstance(covered, int)
        or isinstance(covered, bool)
        or count < 0
        or covered < 0
        or covered > count
    ):
        raise CoverageError(f"invalid {metric_name} count/covered values")
    percent = 0.0 if count == 0 else round((covered * 100.0) / count, 2)
    return {
        "count": count,
        "covered": covered,
        "uncovered": count - covered,
        "percent": percent,
    }


def file_metrics(file_entry: Mapping[str, Any]) -> Dict[str, Any]:
    summary = file_entry.get("summary")
    if not isinstance(summary, dict):
        raise CoverageError(
            f"coverage file has no summary: {file_entry.get('filename', '<unknown>')}"
        )
    return {metric_name: metric(summary, metric_name) for metric_name in METRICS}


def aggregate(file_reports: Iterable[Mapping[str, Any]]) -> Dict[str, Any]:
    totals = {
        metric_name: {"count": 0, "covered": 0}
        for metric_name in METRICS
    }
    for file_report in file_reports:
        for metric_name in METRICS:
            file_metric = file_report[metric_name]
            totals[metric_name]["count"] += file_metric["count"]
            totals[metric_name]["covered"] += file_metric["covered"]
    result: Dict[str, Any] = {}
    for metric_name in METRICS:
        count = totals[metric_name]["count"]
        covered = totals[metric_name]["covered"]
        result[metric_name] = {
            "count": count,
            "covered": covered,
            "uncovered": count - covered,
            "percent": 0.0 if count == 0 else round((covered * 100.0) / count, 2),
        }
    return result


def expected_sources(repository_root: Path, source_root: str) -> List[str]:
    directory = repository_root / source_root
    if not directory.is_dir():
        raise CoverageError(f"configured source root does not exist: {source_root}")
    try:
        result = subprocess.run(
            [
                "git",
                "-C",
                str(repository_root),
                "ls-files",
                "-z",
                "--",
                source_root,
            ],
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
    sources = sorted(path for path in tracked_paths if path.endswith(".swift"))
    if not sources:
        raise CoverageError(
            f"configured source root has no tracked Swift files: {source_root}"
        )
    for source in sources:
        if not source.startswith(source_root + "/"):
            raise CoverageError(f"tracked source escaped configured root: {source}")
        source_path = repository_root / source
        if not source_path.is_file():
            raise CoverageError(f"tracked source is not a regular file: {source}")
        if repository_relative_path(str(source_path), repository_root) != source:
            raise CoverageError(
                f"tracked source resolves through an alias or outside the repository: {source}"
            )
    return sources


def excluded_category(relative_path: Optional[str]) -> str:
    if relative_path is None:
        return "outside_repository"
    if relative_path.startswith(".build/") or relative_path.startswith(".swiftpm/"):
        return "build_or_dependency"
    if relative_path.startswith("Tests/") or "/Tests/" in relative_path:
        return "tests_or_fixtures"
    if relative_path.startswith("Benchmarks/"):
        return "benchmarks"
    if ".derived/" in relative_path or "/DerivedSources/" in relative_path:
        return "generated"
    return "other_repository_sources"


def sha256_text(lines: Sequence[str]) -> str:
    payload = "".join(line + "\n" for line in lines).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def package_resolution_sha256(repository_root: Path) -> str:
    path = repository_root / "Package.resolved"
    if not path.is_file():
        raise CoverageError("Package.resolved is required for coverage provenance")
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build_report(
    raw_report: Mapping[str, Any],
    repository_root: Path,
    targets: Sequence[Mapping[str, Any]],
    source_commit: str,
    xcode_version: str,
    swift_version: str,
    sdk_version: str,
    llvm_cov_version: str,
    llvm_profdata_version: str,
    platform: str,
    architecture: str,
    runner_image: str,
    source_tree_state: str,
    coverage_command: str,
) -> Tuple[Dict[str, Any], List[str], List[str]]:
    if re.fullmatch(r"[0-9a-f]{40}", source_commit) is None:
        raise CoverageError("source commit must be a full 40-character Git SHA")
    toolchain_fields = {
        "xcode": xcode_version,
        "swift": swift_version,
        "sdk": sdk_version,
        "llvm_cov": llvm_cov_version,
        "llvm_profdata": llvm_profdata_version,
        "platform": platform,
        "architecture": architecture,
        "runner_image": runner_image,
    }
    for name, value in toolchain_fields.items():
        if not value.strip():
            raise CoverageError(f"toolchain provenance is empty: {name}")
    raw_files = raw_coverage_files(raw_report)
    expected_by_target: Dict[str, List[str]] = {}
    owner_by_path: Dict[str, str] = {}
    roots_by_target: Dict[str, str] = {}
    allowed_by_target: Dict[str, List[str]] = {}
    for target in targets:
        name = target["name"]
        roots_by_target[name] = target["source_root"]
        expected_by_target[name] = expected_sources(
            repository_root, target["source_root"]
        )
        allowed_by_target[name] = list(target["allowed_uninstrumented_sources"])
        for source in expected_by_target[name]:
            if source in owner_by_path:
                raise CoverageError(f"source belongs to multiple targets: {source}")
            owner_by_path[source] = name

    selected: Dict[str, Mapping[str, Any]] = {}
    excluded = Counter()
    unexpected_target_paths: List[str] = []
    for raw_file in raw_files:
        relative = repository_relative_path(raw_file["filename"], repository_root)
        if relative in owner_by_path:
            if relative in selected:
                raise CoverageError(f"duplicate first-party coverage entry: {relative}")
            selected[relative] = raw_file
            continue
        if relative is not None and relative.startswith("Sources/"):
            unexpected_target_paths.append(relative)
        excluded[excluded_category(relative)] += 1
    if unexpected_target_paths:
        raise CoverageError(
            "coverage reported untracked files inside target roots: "
            + ", ".join(sorted(set(unexpected_target_paths)))
        )

    target_reports: Dict[str, Any] = {}
    included_manifest: List[str] = []
    uninstrumented_manifest: List[str] = []
    all_file_reports: List[Mapping[str, Any]] = []
    for name in sorted(expected_by_target):
        expected = expected_by_target[name]
        instrumented = sorted(source for source in expected if source in selected)
        missing = sorted(source for source in expected if source not in selected)
        allowed = allowed_by_target[name]
        unexpected_missing = sorted(set(missing) - set(allowed))
        stale_allowances = sorted(set(allowed) - set(missing))
        if unexpected_missing:
            raise CoverageError(
                f"{name} sources disappeared from LLVM coverage without an allowance: "
                + ", ".join(unexpected_missing)
            )
        if stale_allowances:
            raise CoverageError(
                f"{name} uninstrumented allowances are stale or missing from disk: "
                + ", ".join(stale_allowances)
            )

        file_reports: List[Dict[str, Any]] = []
        for source in instrumented:
            report = {"path": source, **file_metrics(selected[source])}
            file_reports.append(report)
            all_file_reports.append(report)
            included_manifest.append(f"{name}\t{source}")
        for source in missing:
            uninstrumented_manifest.append(f"{name}\t{source}")

        target_reports[name] = {
            "source_root": roots_by_target[name],
            "source_files": len(expected),
            "instrumented_source_files": len(instrumented),
            "allowed_uninstrumented_source_files": missing,
            "totals": aggregate(file_reports),
            "files": file_reports,
        }

    largest_gaps = sorted(
        (
            report
            for report in all_file_reports
            if report["lines"]["uncovered"] > 0
            or report["functions"]["uncovered"] > 0
        ),
        key=lambda report: (
            -report["lines"]["uncovered"],
            -report["functions"]["uncovered"],
            report["path"],
        ),
    )[:20]

    report = {
        "schema_version": 1,
        "source_commit": source_commit,
        "source_tree_state": source_tree_state.strip(),
        "toolchain": {
            name: value.strip() for name, value in toolchain_fields.items()
        },
        "coverage_command": coverage_command,
        "package_resolved_sha256": package_resolution_sha256(repository_root),
        "raw_llvm_report": {
            "type": raw_report.get("type"),
            "version": raw_report.get("version"),
            "file_entries": len(raw_files),
        },
        "filtering": {
            "rule": "Only tracked .swift files under configured first-party target roots are included.",
            "included_source_files": len(included_manifest),
            "included_sources_sha256": sha256_text(included_manifest),
            "allowed_uninstrumented_source_files": len(uninstrumented_manifest),
            "excluded_raw_file_entries": sum(excluded.values()),
            "excluded_raw_file_entries_by_category": dict(sorted(excluded.items())),
        },
        "targets": target_reports,
        "overall": aggregate(all_file_reports),
        "largest_uncovered_files": largest_gaps,
    }
    return report, included_manifest, uninstrumented_manifest


def summary_markdown(report: Mapping[str, Any]) -> str:
    source_roots = ", ".join(
        f"`{target['source_root']}`"
        for _, target in sorted(report["targets"].items())
    )
    lines = [
        "# First-party Swift source coverage",
        "",
        f"- Source commit: `{report['source_commit']}`",
        f"- Command: `{report['coverage_command']}`",
        f"- Xcode: `{report['toolchain']['xcode'].replace(chr(10), ' / ')}`",
        f"- Swift: `{report['toolchain']['swift'].replace(chr(10), ' / ')}`",
        f"- SDK: `{report['toolchain']['sdk'].replace(chr(10), ' / ')}`",
        f"- LLVM coverage: `{report['toolchain']['llvm_cov'].replace(chr(10), ' / ')}`",
        f"- Source tree: `{report['source_tree_state']}`",
        f"- Filtering: only tracked `.swift` files under {source_roots}; "
        "dependencies, tests, benchmarks, build products, and generated "
        "expansion files are excluded.",
        "- This report is evidence only; it does not enforce a percentage threshold.",
        "",
        "| Target | Instrumented sources | Allowed uninstrumented | Lines | Functions |",
        "| --- | ---: | ---: | ---: | ---: |",
    ]
    for name, target in sorted(report["targets"].items()):
        line_metric = target["totals"]["lines"]
        function_metric = target["totals"]["functions"]
        lines.append(
            f"| {name} | {target['instrumented_source_files']} | "
            f"{len(target['allowed_uninstrumented_source_files'])} | "
            f"{line_metric['covered']}/{line_metric['count']} "
            f"({line_metric['percent']:.2f}%) | "
            f"{function_metric['covered']}/{function_metric['count']} "
            f"({function_metric['percent']:.2f}%) |"
        )

    lines.extend(["", "## Largest uncovered files", ""])
    gaps = report["largest_uncovered_files"]
    if gaps:
        lines.extend(
            [
                "This ranking identifies follow-up candidates; it is not a release gate.",
                "",
                "| Source | Uncovered lines | Uncovered functions |",
                "| --- | ---: | ---: |",
            ]
        )
        for file_report in gaps[:10]:
            lines.append(
                f"| `{file_report['path']}` | "
                f"{file_report['lines']['uncovered']} | "
                f"{file_report['functions']['uncovered']} |"
            )
    else:
        lines.append("No uncovered first-party lines or functions were reported.")

    uninstrumented = [
        source
        for target in report["targets"].values()
        for source in target["allowed_uninstrumented_source_files"]
    ]
    lines.extend(["", "## Allowed uninstrumented sources", ""])
    if uninstrumented:
        lines.extend(f"- `{source}`" for source in sorted(uninstrumented))
        lines.extend(
            [
                "",
                "These files have no executable regions in the current LLVM export. "
                "The explicit allowlist prevents other production sources from "
                "disappearing silently.",
            ]
        )
    else:
        lines.append("None.")
    return "\n".join(lines) + "\n"


def parse_arguments(argv: Optional[Sequence[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--llvm-json", required=True, type=Path)
    parser.add_argument("--repository-root", required=True, type=Path)
    parser.add_argument("--config", required=True, type=Path)
    parser.add_argument("--output-directory", required=True, type=Path)
    parser.add_argument("--source-commit", required=True)
    parser.add_argument("--xcode-version", required=True)
    parser.add_argument("--swift-version", required=True)
    parser.add_argument("--sdk-version", required=True)
    parser.add_argument("--llvm-cov-version", required=True)
    parser.add_argument("--llvm-profdata-version", required=True)
    parser.add_argument("--platform", required=True)
    parser.add_argument("--architecture", required=True)
    parser.add_argument("--runner-image", required=True)
    parser.add_argument("--source-tree-state", choices=("clean", "dirty"), required=True)
    parser.add_argument("--coverage-command", required=True)
    return parser.parse_args(argv)


def run(arguments: argparse.Namespace) -> None:
    repository_root = arguments.repository_root.resolve()
    if not repository_root.is_dir():
        raise CoverageError(
            f"repository root does not exist: {arguments.repository_root}"
        )
    output_directory = arguments.output_directory.resolve()
    output_directory.mkdir(parents=True, exist_ok=True)
    report, included, uninstrumented = build_report(
        raw_report=load_json(arguments.llvm_json),
        repository_root=repository_root,
        targets=load_config(arguments.config),
        source_commit=arguments.source_commit,
        xcode_version=arguments.xcode_version,
        swift_version=arguments.swift_version,
        sdk_version=arguments.sdk_version,
        llvm_cov_version=arguments.llvm_cov_version,
        llvm_profdata_version=arguments.llvm_profdata_version,
        platform=arguments.platform,
        architecture=arguments.architecture,
        runner_image=arguments.runner_image,
        source_tree_state=arguments.source_tree_state,
        coverage_command=arguments.coverage_command,
    )
    (output_directory / "first-party-coverage.json").write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    (output_directory / "included-sources.txt").write_text(
        "".join(line + "\n" for line in included), encoding="utf-8"
    )
    (output_directory / "allowed-uninstrumented-sources.txt").write_text(
        "".join(line + "\n" for line in uninstrumented), encoding="utf-8"
    )
    (output_directory / "summary.md").write_text(
        summary_markdown(report), encoding="utf-8"
    )


def main(argv: Optional[Sequence[str]] = None) -> int:
    try:
        run(parse_arguments(argv))
    except CoverageError as error:
        print(f"error: source coverage report: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
