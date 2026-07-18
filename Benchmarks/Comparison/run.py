#!/usr/bin/env python3
"""Build and run SwiftQL's independently implemented SQLite comparison."""

from __future__ import annotations

import argparse
import dataclasses
import datetime as dt
import gzip
import hashlib
import json
import math
import os
import platform
import re
import shlex
import shutil
import sqlite3
import statistics
import subprocess
import sys
import time
from pathlib import Path
from typing import Sequence


SCRIPT_DIRECTORY = Path(__file__).resolve().parent
GRAPH_TEMPLATE_DIRECTORY = SCRIPT_DIRECTORY / "Graphs"
SUPPORT_PACKAGE_DIRECTORY = (
    SCRIPT_DIRECTORY / "Sources" / "ComparisonBenchmarkSupport"
)
FIXTURE_ARCHIVE = SCRIPT_DIRECTORY / "Fixtures" / "northwind-performance.sqlite.gz"
FIXTURE_LICENSE = SCRIPT_DIRECTORY / "Fixtures" / "Northwind-LICENSE.txt"

FIXTURE_ARCHIVE_SHA256 = (
    "7f6c2731fc6f160d874f7d8ab9527066a8d54515e667948dec9ee05ef41dd6b5"
)
FIXTURE_DATABASE_SHA256 = (
    "22c8a23a6db7720128c22c7082d0bc7922bd40c9e2c14da756300f21c178b43a"
)
FIXTURE_LICENSE_SHA256 = (
    "c28e204be6418b87ae1c83127096aad9c9e1a218c365f8f4d630e84d8ba96c47"
)
FIXTURE_DATABASE_BYTES = 24_412_160
FIXTURE_PAGE_SIZE = 4_096
FIXTURE_PAGE_COUNT = 5_960
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
ROW_COUNT = 16_143
COLUMN_COUNT = len(EXPECTED_ORDER_COLUMNS)
WARMUP_COUNT = 10
SAMPLE_COUNT = 100
PROCESS_COUNT = 3
CROSS_GRAPH_TOLERANCE_PERCENT = 5.0
WORKLOAD_REFERENCE_REPOSITORY = (
    "https://github.com/Lighter-swift/PerformanceTestSuite.git"
)
WORKLOAD_REFERENCE_REVISION = "892dfa0bb8fc023a8a25de873f34c3fb766c927a"
FIXTURE_SOURCE_REPOSITORY = "https://github.com/jpwhite3/northwind-SQLite3.git"
FIXTURE_SOURCE_REVISION = "4f56e7f5906dfd23b25244c5bfe8fb5da6402efd"

COMMON_IMPLEMENTATIONS = (
    "generated_raw_sqlite",
    "lighter",
    "grdb_manual",
    "grdb_codable",
    "sqlite_swift_manual",
    "sqlite_swift_typed",
)


class HarnessError(RuntimeError):
    """A benchmark precondition or subprocess failed."""


@dataclasses.dataclass(frozen=True)
class GraphSpec:
    identifier: str
    template_name: str
    unique_implementation: str
    includes_swiftql: bool

    @property
    def implementations(self) -> tuple[str, ...]:
        return COMMON_IMPLEMENTATIONS + (self.unique_implementation,)


GRAPH_SPECS = (
    GraphSpec(
        identifier="swiftql_grdb6",
        template_name="SwiftQLGRDB6",
        unique_implementation="swiftql",
        includes_swiftql=True,
    ),
    GraphSpec(
        identifier="sqlitedata_grdb7",
        template_name="SQLiteDataGRDB7",
        unique_implementation="sqlite_data",
        includes_swiftql=False,
    ),
)


def utc_timestamp() -> str:
    return (
        dt.datetime.now(dt.timezone.utc)
        .isoformat(timespec="microseconds")
        .replace("+00:00", "Z")
    )


def display_command(arguments: Sequence[str]) -> str:
    return shlex.join(str(argument) for argument in arguments)


def run_visible(arguments: Sequence[str], *, cwd: Path | None = None) -> None:
    command = [str(argument) for argument in arguments]
    print(f"+ {display_command(command)}", flush=True)
    completed = subprocess.run(command, cwd=cwd, check=False)
    if completed.returncode != 0:
        raise HarnessError(
            f"command exited with status {completed.returncode}: "
            f"{display_command(command)}"
        )


def capture_command(arguments: Sequence[str], *, cwd: Path | None = None) -> str:
    command = [str(argument) for argument in arguments]
    completed = subprocess.run(
        command,
        cwd=cwd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if completed.returncode != 0:
        stderr = completed.stderr.decode("utf-8", errors="replace").strip()
        detail = f"\n{stderr}" if stderr else ""
        raise HarnessError(
            f"command exited with status {completed.returncode}: "
            f"{display_command(command)}{detail}"
        )
    return completed.stdout.decode("utf-8", errors="strict").strip()


def optional_command(arguments: Sequence[str]) -> str:
    try:
        return capture_command(arguments)
    except (HarnessError, OSError):
        return "unavailable"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file_handle:
        for block in iter(lambda: file_handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def ensure_empty_workspace(workspace: Path) -> None:
    if workspace.exists():
        if workspace.is_symlink() or not workspace.is_dir():
            raise HarnessError(f"workspace is not a directory: {workspace}")
        if any(workspace.iterdir()):
            raise HarnessError(
                f"workspace must be empty; refusing to delete files: {workspace}"
            )
        return
    workspace.mkdir(parents=True)


def inspect_swiftql_checkout(checkout: Path, allow_dirty: bool) -> tuple[str, bool]:
    if not checkout.is_dir():
        raise HarnessError(f"SwiftQL checkout is not a directory: {checkout}")
    root = Path(capture_command(("git", "rev-parse", "--show-toplevel"), cwd=checkout))
    if root.resolve() != checkout:
        raise HarnessError(
            f"--swiftql-checkout must be the repository root, found {root}"
        )
    revision = capture_command(("git", "rev-parse", "HEAD"), cwd=checkout)
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise HarnessError(f"SwiftQL revision is not a full Git SHA: {revision!r}")
    dirty = bool(
        capture_command(
            ("git", "status", "--porcelain=v1", "--untracked-files=normal"),
            cwd=checkout,
        )
    )
    if dirty and not allow_dirty:
        raise HarnessError(
            "SwiftQL checkout has uncommitted changes; commit them or pass "
            "--allow-dirty to record the non-reproducible state"
        )
    return revision, dirty


def decompress_and_verify_fixture(destination: Path) -> None:
    if sha256_file(FIXTURE_ARCHIVE) != FIXTURE_ARCHIVE_SHA256:
        raise HarnessError("committed fixture archive SHA-256 does not match")
    if sha256_file(FIXTURE_LICENSE) != FIXTURE_LICENSE_SHA256:
        raise HarnessError("committed Northwind license SHA-256 does not match")

    destination.parent.mkdir(parents=True, exist_ok=True)
    with gzip.open(FIXTURE_ARCHIVE, "rb") as compressed:
        with destination.open("wb") as database_file:
            shutil.copyfileobj(compressed, database_file, length=1024 * 1024)

    verify_database_fixture(destination)


def verify_database_fixture(destination: Path) -> None:
    """Verify the exact database bytes and logical contract without rewriting it."""

    if destination.stat().st_size != FIXTURE_DATABASE_BYTES:
        raise HarnessError("decompressed fixture byte count does not match")
    if sha256_file(destination) != FIXTURE_DATABASE_SHA256:
        raise HarnessError("decompressed fixture SHA-256 does not match")

    connection = sqlite3.connect(f"{destination.resolve().as_uri()}?mode=ro", uri=True)
    try:
        quick_check = connection.execute("PRAGMA quick_check").fetchone()
        page_size = int(connection.execute("PRAGMA page_size").fetchone()[0])
        page_count = int(connection.execute("PRAGMA page_count").fetchone()[0])
        columns = tuple(
            row[1] for row in connection.execute('PRAGMA table_info("Orders")')
        )
        row_count = int(
            connection.execute('SELECT COUNT(*) FROM "Orders"').fetchone()[0]
        )
    finally:
        connection.close()

    if quick_check != ("ok",):
        raise HarnessError(f"fixture integrity check failed: {quick_check!r}")
    if (page_size, page_count) != (FIXTURE_PAGE_SIZE, FIXTURE_PAGE_COUNT):
        raise HarnessError(
            f"fixture page layout changed: {(page_size, page_count)!r}"
        )
    if columns != EXPECTED_ORDER_COLUMNS:
        raise HarnessError(f"fixture Orders columns changed: {columns!r}")
    if row_count != ROW_COUNT:
        raise HarnessError(
            f"fixture Orders count changed: expected {ROW_COUNT}, found {row_count}"
        )


def swift_string_literal(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def prepare_graph(
    graph_root: Path,
    spec: GraphSpec,
    swiftql_checkout: Path,
    support_package: Path,
    fixture: Path,
) -> Path:
    template = GRAPH_TEMPLATE_DIRECTORY / spec.template_name
    if not template.is_dir():
        raise HarnessError(f"graph template is missing: {template}")
    destination = graph_root / spec.identifier
    shutil.copytree(template, destination)

    manifest = destination / "Package.swift"
    manifest_text = manifest.read_text(encoding="utf-8")
    support_placeholder = "__SUPPORT_PACKAGE__"
    if manifest_text.count(support_placeholder) != 1:
        raise HarnessError(
            f"{manifest} must contain exactly one {support_placeholder} placeholder"
        )
    manifest_text = manifest_text.replace(
        support_placeholder,
        swift_string_literal(str(support_package)),
    )

    placeholder = "__SWIFTQL_CHECKOUT__"
    if spec.includes_swiftql:
        if manifest_text.count(placeholder) != 1:
            raise HarnessError(
                f"{manifest} must contain exactly one {placeholder} placeholder"
            )
        manifest_text = manifest_text.replace(
            placeholder,
            swift_string_literal(str(swiftql_checkout)),
        )
    elif placeholder in manifest_text:
        raise HarnessError(f"unexpected SwiftQL placeholder in {manifest}")
    manifest.write_text(manifest_text, encoding="utf-8")

    fixture_destination = (
        destination
        / "Sources"
        / "ComparisonBenchmark"
        / "northwind-performance.sqlite"
    )
    fixture_destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(fixture, fixture_destination)
    if sha256_file(fixture_destination) != FIXTURE_DATABASE_SHA256:
        raise HarnessError(f"fixture copy changed in graph {spec.identifier}")
    return destination


def resolved_dependencies(path: Path) -> dict[str, dict[str, str]]:
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise HarnessError(f"could not read {path}: {error}") from error
    if document.get("version") not in (2, 3) or not isinstance(document.get("pins"), list):
        raise HarnessError(f"unsupported Package.resolved structure: {path}")

    dependencies: dict[str, dict[str, str]] = {}
    for pin in document["pins"]:
        if not isinstance(pin, dict) or not isinstance(pin.get("state"), dict):
            raise HarnessError(f"invalid pin in {path}")
        identity = pin.get("identity")
        version = pin["state"].get("version")
        revision = pin["state"].get("revision")
        if not isinstance(identity, str) or not identity:
            raise HarnessError(f"dependency without identity in {path}")
        if not isinstance(version, str) or not version:
            raise HarnessError(f"dependency {identity!r} lacks an exact version")
        if not isinstance(revision, str) or not re.fullmatch(r"[0-9a-f]{40}", revision):
            raise HarnessError(f"dependency {identity!r} lacks a full revision")
        if identity in dependencies:
            raise HarnessError(f"duplicate dependency {identity!r} in {path}")
        dependencies[identity] = {"version": version, "revision": revision}
    return dict(sorted(dependencies.items()))


def build_graph(graph: Path) -> Path:
    resolution = graph / "Package.resolved"
    expected = resolved_dependencies(resolution)
    run_visible(
        ("swift", "build", "--configuration", "release", "--product", "ComparisonBenchmark"),
        cwd=graph,
    )
    if resolved_dependencies(resolution) != expected:
        raise HarnessError(f"SwiftPM rewrote the pinned resolution in {graph}")
    binary_directory = Path(
        capture_command(
            ("swift", "build", "--configuration", "release", "--show-bin-path"),
            cwd=graph,
        )
    )
    executable = binary_directory / "ComparisonBenchmark"
    if not executable.is_file():
        raise HarnessError(f"release executable is missing: {executable}")
    return executable


def parse_samples(
    output: bytes,
    *,
    implementation: str,
    process: int,
) -> list[int]:
    try:
        text = output.decode("utf-8", errors="strict")
    except UnicodeDecodeError as error:
        raise HarnessError(f"benchmark output was not UTF-8: {error}") from error

    samples: list[int] = []
    for line in text.splitlines():
        if not line:
            continue
        fields = line.split("\t")
        if len(fields) != 5 or fields[0] != "SAMPLE":
            raise HarnessError(f"unexpected benchmark stdout line: {line!r}")
        if fields[1] != implementation:
            raise HarnessError(
                f"sample implementation mismatch: {fields[1]!r} != {implementation!r}"
            )
        try:
            line_process = int(fields[2])
            sample_index = int(fields[3])
            nanoseconds = int(fields[4])
        except ValueError as error:
            raise HarnessError(f"non-integer sample field: {line!r}") from error
        if line_process != process:
            raise HarnessError(
                f"sample process mismatch: {line_process} != {process}"
            )
        if sample_index != len(samples) + 1:
            raise HarnessError(
                f"sample index mismatch: expected {len(samples) + 1}, found {sample_index}"
            )
        if nanoseconds <= 0:
            raise HarnessError(f"sample duration must be positive: {nanoseconds}")
        samples.append(nanoseconds)
    if len(samples) != SAMPLE_COUNT:
        raise HarnessError(
            f"expected {SAMPLE_COUNT} samples, found {len(samples)} for "
            f"{implementation} process {process}"
        )
    return samples


def parse_macos_peak_rss(stderr: bytes) -> int:
    text = stderr.decode("utf-8", errors="replace")
    matches = re.findall(
        r"^\s*(\d+)\s+maximum resident set size\s*$",
        text,
        flags=re.MULTILINE,
    )
    if len(matches) != 1:
        raise HarnessError(
            "could not find one maximum resident set size value in /usr/bin/time output"
        )
    value = int(matches[0])
    if value <= 0:
        raise HarnessError(f"peak RSS must be positive, found {value}")
    return value


def run_one_process(
    *,
    graph: Path,
    executable: Path,
    spec: GraphSpec,
    implementation: str,
    process: int,
    schedule_index: int,
    output_directory: Path,
    runs_directory: Path,
) -> dict[str, object]:
    stem = f"{spec.identifier}-{implementation}-process-{process:02d}"
    samples_path = runs_directory / f"{stem}.samples.tsv"
    resource_path = runs_directory / f"{stem}.resource.log"

    environment = dict(os.environ)
    environment.update(
        {
            "LANG": "C",
            "LC_ALL": "C",
        }
    )
    use_macos_time = platform.system() == "Darwin" and Path("/usr/bin/time").is_file()
    command = [str(executable), implementation, str(process)]
    if use_macos_time:
        command = ["/usr/bin/time", "-l", *command]

    print(
        f"[{schedule_index:02d}/42] {spec.identifier} {implementation} "
        f"process {process}",
        flush=True,
    )
    started_at = utc_timestamp()
    completed = subprocess.run(
        command,
        cwd=graph,
        env=environment,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    finished_at = utc_timestamp()
    samples_path.write_bytes(completed.stdout)
    resource_path.write_bytes(completed.stderr)
    if completed.returncode != 0:
        error_text = completed.stderr.decode("utf-8", errors="replace").strip()
        raise HarnessError(
            f"{implementation} process {process} exited with "
            f"{completed.returncode}; raw output: {samples_path}\n{error_text}"
        )

    samples = parse_samples(
        completed.stdout,
        implementation=implementation,
        process=process,
    )
    if use_macos_time:
        peak_rss: dict[str, object] = {
            "scope": "implementation_process",
            "bytes": parse_macos_peak_rss(completed.stderr),
            "method": "usr_bin_time_l_macos",
            "unavailableReason": None,
            "rawOutput": str(resource_path.relative_to(output_directory)),
            "rawOutputSHA256": sha256_file(resource_path),
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
        "implementation": implementation,
        "process": process,
        "scheduleIndex": schedule_index,
        "startedAt": started_at,
        "finishedAt": finished_at,
        "rawSamples": str(samples_path.relative_to(output_directory)),
        "rawSamplesSHA256": sha256_file(samples_path),
        "samplesNanoseconds": samples,
        "peakRSS": peak_rss,
    }


def rotated(values: tuple[str, ...], offset: int) -> tuple[str, ...]:
    offset %= len(values)
    return values[offset:] + values[:offset]


def schedule() -> list[tuple[int, GraphSpec, str]]:
    entries: list[tuple[int, GraphSpec, str]] = []
    for process in range(1, PROCESS_COUNT + 1):
        graphs = GRAPH_SPECS if process % 2 == 1 else tuple(reversed(GRAPH_SPECS))
        for implementation in rotated(COMMON_IMPLEMENTATIONS, process - 1):
            entries.extend(
                (process, graph, implementation)
                for graph in graphs
            )
        entries.extend(
            (process, graph, graph.unique_implementation)
            for graph in graphs
        )
    if len(entries) != 42:
        raise AssertionError(f"unexpected schedule length: {len(entries)}")
    return entries


def median(values: Sequence[int | float]) -> int | float:
    return statistics.median(values)


def nearest_rank_p95(values: Sequence[int]) -> int:
    ordered = sorted(values)
    index = math.ceil(0.95 * len(ordered)) - 1
    return ordered[index]


def implementation_statistics(runs: Sequence[dict[str, object]]) -> dict[str, object]:
    process_medians: list[int | float] = []
    process_p95s: list[int] = []
    peak_values: list[int] = []
    for run in sorted(runs, key=lambda value: int(value["process"])):
        samples = run["samplesNanoseconds"]
        assert isinstance(samples, list)
        process_medians.append(median(samples))
        process_p95s.append(nearest_rank_p95(samples))
        peak_rss = run["peakRSS"]
        assert isinstance(peak_rss, dict)
        if isinstance(peak_rss.get("bytes"), int):
            peak_values.append(peak_rss["bytes"])

    headline_median = median(process_medians)
    headline_p95 = median(process_p95s)
    spread = (
        (max(process_medians) - min(process_medians)) / headline_median * 100.0
    )
    return {
        "medianNanoseconds": headline_median,
        "p95Nanoseconds": headline_p95,
        "rowsPerSecond": ROW_COUNT * 1_000_000_000.0 / headline_median,
        "processMedianMinNanoseconds": min(process_medians),
        "processMedianMaxNanoseconds": max(process_medians),
        "processSpreadPercent": spread,
        "peakRSSBytes": max(peak_values) if len(peak_values) == PROCESS_COUNT else None,
    }


def build_results(graph_documents: Sequence[dict[str, object]]) -> dict[str, object]:
    graphs_by_id = {str(graph["identifier"]): graph for graph in graph_documents}
    graph_statistics: dict[str, dict[str, dict[str, object]]] = {}
    for graph in graph_documents:
        identifier = str(graph["identifier"])
        graph_runs = graph["runs"]
        assert isinstance(graph_runs, list)
        graph_statistics[identifier] = {}
        for implementation in graph["implementations"]:
            matching = [
                run for run in graph_runs
                if run["implementation"] == implementation
            ]
            graph_statistics[identifier][str(implementation)] = (
                implementation_statistics(matching)
            )

    implementations: dict[str, object] = {}
    for implementation in COMMON_IMPLEMENTATIONS:
        result = dict(graph_statistics["swiftql_grdb6"][implementation])
        result["canonicalGraph"] = "swiftql_grdb6"
        implementations[implementation] = result
    implementations["swiftql"] = {
        **graph_statistics["swiftql_grdb6"]["swiftql"],
        "canonicalGraph": "swiftql_grdb6",
    }
    implementations["sqlite_data"] = {
        **graph_statistics["sqlitedata_grdb7"]["sqlite_data"],
        "canonicalGraph": "sqlitedata_grdb7",
    }

    control_drift: dict[str, float] = {}
    for implementation in COMMON_IMPLEMENTATIONS:
        left = graph_statistics["swiftql_grdb6"][implementation][
            "medianNanoseconds"
        ]
        right = graph_statistics["sqlitedata_grdb7"][implementation][
            "medianNanoseconds"
        ]
        assert isinstance(left, (int, float)) and isinstance(right, (int, float))
        midpoint = (left + right) / 2.0
        divergence = abs(left - right) / midpoint * 100.0
        if divergence > CROSS_GRAPH_TOLERANCE_PERCENT:
            raise HarnessError(
                f"cross-graph control {implementation} diverged by "
                f"{divergence:.3f}% (limit {CROSS_GRAPH_TOLERANCE_PERCENT:.1f}%)"
            )
        control_drift[implementation] = divergence

    return {
        "implementations": dict(sorted(implementations.items())),
        "graphImplementations": graph_statistics,
        "controlDriftPercent": dict(sorted(control_drift.items())),
        "controlDriftTolerancePercent": CROSS_GRAPH_TOLERANCE_PERCENT,
    }


def integer_from_optional_command(arguments: Sequence[str]) -> int | None:
    value = optional_command(arguments)
    try:
        return int(value)
    except ValueError:
        return None


def environment_metadata() -> dict[str, object]:
    product_version = optional_command(("sw_vers", "-productVersion"))
    build_version = optional_command(("sw_vers", "-buildVersion"))
    if product_version == "unavailable":
        operating_system = platform.platform()
    else:
        suffix = "" if build_version == "unavailable" else f" ({build_version})"
        operating_system = f"macOS {product_version}{suffix}"
    return {
        "model": optional_command(("sysctl", "-n", "hw.model")),
        "processor": optional_command(("sysctl", "-n", "machdep.cpu.brand_string")),
        "coreCount": os.cpu_count(),
        "memoryBytes": integer_from_optional_command(("sysctl", "-n", "hw.memsize")),
        "architecture": platform.machine(),
        "operatingSystem": operating_system,
        "xcode": optional_command(("xcodebuild", "-version")),
        "swift": optional_command(("swift", "--version")),
        "sqlite": optional_command(("sqlite3", "--version")),
        "python": platform.python_version(),
        "pythonSQLite": sqlite3.sqlite_version,
        "git": optional_command(("git", "--version")),
    }


def relative_to_report(path: Path, output_directory: Path) -> str:
    return os.path.relpath(path, output_directory)


def create_argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Build and run the independently implemented cross-library SQLite "
            "comparison. The workspace must be new or empty."
        )
    )
    parser.add_argument("--workspace", type=Path, required=True)
    parser.add_argument("--swiftql-checkout", type=Path, required=True)
    parser.add_argument(
        "--output",
        type=Path,
        help="report path (default: <workspace>/comparison-results.json)",
    )
    parser.add_argument(
        "--cooldown-seconds",
        type=float,
        default=60.0,
        help="idle delay after both release builds (default: 60)",
    )
    parser.add_argument(
        "--allow-dirty",
        action="store_true",
        help="allow and explicitly record a dirty SwiftQL checkout",
    )
    parser.add_argument(
        "--prepare-only",
        action="store_true",
        help="verify the fixture and prepare graphs without building or timing",
    )
    return parser


def main(arguments: Sequence[str] | None = None) -> int:
    options = create_argument_parser().parse_args(arguments)
    try:
        if not math.isfinite(options.cooldown_seconds) or options.cooldown_seconds < 0:
            raise HarnessError("--cooldown-seconds must be finite and non-negative")
        workspace = options.workspace.expanduser().resolve()
        swiftql_checkout = options.swiftql_checkout.expanduser().resolve()
        output = (
            options.output.expanduser().resolve()
            if options.output is not None
            else workspace / "comparison-results.json"
        )
        output_directory = output.parent
        runs_directory = output_directory / "Runs"

        ensure_empty_workspace(workspace)
        swiftql_revision, swiftql_dirty = inspect_swiftql_checkout(
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
        decompress_and_verify_fixture(fixture)
        if not SUPPORT_PACKAGE_DIRECTORY.is_dir():
            raise HarnessError(
                f"comparison support package is missing: {SUPPORT_PACKAGE_DIRECTORY}"
            )
        support_package = workspace / "Sources" / "ComparisonBenchmarkSupport"
        shutil.copytree(SUPPORT_PACKAGE_DIRECTORY, support_package)
        graph_root = workspace / "Graphs"
        graph_root.mkdir()
        prepared_graphs = {
            spec.identifier: prepare_graph(
                graph_root,
                spec,
                swiftql_checkout,
                support_package,
                fixture,
            )
            for spec in GRAPH_SPECS
        }
        print(f"Verified exact {ROW_COUNT}-row fixture: {fixture}")

        if options.prepare_only:
            print("Prepared both independent graphs; build and timing were skipped.")
            return 0

        output_directory.mkdir(parents=True, exist_ok=True)
        runs_directory.mkdir(exist_ok=True)
        executables = {
            spec.identifier: build_graph(prepared_graphs[spec.identifier])
            for spec in GRAPH_SPECS
        }
        if options.cooldown_seconds:
            print(
                f"Both release graphs built; cooling down for "
                f"{options.cooldown_seconds:g} seconds",
                flush=True,
            )
            time.sleep(options.cooldown_seconds)

        runs_by_graph: dict[str, list[dict[str, object]]] = {
            spec.identifier: [] for spec in GRAPH_SPECS
        }
        for schedule_index, (process, spec, implementation) in enumerate(
            schedule(),
            start=1,
        ):
            run = run_one_process(
                graph=prepared_graphs[spec.identifier],
                executable=executables[spec.identifier],
                spec=spec,
                implementation=implementation,
                process=process,
                schedule_index=schedule_index,
                output_directory=output_directory,
                runs_directory=runs_directory,
            )
            runs_by_graph[spec.identifier].append(run)

        verify_database_fixture(fixture)
        for graph in prepared_graphs.values():
            verify_database_fixture(
                graph
                / "Sources"
                / "ComparisonBenchmark"
                / "northwind-performance.sqlite"
            )
        graph_documents: list[dict[str, object]] = []
        for spec in GRAPH_SPECS:
            graph = prepared_graphs[spec.identifier]
            graph_documents.append(
                {
                    "identifier": spec.identifier,
                    "implementations": list(spec.implementations),
                    "dependencies": resolved_dependencies(graph / "Package.resolved"),
                    "runs": runs_by_graph[spec.identifier],
                }
            )

        result = {
            "formatVersion": 3,
            "generatedAt": utc_timestamp(),
            "provenance": {
                "workloadReference": {
                    "repository": WORKLOAD_REFERENCE_REPOSITORY,
                    "revision": WORKLOAD_REFERENCE_REVISION,
                    "licenseStatus": "absent_at_revision",
                    "usage": "workload_reference_only",
                    "codeCopied": False,
                    "artifactsCopied": False,
                },
                "harness": "independently_implemented",
            },
            "workload": {
                "identifier": "northwind_orders_full_fetch",
                "rowCount": ROW_COUNT,
                "selectedColumnCount": COLUMN_COUNT,
                "warmupCount": WARMUP_COUNT,
                "sampleCount": SAMPLE_COUNT,
                "independentProcessCount": PROCESS_COUNT,
                "configuration": "release",
                "timer": "DispatchTime.uptimeNanoseconds",
                "processIsolation": "one_implementation_per_process",
                "postBuildCooldownSeconds": options.cooldown_seconds,
                "graphProcessOrder": "rotated_implementations_alternating_graph_pairs",
            },
            "fixture": {
                "artifact": relative_to_report(FIXTURE_ARCHIVE, output_directory),
                "artifactSHA256": FIXTURE_ARCHIVE_SHA256,
                "databaseSHA256": FIXTURE_DATABASE_SHA256,
                "databaseBytes": FIXTURE_DATABASE_BYTES,
                "pageSize": FIXTURE_PAGE_SIZE,
                "pageCount": FIXTURE_PAGE_COUNT,
                "rowCount": ROW_COUNT,
                "columnCount": COLUMN_COUNT,
                "sourceRepository": FIXTURE_SOURCE_REPOSITORY,
                "sourceRevision": FIXTURE_SOURCE_REVISION,
                "license": {
                    "spdxIdentifier": "MIT",
                    "path": relative_to_report(FIXTURE_LICENSE, output_directory),
                    "sha256": FIXTURE_LICENSE_SHA256,
                },
                "reproducibility": (
                    "authoritative_snapshot; upstream population is nondeterministic"
                ),
            },
            "sources": {
                "swiftqlRevision": swiftql_revision,
                "swiftqlDirty": swiftql_dirty,
            },
            "environment": environment_metadata(),
            "graphs": graph_documents,
            "results": build_results(graph_documents),
            "durationUnit": "nanoseconds_per_fetch",
        }
        output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
        print(f"Wrote comparison report: {output}")
        return 0
    except (HarnessError, OSError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
