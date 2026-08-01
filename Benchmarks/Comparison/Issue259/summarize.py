#!/usr/bin/env python3
"""Validate and render the issue #259 workload prototype report.

Everything is recomputed from the checked-in raw sample logs, so a hand-edited
summary cannot pass. Uses only the Python standard library.
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
SAMPLE_COUNT = 100
TOLERANCE = 1e-6


class ValidationError(RuntimeError):
    """The report is internally inconsistent or disagrees with its raw logs."""


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValidationError(message)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file_handle:
        for block in iter(lambda: file_handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def nearest_rank_p95(values: Sequence[int]) -> int:
    ordered = sorted(values)
    return ordered[math.ceil(0.95 * len(ordered)) - 1]


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


def validate_structure(document: dict[str, object]) -> None:
    for section in ("provenance", "measurement", "fixture", "sources", "environment"):
        require(
            isinstance(document.get(section), dict),
            f"missing or malformed {section!r} section",
        )
    for section in ("workloads", "runs"):
        require(
            isinstance(document.get(section), list) and document[section],
            f"missing or empty {section!r} section",
        )
    require(
        isinstance(document.get("results"), dict) and document["results"],
        "missing or empty 'results' section",
    )

    revision = document["sources"].get("swiftqlRevision")  # type: ignore[union-attr]
    require(
        isinstance(revision, str) and re.fullmatch(r"[0-9a-f]{40}", revision),
        f"swiftqlRevision is not a full Git SHA: {revision!r}",
    )

    measurement = document["measurement"]
    assert isinstance(measurement, dict)
    require(
        measurement.get("configuration") == "release",
        "prototypes must be recorded from release builds",
    )
    require(
        measurement.get("timedBoundary") == "end_to_end_only"
        and isinstance(measurement.get("timedBoundaryReason"), str)
        and measurement["timedBoundaryReason"],
        "the report must state which timing boundary it measured and why",
    )

    provenance = document["provenance"]
    assert isinstance(provenance, dict)
    require(
        isinstance(provenance.get("relationshipToBaseline"), str)
        and "#250" in str(provenance["relationshipToBaseline"]),
        "the report must state its relationship to the #250 baseline",
    )

    fixture = document["fixture"]
    assert isinstance(fixture, dict)
    artifact = fixture.get("artifact")
    require(
        isinstance(artifact, str) and artifact,
        "the report must record the fixture archive path",
    )
    require(
        fixture.get("artifactPathIsRelativeTo") == "repository_root",
        "the fixture archive path must be declared relative to the repository root",
    )
    require(
        not Path(str(artifact)).is_absolute() and ".." not in Path(str(artifact)).parts,
        f"the fixture archive path must stay inside the repository: {artifact!r}",
    )


def validate_workloads(document: dict[str, object]) -> set[str]:
    workloads = document["workloads"]
    assert isinstance(workloads, list)
    identifiers: set[str] = set()
    for workload in workloads:
        require(isinstance(workload, dict), "every workload must be a JSON object")
        identifier = workload.get("identifier")
        require(
            isinstance(identifier, str) and identifier,
            "every workload needs an identifier",
        )
        require(identifier not in identifiers, f"duplicate workload: {identifier!r}")
        identifiers.add(identifier)
        require(
            isinstance(workload.get("contract"), str) and workload["contract"],
            f"{identifier} has no falsifiable semantic contract",
        )
        tiers = workload.get("apiTierByImplementation")
        require(
            isinstance(tiers, dict)
            and tiers
            and all(isinstance(value, str) and value for value in tiers.values()),
            f"{identifier} must record the API tier each implementation used",
        )
        require(
            isinstance(workload.get("operationsPerIteration"), int)
            and workload["operationsPerIteration"] >= 1,
            f"{identifier} must record a positive operations-per-iteration count",
        )
    return identifiers


def validate_runs(document: dict[str, object], report_path: Path) -> None:
    runs = document["runs"]
    assert isinstance(runs, list)
    directory = report_path.parent
    seen_schedule: set[int] = set()
    seen_identity: set[tuple[object, ...]] = set()

    for run in runs:
        require(isinstance(run, dict), "every run must be a JSON object")
        identity = (run.get("workload"), run.get("implementation"), run.get("process"))
        require(identity not in seen_identity, f"duplicate run: {identity!r}")
        seen_identity.add(identity)

        schedule_index = run.get("scheduleIndex")
        require(
            isinstance(schedule_index, int) and schedule_index >= 1,
            "scheduleIndex must be a positive integer",
        )
        require(
            schedule_index not in seen_schedule,
            f"duplicate scheduleIndex: {schedule_index}",
        )
        seen_schedule.add(schedule_index)
        require(
            str(run.get("startedAt", "")) < str(run.get("finishedAt", "")),
            f"run {identity!r} did not finish after it started",
        )

        samples = run.get("samplesNanoseconds")
        require(
            isinstance(samples, list) and len(samples) == SAMPLE_COUNT,
            f"run {identity!r} must retain {SAMPLE_COUNT} raw samples",
        )
        require(
            all(isinstance(value, int) and value > 0 for value in samples),
            f"run {identity!r} contains a nonpositive sample",
        )

        raw_path = directory / str(run["rawSamples"])
        require(raw_path.is_file(), f"missing raw sample log: {raw_path}")
        require(
            sha256_file(raw_path) == run["rawSamplesSHA256"],
            f"raw sample hash mismatch for {raw_path}",
        )
        parsed = parse_raw_samples(
            raw_path,
            workload=str(run["workload"]),
            implementation=str(run["implementation"]),
            process=int(run["process"]),
        )
        require(
            parsed == samples,
            f"{raw_path} disagrees with the samples recorded in the report",
        )

        peak = run.get("peakRSS")
        require(isinstance(peak, dict), f"run {identity!r} has no peakRSS record")
        assert isinstance(peak, dict)
        if peak.get("bytes") is None:
            require(
                isinstance(peak.get("unavailableReason"), str)
                and peak["unavailableReason"],
                f"run {identity!r} must record why peak RSS is unavailable",
            )
        else:
            require(
                isinstance(peak["bytes"], int) and peak["bytes"] > 0,
                f"run {identity!r} has a nonpositive peak RSS",
            )
            resource_path = directory / str(peak["rawOutput"])
            require(resource_path.is_file(), f"missing resource log: {resource_path}")
            require(
                sha256_file(resource_path) == peak["rawOutputSHA256"],
                f"resource log hash mismatch for {resource_path}",
            )

    require(
        sorted(seen_schedule) == list(range(1, len(runs) + 1)),
        "scheduleIndex values must be contiguous from 1",
    )


def parse_raw_samples(
    path: Path,
    *,
    workload: str,
    implementation: str,
    process: int,
) -> list[int]:
    samples: list[int] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line:
            continue
        fields = line.split("\t")
        require(
            len(fields) == 6 and fields[0] == "SAMPLE",
            f"unexpected line in {path}: {line!r}",
        )
        require(fields[1] == workload, f"workload mismatch in {path}")
        require(fields[2] == implementation, f"implementation mismatch in {path}")
        require(int(fields[3]) == process, f"process mismatch in {path}")
        require(int(fields[4]) == len(samples) + 1, f"sample index gap in {path}")
        samples.append(int(fields[5]))
    return samples


def validate_results(document: dict[str, object]) -> dict[str, dict[str, dict[str, object]]]:
    runs = document["runs"]
    results = document["results"]
    workloads = document["workloads"]
    assert isinstance(runs, list) and isinstance(results, dict)
    assert isinstance(workloads, list)

    operations = {
        str(workload["identifier"]): int(workload["operationsPerIteration"])
        for workload in workloads
    }

    grouped: dict[tuple[str, str], list[dict[str, object]]] = {}
    for run in runs:
        grouped.setdefault(
            (str(run["workload"]), str(run["implementation"])),
            [],
        ).append(run)

    recomputed: dict[str, dict[str, dict[str, object]]] = {}
    for (workload, implementation), group in grouped.items():
        process_medians = []
        process_p95s = []
        peaks = []
        for run in sorted(group, key=lambda value: int(value["process"])):
            samples = run["samplesNanoseconds"]
            assert isinstance(samples, list)
            process_medians.append(statistics.median(samples))
            process_p95s.append(nearest_rank_p95(samples))
            peak = run["peakRSS"]
            assert isinstance(peak, dict)
            if isinstance(peak.get("bytes"), int):
                peaks.append(peak["bytes"])
        headline = statistics.median(process_medians)
        summary = {
            "medianNanoseconds": headline,
            "p95Nanoseconds": statistics.median(process_p95s),
            "operationsPerSecond": (
                operations[workload] * 1_000_000_000.0 / headline
            ),
            "processMedianMinNanoseconds": min(process_medians),
            "processMedianMaxNanoseconds": max(process_medians),
            "processSpreadPercent": (
                (max(process_medians) - min(process_medians)) / headline * 100.0
            ),
            "peakRSSBytes": max(peaks) if len(peaks) == len(group) else None,
        }
        recomputed.setdefault(workload, {})[implementation] = summary

        stored = results.get(workload, {})
        require(
            isinstance(stored, dict) and implementation in stored,
            f"results are missing {workload}/{implementation}",
        )
        recorded = stored[implementation]
        require(
            isinstance(recorded, dict) and set(recorded) == set(summary),
            f"results[{workload}][{implementation}] keys differ from the "
            f"recomputed summary",
        )
        for name, value in summary.items():
            observed = recorded[name]
            if value is None or observed is None:
                require(
                    value == observed,
                    f"results[{workload}][{implementation}][{name}] disagrees",
                )
            elif isinstance(value, int):
                require(
                    observed == value,
                    f"results[{workload}][{implementation}][{name}] disagrees",
                )
            else:
                require(
                    isinstance(observed, (int, float))
                    and abs(float(observed) - float(value)) <= TOLERANCE * max(1.0, abs(value)),
                    f"results[{workload}][{implementation}][{name}] disagrees: "
                    f"{observed!r} != {value!r}",
                )

    require(
        set(results) == set(recomputed),
        f"results cover {sorted(results)} but runs cover {sorted(recomputed)}",
    )
    return recomputed


def validate(document: dict[str, object], report_path: Path) -> dict[str, dict[str, dict[str, object]]]:
    validate_structure(document)
    declared = validate_workloads(document)
    validate_runs(document, report_path)
    recorded = {str(run["workload"]) for run in document["runs"]}  # type: ignore[union-attr]
    require(
        recorded == declared,
        f"declared workloads {sorted(declared)} do not match recorded "
        f"workloads {sorted(recorded)}",
    )
    return validate_results(document)


def format_duration(nanoseconds: float) -> str:
    if nanoseconds >= 1_000_000:
        return f"{nanoseconds / 1_000_000:,.2f} ms"
    if nanoseconds >= 1_000:
        return f"{nanoseconds / 1_000:,.2f} us"
    return f"{nanoseconds:,.0f} ns"


def format_bytes(value: int | None) -> str:
    if value is None:
        return "unavailable"
    return f"{value / (1024 * 1024):,.1f} MiB"


def render(
    document: dict[str, object],
    summaries: dict[str, dict[str, dict[str, object]]],
) -> str:
    environment = document["environment"]
    sources = document["sources"]
    measurement = document["measurement"]
    assert isinstance(environment, dict) and isinstance(sources, dict)
    assert isinstance(measurement, dict)

    title = "Issue #259 cross-library workload prototypes"
    lines = [title, "=" * len(title), ""]
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
        f"{measurement['independentProcessCount']} release processes per cell, "
        f"{measurement['warmupCount']} warmups, {measurement['sampleCount']} "
        f"timed samples each"
    )
    lines.append(f"Timing boundary: {measurement['timedBoundary']}")
    lines.append("")

    workloads = document["workloads"]
    assert isinstance(workloads, list)
    for workload in workloads:
        assert isinstance(workload, dict)
        identifier = str(workload["identifier"])
        lines.append(identifier)
        lines.append("-" * len(identifier))
        lines.append(f"  {workload['contract']}")
        lines.append("")
        lines.append(
            f"  {'implementation':<18}{'API tier':<28}{'median':>12}{'p95':>12}"
            f"{'ops/s':>14}{'spread':>10}{'peak RSS':>12}"
        )
        tiers = workload["apiTierByImplementation"]
        assert isinstance(tiers, dict)
        for implementation, summary in sorted(summaries.get(identifier, {}).items()):
            lines.append(
                f"  {implementation:<18}{str(tiers.get(implementation, '?')):<28}"
                f"{format_duration(float(summary['medianNanoseconds'])):>12}"
                f"{format_duration(float(summary['p95Nanoseconds'])):>12}"
                f"{float(summary['operationsPerSecond']):>14,.0f}"
                f"{float(summary['processSpreadPercent']):>9.1f}%"
                f"{format_bytes(summary['peakRSSBytes']):>12}"
            )
        lines.append("")

    lines.append(
        "API tiers differ where a library has no equivalent surface; read the "
        "tier column before comparing two rows."
    )
    lines.append(
        "Process spread is the relative gap between the fastest and slowest "
        "process median. Treat a difference smaller than the larger of the two "
        "spreads as noise."
    )
    lines.append(
        "These are prototypes for workload design. No value here is a baseline "
        "or a CI gate."
    )
    return "\n".join(lines) + "\n"


def create_argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Validate an issue #259 prototype report against its raw sample "
            "logs and render the per-workload tables."
        )
    )
    parser.add_argument("report", type=Path)
    return parser


def main(arguments: Sequence[str] | None = None) -> int:
    options = create_argument_parser().parse_args(arguments)
    try:
        report_path = options.report.expanduser().resolve()
        document = load_report(report_path)
        summaries = validate(document, report_path)
        sys.stdout.write(render(document, summaries))
        return 0
    except (ValidationError, OSError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
