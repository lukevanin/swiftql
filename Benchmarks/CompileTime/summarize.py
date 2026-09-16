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
import math
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
# SwiftPM's own build duration, printed at the end of a successful build:
# `Build of product 'ConsumerLibrary' complete! (9.83s)`. The product clause is
# optional so a plain `Build complete! (0.31s)` also parses. The decimal mark
# can be `.` or `,` (a locale-formatted `(9,83s)`), and the unit can be `s`,
# `sec`, or `seconds`. `parse_swiftpm_duration` documents how ANSI codes,
# carriage returns, and more than one `complete!` line are handled.
SWIFTPM_COMPLETE_LINE = re.compile(
    r"^\s*Build (?:of product '[^']+' )?complete! "
    r"\(([0-9]+(?:[.,][0-9]+)?) ?(?:s|sec|seconds)\)\s*$"
)
ANSI_ESCAPE = re.compile(
    r"\x1b(?:\[[0-?]*[ -/]*[@-~]|\][^\x07\x1b]*(?:\x07|\x1b\\)|[@-Z\\-_])"
)
# Evidence that the Consumer module compiled. The native build system prints
# `Compiling Consumer ...` or `Emitting module Consumer`. Swift Build (the
# default from Swift 6.4 / Xcode 27) prints neither; run.py therefore builds
# with `-v`, and the verbose compiler driver invocation `-module-name Consumer`
# is the evidence. A no-op build prints none of the three.
RECOMPILE_MARKER = re.compile(
    r"(Compiling Consumer\b|Emitting module Consumer\b|-module-name Consumer\b)"
)

# A sample is rejected when its `/usr/bin/time` wall time is greater than
#
#     WALL_TO_SWIFTPM_FACTOR * swiftpmSeconds + WALL_TO_SWIFTPM_ALLOWANCE_SECONDS
#
# SwiftPM's duration does not count process start, manifest loading, or
# package resolution, so a healthy wall time is always a little longer. On the
# recorded host that overhead is at most about 0.8 s, and a healthy sample is
# never more than 1.2x SwiftPM's duration once the build itself takes more than
# a few seconds. The allowance absorbs the fixed overhead of a sub-second no-op
# build; the factor keeps a long build honest. A wall time outside the limit
# means the `swift build` process waited on something other than its own build
# (for example, a lock held by another SwiftPM process on a loaded host), so
# the sample does not measure build cost. Both values are fixed on purpose:
# they are not command-line options, and changing them changes which recorded
# samples are valid.
WALL_TO_SWIFTPM_FACTOR = 2.0
WALL_TO_SWIFTPM_ALLOWANCE_SECONDS = 2.0


class ValidationError(RuntimeError):
    """The report is internally inconsistent or disagrees with its raw logs."""


def swiftpm_durations(text: str) -> list[float]:
    """Every SwiftPM `complete!` duration in `text`, in order.

    ANSI escape sequences are removed first. The text is then split on line
    feeds and on carriage returns, so a `complete!` line that follows a `\\r`
    progress update on the same terminal line is still found. A `,` decimal
    mark is read as `.`.
    """

    plain = ANSI_ESCAPE.sub("", text)
    durations: list[float] = []
    for segment in re.split(r"\r\n|\r|\n", plain):
        match = SWIFTPM_COMPLETE_LINE.match(segment)
        if match:
            durations.append(float(match.group(1).replace(",", ".")))
    return durations


def parse_swiftpm_duration(text: str) -> float:
    """Return SwiftPM's build duration for one timed `swift build` process.

    When the log has more than one `complete!` line, the result is the sum of
    their durations. Every such line reports a build that ran inside the same
    timed process, so that process's wall time must cover all of them. The sum
    is therefore the honest comparator: it never rejects a sample that any
    single line would keep.
    """

    durations = swiftpm_durations(text)
    require(
        bool(durations),
        "log does not contain a SwiftPM "
        "\"Build of product '...' complete! (N.NNs)\" line",
    )
    for duration in durations:
        require(
            duration > 0.0,
            f"SwiftPM build duration must be positive: {duration}",
        )
    return sum(durations)


def wall_limit_seconds(swiftpm_seconds: float) -> float:
    """The longest wall time that is consistent with SwiftPM's own duration."""

    return (
        WALL_TO_SWIFTPM_FACTOR * swiftpm_seconds + WALL_TO_SWIFTPM_ALLOWANCE_SECONDS
    )


def wall_is_consistent(wall_seconds: float, swiftpm_seconds: float) -> bool:
    return wall_seconds <= wall_limit_seconds(swiftpm_seconds)


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


CONSUMER_TEMPLATE_DIRECTORY = Path(__file__).resolve().parent / "Consumers"
DEFAULT_DECLARATIONS_PER_FILE = 50


def expected_generated_files(
    table_count: int,
    query_count: int,
    *,
    schema_only: bool,
    declarations_per_file: int,
) -> list[str]:
    """The generated file names that a table and query scale must produce.

    Swift consumers split tables and queries into files of at most
    `declarations_per_file` declarations: `Tables.swift`, `Tables2.swift`, and
    so on. A schema-only consumer (Lighter) generates one `schema.sql`.
    """

    if schema_only:
        return ["Sources/Consumer/schema.sql"]

    def names(stem: str, count: int) -> list[str]:
        return [
            f"Sources/Consumer/{stem}{'' if index == 0 else index + 1}.swift"
            for index in range(math.ceil(count / declarations_per_file))
        ]

    return sorted(names("Tables", table_count) + names("Queries", query_count))


def template_source_files(template: str) -> set[str]:
    directory = CONSUMER_TEMPLATE_DIRECTORY / template / "Sources" / "Consumer"
    if not directory.is_dir():
        return set()
    return {
        f"Sources/Consumer/{path.name}"
        for path in directory.iterdir()
        if path.is_file() and not path.name.startswith(".")
    }


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
    templates = {
        str(consumer.get("identifier")): str(consumer.get("template"))
        for consumer in document.get("consumers", [])
        if isinstance(consumer, dict) and consumer.get("template")
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
        # The generated file names must match the declared scale, so a report
        # cannot claim a 1-table point while its generator wrote 500 tables.
        declarations_per_file = workload.get(
            "declarationsPerFile", DEFAULT_DECLARATIONS_PER_FILE
        )
        require(
            isinstance(declarations_per_file, int) and declarations_per_file >= 1,
            "declarationsPerFile must be a positive integer",
        )
        expected_names = expected_generated_files(
            key[1],
            key[2],
            schema_only=any(str(name).endswith(".sql") for name in digests),
            declarations_per_file=declarations_per_file,
        )
        require(
            sorted(digests) == expected_names,
            f"generated files for {key!r} disagree with the declared scale: "
            f"{sorted(digests)!r} != {expected_names!r}",
        )
        # Reports from issue #670 on also record the files actually present in
        # the consumer's Sources/Consumer when it was built. Any file that is
        # neither generated for this point nor part of the checked-in template,
        # such as a stale Tables2.swift from a larger point, fails validation.
        if "consumerSourceFiles" in artifact:
            files = artifact["consumerSourceFiles"]
            require(
                isinstance(files, list) and all(isinstance(name, str) for name in files),
                f"consumerSourceFiles must be a list of paths for {key!r}",
            )
            template = templates.get(key[0])
            expected_files = set(digests) | (
                template_source_files(template) if template else set()
            )
            require(
                set(files) == expected_files,
                f"consumer sources for {key!r} are not exactly the generated and "
                f"template files: extra {sorted(set(files) - expected_files)!r}, "
                f"missing {sorted(expected_files - set(files))!r}",
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
        try:
            parse_swiftpm_duration(text)
        except ValidationError as error:
            raise ValidationError(f"{log_path}: {error}") from error
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

        recompiled = RECOMPILE_MARKER.search(text) is not None
        require(
            recompiled == bool(measurement["recompiledConsumerTarget"]),
            f"{log_path} recompilation evidence disagrees with the report",
        )


def rejected_samples(
    document: dict[str, object],
    report_path: Path,
) -> list[dict[str, object]]:
    """Return every measurement whose wall time its own build log contradicts.

    Run this only on a report that `validate` accepted: it trusts that each raw
    log exists, matches its hash, and contains one SwiftPM `complete!` line.
    """

    measurements = document["measurements"]
    assert isinstance(measurements, list)
    directory = report_path.parent.resolve()
    rejections: list[dict[str, object]] = []
    for measurement in measurements:
        text = (directory / str(measurement["rawLog"])).read_text(
            encoding="utf-8",
            errors="replace",
        )
        swiftpm_seconds = parse_swiftpm_duration(text)
        wall_seconds = float(measurement["wallSeconds"])
        if wall_is_consistent(wall_seconds, swiftpm_seconds):
            continue
        rejections.append(
            {
                "consumer": measurement["consumer"],
                "tableCount": measurement["tableCount"],
                "queryCount": measurement["queryCount"],
                "buildMode": measurement["buildMode"],
                "repetition": measurement["repetition"],
                "rawLog": measurement["rawLog"],
                "wallSeconds": wall_seconds,
                "userSeconds": float(measurement["userSeconds"]),
                "swiftpmSeconds": swiftpm_seconds,
                "wallLimitSeconds": wall_limit_seconds(swiftpm_seconds),
            }
        )
    return rejections


def rejection_rule_description() -> str:
    return (
        f"a sample is rejected when its wall time is greater than "
        f"{WALL_TO_SWIFTPM_FACTOR:g} x SwiftPM's own build duration + "
        f"{WALL_TO_SWIFTPM_ALLOWANCE_SECONDS:g} s"
    )


def medians_without_rejected(
    measurements: Sequence[dict[str, object]],
    rejections: Sequence[dict[str, object]],
) -> dict[str, dict[str, object]]:
    """For each cell with a rejected sample, its medians with and without them.

    `medianWallSecondsWithoutRejected` is `None` when every sample in the cell
    was rejected.
    """

    rejected_logs = {str(rejection["rawLog"]) for rejection in rejections}
    affected = {measurement_key(rejection) for rejection in rejections}
    result: dict[str, dict[str, object]] = {}
    for key in sorted(affected):
        group = [item for item in measurements if measurement_key(item) == key]
        walls = [float(item["wallSeconds"]) for item in group]
        accepted = [
            float(item["wallSeconds"])
            for item in group
            if str(item["rawLog"]) not in rejected_logs
        ]
        result[key] = {
            "sampleCount": len(group),
            "acceptedSampleCount": len(accepted),
            "medianWallSeconds": statistics.median(walls) if walls else None,
            "medianWallSecondsWithoutRejected": (
                statistics.median(accepted) if accepted else None
            ),
        }
    return result


def render_rejections(
    rejections: Sequence[dict[str, object]],
    measurements: Sequence[dict[str, object]] = (),
) -> str:
    heading = "Rejected samples"
    lines = [heading, "-" * len(heading)]
    lines.append(f"  Rule: {rejection_rule_description()}.")
    if not rejections:
        lines.append(
            "  None. Every wall time is consistent with its own build log."
        )
        return "\n".join(lines) + "\n"
    for rejection in rejections:
        wall = float(rejection["wallSeconds"])
        swiftpm = float(rejection["swiftpmSeconds"])
        lines.append(
            f"  {rejection['consumer']} "
            f"{point_label(int(rejection['tableCount']), int(rejection['queryCount']))} "
            f"{rejection['buildMode']} repetition {rejection['repetition']}: "
            f"wall {format_seconds(wall)}, user "
            f"{format_seconds(float(rejection['userSeconds']))}, SwiftPM "
            f"{format_seconds(swiftpm)}, limit "
            f"{format_seconds(float(rejection['wallLimitSeconds']))} "
            f"({wall / swiftpm:,.1f}x)"
        )
        lines.append(f"      {rejection['rawLog']}")
    if measurements:
        lines.append("  Median wall time of each affected cell:")
        for key, medians in medians_without_rejected(measurements, rejections).items():
            consumer, tables, queries, mode = key.split("|")
            with_all = medians["medianWallSeconds"]
            without = medians["medianWallSecondsWithoutRejected"]
            without_text = (
                f"{format_seconds(float(without))} from "
                f"{medians['acceptedSampleCount']} of {medians['sampleCount']} samples"
                if without is not None
                else f"none (0 of {medians['sampleCount']} samples accepted)"
            )
            lines.append(
                f"    {consumer} {point_label(int(tables), int(queries))} {mode}: "
                f"with rejected samples {format_seconds(float(with_all))}; "
                f"without rejected samples {without_text}"
            )
    lines.append(
        "  A cell marked [R] in the matrix contains at least one rejected "
        "sample. Its matrix median includes that sample, so it does not "
        "measure build cost; use the median without rejected samples above."
    )
    return "\n".join(lines) + "\n"


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


def render(
    document: dict[str, object],
    summaries: dict[str, dict[str, object]],
    rejections: Sequence[dict[str, object]] = (),
) -> str:
    rejected_keys = {measurement_key(rejection) for rejection in rejections}
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
        if rejected_keys:
            lines.append(
                "  Medians include every recorded sample, rejected samples too. "
                "See \"Rejected samples\" for [R] cells without them."
            )
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
                    if f"{identifier}|{tables}|{queries}|{mode}" in rejected_keys:
                        cell += " [R]"
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
    lines.append(render_rejections(rejections, measurements).rstrip("\n"))
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
        (
            "environment",
            (
                "model",
                "processor",
                "coreCount",
                "memoryBytes",
                "architecture",
                "operatingSystem",
                "xcode",
                "swift",
            ),
        ),
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
    parser.add_argument(
        "--allow-rejected-samples",
        action="store_true",
        help=(
            "exit 0 even when a sample's wall time is inconsistent with "
            "SwiftPM's build duration in its own log; the rejected samples "
            "are still reported. The matrix medians always include rejected "
            "samples; the \"Rejected samples\" section also prints each "
            "affected cell's median without them"
        ),
    )
    return parser


def report_rejections_or_fail(
    label: str,
    rejections: Sequence[dict[str, object]],
    *,
    allowed: bool,
) -> bool:
    """Print a rejection summary to stderr; return False when it must fail."""

    if not rejections:
        return True
    print(
        f"{'warning' if allowed else 'error'}: {label} has {len(rejections)} "
        f"rejected sample(s); {rejection_rule_description()}",
        file=sys.stderr,
    )
    for rejection in rejections:
        print(
            f"  {rejection['rawLog']}: wall {float(rejection['wallSeconds']):.2f} s, "
            f"SwiftPM {float(rejection['swiftpmSeconds']):.2f} s",
            file=sys.stderr,
        )
    return allowed


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
            baseline_ok = report_rejections_or_fail(
                "the baseline report",
                rejected_samples(baseline, baseline_path),
                allowed=options.allow_rejected_samples,
            )
            candidate_ok = report_rejections_or_fail(
                "the candidate report",
                rejected_samples(candidate, candidate_path),
                allowed=options.allow_rejected_samples,
            )
            if not (baseline_ok and candidate_ok):
                return 1
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
        rejections = rejected_samples(document, report_path)
        sys.stdout.write(render(document, summaries, rejections))
        if not report_rejections_or_fail(
            str(report_path),
            rejections,
            allowed=options.allow_rejected_samples,
        ):
            return 1
        return 0
    except (ValidationError, OSError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
