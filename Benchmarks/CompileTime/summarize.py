#!/usr/bin/env python3
"""Validate and render SwiftQL's consumer compile-time scalability report.

The validator reparses every raw build log, verifies its hash against the JSON,
recomputes every derived statistic, and rejects reports whose declared matrix,
recorded measurements, and raw logs disagree. It uses only the Python standard
library.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import statistics
import sys
from pathlib import Path
from typing import Sequence


REPORT_FORMAT_VERSION = 1
CANONICAL_SCALES = (1, 10, 100, 500)
BUILD_MODES = (
    "clean_dependency_warm",
    "noop_incremental",
    "one_query_edit",
)
TOLERANCE = 1e-9

MEASUREMENT_KEYS = (
    "consumer",
    "tableCount",
    "queryCount",
    "buildMode",
    "repetition",
    "scheduleIndex",
    "startedAt",
    "finishedAt",
    "wallSeconds",
    "userSeconds",
    "systemSeconds",
    "peakRSSBytes",
    "peakRSSUnavailableReason",
    "timingMethod",
    "recompiledConsumerTarget",
    "rawLog",
    "rawLogSHA256",
)

TIME_LINE = re.compile(
    r"^\s*([0-9]+\.[0-9]+)\s+real\s+([0-9]+\.[0-9]+)\s+user\s+"
    r"([0-9]+\.[0-9]+)\s+sys\s*$",
    re.MULTILINE,
)
PEAK_RSS_LINE = re.compile(
    r"^\s*(\d+)\s+maximum resident set size\s*$",
    re.MULTILINE,
)


class ValidationError(RuntimeError):
    """The report is internally inconsistent or disagrees with its raw logs."""


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file_handle:
        for block in iter(lambda: file_handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValidationError(message)


def load_report(path: Path) -> dict[str, object]:
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValidationError(f"could not read {path}: {error}") from error
    require(isinstance(document, dict), f"{path} is not a JSON object")
    require(
        document.get("formatVersion") == REPORT_FORMAT_VERSION,
        f"unsupported report format: {document.get('formatVersion')!r}",
    )
    return document


def measurement_key(measurement: dict[str, object]) -> str:
    return (
        f"{measurement['consumer']}|{measurement['tableCount']}|"
        f"{measurement['queryCount']}|{measurement['buildMode']}"
    )


def point_label(table_count: int, query_count: int) -> str:
    return f"{table_count} tables x {query_count} queries"


def validate_structure(document: dict[str, object]) -> None:
    for section in ("workload", "sources", "environment", "provenance"):
        require(
            isinstance(document.get(section), dict),
            f"missing or malformed {section!r} section",
        )
    for section in ("consumers", "artifacts", "measurements"):
        require(
            isinstance(document.get(section), list) and document[section],
            f"missing or empty {section!r} section",
        )
    require(
        isinstance(document.get("results"), dict) and document["results"],
        "missing or empty 'results' section",
    )

    sources = document["sources"]
    revision = sources.get("swiftqlRevision")
    require(
        isinstance(revision, str) and re.fullmatch(r"[0-9a-f]{40}", revision),
        f"swiftqlRevision is not a full Git SHA: {revision!r}",
    )
    require(
        isinstance(sources.get("swiftqlDirty"), bool),
        "swiftqlDirty must be a boolean",
    )


def validate_workload(document: dict[str, object]) -> None:
    workload = document["workload"]
    assert isinstance(workload, dict)
    require(
        workload.get("identifier") == "consumer_compile_time_scalability",
        f"unexpected workload identifier: {workload.get('identifier')!r}",
    )
    require(
        list(workload.get("canonicalScales", ())) == list(CANONICAL_SCALES),
        "canonicalScales must be the declared 1/10/100/500 matrix",
    )
    require(
        list(workload.get("buildModes", ())) == list(BUILD_MODES),
        "buildModes must be the declared clean/no-op/one-query-edit set",
    )
    require(
        workload.get("attribution") == "whole_consumer_build",
        "the report must state that it attributes whole-consumer build cost",
    )
    for key in ("recordedTableScales", "recordedQueryScales"):
        scales = workload.get(key)
        require(
            isinstance(scales, list)
            and scales
            and all(isinstance(value, int) and value >= 1 for value in scales)
            and scales == sorted(set(scales)),
            f"{key} must be a sorted set of positive integers",
        )
        require(
            set(scales).issubset(set(CANONICAL_SCALES)),
            f"{key} contains a scale outside the canonical matrix: {scales!r}",
        )
    require(
        isinstance(workload.get("repetitionCount"), int)
        and workload["repetitionCount"] >= 1,
        "repetitionCount must be a positive integer",
    )


def expected_points(
    table_scales: Sequence[int],
    query_scales: Sequence[int],
    baseline_tables: int,
    baseline_queries: int,
) -> list[tuple[int, int]]:
    points: list[tuple[int, int]] = [(baseline_tables, baseline_queries)]
    for tables in table_scales:
        point = (tables, baseline_queries)
        if point not in points:
            points.append(point)
    for queries in query_scales:
        point = (baseline_tables, queries)
        if point not in points:
            points.append(point)
    return points


def validate_measurements(document: dict[str, object]) -> None:
    workload = document["workload"]
    assert isinstance(workload, dict)
    measurements = document["measurements"]
    assert isinstance(measurements, list)

    seen_schedule: set[int] = set()
    seen_identity: set[tuple[object, ...]] = set()
    seen_logs: set[str] = set()
    for measurement in measurements:
        require(
            isinstance(measurement, dict),
            "every measurement must be a JSON object",
        )
        missing = [key for key in MEASUREMENT_KEYS if key not in measurement]
        require(not missing, f"measurement is missing keys: {missing!r}")

        for key in ("wallSeconds", "userSeconds", "systemSeconds"):
            value = measurement[key]
            require(
                isinstance(value, (int, float)) and not isinstance(value, bool),
                f"{key} must be numeric",
            )
        require(
            float(measurement["wallSeconds"]) > 0.0,
            f"wallSeconds must be positive: {measurement['wallSeconds']!r}",
        )
        require(
            float(measurement["userSeconds"]) >= 0.0
            and float(measurement["systemSeconds"]) >= 0.0,
            "userSeconds and systemSeconds must be non-negative",
        )

        peak = measurement["peakRSSBytes"]
        reason = measurement["peakRSSUnavailableReason"]
        if peak is None:
            require(
                isinstance(reason, str) and reason,
                "a missing peak RSS must record an explicit unavailable reason",
            )
        else:
            require(
                isinstance(peak, int) and peak > 0,
                f"peakRSSBytes must be a positive integer: {peak!r}",
            )
            require(
                reason is None,
                "peakRSSBytes and peakRSSUnavailableReason cannot both be set",
            )

        recompiled = measurement["recompiledConsumerTarget"]
        require(
            isinstance(recompiled, bool),
            "recompiledConsumerTarget must be a boolean",
        )
        if measurement["buildMode"] == "noop_incremental":
            require(
                not recompiled,
                "a no-op measurement must not have recompiled the consumer",
            )
        else:
            require(
                recompiled,
                f"{measurement['buildMode']} must have recompiled the consumer",
            )

        schedule_index = measurement["scheduleIndex"]
        require(
            isinstance(schedule_index, int) and schedule_index >= 1,
            "scheduleIndex must be a positive integer",
        )
        require(
            schedule_index not in seen_schedule,
            f"duplicate scheduleIndex: {schedule_index}",
        )
        seen_schedule.add(schedule_index)

        identity = (
            measurement["consumer"],
            measurement["tableCount"],
            measurement["queryCount"],
            measurement["buildMode"],
            measurement["repetition"],
        )
        require(identity not in seen_identity, f"duplicate measurement: {identity!r}")
        seen_identity.add(identity)

        raw_log = measurement["rawLog"]
        require(isinstance(raw_log, str) and raw_log, "rawLog must be a path")
        require(raw_log not in seen_logs, f"duplicate rawLog: {raw_log!r}")
        seen_logs.add(raw_log)

        started_at = measurement["startedAt"]
        finished_at = measurement["finishedAt"]
        require(
            isinstance(started_at, str) and isinstance(finished_at, str),
            f"measurement {identity!r} has a non-string startedAt/finishedAt",
        )
        require(
            started_at < finished_at,
            f"measurement {identity!r} did not finish after it started",
        )

    require(
        sorted(seen_schedule) == list(range(1, len(measurements) + 1)),
        "scheduleIndex values must be contiguous from 1",
    )


def validate_matrix_coverage(document: dict[str, object]) -> None:
    workload = document["workload"]
    consumers = document["consumers"]
    measurements = document["measurements"]
    assert isinstance(workload, dict)
    assert isinstance(consumers, list) and isinstance(measurements, list)

    points = expected_points(
        workload["recordedTableScales"],
        workload["recordedQueryScales"],
        workload["baselineTableCount"],
        workload["baselineQueryCount"],
    )
    repetitions = int(workload["repetitionCount"])

    recorded: dict[str, set[tuple[int, int, str, int]]] = {}
    for measurement in measurements:
        recorded.setdefault(str(measurement["consumer"]), set()).add(
            (
                int(measurement["tableCount"]),
                int(measurement["queryCount"]),
                str(measurement["buildMode"]),
                int(measurement["repetition"]),
            )
        )

    declared = {str(consumer["identifier"]) for consumer in consumers}
    require(
        set(recorded) == declared,
        f"declared consumers {sorted(declared)} do not match recorded "
        f"consumers {sorted(recorded)}",
    )

    for consumer in consumers:
        assert isinstance(consumer, dict)
        identifier = str(consumer["identifier"])
        modes = list(consumer["buildModes"])
        require(
            modes and set(modes).issubset(set(BUILD_MODES)),
            f"{identifier} declares unknown build modes: {modes!r}",
        )
        applicability = consumer.get("applicability")
        require(
            isinstance(applicability, dict)
            and applicability.get("tableAxis") in ("applicable", "not_applicable")
            and applicability.get("queryAxis") in ("applicable", "not_applicable")
            and applicability.get("oneQueryEdit") in ("applicable", "not_applicable")
            and isinstance(applicability.get("note"), str)
            and applicability["note"],
            f"{identifier} must declare a complete applicability entry",
        )
        scales_queries = applicability["queryAxis"] == "applicable"
        require(
            scales_queries == ("one_query_edit" in modes),
            f"{identifier} query-axis applicability disagrees with its build modes",
        )
        require(
            (applicability["oneQueryEdit"] == "applicable") == ("one_query_edit" in modes),
            f"{identifier} one-query-edit applicability disagrees with its build modes",
        )

        consumer_points = [
            point
            for point in points
            if scales_queries or point[1] == workload["baselineQueryCount"]
        ]
        expected = {
            (tables, queries, mode, repetition)
            for tables, queries in consumer_points
            for mode in modes
            for repetition in range(1, repetitions + 1)
        }
        missing = sorted(expected - recorded[identifier])
        extra = sorted(recorded[identifier] - expected)
        require(not missing, f"{identifier} is missing measurements: {missing!r}")
        require(not extra, f"{identifier} recorded unexpected measurements: {extra!r}")


def validate_artifacts(document: dict[str, object]) -> None:
    workload = document["workload"]
    artifacts = document["artifacts"]
    measurements = document["measurements"]
    assert isinstance(workload, dict)
    assert isinstance(artifacts, list) and isinstance(measurements, list)

    measured_points = {
        (str(item["consumer"]), int(item["tableCount"]), int(item["queryCount"]))
        for item in measurements
    }
    artifact_points: set[tuple[str, int, int]] = set()
    for artifact in artifacts:
        require(isinstance(artifact, dict), "every artifact must be a JSON object")
        key = (
            str(artifact["consumer"]),
            int(artifact["tableCount"]),
            int(artifact["queryCount"]),
        )
        require(key not in artifact_points, f"duplicate artifact entry: {key!r}")
        artifact_points.add(key)

        source_bytes = artifact.get("generatedSourceBytes")
        require(
            isinstance(source_bytes, int) and source_bytes > 0,
            f"generatedSourceBytes must be positive for {key!r}",
        )
        digests = artifact.get("generatedSourceSHA256")
        require(
            isinstance(digests, dict)
            and digests
            and all(
                isinstance(name, str) and re.fullmatch(r"[0-9a-f]{64}", str(digest))
                for name, digest in digests.items()
            ),
            f"generatedSourceSHA256 must hash every generated file for {key!r}",
        )
        for optional_key in (
            "swiftmoduleBytes",
            "objectBytes",
            "staticLibraryBytes",
            "pluginGeneratedSwiftBytes",
            "macroExpansionBytes",
        ):
            value = artifact.get(optional_key, "missing")
            require(
                value is None or (isinstance(value, int) and value > 0),
                f"{optional_key} must be a positive integer or null for {key!r}",
            )
        reason = artifact.get("macroExpansionUnavailableReason")
        if artifact.get("macroExpansionBytes") is None:
            require(
                isinstance(reason, str) and reason,
                f"{key!r} must record why macro-expansion size is unavailable",
            )
        else:
            require(
                reason is None,
                f"{key!r} has both a macroExpansionBytes measurement and an "
                "unavailability reason -- contradictory",
            )

    require(
        artifact_points == measured_points,
        "artifact points and measured points disagree: "
        f"{sorted(artifact_points ^ measured_points)!r}",
    )


def validate_raw_logs(document: dict[str, object], report_path: Path) -> None:
    measurements = document["measurements"]
    assert isinstance(measurements, list)
    directory = report_path.parent.resolve()
    for measurement in measurements:
        raw_log = str(measurement["rawLog"])
        log_path = (directory / raw_log).resolve()
        require(
            log_path == directory or directory in log_path.parents,
            f"rawLog escapes the report directory: {raw_log!r}",
        )
        require(log_path.is_file(), f"missing raw build log: {log_path}")
        digest = sha256_file(log_path)
        require(
            digest == measurement["rawLogSHA256"],
            f"raw log hash mismatch for {log_path}: "
            f"{digest} != {measurement['rawLogSHA256']}",
        )
        text = log_path.read_text(encoding="utf-8", errors="replace")

        times = TIME_LINE.findall(text)
        require(
            len(times) == 1,
            f"{log_path} does not contain exactly one real/user/sys line",
        )
        wall, user, system = (float(value) for value in times[0])
        for recorded, parsed, name in (
            (float(measurement["wallSeconds"]), wall, "wallSeconds"),
            (float(measurement["userSeconds"]), user, "userSeconds"),
            (float(measurement["systemSeconds"]), system, "systemSeconds"),
        ):
            require(
                abs(recorded - parsed) <= TOLERANCE,
                f"{name} in {log_path} disagrees with the report: "
                f"{parsed} != {recorded}",
            )

        if measurement["peakRSSBytes"] is not None:
            peaks = PEAK_RSS_LINE.findall(text)
            require(
                len(peaks) == 1,
                f"{log_path} does not contain exactly one peak RSS value",
            )
            require(
                int(peaks[0]) == int(measurement["peakRSSBytes"]),
                f"peak RSS in {log_path} disagrees with the report",
            )

        recompiled = bool(
            re.search(r"(Compiling Consumer\b|Emitting module Consumer\b)", text)
        )
        require(
            recompiled == bool(measurement["recompiledConsumerTarget"]),
            f"{log_path} recompilation evidence disagrees with the report",
        )


def validate_results(document: dict[str, object]) -> dict[str, dict[str, object]]:
    measurements = document["measurements"]
    results = document["results"]
    assert isinstance(measurements, list) and isinstance(results, dict)

    grouped: dict[str, list[dict[str, object]]] = {}
    for measurement in measurements:
        grouped.setdefault(measurement_key(measurement), []).append(measurement)

    require(
        set(grouped) == set(results),
        "results groups and measurement groups disagree: "
        f"{sorted(set(grouped) ^ set(results))!r}",
    )

    recomputed: dict[str, dict[str, object]] = {}
    for key, group in grouped.items():
        walls = [float(item["wallSeconds"]) for item in group]
        users = [float(item["userSeconds"]) for item in group]
        systems = [float(item["systemSeconds"]) for item in group]
        peaks = [
            int(item["peakRSSBytes"])
            for item in group
            if isinstance(item["peakRSSBytes"], int)
        ]
        median_wall = statistics.median(walls)
        summary = {
            "repetitionCount": len(group),
            "medianWallSeconds": median_wall,
            "minWallSeconds": min(walls),
            "maxWallSeconds": max(walls),
            "wallSpreadPercent": (max(walls) - min(walls)) / median_wall * 100.0,
            "medianUserSeconds": statistics.median(users),
            "medianSystemSeconds": statistics.median(systems),
            "maxPeakRSSBytes": max(peaks) if len(peaks) == len(group) else None,
        }
        stored = results[key]
        require(isinstance(stored, dict), f"results[{key!r}] is not an object")
        require(
            set(stored) == set(summary),
            f"results[{key!r}] keys differ from the recomputed summary",
        )
        for name, value in summary.items():
            recorded = stored[name]
            if value is None or recorded is None:
                require(
                    value == recorded,
                    f"results[{key!r}][{name!r}] disagrees: {recorded!r} != {value!r}",
                )
            elif isinstance(value, int):
                require(
                    recorded == value,
                    f"results[{key!r}][{name!r}] disagrees: {recorded!r} != {value!r}",
                )
            else:
                require(
                    isinstance(recorded, (int, float))
                    and abs(float(recorded) - value) <= 1e-6,
                    f"results[{key!r}][{name!r}] disagrees: {recorded!r} != {value!r}",
                )
        recomputed[key] = summary
    return recomputed


def validate(
    document: dict[str, object],
    report_path: Path,
    *,
    require_full_matrix: bool,
) -> dict[str, dict[str, object]]:
    validate_structure(document)
    validate_workload(document)
    validate_measurements(document)
    validate_matrix_coverage(document)
    validate_artifacts(document)
    validate_raw_logs(document, report_path)
    if require_full_matrix:
        workload = document["workload"]
        assert isinstance(workload, dict)
        for key in ("recordedTableScales", "recordedQueryScales"):
            require(
                list(workload[key]) == list(CANONICAL_SCALES),
                f"{key} is {workload[key]!r}; the full 1/10/100/500 matrix was "
                f"requested",
            )
    return validate_results(document)


# --------------------------------------------------------------------------
# Rendering
# --------------------------------------------------------------------------


def format_seconds(value: float) -> str:
    return f"{value:,.2f} s"


def format_bytes(value: int | None) -> str:
    if value is None:
        return "unavailable"
    if value >= 1024 * 1024:
        return f"{value / (1024 * 1024):,.1f} MiB"
    if value >= 1024:
        return f"{value / 1024:,.1f} KiB"
    return f"{value} B"


def render(document: dict[str, object], summaries: dict[str, dict[str, object]]) -> str:
    workload = document["workload"]
    environment = document["environment"]
    sources = document["sources"]
    consumers = document["consumers"]
    assert isinstance(workload, dict) and isinstance(environment, dict)
    assert isinstance(sources, dict) and isinstance(consumers, list)

    lines: list[str] = []
    title = "SwiftQL consumer compile-time scalability"
    lines.append(title)
    lines.append("=" * len(title))
    lines.append("")
    lines.append(f"Report generated: {document['generatedAt']}")
    lines.append(
        f"SwiftQL revision: {sources['swiftqlRevision']}"
        + (" (dirty)" if sources["swiftqlDirty"] else "")
    )
    lines.append(
        f"Machine: {environment.get('model')} / {environment.get('processor')} / "
        f"{environment.get('coreCount')} cores"
    )
    lines.append(f"Toolchain: {environment.get('swift')}")
    lines.append(
        f"Configuration: {workload['configuration']}, "
        f"{workload['repetitionCount']} independent build processes per cell, "
        f"dependency-warm"
    )
    lines.append(
        f"Recorded table scales: {workload['recordedTableScales']}; "
        f"recorded query scales: {workload['recordedQueryScales']}; "
        f"canonical matrix: {workload['canonicalScales']}"
    )
    lines.append("")
    lines.append(
        "Cost is whole-consumer build cost. No part of any number is attributed "
        "to macro expansion alone."
    )
    lines.append("")

    applicability_heading = "Applicability"
    lines.append(applicability_heading)
    lines.append("-" * len(applicability_heading))
    for consumer in consumers:
        assert isinstance(consumer, dict)
        applicability = consumer["applicability"]
        assert isinstance(applicability, dict)
        lines.append(
            f"  {consumer['identifier']}: table axis "
            f"{applicability['tableAxis']}, query axis "
            f"{applicability['queryAxis']}, one-query edit "
            f"{applicability['oneQueryEdit']}"
        )
        lines.append(f"      {applicability['note']}")
    lines.append("")

    measurements = document["measurements"]
    assert isinstance(measurements, list)
    points = sorted(
        {
            (int(item["tableCount"]), int(item["queryCount"]))
            for item in measurements
        }
    )
    identifiers = [str(consumer["identifier"]) for consumer in consumers]

    for mode in BUILD_MODES:
        relevant = [
            identifier
            for identifier in identifiers
            if any(key.startswith(f"{identifier}|") and key.endswith(f"|{mode}")
                   for key in summaries)
        ]
        if not relevant:
            continue
        heading = f"Median wall time - {mode}"
        lines.append(heading)
        lines.append("-" * len(heading))
        header = f"  {'scale':<24}" + "".join(
            f"{identifier:>22}" for identifier in relevant
        )
        lines.append(header)
        for tables, queries in points:
            cells = []
            for identifier in relevant:
                summary = summaries.get(f"{identifier}|{tables}|{queries}|{mode}")
                if summary is None:
                    cells.append(f"{'n/a':>22}")
                else:
                    cell = (
                        f"{format_seconds(float(summary['medianWallSeconds']))}"
                        f" +/-{float(summary['wallSpreadPercent']):.0f}%"
                    )
                    cells.append(f"{cell:>22}")
            lines.append(f"  {point_label(tables, queries):<24}" + "".join(cells))
        lines.append("")

    outputs_heading = "Build outputs and generated source"
    lines.append(outputs_heading)
    lines.append("-" * len(outputs_heading))
    lines.append(
        f"  {'consumer':<20}{'scale':<24}{'source':>12}{'objects':>12}"
        f"{'swiftmodule':>14}{'static lib':>14}{'plugin swift':>14}"
    )
    artifacts = document["artifacts"]
    assert isinstance(artifacts, list)
    for artifact in sorted(
        artifacts,
        key=lambda item: (
            str(item["consumer"]),
            int(item["tableCount"]),
            int(item["queryCount"]),
        ),
    ):
        lines.append(
            f"  {str(artifact['consumer']):<20}"
            f"{point_label(int(artifact['tableCount']), int(artifact['queryCount'])):<24}"
            f"{format_bytes(int(artifact['generatedSourceBytes'])):>12}"
            f"{format_bytes(artifact['objectBytes']):>12}"
            f"{format_bytes(artifact['swiftmoduleBytes']):>14}"
            f"{format_bytes(artifact['staticLibraryBytes']):>14}"
            f"{format_bytes(artifact['pluginGeneratedSwiftBytes']):>14}"
        )
    lines.append("")
    lines.append(
        "Peak RSS is the peak of the whole `swift build` process tree, not an "
        "allocation attributed to any one API."
    )
    lines.append(
        "These are machine-dependent measurements from one host. Nothing here "
        "is a CI gate or a regression threshold."
    )
    return "\n".join(lines) + "\n"


def compare(
    baseline: dict[str, object],
    baseline_summaries: dict[str, dict[str, object]],
    candidate: dict[str, object],
    candidate_summaries: dict[str, dict[str, object]],
) -> str:
    for section, keys in (
        (
            "workload",
            (
                "identifier",
                "configuration",
                "repetitionCount",
                "attribution",
                "recordedTableScales",
                "recordedQueryScales",
                "buildModes",
            ),
        ),
        ("environment", ("model", "processor", "architecture", "swift")),
    ):
        left = baseline[section]
        right = candidate[section]
        assert isinstance(left, dict) and isinstance(right, dict)
        for key in keys:
            require(
                left.get(key) == right.get(key),
                f"{section}.{key} differs between the reports: "
                f"{left.get(key)!r} != {right.get(key)!r}",
            )

    def consumer_compatibility_key(consumer: dict[str, object]) -> dict[str, object]:
        return {
            "dependencies": consumer["dependencies"],
            "buildModes": consumer["buildModes"],
            "applicability": consumer["applicability"],
        }

    baseline_consumers = {
        str(consumer["identifier"]): consumer_compatibility_key(consumer)  # type: ignore[arg-type]
        for consumer in baseline["consumers"]  # type: ignore[union-attr]
    }
    candidate_consumers = {
        str(consumer["identifier"]): consumer_compatibility_key(consumer)  # type: ignore[arg-type]
        for consumer in candidate["consumers"]  # type: ignore[union-attr]
    }
    require(
        set(baseline_consumers) == set(candidate_consumers),
        "the two reports cover different consumers",
    )
    for identifier, compatibility in baseline_consumers.items():
        require(
            compatibility == candidate_consumers[identifier],
            f"{identifier} dependency pins, build modes, or applicability "
            "drifted between the reports",
        )

    shared = sorted(set(baseline_summaries) & set(candidate_summaries))
    require(shared, "the two reports share no comparable cells")

    title = "Compile-time comparison"
    lines = [title, "=" * len(title), ""]
    lines.append(
        f"  {'cell':<52}{'baseline':>14}{'candidate':>14}{'ratio':>10}"
    )
    for key in shared:
        left = float(baseline_summaries[key]["medianWallSeconds"])
        right = float(candidate_summaries[key]["medianWallSeconds"])
        lines.append(
            f"  {key:<52}{format_seconds(left):>14}{format_seconds(right):>14}"
            f"{right / left:>9.2f}x"
        )
    lines.append("")
    lines.append(
        "Both reports come from one machine each. Treat a small ratio as noise "
        "until repeated runs establish this harness's variance."
    )
    return "\n".join(lines) + "\n"


def create_argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Validate a compile-time scalability report against its raw build "
            "logs and render the human-readable matrix."
        )
    )
    parser.add_argument("report", type=Path, nargs="?")
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--candidate", type=Path)
    parser.add_argument(
        "--require-full-matrix",
        action="store_true",
        help="reject a report that does not record every canonical scale",
    )
    return parser


def main(arguments: Sequence[str] | None = None) -> int:
    options = create_argument_parser().parse_args(arguments)
    try:
        if options.baseline is not None or options.candidate is not None:
            if options.baseline is None or options.candidate is None:
                raise ValidationError(
                    "--baseline and --candidate must be given together"
                )
            if options.report is not None:
                raise ValidationError(
                    "pass either one report or --baseline/--candidate, not both"
                )
            baseline_path = options.baseline.expanduser().resolve()
            candidate_path = options.candidate.expanduser().resolve()
            baseline = load_report(baseline_path)
            candidate = load_report(candidate_path)
            baseline_summaries = validate(
                baseline,
                baseline_path,
                require_full_matrix=options.require_full_matrix,
            )
            candidate_summaries = validate(
                candidate,
                candidate_path,
                require_full_matrix=options.require_full_matrix,
            )
            sys.stdout.write(
                compare(baseline, baseline_summaries, candidate, candidate_summaries)
            )
            return 0

        if options.report is None:
            raise ValidationError("a report path is required")
        report_path = options.report.expanduser().resolve()
        document = load_report(report_path)
        summaries = validate(
            document,
            report_path,
            require_full_matrix=options.require_full_matrix,
        )
        sys.stdout.write(render(document, summaries))
        return 0
    except (ValidationError, OSError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
