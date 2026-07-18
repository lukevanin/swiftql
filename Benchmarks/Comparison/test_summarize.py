#!/usr/bin/env python3
"""Tests for the independently authored format-v3 report validator."""

from __future__ import annotations

import copy
import gzip
import hashlib
import json
import sqlite3
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path


sys.path.insert(0, str(Path(__file__).parent))

import summarize  # noqa: E402


REVISION_1 = "1" * 40
REVISION_2 = "2" * 40
BASE_LATENCIES = {
    "sqlite_data": 800_000,
    "generated_raw_sqlite": 1_000_000,
    "lighter": 1_200_000,
    "grdb_manual": 2_600_000,
    "sqlite_swift_manual": 3_600_000,
    "swiftql": 4_400_000,
    "sqlite_swift_typed": 6_100_000,
    "grdb_codable": 7_000_000,
}


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def graph(report: dict, identifier: str) -> dict:
    return next(item for item in report["graphs"] if item["identifier"] == identifier)


def find_run(
    report: dict, identifier: str, implementation: str, process: int
) -> dict:
    return next(
        run
        for run in graph(report, identifier)["runs"]
        if run["implementation"] == implementation and run["process"] == process
    )


class V3ReportTests(unittest.TestCase):
    fixture_database: bytes
    fixture_archive: bytes
    license_text = b"The MIT License\nCopyright test fixture\n"

    @classmethod
    def setUpClass(cls) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            database_path = Path(temporary) / "fixture.sqlite"
            connection = sqlite3.connect(database_path)
            columns = ["OrderID INTEGER PRIMARY KEY"] + [
                f'"{name}" TEXT' for name in summarize.EXPECTED_ORDER_COLUMNS[1:]
            ]
            connection.execute(f'CREATE TABLE "Orders" ({", ".join(columns)})')
            connection.executemany(
                'INSERT INTO "Orders" ("OrderID") VALUES (?)',
                ((row_id,) for row_id in range(1, 16_144)),
            )
            connection.commit()
            connection.close()
            cls.fixture_database = database_path.read_bytes()
        cls.fixture_archive = gzip.compress(cls.fixture_database, mtime=0)

    def build_report(
        self,
        directory: Path,
        *,
        name: str = "report",
        swiftql_revision: str = REVISION_2,
        swiftql_multiplier: float = 1.0,
        data_graph_multiplier: float = 1.01,
        rss_available: bool = True,
    ) -> tuple[dict, Path]:
        fixtures = directory / "Fixtures"
        runs_directory = directory / "Runs"
        fixtures.mkdir(parents=True)
        runs_directory.mkdir()
        artifact = fixtures / "northwind-performance.sqlite.gz"
        license_path = fixtures / "Northwind-LICENSE.txt"
        artifact.write_bytes(self.fixture_archive)
        license_path.write_bytes(self.license_text)

        report: dict = {
            "formatVersion": 3,
            "generatedAt": "pending",
            "durationUnit": "nanoseconds_per_fetch",
            "workload": dict(summarize.EXPECTED_WORKLOAD),
            "environment": {
                "model": "TestMac1,1",
                "processor": "Test CPU",
                "coreCount": 8,
                "memoryBytes": 16 * 1024 * 1024 * 1024,
                "architecture": "arm64",
                "operatingSystem": "macOS test",
                "xcode": "Xcode test",
                "swift": "Swift test",
                "sqlite": "SQLite test",
            },
            "provenance": {
                "workloadReference": {
                    "repository": "https://github.com/Lighter-swift/PerformanceTestSuite",
                    "revision": REVISION_1,
                    "licenseStatus": "absent_at_revision",
                    "usage": "workload_reference_only",
                    "codeCopied": False,
                    "artifactsCopied": False,
                },
                "harness": "independently_implemented",
            },
            "fixture": {
                "artifact": "Fixtures/northwind-performance.sqlite.gz",
                "artifactSHA256": sha256(self.fixture_archive),
                "databaseSHA256": sha256(self.fixture_database),
                "databaseBytes": len(self.fixture_database),
                "pageSize": 4_096,
                "pageCount": len(self.fixture_database) // 4_096,
                "rowCount": 16_143,
                "columnCount": 14,
                "sourceRepository": "https://github.com/jpwhite3/northwind-SQLite3",
                "sourceRevision": "3" * 40,
                "license": {
                    "spdxIdentifier": "MIT",
                    "path": "Fixtures/Northwind-LICENSE.txt",
                    "sha256": sha256(self.license_text),
                },
                "reproducibility": "authoritative_snapshot; test fixture",
            },
            "sources": {
                "swiftqlRevision": swiftql_revision,
                "swiftqlDirty": False,
            },
            "graphs": [
                {
                    "identifier": summarize.SWIFTQL_GRAPH,
                    "implementations": list(
                        summarize.GRAPH_IMPLEMENTATIONS[summarize.SWIFTQL_GRAPH]
                    ),
                    "dependencies": {
                        "SwiftQL": {
                            "version": "source checkout",
                            "revision": swiftql_revision,
                        },
                        "grdb.swift": {"version": "6.29.3", "revision": "4" * 40},
                        "lighter": {"version": "1.4.12", "revision": "5" * 40},
                        "sqlite.swift": {"version": "0.16.0", "revision": "6" * 40},
                        "swift-syntax": {"version": "509.1.1", "revision": "7" * 40},
                    },
                    "runs": [],
                },
                {
                    "identifier": summarize.SQLITEDATA_GRAPH,
                    "implementations": list(
                        summarize.GRAPH_IMPLEMENTATIONS[summarize.SQLITEDATA_GRAPH]
                    ),
                    "dependencies": {
                        "sqlite-data": {"version": "1.7.0", "revision": "8" * 40},
                        "swift-structured-queries": {
                            "version": "0.33.3",
                            "revision": "9" * 40,
                        },
                        "grdb.swift": {"version": "7.11.1", "revision": "a" * 40},
                        "lighter": {"version": "1.4.12", "revision": "5" * 40},
                        "sqlite.swift": {"version": "0.16.0", "revision": "6" * 40},
                    },
                    "runs": [],
                },
            ],
        }
        report["workload"]["postBuildCooldownSeconds"] = 60.0

        first_start = datetime(2026, 7, 18, 12, 0, tzinfo=timezone.utc)
        for schedule_index, (identifier, implementation, process) in enumerate(
            summarize._expected_schedule(), start=1
        ):
            base = BASE_LATENCIES[implementation]
            if identifier == summarize.SQLITEDATA_GRAPH:
                base = int(base * data_graph_multiplier)
            if implementation == "swiftql":
                base = int(base * swiftql_multiplier)
            process_offset = (process - 2) * 10_000
            samples = [
                base + process_offset + sample_index * 100
                for sample_index in range(1, 101)
            ]
            sample_relative = Path("Runs") / f"{name}-{schedule_index:02d}.samples.tsv"
            sample_bytes = "".join(
                f"SAMPLE\t{implementation}\t{process}\t{index}\t{value}\n"
                for index, value in enumerate(samples, start=1)
            ).encode()
            (directory / sample_relative).write_bytes(sample_bytes)

            if rss_available:
                peak_bytes = 50_000_000 + schedule_index * 1_000
                resource_relative = (
                    Path("Runs") / f"{name}-{schedule_index:02d}.resource.log"
                )
                resource_bytes = (
                    f"schedule {schedule_index}\n"
                    f"{peak_bytes}  maximum resident set size\n"
                ).encode()
                (directory / resource_relative).write_bytes(resource_bytes)
                peak_rss = {
                    "scope": "implementation_process",
                    "bytes": peak_bytes,
                    "method": "/usr/bin/time -l",
                    "unavailableReason": None,
                    "rawOutput": resource_relative.as_posix(),
                    "rawOutputSHA256": sha256(resource_bytes),
                }
            else:
                peak_rss = {
                    "scope": "implementation_process",
                    "bytes": None,
                    "method": None,
                    "unavailableReason": "resource tool unavailable on test platform",
                    "rawOutput": None,
                    "rawOutputSHA256": None,
                }

            started = first_start + timedelta(seconds=(schedule_index - 1) * 2)
            finished = started + timedelta(seconds=1)
            run = {
                "implementation": implementation,
                "process": process,
                "scheduleIndex": schedule_index,
                "startedAt": started.isoformat().replace("+00:00", "Z"),
                "finishedAt": finished.isoformat().replace("+00:00", "Z"),
                "rawSamples": sample_relative.as_posix(),
                "rawSamplesSHA256": sha256(sample_bytes),
                "samplesNanoseconds": samples,
                "peakRSS": peak_rss,
            }
            graph(report, identifier)["runs"].append(run)

        final_finish = first_start + timedelta(seconds=83)
        report["generatedAt"] = (final_finish + timedelta(seconds=1)).isoformat().replace(
            "+00:00", "Z"
        )
        report["results"] = summarize.derive_results(report)
        report_path = directory / f"{name}.json"
        report_path.write_text(json.dumps(report), encoding="utf-8")
        return report, report_path

    def rewrite(self, path: Path, report: dict) -> None:
        path.write_text(json.dumps(report), encoding="utf-8")

    def test_valid_report_recomputes_summary_statistics(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            report_data, path = self.build_report(directory)

            report = summarize.load_report(path)
            table = summarize.format_summary(report)

            swiftql = report["results"]["implementations"]["swiftql"]
            self.assertEqual(swiftql["medianNanoseconds"], 4_405_050)
            self.assertEqual(swiftql["p95Nanoseconds"], 4_409_500)
            self.assertAlmostEqual(
                swiftql["processSpreadPercent"], 20_000 / 4_405_050 * 100
            )
            expected_peak = max(
                run["peakRSS"]["bytes"]
                for run in graph(report_data, summarize.SWIFTQL_GRAPH)["runs"]
                if run["implementation"] == "swiftql"
            )
            self.assertEqual(swiftql["peakRSSBytes"], expected_peak)
            self.assertIn("| API path | Median | p95 | Rows/s |", table)
            self.assertIn("| SwiftQL | 4.41 ms | 4.41 ms |", table)
            self.assertIn("MiB", table)

    def test_comparison_allows_only_swiftql_revision_and_measurements_to_change(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            baseline_directory = root / "baseline"
            candidate_directory = root / "candidate"
            baseline_directory.mkdir()
            candidate_directory.mkdir()
            _, baseline_path = self.build_report(
                baseline_directory, name="baseline", swiftql_revision=REVISION_2
            )
            _, candidate_path = self.build_report(
                candidate_directory,
                name="candidate",
                swiftql_revision="b" * 40,
                swiftql_multiplier=0.8,
            )

            comparison = summarize.format_comparison(
                summarize.load_report(baseline_path),
                summarize.load_report(candidate_path),
            )

            self.assertIn("Median latency", comparison)
            self.assertIn("p95 latency", comparison)
            self.assertIn("Median / generated-raw control", comparison)
            self.assertIn("-19.", comparison)

    def test_sample_tsv_must_match_json_exactly(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            report, path = self.build_report(directory)
            run = find_run(report, summarize.SWIFTQL_GRAPH, "swiftql", 1)
            run["samplesNanoseconds"][0] += 1
            self.rewrite(path, report)

            with self.assertRaisesRegex(summarize.ReportError, "does not match report samples"):
                summarize.load_report(path)

    def test_sample_log_ids_and_hashes_are_checked(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            report, path = self.build_report(directory)
            run = find_run(report, summarize.SWIFTQL_GRAPH, "swiftql", 1)
            sample_path = directory / run["rawSamples"]
            lines = sample_path.read_text(encoding="utf-8").splitlines()
            fields = lines[0].split("\t")
            fields[3] = "2"
            lines[0] = "\t".join(fields)
            changed = ("\n".join(lines) + "\n").encode()
            sample_path.write_bytes(changed)
            run["rawSamplesSHA256"] = sha256(changed)
            self.rewrite(path, report)

            with self.assertRaisesRegex(summarize.ReportError, "does not match report samples"):
                summarize.load_report(path)

    def test_duplicate_linked_paths_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            report, path = self.build_report(directory)
            first = find_run(report, summarize.SWIFTQL_GRAPH, "swiftql", 1)
            second = find_run(report, summarize.SWIFTQL_GRAPH, "swiftql", 2)
            second["rawSamples"] = first["rawSamples"]
            second["rawSamplesSHA256"] = first["rawSamplesSHA256"]
            self.rewrite(path, report)

            with self.assertRaisesRegex(summarize.ReportError, "linked path is reused"):
                summarize.load_report(path)

    def test_stored_result_fields_are_recomputed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            report, path = self.build_report(directory)
            report["results"]["implementations"]["swiftql"][
                "p95Nanoseconds"
            ] += 1
            self.rewrite(path, report)

            with self.assertRaisesRegex(summarize.ReportError, "does not match raw samples"):
                summarize.load_report(path)

    def test_exact_workload_and_provenance_are_required(self) -> None:
        mutations = (
            ("row count", lambda report: report["workload"].__setitem__("rowCount", 16_282)),
            (
                "license status",
                lambda report: report["provenance"]["workloadReference"].__setitem__(
                    "licenseStatus", "unknown"
                ),
            ),
            (
                "copied code",
                lambda report: report["provenance"]["workloadReference"].__setitem__(
                    "codeCopied", True
                ),
            ),
        )
        for label, mutate in mutations:
            with self.subTest(label=label), tempfile.TemporaryDirectory() as temporary:
                directory = Path(temporary)
                report, path = self.build_report(directory)
                mutate(report)
                self.rewrite(path, report)
                with self.assertRaises(summarize.ReportError):
                    summarize.load_report(path)

    def test_fixture_artifact_and_license_hashes_are_verified(self) -> None:
        for linked_file in (
            "Fixtures/northwind-performance.sqlite.gz",
            "Fixtures/Northwind-LICENSE.txt",
        ):
            with self.subTest(linked_file=linked_file), tempfile.TemporaryDirectory() as temporary:
                directory = Path(temporary)
                _, path = self.build_report(directory)
                (directory / linked_file).write_bytes(b"tampered")
                with self.assertRaisesRegex(summarize.ReportError, "sha256 does not match"):
                    summarize.load_report(path)

    def test_peak_rss_is_parsed_or_explicitly_unavailable(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            _, path = self.build_report(directory, rss_available=False)
            loaded = summarize.load_report(path)
            self.assertIsNone(
                loaded["results"]["implementations"]["swiftql"]["peakRSSBytes"]
            )
            self.assertIn("unavailable", summarize.format_summary(loaded))

        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            report, path = self.build_report(directory)
            run = find_run(report, summarize.SWIFTQL_GRAPH, "swiftql", 1)
            run["peakRSS"]["bytes"] += 1
            self.rewrite(path, report)
            with self.assertRaisesRegex(summarize.ReportError, "does not match resource output"):
                summarize.load_report(path)

    def test_schedule_indices_order_and_timestamps_are_validated(self) -> None:
        for label, mutate, message in (
            (
                "schedule order",
                lambda report: (
                    find_run(
                        report,
                        summarize.SWIFTQL_GRAPH,
                        summarize.COMMON_IMPLEMENTATIONS[0],
                        1,
                    ).__setitem__("scheduleIndex", 2),
                    find_run(
                        report,
                        summarize.SQLITEDATA_GRAPH,
                        summarize.COMMON_IMPLEMENTATIONS[0],
                        1,
                    ).__setitem__("scheduleIndex", 1),
                ),
                "deterministic interleaving schedule",
            ),
            (
                "overlap",
                lambda report: find_run(
                    report,
                    summarize.SQLITEDATA_GRAPH,
                    summarize.COMMON_IMPLEMENTATIONS[0],
                    1,
                ).__setitem__("startedAt", "2026-07-18T12:00:00.500000Z"),
                "overlap",
            ),
        ):
            with self.subTest(label=label), tempfile.TemporaryDirectory() as temporary:
                directory = Path(temporary)
                report, path = self.build_report(directory)
                mutate(report)
                self.rewrite(path, report)
                with self.assertRaisesRegex(summarize.ReportError, message):
                    summarize.load_report(path)

    def test_dependency_revisions_and_cross_graph_control_drift_are_checked(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            report, path = self.build_report(directory)
            graph(report, summarize.SWIFTQL_GRAPH)["dependencies"]["grdb.swift"][
                "revision"
            ] = "short"
            self.rewrite(path, report)
            with self.assertRaisesRegex(summarize.ReportError, "160-bit"):
                summarize.load_report(path)

        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            _, path = self.build_report(directory, data_graph_multiplier=1.20)
            with self.assertRaisesRegex(summarize.ReportError, "cross-graph drift"):
                summarize.load_report(path)

    def test_comparison_rejects_non_swiftql_input_changes(self) -> None:
        for field in ("environment", "dependency", "fixture"):
            with self.subTest(field=field), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                baseline_directory = root / "baseline"
                candidate_directory = root / "candidate"
                baseline_directory.mkdir()
                candidate_directory.mkdir()
                _, baseline_path = self.build_report(baseline_directory, name="baseline")
                candidate, candidate_path = self.build_report(
                    candidate_directory,
                    name="candidate",
                    swiftql_revision="b" * 40,
                )
                if field == "environment":
                    candidate["environment"]["processor"] = "Different CPU"
                elif field == "dependency":
                    graph(candidate, summarize.SWIFTQL_GRAPH)["dependencies"][
                        "grdb.swift"
                    ]["version"] = "different"
                else:
                    candidate["fixture"]["sourceRevision"] = "c" * 40
                self.rewrite(candidate_path, candidate)
                baseline = summarize.load_report(baseline_path)
                loaded_candidate = summarize.load_report(candidate_path)
                with self.assertRaises(summarize.ReportError):
                    summarize.validate_compatible_reports(baseline, loaded_candidate)


if __name__ == "__main__":
    unittest.main()
