from __future__ import annotations

import argparse
import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("run.py")
SPEC = importlib.util.spec_from_file_location("compile_time_run", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
compile_time_run = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = compile_time_run
SPEC.loader.exec_module(compile_time_run)


class ConsumerSpecTests(unittest.TestCase):
    def test_every_consumer_template_exists_and_is_complete(self) -> None:
        for spec in compile_time_run.CONSUMER_SPECS:
            template = (
                compile_time_run.CONSUMER_TEMPLATE_DIRECTORY / spec.template_name
            )
            self.assertTrue(template.is_dir(), f"missing template: {template}")
            manifest = template / "Package.swift"
            self.assertTrue(manifest.is_file(), f"missing manifest: {manifest}")
            text = manifest.read_text(encoding="utf-8")
            expected = 1 if spec.requires_swiftql_checkout else 0
            self.assertEqual(
                text.count("__SWIFTQL_CHECKOUT__"),
                expected,
                f"{manifest} has the wrong placeholder count",
            )
            self.assertIn(f'name: "{compile_time_run.PRODUCT_NAME}"', text)
            self.assertIn(f'name: "{compile_time_run.TARGET_NAME}"', text)

    def test_only_swiftql_depends_on_the_measured_checkout(self) -> None:
        requiring = [
            spec.identifier
            for spec in compile_time_run.CONSUMER_SPECS
            if spec.requires_swiftql_checkout
        ]
        self.assertEqual(requiring, ["swiftql"])

    def test_pinned_resolutions_are_exact(self) -> None:
        for spec in compile_time_run.CONSUMER_SPECS:
            resolved = (
                compile_time_run.CONSUMER_TEMPLATE_DIRECTORY
                / spec.template_name
                / "Package.resolved"
            )
            if not resolved.is_file():
                continue
            dependencies = compile_time_run.resolved_dependencies(resolved)
            self.assertTrue(dependencies, f"{resolved} pins nothing")
            for identity, pin in dependencies.items():
                self.assertRegex(pin["revision"], r"^[0-9a-f]{40}$", identity)

    def test_query_axis_and_build_modes_agree(self) -> None:
        for spec in compile_time_run.CONSUMER_SPECS:
            if spec.scales_query_declarations:
                self.assertIn("one_query_edit", spec.build_modes)
                self.assertEqual(spec.query_axis_status, "applicable")
            else:
                self.assertNotIn("one_query_edit", spec.build_modes)
                self.assertEqual(spec.query_axis_status, "not_applicable")


class MatrixTests(unittest.TestCase):
    def test_axes_scale_independently_around_one_shared_baseline(self) -> None:
        points = compile_time_run.matrix_points((1, 10, 100, 500), (1, 10, 100, 500))
        self.assertEqual(
            points,
            [(1, 1), (10, 1), (100, 1), (500, 1), (1, 10), (1, 100), (1, 500)],
        )
        for tables, queries in points:
            self.assertTrue(
                tables == compile_time_run.BASELINE_TABLE_COUNT
                or queries == compile_time_run.BASELINE_QUERY_COUNT,
                "a point varies both axes at once",
            )

    def test_a_consumer_without_a_query_axis_only_gets_table_points(self) -> None:
        spec = compile_time_run.CONSUMERS_BY_IDENTIFIER["lighter"]
        points = compile_time_run.consumer_points(spec, (1, 10, 100), (1, 10, 100))
        self.assertEqual(points, [(1, 1), (10, 1), (100, 1)])

    def test_scale_parsing_rejects_bad_input(self) -> None:
        self.assertEqual(compile_time_run.parse_scale_list("100,1,10"), (1, 10, 100))
        for value in ("", "0", "-1", "1,1", "ten"):
            with self.assertRaises(argparse.ArgumentTypeError):
                compile_time_run.parse_scale_list(value)

    def test_consumer_parsing_rejects_unknown_and_duplicate_names(self) -> None:
        self.assertEqual(compile_time_run.parse_consumer_list("swiftql"), ("swiftql",))
        for value in ("", "nope", "swiftql,swiftql"):
            with self.assertRaises(argparse.ArgumentTypeError):
                compile_time_run.parse_consumer_list(value)


class GenerationTests(unittest.TestCase):
    def test_generation_is_deterministic(self) -> None:
        for spec in compile_time_run.CONSUMER_SPECS:
            first = compile_time_run.generate_sources(spec, 7, 3, "base")
            second = compile_time_run.generate_sources(spec, 7, 3, "base")
            self.assertEqual(first, second, spec.identifier)

    def test_declaration_counts_match_the_requested_scale(self) -> None:
        for spec in compile_time_run.CONSUMER_SPECS:
            sources = compile_time_run.generate_sources(spec, 12, 5, "base")
            joined = "\n".join(sources.values())
            for index in range(1, 13):
                self.assertIn(
                    compile_time_run.table_name(index),
                    joined,
                    f"{spec.identifier} is missing table {index}",
                )
            self.assertNotIn(compile_time_run.table_name(13), joined)
            if not spec.scales_query_declarations:
                continue
            for index in range(1, 6):
                self.assertIn(
                    f"{compile_time_run.query_name(index)}(",
                    joined,
                    f"{spec.identifier} is missing query {index}",
                )
            self.assertNotIn(f"{compile_time_run.query_name(6)}(", joined)

    def test_every_consumer_declares_the_same_column_shape(self) -> None:
        for spec in compile_time_run.CONSUMER_SPECS:
            if spec.generator == "lighter":
                sources = compile_time_run.generate_sources(spec, 2, 1, "base")
                schema = sources["Sources/Consumer/schema.sql"]
                for _, column, _ in compile_time_run.COLUMNS:
                    self.assertIn(column, schema)
                continue
            sources = compile_time_run.generate_sources(spec, 2, 1, "base")
            joined = "\n".join(sources.values())
            for swift, _, _ in compile_time_run.COLUMNS:
                self.assertIn(swift, joined, f"{spec.identifier} lacks {swift}")

    def test_the_edit_token_only_changes_the_first_query(self) -> None:
        for spec in compile_time_run.CONSUMER_SPECS:
            if not spec.scales_query_declarations:
                continue
            base = compile_time_run.generate_sources(spec, 1, 4, "base")
            edited = compile_time_run.generate_sources(spec, 1, 4, "edit1")
            self.assertNotEqual(base, edited, spec.identifier)
            self.assertEqual(
                base["Sources/Consumer/Tables.swift"],
                edited["Sources/Consumer/Tables.swift"],
                f"{spec.identifier} changed a table declaration for a query edit",
            )
            base_queries = base["Sources/Consumer/Queries.swift"]
            edited_queries = edited["Sources/Consumer/Queries.swift"]
            self.assertEqual(
                len(base_queries.splitlines()),
                len(edited_queries.splitlines()),
                f"{spec.identifier} changed the query file's shape",
            )
            differing = [
                index
                for index, (left, right) in enumerate(
                    zip(base_queries.splitlines(), edited_queries.splitlines())
                )
                if left != right
            ]
            self.assertEqual(
                len(differing),
                1,
                f"{spec.identifier} changed more than one line for a query edit",
            )

    def test_queries_spread_deterministically_across_declared_tables(self) -> None:
        self.assertEqual(compile_time_run.query_table_index(1, 3), 1)
        self.assertEqual(compile_time_run.query_table_index(4, 3), 1)
        self.assertEqual(compile_time_run.query_table_index(5, 3), 2)
        self.assertEqual(compile_time_run.query_table_index(7, 1), 1)

    def test_generation_rejects_nonpositive_scales(self) -> None:
        spec = compile_time_run.CONSUMERS_BY_IDENTIFIER["swiftql"]
        with self.assertRaises(compile_time_run.HarnessError):
            compile_time_run.generate_sources(spec, 0, 1, "base")
        with self.assertRaises(compile_time_run.HarnessError):
            compile_time_run.generate_sources(spec, 1, 0, "base")

    def test_generated_source_bytes_grow_with_scale(self) -> None:
        spec = compile_time_run.CONSUMERS_BY_IDENTIFIER["swiftql"]
        small = compile_time_run.generated_source_bytes(spec, 1, 1)
        larger = compile_time_run.generated_source_bytes(spec, 10, 1)
        self.assertGreater(larger, small)

    def test_write_generated_sources_hashes_every_file(self) -> None:
        spec = compile_time_run.CONSUMERS_BY_IDENTIFIER["grdb"]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            digests, written = compile_time_run.write_generated_sources(
                root,
                spec,
                3,
                2,
                "base",
            )
            expected = {
                "Sources/Consumer/Tables.swift",
                "Sources/Consumer/Queries.swift",
            }
            self.assertEqual(set(digests), expected)
            self.assertEqual(set(written), expected)
            for relative, digest in digests.items():
                path = root / relative
                self.assertTrue(path.is_file())
                self.assertEqual(
                    compile_time_run.sha256_text(path.read_text(encoding="utf-8")),
                    digest,
                )

    def test_an_unchanged_file_is_left_alone_unless_a_rewrite_is_forced(self) -> None:
        """A one-line query edit must not restamp the table declarations."""

        for spec in compile_time_run.CONSUMER_SPECS:
            if not spec.scales_query_declarations:
                continue
            with tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                compile_time_run.write_generated_sources(root, spec, 4, 2, "base")
                _, written = compile_time_run.write_generated_sources(
                    root,
                    spec,
                    4,
                    2,
                    "edit1",
                )
                self.assertEqual(
                    written,
                    ["Sources/Consumer/Queries.swift"],
                    f"{spec.identifier} rewrote more than the query file",
                )
                _, unchanged = compile_time_run.write_generated_sources(
                    root,
                    spec,
                    4,
                    2,
                    "edit1",
                )
                self.assertEqual(unchanged, [], spec.identifier)
                _, forced = compile_time_run.write_generated_sources(
                    root,
                    spec,
                    4,
                    2,
                    "edit1",
                    rewrite_unchanged=True,
                )
                self.assertEqual(
                    set(forced),
                    {
                        "Sources/Consumer/Tables.swift",
                        "Sources/Consumer/Queries.swift",
                    },
                    spec.identifier,
                )


class ParsingTests(unittest.TestCase):
    SAMPLE = (
        "Building for debugging...\n"
        "[1/2] Compiling Consumer Tables.swift\n"
        "Build complete!\n"
        "        3.20 real         9.60 user         1.10 sys\n"
        "          123456789  maximum resident set size\n"
    )

    def test_time_and_rss_parsing(self) -> None:
        self.assertEqual(
            compile_time_run.parse_time_output(self.SAMPLE),
            (3.20, 9.60, 1.10),
        )
        self.assertEqual(compile_time_run.parse_peak_rss(self.SAMPLE), 123456789)

    def test_parsing_rejects_missing_or_duplicated_lines(self) -> None:
        with self.assertRaises(compile_time_run.HarnessError):
            compile_time_run.parse_time_output("Build complete!\n")
        with self.assertRaises(compile_time_run.HarnessError):
            compile_time_run.parse_time_output(self.SAMPLE + self.SAMPLE)
        with self.assertRaises(compile_time_run.HarnessError):
            compile_time_run.parse_peak_rss("Build complete!\n")
        with self.assertRaises(compile_time_run.HarnessError):
            compile_time_run.parse_peak_rss(
                "          0  maximum resident set size\n"
            )

    def test_recompile_marker_distinguishes_a_no_op_build(self) -> None:
        self.assertIsNotNone(compile_time_run.RECOMPILE_MARKER.search(self.SAMPLE))
        self.assertIsNone(
            compile_time_run.RECOMPILE_MARKER.search(
                "Building for debugging...\nBuild complete! (0.31s)\n"
            )
        )


class StatisticsTests(unittest.TestCase):
    @staticmethod
    def measurement(wall: float, peak: int | None = 1024) -> dict[str, object]:
        return {
            "wallSeconds": wall,
            "userSeconds": wall * 2,
            "systemSeconds": wall / 2,
            "peakRSSBytes": peak,
        }

    def test_summary_uses_medians_and_a_median_relative_spread(self) -> None:
        summary = compile_time_run.summarize_measurements(
            [self.measurement(1.0), self.measurement(2.0), self.measurement(4.0)]
        )
        self.assertEqual(summary["repetitionCount"], 3)
        self.assertEqual(summary["medianWallSeconds"], 2.0)
        self.assertEqual(summary["minWallSeconds"], 1.0)
        self.assertEqual(summary["maxWallSeconds"], 4.0)
        self.assertAlmostEqual(summary["wallSpreadPercent"], 150.0)
        self.assertEqual(summary["maxPeakRSSBytes"], 1024)

    def test_a_partially_unavailable_peak_rss_is_not_reported(self) -> None:
        summary = compile_time_run.summarize_measurements(
            [self.measurement(1.0), self.measurement(1.0, peak=None)]
        )
        self.assertIsNone(summary["maxPeakRSSBytes"])


if __name__ == "__main__":
    unittest.main()
