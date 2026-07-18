#!/usr/bin/env python3
"""Validate, summarize, and compare independent SQLite benchmark reports."""

from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import math
import re
import sqlite3
import statistics
import tempfile
from datetime import datetime
from pathlib import Path
from typing import Any, Iterable, Mapping, Sequence


DEFAULT_REPORT = Path(__file__).with_name("2026-07-18-mac16-8.json")
SWIFTQL_GRAPH = "swiftql_grdb6"
SQLITEDATA_GRAPH = "sqlitedata_grdb7"
GRAPH_IDENTIFIERS = (SWIFTQL_GRAPH, SQLITEDATA_GRAPH)
COMMON_IMPLEMENTATIONS = (
    "generated_raw_sqlite",
    "lighter",
    "grdb_manual",
    "grdb_codable",
    "sqlite_swift_manual",
    "sqlite_swift_typed",
)
GRAPH_IMPLEMENTATIONS = {
    SWIFTQL_GRAPH: COMMON_IMPLEMENTATIONS + ("swiftql",),
    SQLITEDATA_GRAPH: COMMON_IMPLEMENTATIONS + ("sqlite_data",),
}
CANONICAL_GRAPH = {
    **{implementation: SWIFTQL_GRAPH for implementation in COMMON_IMPLEMENTATIONS},
    "swiftql": SWIFTQL_GRAPH,
    "sqlite_data": SQLITEDATA_GRAPH,
}
DISPLAY_ORDER = (
    ("sqlite_data", "SQLiteData"),
    ("generated_raw_sqlite", "Generated raw SQLite"),
    ("lighter", "Lighter"),
    ("grdb_manual", "GRDB manual"),
    ("sqlite_swift_manual", "SQLite.swift manual"),
    ("swiftql", "SwiftQL"),
    ("sqlite_swift_typed", "SQLite.swift typed"),
    ("grdb_codable", "GRDB Codable"),
)
CONTROL_IMPLEMENTATIONS = COMMON_IMPLEMENTATIONS
MAX_CONTROL_DRIFT = 0.05
REQUIRED_DEPENDENCIES = {
    SWIFTQL_GRAPH: frozenset(
        ("grdb.swift", "lighter", "sqlite.swift", "swift-syntax")
    ),
    SQLITEDATA_GRAPH: frozenset(
        (
            "sqlite-data",
            "swift-structured-queries",
            "grdb.swift",
            "lighter",
            "sqlite.swift",
        )
    ),
}
EXPECTED_WORKLOAD = {
    "identifier": "northwind_orders_full_fetch",
    "rowCount": 16_143,
    "selectedColumnCount": 14,
    "warmupCount": 10,
    "sampleCount": 100,
    "independentProcessCount": 3,
    "configuration": "release",
    "timer": "DispatchTime.uptimeNanoseconds",
    "processIsolation": "one_implementation_per_process",
    "graphProcessOrder": "rotated_implementations_alternating_graph_pairs",
}
EXPECTED_ORDER_COLUMNS = (
    "OrderID",
    "CustomerID",
    "EmployeeID",
    "OrderDate",
    "RequiredDate",
    "ShippedDate",
    "ShipVia",
    "Freight",
    "ShipName",
    "ShipAddress",
    "ShipCity",
    "ShipRegion",
    "ShipPostalCode",
    "ShipCountry",
)
RESULT_FIELDS = frozenset(
    (
        "medianNanoseconds",
        "p95Nanoseconds",
        "rowsPerSecond",
        "processMedianMinNanoseconds",
        "processMedianMaxNanoseconds",
        "processSpreadPercent",
        "peakRSSBytes",
    )
)
ENVIRONMENT_STRING_FIELDS = (
    "model",
    "processor",
    "architecture",
    "operatingSystem",
    "xcode",
    "swift",
    "sqlite",
)
_REVISION_RE = re.compile(r"[0-9a-f]{40}\Z")
_SHA256_RE = re.compile(r"[0-9a-f]{64}\Z")
_RFC3339_RE = re.compile(
    r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})\Z"
)
_MAX_RSS_RE = re.compile(r"\s*(\d+)\s+maximum resident set size\s*\Z")


class ReportError(ValueError):
    """A report or comparison violates the benchmark contract."""


def _mapping(value: Any, location: str) -> Mapping[str, Any]:
    if not isinstance(value, dict):
        raise ReportError(f"{location} must be an object")
    return value


def _array(value: Any, location: str) -> Sequence[Any]:
    if not isinstance(value, list):
        raise ReportError(f"{location} must be an array")
    return value


def _string(value: Any, location: str) -> str:
    if not isinstance(value, str) or not value:
        raise ReportError(f"{location} must be a non-empty string")
    return value


def _positive_integer(value: Any, location: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        raise ReportError(f"{location} must be a positive integer")
    return value


def _finite_number(value: Any, location: str) -> float:
    if (
        isinstance(value, bool)
        or not isinstance(value, (int, float))
        or not math.isfinite(value)
    ):
        raise ReportError(f"{location} must be finite")
    return float(value)


def _hash(value: Any, location: str, pattern: re.Pattern[str], bits: int) -> str:
    if not isinstance(value, str) or pattern.fullmatch(value) is None:
        raise ReportError(
            f"{location} must be a lowercase {bits}-bit hexadecimal hash"
        )
    return value


def _revision(value: Any, location: str) -> str:
    return _hash(value, location, _REVISION_RE, 160)


def _sha256(value: Any, location: str) -> str:
    return _hash(value, location, _SHA256_RE, 256)


def _timestamp(value: Any, location: str) -> datetime:
    text = _string(value, location)
    if _RFC3339_RE.fullmatch(text) is None:
        raise ReportError(f"{location} must be an RFC 3339 timestamp")
    try:
        parsed = datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError as error:
        raise ReportError(f"{location} must be an RFC 3339 timestamp") from error
    if parsed.utcoffset() is None:
        raise ReportError(f"{location} must include a UTC offset")
    return parsed


def _file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _linked_file(
    report_directory: Path | None,
    raw_path: Any,
    raw_hash: Any,
    location: str,
    linked_paths: set[str],
    linked_hashes: set[str],
    *,
    allow_parent: bool = False,
) -> Path | None:
    relative_text = _string(raw_path, f"{location}.path")
    relative = Path(relative_text)
    if relative.is_absolute() or (not allow_parent and ".." in relative.parts):
        raise ReportError(f"{location}.path must be a safe relative path")
    expected_hash = _sha256(raw_hash, f"{location}.sha256")
    normalized = relative.as_posix()
    if normalized in linked_paths:
        raise ReportError(f"linked path is reused: {normalized}")
    linked_paths.add(normalized)
    linked_hashes.add(expected_hash)
    if report_directory is None:
        return None

    base = report_directory.resolve()
    resolved = (base / relative).resolve()
    if not allow_parent:
        try:
            resolved.relative_to(base)
        except ValueError as error:
            raise ReportError(
                f"{location}.path resolves outside the report directory"
            ) from error
    if not resolved.is_file():
        raise ReportError(f"linked file does not exist: {normalized}")
    actual_hash = _file_sha256(resolved)
    if actual_hash != expected_hash:
        raise ReportError(f"{location}.sha256 does not match {normalized}")
    return resolved


def _validate_workload(report: Mapping[str, Any]) -> Mapping[str, Any]:
    workload = _mapping(report.get("workload"), "workload")
    for key, expected in EXPECTED_WORKLOAD.items():
        if workload.get(key) != expected:
            raise ReportError(f"workload.{key} must be {expected!r}")
    cooldown = workload.get("postBuildCooldownSeconds")
    if (
        isinstance(cooldown, bool)
        or not isinstance(cooldown, (int, float))
        or not math.isfinite(cooldown)
        or cooldown < 0
    ):
        raise ReportError(
            "workload.postBuildCooldownSeconds must be finite and non-negative"
        )
    return workload


def _validate_provenance(report: Mapping[str, Any]) -> Mapping[str, Any]:
    provenance = _mapping(report.get("provenance"), "provenance")
    if provenance.get("harness") != "independently_implemented":
        raise ReportError("provenance.harness must be independently_implemented")
    reference = _mapping(
        provenance.get("workloadReference"), "provenance.workloadReference"
    )
    repository = _string(
        reference.get("repository"), "provenance.workloadReference.repository"
    ).removesuffix(".git")
    if repository != "https://github.com/Lighter-swift/PerformanceTestSuite":
        raise ReportError(
            "provenance.workloadReference.repository must identify "
            "Lighter-swift/PerformanceTestSuite"
        )
    _revision(
        reference.get("revision"), "provenance.workloadReference.revision"
    )
    expected_literals = {
        "licenseStatus": "absent_at_revision",
        "usage": "workload_reference_only",
        "codeCopied": False,
        "artifactsCopied": False,
    }
    for key, expected in expected_literals.items():
        if reference.get(key) != expected:
            raise ReportError(
                f"provenance.workloadReference.{key} must be {expected!r}"
            )
    return provenance


def _inspect_compressed_fixture(
    artifact: Path, expected_database_hash: str
) -> tuple[int, int, int]:
    database_digest = hashlib.sha256()
    database_bytes = 0
    try:
        with tempfile.NamedTemporaryFile(suffix=".sqlite") as temporary:
            with gzip.open(artifact, "rb") as source:
                for block in iter(lambda: source.read(1024 * 1024), b""):
                    database_digest.update(block)
                    database_bytes += len(block)
                    temporary.write(block)
            temporary.flush()
            if database_digest.hexdigest() != expected_database_hash:
                raise ReportError("fixture.databaseSHA256 does not match decompressed bytes")

            uri = Path(temporary.name).resolve().as_uri() + "?mode=ro"
            try:
                connection = sqlite3.connect(uri, uri=True)
            except sqlite3.Error as error:
                raise ReportError(f"fixture is not a SQLite database: {error}") from error
            try:
                quick_check = connection.execute("PRAGMA quick_check").fetchone()
                page_size = int(connection.execute("PRAGMA page_size").fetchone()[0])
                page_count = int(connection.execute("PRAGMA page_count").fetchone()[0])
                row = connection.execute('SELECT COUNT(*) FROM "Orders"').fetchone()
                columns = connection.execute('PRAGMA table_info("Orders")').fetchall()
            except sqlite3.Error as error:
                raise ReportError(f"fixture is not the expected SQLite database: {error}") from error
            finally:
                connection.close()
    except (OSError, gzip.BadGzipFile) as error:
        raise ReportError(f"could not decompress fixture artifact: {error}") from error

    if row is None or row[0] != EXPECTED_WORKLOAD["rowCount"]:
        raise ReportError("fixture Orders row count must be 16143")
    if tuple(column[1] for column in columns) != EXPECTED_ORDER_COLUMNS:
        raise ReportError("fixture Orders columns do not match the 14-column workload")
    if quick_check != ("ok",):
        raise ReportError("fixture SQLite quick_check did not return ok")
    return database_bytes, page_size, page_count


def _validate_fixture(
    report: Mapping[str, Any],
    report_directory: Path | None,
    linked_paths: set[str],
    linked_hashes: set[str],
) -> Mapping[str, Any]:
    fixture = _mapping(report.get("fixture"), "fixture")
    if fixture.get("rowCount") != EXPECTED_WORKLOAD["rowCount"]:
        raise ReportError("fixture.rowCount must be 16143")
    if fixture.get("columnCount") != EXPECTED_WORKLOAD["selectedColumnCount"]:
        raise ReportError("fixture.columnCount must be 14")
    repository = _string(
        fixture.get("sourceRepository"), "fixture.sourceRepository"
    ).removesuffix(".git")
    if repository != "https://github.com/jpwhite3/northwind-SQLite3":
        raise ReportError("fixture.sourceRepository must identify jpwhite3/northwind-SQLite3")
    _revision(fixture.get("sourceRevision"), "fixture.sourceRevision")
    database_bytes = _positive_integer(
        fixture.get("databaseBytes"), "fixture.databaseBytes"
    )
    page_size = _positive_integer(fixture.get("pageSize"), "fixture.pageSize")
    page_count = _positive_integer(fixture.get("pageCount"), "fixture.pageCount")
    _string(fixture.get("reproducibility"), "fixture.reproducibility")
    database_hash = _sha256(
        fixture.get("databaseSHA256"), "fixture.databaseSHA256"
    )
    artifact = _linked_file(
        report_directory,
        fixture.get("artifact"),
        fixture.get("artifactSHA256"),
        "fixture.artifact",
        linked_paths,
        linked_hashes,
        allow_parent=True,
    )

    license_metadata = _mapping(fixture.get("license"), "fixture.license")
    if license_metadata.get("spdxIdentifier") != "MIT":
        raise ReportError("fixture.license.spdxIdentifier must be MIT")
    _linked_file(
        report_directory,
        license_metadata.get("path"),
        license_metadata.get("sha256"),
        "fixture.license",
        linked_paths,
        linked_hashes,
        allow_parent=True,
    )
    if artifact is not None:
        actual_layout = _inspect_compressed_fixture(artifact, database_hash)
        if actual_layout != (database_bytes, page_size, page_count):
            raise ReportError("fixture byte or SQLite page metadata does not match artifact")
    return fixture


def _validate_sources(report: Mapping[str, Any]) -> Mapping[str, Any]:
    sources = _mapping(report.get("sources"), "sources")
    _revision(sources.get("swiftqlRevision"), "sources.swiftqlRevision")
    if not isinstance(sources.get("swiftqlDirty"), bool):
        raise ReportError("sources.swiftqlDirty must be a boolean")
    for key, value in sources.items():
        if key.endswith("Revision"):
            _revision(value, f"sources.{key}")
    return sources


def _validate_environment(report: Mapping[str, Any]) -> Mapping[str, Any]:
    environment = _mapping(report.get("environment"), "environment")
    for key in ENVIRONMENT_STRING_FIELDS:
        _string(environment.get(key), f"environment.{key}")
    for key in ("coreCount", "memoryBytes"):
        _positive_integer(environment.get(key), f"environment.{key}")
    return environment


def _validate_dependencies(
    graph: Mapping[str, Any], identifier: str, sources: Mapping[str, Any]
) -> Mapping[str, Any]:
    dependencies = _mapping(graph.get("dependencies"), f"{identifier}.dependencies")
    missing = REQUIRED_DEPENDENCIES[identifier] - set(dependencies)
    if missing:
        raise ReportError(
            f"{identifier}.dependencies is missing: {', '.join(sorted(missing))}"
        )
    for identity, raw_dependency in dependencies.items():
        dependency = _mapping(raw_dependency, f"{identifier}.dependencies.{identity}")
        _string(dependency.get("version"), f"{identifier}.dependencies.{identity}.version")
        _revision(
            dependency.get("revision"),
            f"{identifier}.dependencies.{identity}.revision",
        )
    return dependencies


def _parse_sample_log(
    path: Path | None,
    implementation: str,
    process: int,
    samples: Sequence[int],
    location: str,
) -> None:
    if path is None:
        return
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeDecodeError) as error:
        raise ReportError(f"{location} is not a UTF-8 TSV file: {error}") from error
    if len(lines) != EXPECTED_WORKLOAD["sampleCount"]:
        raise ReportError(f"{location} must contain exactly 100 SAMPLE lines")
    for sample_index, (line, expected_nanoseconds) in enumerate(
        zip(lines, samples), start=1
    ):
        fields = line.split("\t")
        if len(fields) != 5 or fields[0] != "SAMPLE":
            raise ReportError(f"{location} line {sample_index} is not a SAMPLE record")
        _, logged_implementation, logged_process, logged_index, logged_value = fields
        expected_fields = (
            implementation,
            str(process),
            str(sample_index),
            str(expected_nanoseconds),
        )
        if (
            logged_implementation,
            logged_process,
            logged_index,
            logged_value,
        ) != expected_fields:
            raise ReportError(
                f"{location} line {sample_index} does not match report samples"
            )


def _validate_peak_rss(
    raw_peak: Any,
    report_directory: Path | None,
    location: str,
    linked_paths: set[str],
    linked_hashes: set[str],
) -> Mapping[str, Any]:
    peak = _mapping(raw_peak, location)
    if peak.get("scope") != "implementation_process":
        raise ReportError(f"{location}.scope must be implementation_process")
    bytes_value = peak.get("bytes")
    unavailable_reason = peak.get("unavailableReason")
    if bytes_value is None:
        if not isinstance(unavailable_reason, str) or not unavailable_reason.strip():
            raise ReportError(f"{location}.unavailableReason must explain missing RSS")
        if peak.get("rawOutput") is not None or peak.get("rawOutputSHA256") is not None:
            raise ReportError(f"{location} raw-output fields must be null when unavailable")
        method = peak.get("method")
        if method is not None and (not isinstance(method, str) or not method):
            raise ReportError(f"{location}.method must be null or non-empty")
        return peak

    expected_bytes = _positive_integer(bytes_value, f"{location}.bytes")
    _string(peak.get("method"), f"{location}.method")
    if unavailable_reason is not None:
        raise ReportError(f"{location}.unavailableReason must be null when RSS is available")
    resource_path = _linked_file(
        report_directory,
        peak.get("rawOutput"),
        peak.get("rawOutputSHA256"),
        f"{location}.rawOutput",
        linked_paths,
        linked_hashes,
    )
    if resource_path is not None:
        try:
            lines = resource_path.read_text(encoding="utf-8").splitlines()
        except (OSError, UnicodeDecodeError) as error:
            raise ReportError(f"{location}.rawOutput is not UTF-8: {error}") from error
        matches = [match for line in lines if (match := _MAX_RSS_RE.fullmatch(line))]
        if len(matches) != 1:
            raise ReportError(
                f"{location}.rawOutput must contain one maximum resident set size line"
            )
        if int(matches[0].group(1)) != expected_bytes:
            raise ReportError(f"{location}.bytes does not match resource output")
    return peak


def _validate_run(
    raw_run: Any,
    identifier: str,
    implementations: tuple[str, ...],
    report_directory: Path | None,
    linked_paths: set[str],
    linked_hashes: set[str],
) -> dict[str, Any]:
    run = _mapping(raw_run, f"{identifier}.run")
    implementation = _string(run.get("implementation"), "run.implementation")
    if implementation not in implementations:
        raise ReportError(f"{identifier} has unexpected implementation {implementation!r}")
    process = _positive_integer(run.get("process"), "run.process")
    if process > EXPECTED_WORKLOAD["independentProcessCount"]:
        raise ReportError("run.process must be in 1...3")
    schedule_index = _positive_integer(run.get("scheduleIndex"), "run.scheduleIndex")
    started_at = _timestamp(run.get("startedAt"), "run.startedAt")
    finished_at = _timestamp(run.get("finishedAt"), "run.finishedAt")
    if finished_at <= started_at:
        raise ReportError("run.finishedAt must be later than run.startedAt")

    raw_samples = _array(run.get("samplesNanoseconds"), "run.samplesNanoseconds")
    if len(raw_samples) != EXPECTED_WORKLOAD["sampleCount"]:
        raise ReportError("run.samplesNanoseconds must contain exactly 100 samples")
    samples = [
        _positive_integer(sample, f"run.samplesNanoseconds[{index}]")
        for index, sample in enumerate(raw_samples)
    ]
    sample_log = _linked_file(
        report_directory,
        run.get("rawSamples"),
        run.get("rawSamplesSHA256"),
        "run.rawSamples",
        linked_paths,
        linked_hashes,
    )
    _parse_sample_log(
        sample_log,
        implementation,
        process,
        samples,
        "run.rawSamples",
    )
    peak_rss = _validate_peak_rss(
        run.get("peakRSS"),
        report_directory,
        "run.peakRSS",
        linked_paths,
        linked_hashes,
    )
    return {
        "graph": identifier,
        "implementation": implementation,
        "process": process,
        "scheduleIndex": schedule_index,
        "started": started_at,
        "finished": finished_at,
        "samples": samples,
        "peakRSS": peak_rss,
    }


def _expected_schedule() -> list[tuple[str, str, int]]:
    schedule: list[tuple[str, str, int]] = []
    for process in range(1, EXPECTED_WORKLOAD["independentProcessCount"] + 1):
        offset = process - 1
        implementations = (
            COMMON_IMPLEMENTATIONS[offset:] + COMMON_IMPLEMENTATIONS[:offset]
        )
        graph_order = (
            GRAPH_IDENTIFIERS if process % 2 == 1 else tuple(reversed(GRAPH_IDENTIFIERS))
        )
        for implementation in implementations:
            for graph in graph_order:
                schedule.append((graph, implementation, process))
        for graph in graph_order:
            unique = "swiftql" if graph == SWIFTQL_GRAPH else "sqlite_data"
            schedule.append((graph, unique, process))
    return schedule


def _validate_schedule(events: Sequence[Mapping[str, Any]], generated_at: datetime) -> None:
    expected = _expected_schedule()
    if len(events) != len(expected):
        raise ReportError(f"report must contain exactly {len(expected)} implementation runs")
    indices = [event["scheduleIndex"] for event in events]
    if set(indices) != set(range(1, len(expected) + 1)):
        raise ReportError("scheduleIndex values must be unique and contiguous from 1")
    ordered = sorted(events, key=lambda event: event["scheduleIndex"])
    actual = [
        (event["graph"], event["implementation"], event["process"])
        for event in ordered
    ]
    if actual != expected:
        raise ReportError("implementation runs do not match the deterministic interleaving schedule")
    for previous, current in zip(ordered, ordered[1:]):
        if current["started"] < previous["finished"]:
            raise ReportError("scheduled implementation runs overlap")
    if generated_at < ordered[-1]["finished"]:
        raise ReportError("generatedAt must not precede the final run")


def nearest_rank_p95(samples: Sequence[int]) -> int:
    """Return the nearest-rank 95th percentile for a non-empty sample array."""

    if not samples:
        raise ReportError("cannot compute p95 for an empty sample array")
    ordered = sorted(samples)
    rank = math.ceil(0.95 * len(ordered))
    return ordered[rank - 1]


def _events_by_key(
    events: Sequence[Mapping[str, Any]],
) -> dict[tuple[str, str], list[Mapping[str, Any]]]:
    grouped: dict[tuple[str, str], list[Mapping[str, Any]]] = {}
    for event in events:
        grouped.setdefault((event["graph"], event["implementation"]), []).append(event)
    for key, runs in grouped.items():
        if {run["process"] for run in runs} != {1, 2, 3} or len(runs) != 3:
            raise ReportError(f"{key[0]}/{key[1]} must contain process IDs 1, 2, and 3")
        availability = {run["peakRSS"]["bytes"] is not None for run in runs}
        if len(availability) != 1:
            raise ReportError(f"{key[0]}/{key[1]} has inconsistent peak RSS availability")
    return grouped


def _result_for_runs(runs: Sequence[Mapping[str, Any]], row_count: int) -> dict[str, Any]:
    process_medians = [statistics.median(run["samples"]) for run in runs]
    process_p95s = [nearest_rank_p95(run["samples"]) for run in runs]
    headline_median = statistics.median(process_medians)
    headline_p95 = statistics.median(process_p95s)
    minimum = min(process_medians)
    maximum = max(process_medians)
    peak_values = [run["peakRSS"]["bytes"] for run in runs]
    peak_rss = max(peak_values) if all(value is not None for value in peak_values) else None
    return {
        "medianNanoseconds": headline_median,
        "p95Nanoseconds": headline_p95,
        "rowsPerSecond": row_count * 1_000_000_000 / headline_median,
        "processMedianMinNanoseconds": minimum,
        "processMedianMaxNanoseconds": maximum,
        "processSpreadPercent": (maximum - minimum) / headline_median * 100,
        "peakRSSBytes": peak_rss,
    }


def derive_results(
    report: Mapping[str, Any], events: Sequence[Mapping[str, Any]] | None = None
) -> dict[str, Any]:
    """Derive every stored headline and graph-specific result from raw runs."""

    if events is None:
        events = []
        for graph in report["graphs"]:
            for run in graph["runs"]:
                events.append(
                    {
                        "graph": graph["identifier"],
                        "implementation": run["implementation"],
                        "process": run["process"],
                        "samples": run["samplesNanoseconds"],
                        "peakRSS": run["peakRSS"],
                    }
                )
    grouped = _events_by_key(events)
    row_count = report["workload"]["rowCount"]
    graph_results = {
        graph: {
            implementation: _result_for_runs(
                grouped[(graph, implementation)], row_count
            )
            for implementation in GRAPH_IMPLEMENTATIONS[graph]
        }
        for graph in GRAPH_IDENTIFIERS
    }
    implementations: dict[str, dict[str, Any]] = {}
    for implementation, graph in CANONICAL_GRAPH.items():
        implementations[implementation] = {
            **graph_results[graph][implementation],
            "canonicalGraph": graph,
        }
    drift = {}
    for implementation in COMMON_IMPLEMENTATIONS:
        lhs = graph_results[SWIFTQL_GRAPH][implementation]["medianNanoseconds"]
        rhs = graph_results[SQLITEDATA_GRAPH][implementation]["medianNanoseconds"]
        drift[implementation] = abs(lhs - rhs) / ((lhs + rhs) / 2) * 100
    return {
        "implementations": dict(sorted(implementations.items())),
        "graphImplementations": graph_results,
        "controlDriftPercent": dict(sorted(drift.items())),
        "controlDriftTolerancePercent": MAX_CONTROL_DRIFT * 100,
    }


def _same_number(actual: Any, expected: Any) -> bool:
    if (
        isinstance(actual, bool)
        or not isinstance(actual, (int, float))
        or not math.isfinite(actual)
    ):
        return False
    return math.isclose(float(actual), float(expected), rel_tol=1e-12, abs_tol=1e-9)


def _validate_result_record(
    stored_value: Any,
    expected: Mapping[str, Any],
    location: str,
    canonical_graph: str | None = None,
) -> None:
    stored = _mapping(stored_value, location)
    expected_fields = set(RESULT_FIELDS)
    if canonical_graph is not None:
        expected_fields.add("canonicalGraph")
    if set(stored) != expected_fields:
        raise ReportError(f"{location} has unexpected fields")
    if canonical_graph is not None and stored.get("canonicalGraph") != canonical_graph:
        raise ReportError(f"{location}.canonicalGraph does not match the report contract")
    for field, expected_value in expected.items():
        actual = stored.get(field)
        if expected_value is None:
            if actual is not None:
                raise ReportError(f"{location}.{field} must be null")
        elif not _same_number(actual, expected_value):
            raise ReportError(f"{location}.{field} does not match raw samples")


def _validate_stored_results(report: Mapping[str, Any], expected: Mapping[str, Any]) -> None:
    results = _mapping(report.get("results"), "results")
    if set(results) != {
        "implementations",
        "graphImplementations",
        "controlDriftPercent",
        "controlDriftTolerancePercent",
    }:
        raise ReportError("results has unexpected fields")

    implementations = _mapping(results["implementations"], "results.implementations")
    if set(implementations) != set(CANONICAL_GRAPH):
        raise ReportError("results.implementations has unexpected IDs")
    for implementation, canonical_graph in CANONICAL_GRAPH.items():
        expected_record = expected["implementations"][implementation]
        expected_statistics = {
            key: value
            for key, value in expected_record.items()
            if key != "canonicalGraph"
        }
        _validate_result_record(
            implementations[implementation],
            expected_statistics,
            f"results.implementations.{implementation}",
            canonical_graph,
        )

    graph_results = _mapping(
        results["graphImplementations"], "results.graphImplementations"
    )
    if set(graph_results) != set(GRAPH_IDENTIFIERS):
        raise ReportError("results.graphImplementations has unexpected graph IDs")
    for graph in GRAPH_IDENTIFIERS:
        stored_graph = _mapping(
            graph_results[graph], f"results.graphImplementations.{graph}"
        )
        if set(stored_graph) != set(GRAPH_IMPLEMENTATIONS[graph]):
            raise ReportError(
                f"results.graphImplementations.{graph} has unexpected IDs"
            )
        for implementation in GRAPH_IMPLEMENTATIONS[graph]:
            _validate_result_record(
                stored_graph[implementation],
                expected["graphImplementations"][graph][implementation],
                f"results.graphImplementations.{graph}.{implementation}",
            )

    stored_drift = _mapping(
        results["controlDriftPercent"], "results.controlDriftPercent"
    )
    if set(stored_drift) != set(COMMON_IMPLEMENTATIONS):
        raise ReportError("results.controlDriftPercent has unexpected IDs")
    for implementation, expected_value in expected["controlDriftPercent"].items():
        if not _same_number(stored_drift.get(implementation), expected_value):
            raise ReportError(
                f"results.controlDriftPercent.{implementation} does not match raw samples"
            )
    if not _same_number(
        results["controlDriftTolerancePercent"], MAX_CONTROL_DRIFT * 100
    ):
        raise ReportError("results.controlDriftTolerancePercent must be 5")


def _validate_control_drift(
    report: Mapping[str, Any], grouped: Mapping[tuple[str, str], Sequence[Mapping[str, Any]]]
) -> None:
    row_count = report["workload"]["rowCount"]
    for implementation in CONTROL_IMPLEMENTATIONS:
        lhs = _result_for_runs(grouped[(SWIFTQL_GRAPH, implementation)], row_count)[
            "medianNanoseconds"
        ]
        rhs = _result_for_runs(grouped[(SQLITEDATA_GRAPH, implementation)], row_count)[
            "medianNanoseconds"
        ]
        drift = abs(lhs - rhs) / ((lhs + rhs) / 2)
        if drift > MAX_CONTROL_DRIFT:
            raise ReportError(
                f"{implementation} cross-graph drift is {drift:.2%}; maximum is 5.00%"
            )


def validate_report(
    report: Mapping[str, Any], report_directory: Path | None = None
) -> Mapping[str, Any]:
    """Validate an in-memory format-v3 report and every linked artifact."""

    if report.get("formatVersion") != 3:
        raise ReportError("formatVersion must be 3")
    if report.get("durationUnit") != "nanoseconds_per_fetch":
        raise ReportError("durationUnit must be nanoseconds_per_fetch")
    generated_at = _timestamp(report.get("generatedAt"), "generatedAt")
    _validate_workload(report)
    _validate_provenance(report)
    linked_paths: set[str] = set()
    linked_hashes: set[str] = set()
    _validate_fixture(report, report_directory, linked_paths, linked_hashes)
    sources = _validate_sources(report)
    _validate_environment(report)

    raw_graphs = _array(report.get("graphs"), "graphs")
    if len(raw_graphs) != len(GRAPH_IDENTIFIERS):
        raise ReportError("graphs must contain exactly two dependency graphs")
    seen_graphs: set[str] = set()
    events: list[dict[str, Any]] = []
    for raw_graph in raw_graphs:
        graph = _mapping(raw_graph, "graph")
        identifier = _string(graph.get("identifier"), "graph.identifier")
        if identifier not in GRAPH_IDENTIFIERS or identifier in seen_graphs:
            raise ReportError(f"unexpected or duplicate graph identifier: {identifier}")
        seen_graphs.add(identifier)
        raw_implementations = _array(
            graph.get("implementations"), f"{identifier}.implementations"
        )
        implementations = tuple(raw_implementations)
        if implementations != GRAPH_IMPLEMENTATIONS[identifier]:
            raise ReportError(f"{identifier}.implementations must use canonical IDs/order")
        _validate_dependencies(graph, identifier, sources)
        runs = _array(graph.get("runs"), f"{identifier}.runs")
        if len(runs) != len(implementations) * 3:
            raise ReportError(f"{identifier}.runs must contain 3 runs per implementation")
        for run in runs:
            events.append(
                _validate_run(
                    run,
                    identifier,
                    implementations,
                    report_directory,
                    linked_paths,
                    linked_hashes,
                )
            )
    if seen_graphs != set(GRAPH_IDENTIFIERS):
        raise ReportError("both dependency graph identifiers are required")

    _validate_schedule(events, generated_at)
    grouped = _events_by_key(events)
    _validate_control_drift(report, grouped)
    derived = derive_results(report, events)
    _validate_stored_results(report, derived)
    return report


def load_report(path: Path | str = DEFAULT_REPORT) -> Mapping[str, Any]:
    """Load and fully validate a report and its linked files."""

    report_path = Path(path)
    try:
        document = json.loads(report_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ReportError(f"could not read report {report_path}: {error}") from error
    return validate_report(_mapping(document, "report"), report_path.parent)


def format_summary(report: Mapping[str, Any]) -> str:
    """Render the checked and recomputed headline results as Markdown."""

    results = report["results"]["implementations"]
    swiftql_median = results["swiftql"]["medianNanoseconds"]
    lines = [
        "| API path | Median | p95 | Rows/s | Latency vs SwiftQL | Process spread | Peak RSS |",
        "| --- | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for implementation, label in DISPLAY_ORDER:
        result = results[implementation]
        peak = result["peakRSSBytes"]
        peak_text = "unavailable" if peak is None else f"{peak / (1024 * 1024):.1f} MiB"
        lines.append(
            f"| {label} | {result['medianNanoseconds'] / 1_000_000:.2f} ms | "
            f"{result['p95Nanoseconds'] / 1_000_000:.2f} ms | "
            f"{result['rowsPerSecond']:,.0f} | "
            f"{result['medianNanoseconds'] / swiftql_median:.2f}x | "
            f"{result['processSpreadPercent']:.2f}% | {peak_text} |"
        )
    return "\n".join(lines)


def _graph_map(report: Mapping[str, Any]) -> dict[str, Mapping[str, Any]]:
    return {graph["identifier"]: graph for graph in report["graphs"]}


def _fixture_signature(report: Mapping[str, Any]) -> dict[str, Any]:
    fixture = dict(report["fixture"])
    fixture.pop("artifact")
    license_metadata = dict(fixture["license"])
    license_metadata.pop("path")
    fixture["license"] = license_metadata
    return fixture


def _rss_signature(report: Mapping[str, Any]) -> dict[tuple[str, str, int], tuple[Any, ...]]:
    signature: dict[tuple[str, str, int], tuple[Any, ...]] = {}
    for graph in report["graphs"]:
        for run in graph["runs"]:
            peak = run["peakRSS"]
            signature[(graph["identifier"], run["implementation"], run["process"])] = (
                peak["scope"],
                peak["bytes"] is not None,
                peak["method"],
                peak["unavailableReason"] if peak["bytes"] is None else None,
            )
    return signature


def validate_compatible_reports(
    baseline: Mapping[str, Any], candidate: Mapping[str, Any]
) -> None:
    """Require every controlled input except the SwiftQL revision to match."""

    for key in ("durationUnit", "workload", "environment", "provenance"):
        if baseline[key] != candidate[key]:
            raise ReportError(f"{key} differs between reports")
    if _fixture_signature(baseline) != _fixture_signature(candidate):
        raise ReportError("fixture metadata differs between reports")

    baseline_sources = dict(baseline["sources"])
    candidate_sources = dict(candidate["sources"])
    baseline_sources.pop("swiftqlRevision")
    candidate_sources.pop("swiftqlRevision")
    if baseline_sources != candidate_sources:
        raise ReportError("non-SwiftQL source metadata differs between reports")

    baseline_graphs = _graph_map(baseline)
    candidate_graphs = _graph_map(candidate)
    for identifier in GRAPH_IDENTIFIERS:
        if (
            baseline_graphs[identifier]["implementations"]
            != candidate_graphs[identifier]["implementations"]
        ):
            raise ReportError(f"{identifier}.implementations differs between reports")
        baseline_dependencies = dict(baseline_graphs[identifier]["dependencies"])
        candidate_dependencies = dict(candidate_graphs[identifier]["dependencies"])
        if identifier == SWIFTQL_GRAPH:
            baseline_dependencies.pop("SwiftQL", None)
            candidate_dependencies.pop("SwiftQL", None)
        if baseline_dependencies != candidate_dependencies:
            raise ReportError(f"{identifier}.dependencies differs between reports")
    if _rss_signature(baseline) != _rss_signature(candidate):
        raise ReportError("peak RSS measurement availability or method differs")


def _percent(value: float) -> str:
    return f"{value:+.2%}"


def format_comparison(
    baseline: Mapping[str, Any], candidate: Mapping[str, Any]
) -> str:
    """Render SwiftQL changes after confirming all controlled inputs match."""

    validate_compatible_reports(baseline, candidate)
    before_results = baseline["results"]["implementations"]
    after_results = candidate["results"]["implementations"]
    before = before_results["swiftql"]
    after = after_results["swiftql"]
    before_control = before_results["generated_raw_sqlite"]
    after_control = after_results["generated_raw_sqlite"]
    rows = [
        "| SwiftQL metric | Baseline | Candidate | Delta |",
        "| --- | ---: | ---: | ---: |",
        (
            f"| Median latency | {before['medianNanoseconds'] / 1_000_000:.2f} ms | "
            f"{after['medianNanoseconds'] / 1_000_000:.2f} ms | "
            f"{_percent(after['medianNanoseconds'] / before['medianNanoseconds'] - 1)} |"
        ),
        (
            f"| p95 latency | {before['p95Nanoseconds'] / 1_000_000:.2f} ms | "
            f"{after['p95Nanoseconds'] / 1_000_000:.2f} ms | "
            f"{_percent(after['p95Nanoseconds'] / before['p95Nanoseconds'] - 1)} |"
        ),
        (
            f"| Throughput | {before['rowsPerSecond']:,.0f} rows/s | "
            f"{after['rowsPerSecond']:,.0f} rows/s | "
            f"{_percent(after['rowsPerSecond'] / before['rowsPerSecond'] - 1)} |"
        ),
        (
            f"| Process spread | {before['processSpreadPercent']:.2f}% | "
            f"{after['processSpreadPercent']:.2f}% | "
            f"{after['processSpreadPercent'] - before['processSpreadPercent']:+.2f} pp |"
        ),
    ]
    before_peak = before["peakRSSBytes"]
    after_peak = after["peakRSSBytes"]
    if before_peak is not None and after_peak is not None:
        rows.append(
            f"| Peak RSS | {before_peak / (1024 * 1024):.1f} MiB | "
            f"{after_peak / (1024 * 1024):.1f} MiB | "
            f"{_percent(after_peak / before_peak - 1)} |"
        )
    before_normalized = (
        before["medianNanoseconds"] / before_control["medianNanoseconds"]
    )
    after_normalized = (
        after["medianNanoseconds"] / after_control["medianNanoseconds"]
    )
    rows.append(
        f"| Median / generated-raw control | {before_normalized:.3f}x | "
        f"{after_normalized:.3f}x | "
        f"{_percent(after_normalized / before_normalized - 1)} |"
    )
    return "\n".join(rows)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Validate and summarize independent SQLite comparison reports."
    )
    parser.add_argument("report", nargs="?", type=Path)
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--candidate", type=Path)
    return parser


def main(arguments: Iterable[str] | None = None) -> int:
    parser = build_parser()
    options = parser.parse_args(arguments)
    comparison = options.baseline is not None or options.candidate is not None
    if comparison:
        if options.baseline is None or options.candidate is None:
            parser.error("--baseline and --candidate must be supplied together")
        if options.report is not None:
            parser.error("a positional report cannot accompany comparison options")
    try:
        if comparison:
            print(
                format_comparison(
                    load_report(options.baseline), load_report(options.candidate)
                )
            )
        else:
            print(format_summary(load_report(options.report or DEFAULT_REPORT)))
    except ReportError as error:
        parser.error(str(error))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
