from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("run.py")
SPEC = importlib.util.spec_from_file_location("comparison_run", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
comparison_run = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = comparison_run
SPEC.loader.exec_module(comparison_run)


class FixtureTests(unittest.TestCase):
    def test_committed_fixture_round_trips_and_verifies(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            database = Path(directory) / "northwind-performance.sqlite"
            comparison_run.decompress_and_verify_fixture(database)
            self.assertEqual(
                comparison_run.sha256_file(database),
                comparison_run.FIXTURE_DATABASE_SHA256,
            )


class ScheduleTests(unittest.TestCase):
    def test_schedule_is_complete_rotated_and_graph_paired(self) -> None:
        entries = comparison_run.schedule()
        self.assertEqual(len(entries), 42)

        for process in range(1, 4):
            process_entries = [entry for entry in entries if entry[0] == process]
            self.assertEqual(len(process_entries), 14)
            graph_ids = [entry[1].identifier for entry in process_entries]
            expected_pair = (
                ["swiftql_grdb6", "sqlitedata_grdb7"]
                if process % 2 == 1
                else ["sqlitedata_grdb7", "swiftql_grdb6"]
            )
            self.assertEqual(graph_ids, expected_pair * 7)

            control_ids = [
                process_entries[index][2]
                for index in range(0, 12, 2)
            ]
            self.assertEqual(
                control_ids,
                list(
                    comparison_run.rotated(
                        comparison_run.COMMON_IMPLEMENTATIONS,
                        process - 1,
                    )
                ),
            )
            self.assertEqual(
                {process_entries[12][2], process_entries[13][2]},
                {"swiftql", "sqlite_data"},
            )


class SampleParsingTests(unittest.TestCase):
    def valid_output(self) -> bytes:
        return "".join(
            f"SAMPLE\tswiftql\t2\t{index}\t{index + 100}\n"
            for index in range(1, 101)
        ).encode()

    def test_parse_samples_accepts_exact_machine_output(self) -> None:
        samples = comparison_run.parse_samples(
            self.valid_output(),
            implementation="swiftql",
            process=2,
        )
        self.assertEqual(samples[0], 101)
        self.assertEqual(samples[-1], 200)

    def test_parse_samples_rejects_missing_sample(self) -> None:
        with self.assertRaisesRegex(comparison_run.HarnessError, "expected 100"):
            comparison_run.parse_samples(
                self.valid_output().splitlines(keepends=True)[0],
                implementation="swiftql",
                process=2,
            )

    def test_parse_samples_rejects_unexpected_stdout(self) -> None:
        with self.assertRaisesRegex(comparison_run.HarnessError, "unexpected"):
            comparison_run.parse_samples(
                b"diagnostic text\n",
                implementation="swiftql",
                process=2,
            )

    def test_parse_samples_rejects_wrong_process(self) -> None:
        with self.assertRaisesRegex(comparison_run.HarnessError, "process mismatch"):
            comparison_run.parse_samples(
                self.valid_output(),
                implementation="swiftql",
                process=1,
            )

    def test_parse_peak_rss(self) -> None:
        self.assertEqual(
            comparison_run.parse_macos_peak_rss(
                b"  123456  maximum resident set size\n"
            ),
            123456,
        )

    def test_parse_peak_rss_rejects_ambiguous_output(self) -> None:
        with self.assertRaises(comparison_run.HarnessError):
            comparison_run.parse_macos_peak_rss(b"")


class ResolutionTests(unittest.TestCase):
    def test_resolution_requires_exact_versions_and_full_revisions(self) -> None:
        document = {
            "version": 2,
            "pins": [
                {
                    "identity": "example",
                    "kind": "remoteSourceControl",
                    "location": "https://example.com/example.git",
                    "state": {
                        "revision": "a" * 40,
                        "version": "1.2.3",
                    },
                }
            ],
        }
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Package.resolved"
            path.write_text(json.dumps(document), encoding="utf-8")
            self.assertEqual(
                comparison_run.resolved_dependencies(path),
                {
                    "example": {
                        "version": "1.2.3",
                        "revision": "a" * 40,
                    }
                },
            )

            document["pins"][0]["state"]["revision"] = "short"
            path.write_text(json.dumps(document), encoding="utf-8")
            with self.assertRaises(comparison_run.HarnessError):
                comparison_run.resolved_dependencies(path)


class StatisticsTests(unittest.TestCase):
    def make_run(self, process: int, value: int, peak: int = 10) -> dict[str, object]:
        return {
            "process": process,
            "samplesNanoseconds": [value] * 100,
            "peakRSS": {"bytes": peak},
        }

    def test_statistics_weight_independent_processes_equally(self) -> None:
        result = comparison_run.implementation_statistics(
            [
                self.make_run(1, 100),
                self.make_run(2, 200),
                self.make_run(3, 400),
            ]
        )
        self.assertEqual(result["medianNanoseconds"], 200)
        self.assertEqual(result["p95Nanoseconds"], 200)
        self.assertEqual(result["processMedianMinNanoseconds"], 100)
        self.assertEqual(result["processMedianMaxNanoseconds"], 400)
        self.assertEqual(result["processSpreadPercent"], 150.0)
        self.assertEqual(result["peakRSSBytes"], 10)

    def test_nearest_rank_p95(self) -> None:
        self.assertEqual(comparison_run.nearest_rank_p95(range(1, 101)), 95)

    def test_control_drift_is_symmetric_and_guarded(self) -> None:
        def graph(identifier: str, unique: str, common_value: int) -> dict[str, object]:
            implementations = list(comparison_run.COMMON_IMPLEMENTATIONS) + [unique]
            runs: list[dict[str, object]] = []
            for implementation in implementations:
                value = common_value if implementation in comparison_run.COMMON_IMPLEMENTATIONS else 200
                for process in range(1, 4):
                    run = self.make_run(process, value)
                    run["implementation"] = implementation
                    runs.append(run)
            return {
                "identifier": identifier,
                "implementations": implementations,
                "runs": runs,
            }

        result = comparison_run.build_results(
            [
                graph("swiftql_grdb6", "swiftql", 100),
                graph("sqlitedata_grdb7", "sqlite_data", 104),
            ]
        )
        self.assertAlmostEqual(
            result["controlDriftPercent"]["generated_raw_sqlite"],
            100 * 4 / 102,
        )

        with self.assertRaisesRegex(comparison_run.HarnessError, "diverged"):
            comparison_run.build_results(
                [
                    graph("swiftql_grdb6", "swiftql", 100),
                    graph("sqlitedata_grdb7", "sqlite_data", 110),
                ]
            )


if __name__ == "__main__":
    unittest.main()
