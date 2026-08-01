#!/usr/bin/env python3
"""Build and run the issue #259 cross-library workload prototypes.

This is research evidence for whether point lookup, join/aggregate, and
transactional write can be compared fairly across libraries. It is a prototype,
not the #250 baseline: it does not touch `Benchmarks/Comparison/run.py`, the
committed full-fetch report, or that report's raw logs.

Fixture verification, environment capture, and dependency-pin reading are
imported from #250's runner rather than reimplemented, so both harnesses agree
on exactly which database bytes they are measuring.
"""

from __future__ import annotations

import argparse
import dataclasses
import importlib.util
import json
import math
import os
import platform
import shutil
import sqlite3
import statistics
import subprocess
import sys
import time
from pathlib import Path
from typing import Sequence


SCRIPT_DIRECTORY = Path(__file__).resolve().parent
COMPARISON_DIRECTORY = SCRIPT_DIRECTORY.parent
REPOSITORY_ROOT = SCRIPT_DIRECTORY.parents[2]
PROTOTYPE_TEMPLATE = SCRIPT_DIRECTORY / "Prototype"

_BASELINE_RUNNER = COMPARISON_DIRECTORY / "run.py"
_SPEC = importlib.util.spec_from_file_location(
    "issue259_comparison_run",
    _BASELINE_RUNNER,
)
if _SPEC is None or _SPEC.loader is None:
    raise ImportError(f"could not load the #250 runner from {_BASELINE_RUNNER}")
comparison_run = importlib.util.module_from_spec(_SPEC)
sys.modules[_SPEC.name] = comparison_run
_SPEC.loader.exec_module(comparison_run)

HarnessError = comparison_run.HarnessError

REPORT_FORMAT_VERSION = 1
PRODUCT_NAME = "WorkloadPrototype"
WARMUP_COUNT = 10
SAMPLE_COUNT = 100
PROCESS_COUNT = 3
SCRATCH_TABLE = "Issue259PrototypeWrites"
SCRATCH_TABLE_SQL = (
    f'CREATE TABLE "{SCRATCH_TABLE}" '
    "(id INTEGER PRIMARY KEY, name TEXT NOT NULL, amount REAL NOT NULL)"
)
EXPECTED_COUNTRY_GROUPS = 22
WRITE_BATCH_SIZE = 100
LOOKUP_KEY_COUNT = 256

IMPLEMENTATIONS = ("swiftql", "grdb", "sqlite_swift")


@dataclasses.dataclass(frozen=True)
class WorkloadSpec:
    identifier: str
    writable: bool
    unit: str
    operations_per_iteration: int
    contract: str
    tiers: dict[str, str]


WORKLOADS: tuple[WorkloadSpec, ...] = (
    WorkloadSpec(
        identifier="point_lookup",
        writable=False,
        unit="one_indexed_row",
        operations_per_iteration=1,
        contract=(
            "Fetch all 14 Orders columns for one OrderID drawn from a fixed "
            "256-key rotation, decoded into the shared row shape. Exactly one "
            "row, verified every iteration against the bound key."
        ),
        tiers={
            "swiftql": "typed_declared_query",
            "grdb": "typed_record_request",
            "sqlite_swift": "typed_query_builder",
        },
    ),
    WorkloadSpec(
        identifier="join_aggregate",
        writable=False,
        unit="twenty_two_groups",
        operations_per_iteration=1,
        contract=(
            "Inner-join Orders to Customers on CustomerID, group by "
            "Customers.Country, and return COUNT(Orders.OrderID) and "
            "TOTAL(Orders.Freight) per group, ordered by country. Exactly 22 "
            "groups including the NULL-country group."
        ),
        tiers={
            "swiftql": "typed_query_builder",
            "grdb": "raw_sql_row_mapping",
            "sqlite_swift": "typed_query_builder",
        },
    ),
    WorkloadSpec(
        identifier="transactional_write",
        writable=True,
        unit="one_hundred_row_transaction",
        operations_per_iteration=WRITE_BATCH_SIZE,
        contract=(
            f"Insert the same deterministic {WRITE_BATCH_SIZE}-row batch into a "
            f"dedicated scratch table inside one explicit transaction and "
            f"commit. The batch is deleted between iterations, outside timing, "
            f"so committed state is identical before every measured "
            f"transaction."
        ),
        tiers={
            "swiftql": "typed_transaction_scope",
            "grdb": "typed_persistable_record",
            "sqlite_swift": "typed_query_builder",
        },
    ),
)

WORKLOADS_BY_IDENTIFIER = {workload.identifier: workload for workload in WORKLOADS}


def rotated(values: Sequence[str], offset: int) -> tuple[str, ...]:
    offset %= len(values)
    return tuple(values[offset:]) + tuple(values[:offset])


def schedule(
    workloads: Sequence[WorkloadSpec],
    implementations: Sequence[str],
    processes: int,
) -> list[tuple[int, WorkloadSpec, str]]:
    """Rotate implementation order per process so no path always runs first."""

    entries: list[tuple[int, WorkloadSpec, str]] = []
    for process in range(1, processes + 1):
        for workload in workloads:
            for implementation in rotated(implementations, process - 1):
                entries.append((process, workload, implementation))
    return entries


def prepare_prototype(workspace: Path, swiftql_checkout: Path) -> Path:
    if not PROTOTYPE_TEMPLATE.is_dir():
        raise HarnessError(f"prototype template is missing: {PROTOTYPE_TEMPLATE}")
    destination = workspace / "Prototype"
    shutil.copytree(PROTOTYPE_TEMPLATE, destination)
    manifest = destination / "Package.swift"
    text = manifest.read_text(encoding="utf-8")
    placeholder = "__SWIFTQL_CHECKOUT__"
    if text.count(placeholder) != 1:
        raise HarnessError(
            f"{manifest} must contain exactly one {placeholder} placeholder"
        )
    manifest.write_text(
        text.replace(placeholder, comparison_run.swift_string_literal(str(swiftql_checkout))),
        encoding="utf-8",
    )
    return destination


def build_prototype(prototype: Path) -> Path:
    resolution = prototype / "Package.resolved"
    expected = (
        comparison_run.resolved_dependencies(resolution)
        if resolution.is_file()
        else None
    )
    comparison_run.run_visible(
        ("swift", "build", "--configuration", "release", "--product", PRODUCT_NAME),
        cwd=prototype,
    )
    if expected is not None:
        if comparison_run.resolved_dependencies(resolution) != expected:
            raise HarnessError(f"SwiftPM rewrote the pinned resolution in {prototype}")
    binary_directory = Path(
        comparison_run.capture_command(
            ("swift", "build", "--configuration", "release", "--show-bin-path"),
            cwd=prototype,
        )
    )
    executable = binary_directory / PRODUCT_NAME
    if not executable.is_file():
        raise HarnessError(f"release executable is missing: {executable}")
    return executable


def add_scratch_table(database: Path) -> None:
    connection = sqlite3.connect(database)
    try:
        existing = connection.execute(
            "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = ?",
            (SCRATCH_TABLE,),
        ).fetchone()[0]
        if existing:
            raise HarnessError(
                f"{database} already contains {SCRATCH_TABLE}; the write copy "
                f"must start from the pristine fixture"
            )
        connection.execute(SCRATCH_TABLE_SQL)
        connection.commit()
    finally:
        connection.close()


def parse_samples(
    output: bytes,
    *,
    workload: str,
    implementation: str,
    process: int,
) -> list[int]:
    try:
        text = output.decode("utf-8", errors="strict")
    except UnicodeDecodeError as error:
        raise HarnessError(f"prototype output was not UTF-8: {error}") from error

    samples: list[int] = []
    for line in text.splitlines():
        if not line:
            continue
        fields = line.split("\t")
        if len(fields) != 6 or fields[0] != "SAMPLE":
            raise HarnessError(f"unexpected prototype stdout line: {line!r}")
        if fields[1] != workload:
            raise HarnessError(f"sample workload mismatch: {fields[1]!r} != {workload!r}")
        if fields[2] != implementation:
            raise HarnessError(
                f"sample implementation mismatch: {fields[2]!r} != {implementation!r}"
            )
        try:
            line_process = int(fields[3])
            sample_index = int(fields[4])
            nanoseconds = int(fields[5])
        except ValueError as error:
            raise HarnessError(f"non-integer sample field: {line!r}") from error
        if line_process != process:
            raise HarnessError(f"sample process mismatch: {line_process} != {process}")
        if sample_index != len(samples) + 1:
            raise HarnessError(
                f"sample index mismatch: expected {len(samples) + 1}, "
                f"found {sample_index}"
            )
        if nanoseconds <= 0:
            raise HarnessError(f"sample duration must be positive: {nanoseconds}")
        samples.append(nanoseconds)
    if len(samples) != SAMPLE_COUNT:
        raise HarnessError(
            f"expected {SAMPLE_COUNT} samples, found {len(samples)} for "
            f"{workload}/{implementation} process {process}"
        )
    return samples


def run_one_process(
    *,
    executable: Path,
    prototype: Path,
    workload: WorkloadSpec,
    implementation: str,
    process: int,
    schedule_index: int,
    total: int,
    database: Path,
    runs_directory: Path,
    output_directory: Path,
) -> dict[str, object]:
    stem = f"{workload.identifier}-{implementation}-process-{process:02d}"
    samples_path = runs_directory / f"{stem}.samples.tsv"
    resource_path = runs_directory / f"{stem}.resource.log"

    environment = dict(os.environ)
    environment.update({"LANG": "C", "LC_ALL": "C"})
    use_macos_time = platform.system() == "Darwin" and Path("/usr/bin/time").is_file()
    command = [
        str(executable),
        workload.identifier,
        implementation,
        str(process),
        str(database),
    ]
    if use_macos_time:
        command = ["/usr/bin/time", "-l", *command]

    print(
        f"[{schedule_index:02d}/{total:02d}] {workload.identifier} "
        f"{implementation} process {process}",
        flush=True,
    )
    started_at = comparison_run.utc_timestamp()
    completed = subprocess.run(
        command,
        cwd=prototype,
        env=environment,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    finished_at = comparison_run.utc_timestamp()
    samples_path.write_bytes(completed.stdout)
    resource_path.write_bytes(completed.stderr)
    if completed.returncode != 0:
        detail = completed.stderr.decode("utf-8", errors="replace").strip()
        raise HarnessError(
            f"{stem} exited with {completed.returncode}; raw output: "
            f"{samples_path}\n{detail}"
        )

    samples = parse_samples(
        completed.stdout,
        workload=workload.identifier,
        implementation=implementation,
        process=process,
    )
    if use_macos_time:
        peak_rss: dict[str, object] = {
            "scope": "implementation_process",
            "bytes": comparison_run.parse_macos_peak_rss(completed.stderr),
            "method": "usr_bin_time_l_macos",
            "unavailableReason": None,
            "rawOutput": str(resource_path.relative_to(output_directory)),
            "rawOutputSHA256": comparison_run.sha256_file(resource_path),
        }
    else:
        peak_rss = {
            "scope": "implementation_process",
            "bytes": None,
            "method": None,
            "unavailableReason": "/usr/bin/time -l is unavailable on this platform",
            "rawOutput": None,
            "rawOutputSHA256": None,
        }

    return {
        "workload": workload.identifier,
        "implementation": implementation,
        "process": process,
        "scheduleIndex": schedule_index,
        "startedAt": started_at,
        "finishedAt": finished_at,
        "rawSamples": str(samples_path.relative_to(output_directory)),
        "rawSamplesSHA256": comparison_run.sha256_file(samples_path),
        "samplesNanoseconds": samples,
        "peakRSS": peak_rss,
    }


def nearest_rank_p95(values: Sequence[int]) -> int:
    ordered = sorted(values)
    index = math.ceil(0.95 * len(ordered)) - 1
    return ordered[index]


def summarize(
    runs: Sequence[dict[str, object]],
    workload: WorkloadSpec,
) -> dict[str, object]:
    process_medians: list[float] = []
    process_p95s: list[int] = []
    peaks: list[int] = []
    for run in sorted(runs, key=lambda value: int(value["process"])):
        samples = run["samplesNanoseconds"]
        assert isinstance(samples, list)
        process_medians.append(statistics.median(samples))
        process_p95s.append(nearest_rank_p95(samples))
        peak_rss = run["peakRSS"]
        assert isinstance(peak_rss, dict)
        if isinstance(peak_rss.get("bytes"), int):
            peaks.append(peak_rss["bytes"])

    headline_median = statistics.median(process_medians)
    return {
        "medianNanoseconds": headline_median,
        "p95Nanoseconds": statistics.median(process_p95s),
        "operationsPerSecond": (
            workload.operations_per_iteration * 1_000_000_000.0 / headline_median
        ),
        "processMedianMinNanoseconds": min(process_medians),
        "processMedianMaxNanoseconds": max(process_medians),
        "processSpreadPercent": (
            (max(process_medians) - min(process_medians)) / headline_median * 100.0
        ),
        "peakRSSBytes": max(peaks) if len(peaks) == len(runs) else None,
    }


def build_results(
    runs: Sequence[dict[str, object]],
    workloads: Sequence[WorkloadSpec],
    implementations: Sequence[str],
) -> dict[str, object]:
    results: dict[str, dict[str, object]] = {}
    for workload in workloads:
        per_implementation: dict[str, object] = {}
        for implementation in implementations:
            matching = [
                run
                for run in runs
                if run["workload"] == workload.identifier
                and run["implementation"] == implementation
            ]
            if not matching:
                continue
            per_implementation[implementation] = summarize(matching, workload)
        results[workload.identifier] = per_implementation
    return results


def create_argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Build and run the issue #259 cross-library workload prototypes. "
            "The workspace must be new or empty."
        )
    )
    parser.add_argument("--workspace", type=Path, required=True)
    parser.add_argument("--swiftql-checkout", type=Path, required=True)
    parser.add_argument(
        "--output",
        type=Path,
        help="report path (default: <workspace>/prototype-results.json)",
    )
    parser.add_argument(
        "--processes",
        type=int,
        default=PROCESS_COUNT,
        help="independent processes per workload and implementation (default: 3)",
    )
    parser.add_argument(
        "--cooldown-seconds",
        type=float,
        default=60.0,
        help="idle delay after the release build (default: 60)",
    )
    parser.add_argument(
        "--allow-dirty",
        action="store_true",
        help="allow and explicitly record a dirty SwiftQL checkout",
    )
    parser.add_argument(
        "--prepare-only",
        action="store_true",
        help="verify the fixture and prepare the graph without building or timing",
    )
    return parser


def main(arguments: Sequence[str] | None = None) -> int:
    options = create_argument_parser().parse_args(arguments)
    try:
        if options.processes < 1:
            raise HarnessError("--processes must be at least 1")
        if (
            not math.isfinite(options.cooldown_seconds)
            or options.cooldown_seconds < 0
        ):
            raise HarnessError("--cooldown-seconds must be finite and non-negative")

        workspace = options.workspace.expanduser().resolve()
        swiftql_checkout = options.swiftql_checkout.expanduser().resolve()
        output = (
            options.output.expanduser().resolve()
            if options.output is not None
            else workspace / "prototype-results.json"
        )
        output_directory = output.parent
        runs_directory = output_directory / "Runs"

        comparison_run.ensure_empty_workspace(workspace)
        swiftql_revision, swiftql_dirty = comparison_run.inspect_swiftql_checkout(
            swiftql_checkout,
            options.allow_dirty,
        )
        if not options.prepare_only:
            if output.exists():
                raise HarnessError(f"refusing to overwrite report: {output}")
            if runs_directory.exists() and any(runs_directory.iterdir()):
                raise HarnessError(
                    f"refusing to mix outputs with existing files: {runs_directory}"
                )

        fixture = workspace / "Fixture" / "northwind-performance.sqlite"
        comparison_run.decompress_and_verify_fixture(fixture)
        print(f"Verified exact {comparison_run.ROW_COUNT}-row fixture: {fixture}")

        prototype = prepare_prototype(workspace, swiftql_checkout)
        if options.prepare_only:
            print("Prepared the prototype graph; build and timing were skipped.")
            return 0

        output_directory.mkdir(parents=True, exist_ok=True)
        runs_directory.mkdir(exist_ok=True)
        executable = build_prototype(prototype)
        if options.cooldown_seconds:
            print(
                f"Release prototype built; cooling down for "
                f"{options.cooldown_seconds:g} seconds",
                flush=True,
            )
            time.sleep(options.cooldown_seconds)

        # Reads share one pristine copy. The write workload gets its own copy
        # per process so no run observes another run's committed state.
        read_database = workspace / "Databases" / "read.sqlite"
        read_database.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(fixture, read_database)
        comparison_run.verify_database_fixture(read_database)

        entries = schedule(WORKLOADS, IMPLEMENTATIONS, options.processes)
        runs: list[dict[str, object]] = []
        for schedule_index, (process, workload, implementation) in enumerate(
            entries,
            start=1,
        ):
            if workload.writable:
                database = (
                    workspace
                    / "Databases"
                    / f"write-{workload.identifier}-{implementation}-{process}.sqlite"
                )
                shutil.copyfile(fixture, database)
                comparison_run.verify_database_fixture(database)
                add_scratch_table(database)
            else:
                database = read_database
            runs.append(
                run_one_process(
                    executable=executable,
                    prototype=prototype,
                    workload=workload,
                    implementation=implementation,
                    process=process,
                    schedule_index=schedule_index,
                    total=len(entries),
                    database=database,
                    runs_directory=runs_directory,
                    output_directory=output_directory,
                )
            )

        # The shared read database must be byte-identical afterwards: a read
        # workload that mutated it would invalidate every later read sample.
        comparison_run.verify_database_fixture(read_database)

        result = {
            "formatVersion": REPORT_FORMAT_VERSION,
            "generatedAt": comparison_run.utc_timestamp(),
            "provenance": {
                "harness": "independently_implemented",
                "purpose": "issue_259_workload_family_research_prototype",
                "relationshipToBaseline": (
                    "separate graph and separate report; it does not modify or "
                    "broaden the #250 full-fetch baseline"
                ),
            },
            "workloads": [
                {
                    "identifier": workload.identifier,
                    "contract": workload.contract,
                    "unit": workload.unit,
                    "operationsPerIteration": workload.operations_per_iteration,
                    "requiresWritableDatabase": workload.writable,
                    "apiTierByImplementation": dict(sorted(workload.tiers.items())),
                }
                for workload in WORKLOADS
            ],
            "measurement": {
                "warmupCount": WARMUP_COUNT,
                "sampleCount": SAMPLE_COUNT,
                "independentProcessCount": options.processes,
                "configuration": "release",
                "timer": "DispatchTime.uptimeNanoseconds",
                "processIsolation": "one_workload_and_implementation_per_process",
                "postBuildCooldownSeconds": options.cooldown_seconds,
                "scheduleOrder": "rotated_implementations_per_process",
                "timedBoundary": "end_to_end_only",
                "timedBoundaryReason": (
                    "the three libraries do not expose comparable construction, "
                    "preparation, binding, execution, and decoding seams, so "
                    "only the end-to-end operation is measured"
                ),
                "expectedCountryGroups": EXPECTED_COUNTRY_GROUPS,
                "writeBatchSize": WRITE_BATCH_SIZE,
                "lookupKeyCount": LOOKUP_KEY_COUNT,
            },
            "fixture": {
                # Relative to the repository root rather than to the report, so
                # the value stays meaningful wherever the report is written and
                # never records a machine-specific absolute path.
                "artifact": str(
                    comparison_run.FIXTURE_ARCHIVE.relative_to(REPOSITORY_ROOT)
                ),
                "artifactPathIsRelativeTo": "repository_root",
                "artifactSHA256": comparison_run.FIXTURE_ARCHIVE_SHA256,
                "databaseSHA256": comparison_run.FIXTURE_DATABASE_SHA256,
                "rowCount": comparison_run.ROW_COUNT,
                "sourceRepository": comparison_run.FIXTURE_SOURCE_REPOSITORY,
                "sourceRevision": comparison_run.FIXTURE_SOURCE_REVISION,
                "sharedWith": "Benchmarks/Comparison (#250)",
                "scratchTable": SCRATCH_TABLE,
                "scratchTableSQL": SCRATCH_TABLE_SQL,
            },
            "sources": {
                "swiftqlRevision": swiftql_revision,
                "swiftqlDirty": swiftql_dirty,
            },
            "environment": comparison_run.environment_metadata(),
            "dependencies": (
                comparison_run.resolved_dependencies(prototype / "Package.resolved")
                if (prototype / "Package.resolved").is_file()
                else {}
            ),
            "runs": runs,
            "results": build_results(runs, WORKLOADS, IMPLEMENTATIONS),
            "durationUnit": "nanoseconds_per_iteration",
        }
        output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
        print(f"Wrote prototype report: {output}")
        return 0
    except (HarnessError, OSError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
