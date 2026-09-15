from __future__ import annotations

import argparse
import contextlib
import importlib.util
import io
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


# Build outputs that both parsers must read the same way (issue #670 review).
SWIFTPM_DURATION_CASES = (
    ("Build of product 'ConsumerLibrary' complete! (9.83s)\n", 9.83),
    ("Build of product 'ConsumerLibrary' complete! (9,83s)\n", 9.83),
    ("Build complete! (43,01 sec)\n", 43.01),
    ("\x1b[1;32mBuild of product 'ConsumerLibrary' complete!\x1b[0m (9.83s)\n", 9.83),
    ("[5/6] Compiling Consumer\rBuild of product 'ConsumerLibrary' complete! (9.83s)\r\n", 9.83),
    (
        "Build of product 'ConsumerLibrary' complete! (9.83s)\n"
        "Build of product 'OtherLibrary' complete! (1.17s)\n",
        11.0,
    ),
)


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


SUMMARIZE_PATH = Path(__file__).with_name("summarize.py")
SUMMARIZE_SPEC = importlib.util.spec_from_file_location(
    "compile_time_summarize_for_run_tests",
    SUMMARIZE_PATH,
)
assert SUMMARIZE_SPEC is not None and SUMMARIZE_SPEC.loader is not None
compile_time_summarize = importlib.util.module_from_spec(SUMMARIZE_SPEC)
sys.modules[SUMMARIZE_SPEC.name] = compile_time_summarize
SUMMARIZE_SPEC.loader.exec_module(compile_time_summarize)


def fake_build_output(*, wall: float, swiftpm: float, recompiled: bool = True) -> bytes:
    lines = ["Building for debugging..."]
    if recompiled:
        lines.append("[1/2] Compiling Consumer Tables.swift")
    lines.append(f"Build of product 'ConsumerLibrary' complete! ({swiftpm:.2f}s)")
    lines.append(f"        {wall:.2f} real        17.66 user         0.49 sys")
    lines.append("          123456789  maximum resident set size")
    return ("\n".join(lines) + "\n").encode("utf-8")


class RejectedSampleTests(unittest.TestCase):
    def test_rule_matches_the_summarizer(self) -> None:
        self.assertEqual(
            compile_time_run.SWIFTPM_COMPLETE_LINE.pattern,
            compile_time_summarize.SWIFTPM_COMPLETE_LINE.pattern,
        )
        self.assertEqual(
            compile_time_run.WALL_TO_SWIFTPM_FACTOR,
            compile_time_summarize.WALL_TO_SWIFTPM_FACTOR,
        )
        self.assertEqual(
            compile_time_run.WALL_TO_SWIFTPM_ALLOWANCE_SECONDS,
            compile_time_summarize.WALL_TO_SWIFTPM_ALLOWANCE_SECONDS,
        )

    def test_both_parsers_read_every_build_output_the_same_way(self) -> None:
        for text, expected in SWIFTPM_DURATION_CASES:
            with self.subTest(text=text):
                self.assertAlmostEqual(
                    compile_time_run.parse_swiftpm_duration(text), expected
                )
                self.assertAlmostEqual(
                    compile_time_summarize.parse_swiftpm_duration(text), expected
                )

    def test_parses_swiftpm_duration_and_rejects_the_cited_cell(self) -> None:
        text = fake_build_output(wall=912.21, swiftpm=9.83).decode("utf-8")
        self.assertEqual(compile_time_run.parse_swiftpm_duration(text), 9.83)
        self.assertFalse(compile_time_run.wall_is_consistent(912.21, 9.83))
        self.assertTrue(compile_time_run.wall_is_consistent(13.35, 12.84))
        with self.assertRaises(compile_time_run.HarnessError):
            compile_time_run.parse_swiftpm_duration("Build complete!\n")

    def request(self, directory: Path, prepared: list[int], attempts: int):
        return compile_time_run.MeasurementRequest(
            spec=compile_time_run.CONSUMERS_BY_IDENTIFIER["swiftql"],
            consumer_root=directory,
            table_count=10,
            query_count=1,
            build_mode="clean_dependency_warm",
            repetition=1,
            schedule_index=1,
            runs_directory=directory,
            output_directory=directory,
            total_measurements=1,
            prepare=prepared.append,
            max_attempts=attempts,
        )

    def run_with_outputs(self, outputs: list[bytes], attempts: int):
        directory_handle = tempfile.TemporaryDirectory()
        self.addCleanup(directory_handle.cleanup)
        directory = Path(directory_handle.name)
        prepared: list[int] = []
        completed = [
            subprocess.CompletedProcess(args=[], returncode=0, stdout=output)
            for output in outputs
        ]
        with mock.patch.object(
            compile_time_run, "macos_time_available", return_value=True
        ), mock.patch.object(
            compile_time_run.subprocess, "run", side_effect=completed
        ), contextlib.redirect_stdout(io.StringIO()):
            try:
                result = compile_time_run.measure_build(
                    self.request(directory, prepared, attempts)
                )
            except compile_time_run.HarnessError as error:
                result = error
        return directory, prepared, result

    def test_a_rejected_attempt_is_kept_and_measured_again(self) -> None:
        directory, prepared, result = self.run_with_outputs(
            [
                fake_build_output(wall=912.21, swiftpm=9.83),
                fake_build_output(wall=13.35, swiftpm=12.84),
            ],
            attempts=3,
        )
        self.assertIsInstance(result, dict)
        self.assertEqual(prepared, [1, 2])
        self.assertEqual(result["wallSeconds"], 13.35)
        stem = "swiftql-t010-q001-clean_dependency_warm-rep-01"
        self.assertIn(
            "912.21 real",
            (directory / f"{stem}.rejected-01.build.log").read_text(encoding="utf-8"),
        )
        self.assertIn(
            "13.35 real",
            (directory / f"{stem}.build.log").read_text(encoding="utf-8"),
        )
        self.assertEqual(result["rawLog"], f"{stem}.build.log")

    def test_the_run_fails_when_every_attempt_is_rejected(self) -> None:
        _, prepared, result = self.run_with_outputs(
            [
                fake_build_output(wall=912.21, swiftpm=9.83),
                fake_build_output(wall=911.65, swiftpm=9.56),
            ],
            attempts=2,
        )
        self.assertIsInstance(result, compile_time_run.HarnessError)
        self.assertIn("No attempts remain", str(result))
        self.assertEqual(prepared, [1, 2])

    def test_a_retried_query_edit_changes_the_literal_again(self) -> None:
        spec = compile_time_run.CONSUMERS_BY_IDENTIFIER["swiftql"]
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            compile_time_run.write_generated_sources(root, spec, 1, 3, "base")
            for attempt in (1, 2):
                compile_time_run.prepare_build_mode(
                    root, spec, 1, 3, "one_query_edit", 1, attempt
                )
            self.assertIn(
                "edit1retry2",
                (root / "Sources/Consumer/Queries.swift").read_text(encoding="utf-8"),
            )


class ExtendedScaleTests(unittest.TestCase):
    def test_presets_extend_past_ten_tables(self) -> None:
        tables, queries = compile_time_run.resolve_matrix("extended", None, None)
        self.assertEqual(tables, (1, 10, 100, 500))
        self.assertEqual(queries, (1, 10, 100))
        self.assertTrue(set(tables) <= set(compile_time_run.CANONICAL_SCALES))
        self.assertEqual(
            compile_time_run.resolve_matrix(None, None, None),
            (compile_time_run.CANONICAL_SCALES, compile_time_run.CANONICAL_SCALES),
        )
        self.assertEqual(
            compile_time_run.resolve_matrix("reduced", (1, 100), None),
            ((1, 100), (1, 10)),
        )

    def test_large_scales_split_declarations_across_files(self) -> None:
        for spec in compile_time_run.CONSUMER_SPECS:
            sources = compile_time_run.generate_sources(spec, 500, 120, "base")
            if spec.generator == "lighter":
                self.assertEqual(list(sources), ["Sources/Consumer/schema.sql"])
                self.assertEqual(
                    sources["Sources/Consumer/schema.sql"].count("CREATE TABLE"),
                    500,
                )
                continue
            table_files = [name for name in sources if "/Tables" in name]
            query_files = [name for name in sources if "/Queries" in name]
            self.assertEqual(len(table_files), 10, spec.identifier)
            self.assertEqual(len(query_files), 3, spec.identifier)
            self.assertIn("Sources/Consumer/Tables10.swift", sources)
            joined = "\n".join(sources.values())
            self.assertRegex(joined, rf"\b{compile_time_run.table_type(500)}\b")
            self.assertNotRegex(joined, rf"\b{compile_time_run.table_type(501)}\b")
            self.assertIn(f"{compile_time_run.query_name(120)}(", joined)
            for name in query_files:
                text = sources[name]
                self.assertTrue(text.startswith("import Foundation"), name)
                if spec.generator == "swiftql":
                    self.assertTrue(text.rstrip().endswith("}"), name)
                    self.assertIn("extension GRDBDatabase {", text)

    def test_a_query_edit_at_a_large_scale_touches_only_the_first_query_file(self) -> None:
        spec = compile_time_run.CONSUMERS_BY_IDENTIFIER["swiftql"]
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            compile_time_run.write_generated_sources(root, spec, 100, 120, "base")
            _, written = compile_time_run.write_generated_sources(
                root, spec, 100, 120, "edit1"
            )
            self.assertEqual(written, ["Sources/Consumer/Queries.swift"])

    def test_checked_in_points_generate_byte_identical_sources(self) -> None:
        report = json.loads(
            Path(__file__).with_name("compile-time-results.json").read_text(
                encoding="utf-8"
            )
        )
        for artifact in report["artifacts"]:
            spec = compile_time_run.CONSUMERS_BY_IDENTIFIER[artifact["consumer"]]
            sources = compile_time_run.generate_sources(
                spec,
                artifact["tableCount"],
                artifact["queryCount"],
                compile_time_run.BASE_EDIT_TOKEN,
            )
            self.assertEqual(
                {
                    relative: compile_time_run.sha256_text(text)
                    for relative, text in sources.items()
                },
                artifact["generatedSourceSHA256"],
                f"{artifact['consumer']} {artifact['tableCount']}x{artifact['queryCount']}",
            )

    def test_generate_only_writes_sources_without_swiftpm(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            workspace = Path(name) / "workspace"
            with mock.patch.object(
                compile_time_run.subprocess,
                "run",
                side_effect=AssertionError("SwiftPM must not run"),
            ), contextlib.redirect_stdout(io.StringIO()):
                status = compile_time_run.main(
                    [
                        "--workspace", str(workspace),
                        "--swiftql-checkout", str(Path(name)),
                        "--consumers", "swiftql,lighter",
                        "--tables", "1,100",
                        "--queries", "1",
                        "--generate-only",
                    ]
                )
            self.assertEqual(status, 0)
            generated = workspace / "Generated"
            self.assertTrue(
                (generated / "swiftql/t100-q001/Sources/Consumer/Tables2.swift").is_file()
            )
            self.assertTrue(
                (generated / "lighter/t100-q001/Sources/Consumer/schema.sql").is_file()
            )


SWIFTBUILD_RECOMPILED_LOG = (
    "Building for debugging...\n"
    "Planning Swift module Consumer (arm64)\n"
    "    builtin-SwiftDriver -- /Applications/Xcode.app/usr/bin/swiftc "
    "-parse-as-library -module-name Consumer -Onone @/tmp/Consumer.SwiftFileList\n"
    "[4 / 7] Consumer\n"
    "Build complete! (0,45 sec)\n"
)
SWIFTBUILD_NOOP_LOG = (
    "Building for debugging...\n"
    "[Planning deferred tasks]\n"
    "Build complete! (0,26 sec)\n"
)
# A verbose Swift Build no-op build: no compiler invocation, no progress line.
SWIFTBUILD_VERBOSE_NOOP_LOG = (
    "info: Target dependency graph (2 targets)\n"
    "info: Target 'Consumer' in project 'ControlRawSQLiteConsumer' (no dependencies)\n"
    "Building for debugging...\n"
    "Planning build\n"
    "Create build description\n"
    "Target PACKAGE-TARGET:Consumer up to date.\n"
    "Target PACKAGE-PRODUCT:control_raw_sqlite-consumer_ConsumerLibrary.ConsumerLibrary up to date.\n"
    "Build complete! (0,15 sec)\n"
)
NATIVE_RECOMPILED_LOG = (
    "[3/5] Emitting module Consumer\n"
    "[4/5] Compiling Consumer Tables.swift\n"
    "Build of product 'ConsumerLibrary' complete! (0.17s)\n"
)


class BuildSystemTests(unittest.TestCase):
    def test_build_arguments_are_verbose(self) -> None:
        self.assertIn("-v", compile_time_run.BUILD_ARGUMENTS)

    def test_recompile_marker_reads_both_build_systems(self) -> None:
        marker = compile_time_run.RECOMPILE_MARKER
        self.assertIsNotNone(marker.search(SWIFTBUILD_RECOMPILED_LOG))
        self.assertIsNotNone(marker.search(NATIVE_RECOMPILED_LOG))
        self.assertIsNone(marker.search(SWIFTBUILD_NOOP_LOG))
        self.assertIsNone(marker.search(SWIFTBUILD_VERBOSE_NOOP_LOG))
        self.assertIsNone(
            compile_time_summarize.RECOMPILE_MARKER.search(SWIFTBUILD_VERBOSE_NOOP_LOG)
        )
        self.assertIsNone(marker.search("swiftc -module-name ConsumerLibrary\n"))
        self.assertEqual(marker.pattern, compile_time_summarize.RECOMPILE_MARKER.pattern)

    def test_detects_the_build_system(self) -> None:
        self.assertEqual(
            compile_time_run.detect_build_system(SWIFTBUILD_RECOMPILED_LOG),
            "swiftbuild",
        )
        self.assertEqual(
            compile_time_run.detect_build_system(SWIFTBUILD_NOOP_LOG), "swiftbuild"
        )
        self.assertEqual(
            compile_time_run.detect_build_system(NATIVE_RECOMPILED_LOG), "native"
        )
        self.assertEqual(
            compile_time_run.detect_build_system(SWIFTBUILD_VERBOSE_NOOP_LOG),
            "swiftbuild",
        )
        self.assertEqual(compile_time_run.detect_build_system(""), "unknown")
        self.assertEqual(
            compile_time_run.parse_swiftpm_duration(SWIFTBUILD_RECOMPILED_LOG), 0.45
        )

    def artifacts(self, root: Path, binary_directory: Path) -> dict[str, object]:
        with mock.patch.object(
            compile_time_run, "show_bin_path", return_value=binary_directory
        ):
            return compile_time_run.collect_artifacts(
                root, compile_time_run.CONSUMERS_BY_IDENTIFIER["grdb"]
            )

    def test_artifacts_in_the_native_layout(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            binary = root / ".build/arm64-apple-macosx/debug"
            (binary / "Consumer.build").mkdir(parents=True)
            (binary / "Consumer.build/Tables.swift.o").write_bytes(b"x" * 10)
            (binary / "Modules").mkdir()
            (binary / "Modules/Consumer.swiftmodule").write_bytes(b"m" * 7)
            (binary / "libConsumerLibrary.a").write_bytes(b"a" * 3)
            artifacts = self.artifacts(root, binary)
            self.assertEqual(artifacts["objectBytes"], 10)
            self.assertEqual(artifacts["swiftmoduleBytes"], 7)
            self.assertEqual(artifacts["staticLibraryBytes"], 3)

    def test_artifacts_in_the_swiftbuild_layout(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            binary = root / ".build/out/Products/Debug"
            binary.mkdir(parents=True)
            (binary / "Consumer.o").write_bytes(b"p" * 100)
            (binary / "Consumer.swiftmodule").mkdir()
            (binary / "Consumer.swiftmodule/arm64.swiftmodule").write_bytes(b"m" * 5)
            (binary / "libConsumerLibrary.a").write_bytes(b"a" * 3)
            objects = root / (
                ".build/out/Intermediates.noindex/GRDBConsumer.build/Debug/"
                "Consumer-t.build/Objects-normal/arm64"
            )
            objects.mkdir(parents=True)
            (objects / "Tables.o").write_bytes(b"x" * 11)
            (objects / "Queries.o").write_bytes(b"y" * 4)
            artifacts = self.artifacts(root, binary)
            # The prelinked Products/Debug/Consumer.o is not counted.
            self.assertEqual(artifacts["objectBytes"], 15)
            self.assertEqual(artifacts["swiftmoduleBytes"], 5)
            self.assertEqual(artifacts["staticLibraryBytes"], 3)


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
