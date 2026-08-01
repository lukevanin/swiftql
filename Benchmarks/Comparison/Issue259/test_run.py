from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path


def _load(name: str, filename: str):
    path = Path(__file__).with_name(filename)
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


issue259_run = _load("issue259_run", "run.py")
issue259_summarize = _load("issue259_summarize", "summarize.py")


class ContractTests(unittest.TestCase):
    def test_every_workload_states_a_falsifiable_contract(self) -> None:
        for workload in issue259_run.WORKLOADS:
            self.assertTrue(workload.contract.strip(), workload.identifier)
            self.assertGreaterEqual(workload.operations_per_iteration, 1)
            self.assertTrue(workload.unit)

    def test_every_workload_declares_a_tier_for_every_implementation(self) -> None:
        for workload in issue259_run.WORKLOADS:
            self.assertEqual(
                sorted(workload.tiers),
                sorted(issue259_run.IMPLEMENTATIONS),
                workload.identifier,
            )
            for implementation, tier in workload.tiers.items():
                self.assertTrue(tier, f"{workload.identifier}/{implementation}")

    def test_the_three_prototyped_families_are_present(self) -> None:
        self.assertEqual(
            sorted(workload.identifier for workload in issue259_run.WORKLOADS),
            ["join_aggregate", "point_lookup", "transactional_write"],
        )

    def test_only_the_write_workload_needs_a_writable_database(self) -> None:
        writable = [
            workload.identifier
            for workload in issue259_run.WORKLOADS
            if workload.writable
        ]
        self.assertEqual(writable, ["transactional_write"])

    def test_the_prototype_reuses_the_committed_250_fixture(self) -> None:
        """The prototype must measure the same bytes the baseline measured."""

        self.assertTrue(issue259_run.comparison_run.FIXTURE_ARCHIVE.is_file())
        self.assertEqual(issue259_run.comparison_run.ROW_COUNT, 16_143)

    def test_the_prototype_graph_is_separate_from_the_250_graphs(self) -> None:
        template = issue259_run.PROTOTYPE_TEMPLATE
        self.assertTrue((template / "Package.swift").is_file())
        self.assertNotIn(
            template.resolve(),
            [
                (issue259_run.COMPARISON_DIRECTORY / "Graphs" / name).resolve()
                for name in ("SwiftQLGRDB6", "SQLiteDataGRDB7")
            ],
        )
        manifest = (template / "Package.swift").read_text(encoding="utf-8")
        self.assertEqual(manifest.count("__SWIFTQL_CHECKOUT__"), 1)


class ScheduleTests(unittest.TestCase):
    def test_implementation_order_rotates_per_process(self) -> None:
        entries = issue259_run.schedule(
            issue259_run.WORKLOADS,
            issue259_run.IMPLEMENTATIONS,
            3,
        )
        expected = len(issue259_run.WORKLOADS) * len(issue259_run.IMPLEMENTATIONS) * 3
        self.assertEqual(len(entries), expected)

        for process in (1, 2, 3):
            first_workload = issue259_run.WORKLOADS[0]
            order = [
                implementation
                for entry_process, workload, implementation in entries
                if entry_process == process and workload is first_workload
            ]
            self.assertEqual(
                order,
                list(
                    issue259_run.rotated(
                        issue259_run.IMPLEMENTATIONS,
                        process - 1,
                    )
                ),
            )

    def test_every_cell_is_scheduled_exactly_once_per_process(self) -> None:
        entries = issue259_run.schedule(
            issue259_run.WORKLOADS,
            issue259_run.IMPLEMENTATIONS,
            3,
        )
        seen = [
            (process, workload.identifier, implementation)
            for process, workload, implementation in entries
        ]
        self.assertEqual(len(seen), len(set(seen)))


class SampleParsingTests(unittest.TestCase):
    @staticmethod
    def stdout(count: int, *, workload: str = "point_lookup") -> bytes:
        lines = [
            f"SAMPLE\t{workload}\tswiftql\t1\t{index}\t{100 + index}"
            for index in range(1, count + 1)
        ]
        return ("\n".join(lines) + "\n").encode("utf-8")

    def test_parses_a_complete_run(self) -> None:
        samples = issue259_run.parse_samples(
            self.stdout(issue259_run.SAMPLE_COUNT),
            workload="point_lookup",
            implementation="swiftql",
            process=1,
        )
        self.assertEqual(len(samples), issue259_run.SAMPLE_COUNT)
        self.assertEqual(samples[0], 101)

    def test_rejects_a_short_run(self) -> None:
        with self.assertRaises(issue259_run.HarnessError):
            issue259_run.parse_samples(
                self.stdout(5),
                workload="point_lookup",
                implementation="swiftql",
                process=1,
            )

    def test_rejects_a_workload_mismatch(self) -> None:
        with self.assertRaises(issue259_run.HarnessError):
            issue259_run.parse_samples(
                self.stdout(issue259_run.SAMPLE_COUNT, workload="join_aggregate"),
                workload="point_lookup",
                implementation="swiftql",
                process=1,
            )

    def test_rejects_a_nonpositive_sample(self) -> None:
        bad = b"SAMPLE\tpoint_lookup\tswiftql\t1\t1\t0\n"
        with self.assertRaises(issue259_run.HarnessError):
            issue259_run.parse_samples(
                bad,
                workload="point_lookup",
                implementation="swiftql",
                process=1,
            )


class StatisticsTests(unittest.TestCase):
    @staticmethod
    def run_document(process: int, samples: list[int]) -> dict[str, object]:
        return {
            "process": process,
            "samplesNanoseconds": samples,
            "peakRSS": {"bytes": 1_000 * process},
        }

    def test_headline_is_the_median_of_process_medians(self) -> None:
        workload = issue259_run.WORKLOADS_BY_IDENTIFIER["point_lookup"]
        summary = issue259_run.summarize(
            [
                self.run_document(1, [10, 10, 10]),
                self.run_document(2, [20, 20, 20]),
                self.run_document(3, [30, 30, 30]),
            ],
            workload,
        )
        self.assertEqual(summary["medianNanoseconds"], 20)
        self.assertEqual(summary["processMedianMinNanoseconds"], 10)
        self.assertEqual(summary["processMedianMaxNanoseconds"], 30)
        self.assertAlmostEqual(summary["processSpreadPercent"], 100.0)
        self.assertEqual(summary["peakRSSBytes"], 3_000)

    def test_operations_per_second_uses_the_workloads_own_batch_size(self) -> None:
        write = issue259_run.WORKLOADS_BY_IDENTIFIER["transactional_write"]
        summary = issue259_run.summarize([self.run_document(1, [1_000_000])], write)
        self.assertAlmostEqual(
            summary["operationsPerSecond"],
            issue259_run.WRITE_BATCH_SIZE * 1_000.0,
        )

    def test_nearest_rank_p95_matches_the_summarizer(self) -> None:
        values = list(range(1, 101))
        self.assertEqual(issue259_run.nearest_rank_p95(values), 95)
        self.assertEqual(
            issue259_summarize.nearest_rank_p95(values),
            issue259_run.nearest_rank_p95(values),
        )


if __name__ == "__main__":
    unittest.main()
