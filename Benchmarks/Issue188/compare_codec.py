#!/usr/bin/env python3
"""Render issue #188 workload comparisons from SwiftQL benchmark JSON."""

import argparse
import json
import statistics
import sys
from pathlib import Path


def load_report(path: Path) -> dict:
    with path.open(encoding="utf-8") as stream:
        report = json.load(stream)
    if report.get("formatVersion") != 1:
        raise ValueError(f"{path}: unsupported benchmark format")
    return report


def case(report: dict, identifier: str) -> dict:
    matches = [item for item in report["cases"] if item["identifier"] == identifier]
    if len(matches) != 1:
        raise ValueError(f"expected one {identifier!r} case, found {len(matches)}")
    return matches[0]


def phase_median(report: dict, benchmark_case: dict, phase_name: str) -> float:
    matches = [item for item in benchmark_case["phases"] if item["phase"] == phase_name]
    if len(matches) != 1 or matches[0]["applicability"] != "measured":
        raise ValueError(
            f"{benchmark_case['identifier']}: {phase_name} is not measured exactly once"
        )
    measurement = matches[0].get("measurement")
    if not isinstance(measurement, dict):
        raise ValueError(
            f"{benchmark_case['identifier']}: {phase_name} has no measurement"
        )
    samples = measurement.get("samplesNanoseconds")
    expected_count = report["configuration"]["sampleCount"]
    if (
        not isinstance(samples, list)
        or len(samples) != expected_count
        or any(
            isinstance(sample, bool) or not isinstance(sample, int) or sample < 0
            for sample in samples
        )
    ):
        raise ValueError(
            f"{benchmark_case['identifier']}: {phase_name} has invalid raw samples"
        )
    calculated = float(statistics.median(samples))
    stored = float(measurement["summary"]["medianNanoseconds"])
    if stored != calculated:
        raise ValueError(
            f"{benchmark_case['identifier']}: {phase_name} median does not match raw samples"
        )
    return calculated


def case_contracts(report: dict) -> list[dict]:
    contracts = []
    for benchmark_case in report["cases"]:
        phases = []
        for phase in benchmark_case["phases"]:
            measurement = phase.get("measurement")
            phases.append(
                {
                    "phase": phase["phase"],
                    "applicability": phase["applicability"],
                    "reason": phase.get("reason"),
                    "notes": measurement.get("notes")
                    if isinstance(measurement, dict)
                    else None,
                }
            )
        contracts.append(
            {
                "identifier": benchmark_case["identifier"],
                "purpose": benchmark_case["purpose"],
                "sql": benchmark_case["sql"],
                "parameters": benchmark_case["parameters"],
                "queryPlan": benchmark_case["queryPlan"],
                "expectedResultRowCount": benchmark_case.get(
                    "expectedResultRowCount"
                ),
                "expectedAffectedRowCount": benchmark_case.get(
                    "expectedAffectedRowCount"
                ),
                "phases": phases,
            }
        )
    return contracts


def compatibility_key(report: dict) -> tuple:
    def canonical(value: object) -> str:
        return json.dumps(value, sort_keys=True, separators=(",", ":"))

    return (
        report["formatVersion"],
        report["monotonicClock"],
        report["sampleUnit"],
        canonical(report["configuration"]),
        canonical(report["environment"]),
        canonical(report["database"]),
        canonical(report["fixture"]),
        canonical(report["schemaSQL"]),
        canonical(case_contracts(report)),
    )


def format_ns(value: float) -> str:
    return f"{value:,.0f}"


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Compare issue #188 codec and existing benchmark workloads."
    )
    parser.add_argument("reports", nargs="+", type=Path)
    arguments = parser.parse_args()

    reports = [(path, load_report(path)) for path in arguments.reports]
    if len(reports) < 3:
        raise ValueError("expected at least three independent benchmark reports")
    timestamps = [report.get("generatedAt") for _, report in reports]
    if (
        any(not isinstance(timestamp, str) or not timestamp for timestamp in timestamps)
        or len(set(timestamps)) != len(timestamps)
    ):
        raise ValueError("reports must have distinct generated-at timestamps")
    for path, report in reports:
        if report["environment"]["buildConfiguration"] != "release":
            raise ValueError(f"{path}: benchmark report is not a release build")
        if report["environment"]["repositoryState"] != "clean":
            raise ValueError(f"{path}: benchmark report is not from a clean repository")
        if report["configuration"] != {"warmupCount": 50, "sampleCount": 500}:
            raise ValueError(
                f"{path}: benchmark report does not use the standard 50/500 configuration"
            )
    compatibility = {compatibility_key(report) for _, report in reports}
    if len(compatibility) != 1:
        raise ValueError(
            "reports mix revisions, repository states, builds, toolchains, "
            "dependencies, SQLite sources, sample configurations, or case contracts"
        )

    rows = []
    for path, report in reports:
        contextual = case(report, "contextual_value_codec")
        simple = case(report, "simple_parameterized_lookup")
        wide_decode = case(report, "deterministic_row_decode")
        contextual_binding = phase_median(
            report, contextual, "statement_reset_and_binding"
        )
        simple_binding = phase_median(report, simple, "statement_reset_and_binding")
        contextual_decoding = phase_median(report, contextual, "row_decoding")
        wide_decoding = phase_median(report, wide_decode, "row_decoding")
        if (
            min(
                contextual_binding,
                simple_binding,
                contextual_decoding,
                wide_decoding,
            )
            <= 0
        ):
            raise ValueError(f"{path}: compared phase medians must be positive")
        rows.append(
            (
                path.name,
                contextual_binding,
                simple_binding,
                contextual_binding / simple_binding,
                contextual_decoding,
                wide_decoding,
                contextual_decoding / wide_decoding,
            )
        )

    print(
        "| Run | Resolved codec + bind ns | Simple bind ns | Bind ratio | "
        "Contextual scalar decode ns | Wide two-row decode ns | Decode ratio |"
    )
    print("| --- | ---: | ---: | ---: | ---: | ---: | ---: |")
    for row in rows:
        print(
            f"| {row[0]} | {format_ns(row[1])} | {format_ns(row[2])} | "
            f"{row[3]:.3f}x | {format_ns(row[4])} | {format_ns(row[5])} | "
            f"{row[6]:.3f}x |"
        )

    if len(rows) > 1:
        print(
            "\nMedian of per-run ratios: "
            f"bind {statistics.median(row[3] for row in rows):.3f}x; "
            f"decode {statistics.median(row[6] for row in rows):.3f}x."
        )
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (KeyError, OSError, TypeError, ValueError, json.JSONDecodeError) as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)
