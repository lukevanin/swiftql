from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path


def _load(name: str, filename: str):
    path = Path(__file__).with_name(filename)
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise ImportError(f"could not load {name} from {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


paired = _load("issue353_paired", "paired.py")


class ProcessIdentifierTests(unittest.TestCase):

    def test_first_three_pairs_use_their_own_identifier(self) -> None:
        self.assertEqual(
            [paired.process_id(pair) for pair in (1, 2, 3)],
            [1, 2, 3],
        )

    def test_later_pairs_reuse_the_three_accepted_identifiers(self) -> None:
        self.assertEqual(
            [paired.process_id(pair) for pair in (4, 5, 6, 7)],
            [1, 2, 3, 1],
        )

    def test_a_pair_index_below_one_is_rejected(self) -> None:
        with self.assertRaises(ValueError):
            paired.process_id(0)


class PairScheduleTests(unittest.TestCase):

    def test_both_arms_of_a_pair_run_next_to_each_other(self) -> None:
        for pair, arms in self._by_pair(paired.pair_schedule(4)).items():
            self.assertEqual(sorted(arms), ["baseline", "candidate"], pair)

    def test_the_leading_arm_alternates_between_pairs(self) -> None:
        leading = [
            arm for index, (_, arm) in enumerate(paired.pair_schedule(6))
            if index % 2 == 0
        ]
        self.assertEqual(
            leading,
            ["baseline", "candidate", "baseline", "candidate", "baseline", "candidate"],
        )

    def test_each_arm_runs_once_per_pair(self) -> None:
        schedule = paired.pair_schedule(5)
        self.assertEqual(len(schedule), 10)
        for arm in ("baseline", "candidate"):
            self.assertEqual(sum(1 for _, entry in schedule if entry == arm), 5)

    def test_a_pair_count_below_one_is_rejected(self) -> None:
        with self.assertRaises(ValueError):
            paired.pair_schedule(0)

    @staticmethod
    def _by_pair(schedule):
        grouped: dict[int, list[str]] = {}
        for pair, arm in schedule:
            grouped.setdefault(pair, []).append(arm)
        return grouped


class PercentageChangeTests(unittest.TestCase):

    def test_a_faster_candidate_reports_a_negative_change(self) -> None:
        self.assertAlmostEqual(paired.percentage_change(100.0, 60.0), -40.0)

    def test_a_slower_candidate_reports_a_positive_change(self) -> None:
        self.assertAlmostEqual(paired.percentage_change(100.0, 101.61), 1.61)

    def test_an_unchanged_candidate_reports_zero(self) -> None:
        self.assertAlmostEqual(paired.percentage_change(72.38, 72.38), 0.0)

    def test_a_non_positive_baseline_is_rejected(self) -> None:
        with self.assertRaises(ValueError):
            paired.percentage_change(0.0, 1.0)


if __name__ == "__main__":
    unittest.main()
