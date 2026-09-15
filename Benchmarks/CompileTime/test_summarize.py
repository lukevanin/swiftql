from __future__ import annotations

import contextlib
import copy
import hashlib
import io
import importlib.util
import json
import statistics
import sys
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("summarize.py")
SPEC = importlib.util.spec_from_file_location("compile_time_summarize", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
summarize = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = summarize
SPEC.loader.exec_module(summarize)


REVISION = "0" * 40
CONSUMERS = ("control_consumer", "macro_consumer")
POINTS = ((1, 1), (10, 1), (1, 10))
MODES = ("clean_dependency_warm", "noop_incremental", "one_query_edit")
REPETITIONS = 3


def build_log(
    *,
    wall: float,
    user: float,
    system: float,
    peak: int,
    recompiled: bool,
    swiftpm: float | None = None,
) -> str:
    lines = ["Building for debugging..."]
    if recompiled:
        lines.append("[1/3] Compiling Consumer Tables.swift")
        lines.append("[2/3] Emitting module Consumer")
    duration = round(wall * 0.8, 2) if swiftpm is None else swiftpm
    lines.append(f"Build of product 'ConsumerLibrary' complete! ({duration:.2f}s)")
    lines.append(f"        {wall:.2f} real         {user:.2f} user         {system:.2f} sys")
    lines.append(f"          {peak}  maximum resident set size")
    return "\n".join(lines) + "\n"


def synthesize(directory: Path) -> Path:
    """Write a complete, self-consistent report and its raw logs."""

    runs = directory / "Runs"
    runs.mkdir(parents=True, exist_ok=True)

    measurements: list[dict[str, object]] = []
    artifacts: list[dict[str, object]] = []
    schedule_index = 0
    for consumer in CONSUMERS:
        for table_count, query_count in POINTS:
            artifacts.append(
                {
                    "consumer": consumer,
                    "tableCount": table_count,
                    "queryCount": query_count,
                    "generatedSourceBytes": 100 * table_count + 50 * query_count,
                    "generatedSourceSHA256": {
                        "Sources/Consumer/Tables.swift": "a" * 64,
                        "Sources/Consumer/Queries.swift": "b" * 64,
                    },
                    "swiftmoduleBytes": 1000,
                    "objectBytes": 2000,
                    "staticLibraryBytes": 3000,
                    "pluginGeneratedSwiftBytes": None,
                    "macroExpansionBytes": None,
                    "macroExpansionUnavailableReason": "not observable",
                }
            )
            for repetition in range(1, REPETITIONS + 1):
                for mode in MODES:
                    schedule_index += 1
                    wall = round(1.0 + 0.25 * repetition + 0.5 * len(mode) % 3, 2)
                    user = round(wall * 2, 2)
                    system = round(wall / 2, 2)
                    peak = 1_000_000 + schedule_index
                    recompiled = mode != "noop_incremental"
                    stem = (
                        f"{consumer}-t{table_count:03d}-q{query_count:03d}"
                        f"-{mode}-rep-{repetition:02d}"
                    )
                    log_path = runs / f"{stem}.build.log"
                    text = build_log(
                        wall=wall,
                        user=user,
                        system=system,
                        peak=peak,
                        recompiled=recompiled,
                    )
                    log_path.write_text(text, encoding="utf-8")
                    measurements.append(
                        {
                            "consumer": consumer,
                            "tableCount": table_count,
                            "queryCount": query_count,
                            "buildMode": mode,
                            "repetition": repetition,
                            "scheduleIndex": schedule_index,
                            "startedAt": f"2026-08-01T00:00:{schedule_index:02d}.000000Z",
                            "finishedAt": f"2026-08-01T00:01:{schedule_index:02d}.000000Z",
                            "wallSeconds": wall,
                            "userSeconds": user,
                            "systemSeconds": system,
                            "peakRSSBytes": peak,
                            "peakRSSUnavailableReason": None,
                            "timingMethod": "usr_bin_time_l_macos",
                            "recompiledConsumerTarget": recompiled,
                            "rawLog": f"Runs/{stem}.build.log",
                            "rawLogSHA256": hashlib.sha256(
                                text.encode("utf-8")
                            ).hexdigest(),
                        }
                    )

    results: dict[str, dict[str, object]] = {}
    grouped: dict[str, list[dict[str, object]]] = {}
    for measurement in measurements:
        grouped.setdefault(summarize.measurement_key(measurement), []).append(
            measurement
        )
    for key, group in grouped.items():
        walls = [float(item["wallSeconds"]) for item in group]
        median_wall = statistics.median(walls)
        results[key] = {
            "repetitionCount": len(group),
            "medianWallSeconds": median_wall,
            "minWallSeconds": min(walls),
            "maxWallSeconds": max(walls),
            "wallSpreadPercent": (max(walls) - min(walls)) / median_wall * 100.0,
            "medianUserSeconds": statistics.median(
                [float(item["userSeconds"]) for item in group]
            ),
            "medianSystemSeconds": statistics.median(
                [float(item["systemSeconds"]) for item in group]
            ),
            "maxPeakRSSBytes": max(int(item["peakRSSBytes"]) for item in group),
        }

    document = {
        "formatVersion": 1,
        "generatedAt": "2026-08-01T00:00:00.000000Z",
        "provenance": {"harness": "independently_implemented"},
        "workload": {
            "identifier": "consumer_compile_time_scalability",
            "canonicalScales": [1, 10, 100, 500],
            "recordedTableScales": [1, 10],
            "recordedQueryScales": [1, 10],
            "baselineTableCount": 1,
            "baselineQueryCount": 1,
            "buildModes": list(MODES),
            "configuration": "debug",
            "product": "ConsumerLibrary",
            "target": "Consumer",
            "repetitionCount": REPETITIONS,
            "timer": "usr_bin_time_l",
            "processIsolation": "one_swift_build_process_per_measurement",
            "dependencyState": "dependency_warm",
            "cleanModeDefinition": "sources rewritten, dependencies warm",
            "postWarmupCooldownSeconds": 0.0,
            "columnCount": 6,
            "attribution": "whole_consumer_build",
        },
        "sources": {"swiftqlRevision": REVISION, "swiftqlDirty": False},
        "environment": {
            "model": "TestMac",
            "processor": "Test",
            "architecture": "arm64",
            "swift": "test toolchain",
            "coreCount": 8,
        },
        "consumers": [
            {
                "identifier": consumer,
                "template": consumer,
                "dependencies": {},
                "buildModes": list(MODES),
                "applicability": {
                    "tableAxis": "applicable",
                    "queryAxis": "applicable",
                    "oneQueryEdit": "applicable",
                    "note": "synthetic consumer",
                },
            }
            for consumer in CONSUMERS
        ],
        "artifacts": artifacts,
        "measurements": measurements,
        "results": results,
        "durationUnit": "seconds_per_build",
    }
    report = directory / "report.json"
    report.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")
    return report


class ValidatorTests(unittest.TestCase):
    def setUp(self) -> None:
        self._directory = tempfile.TemporaryDirectory()
        self.directory = Path(self._directory.name)
        self.report = synthesize(self.directory)

    def tearDown(self) -> None:
        self._directory.cleanup()

    def rewrite(self, mutate) -> Path:
        document = json.loads(self.report.read_text(encoding="utf-8"))
        mutate(document)
        self.report.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")
        return self.report

    def assertRejected(self, mutate, fragment: str) -> None:
        path = self.rewrite(mutate)
        document = summarize.load_report(path)
        with self.assertRaises(summarize.ValidationError) as context:
            summarize.validate(document, path, require_full_matrix=False)
        self.assertIn(fragment, str(context.exception))

    def test_a_complete_report_validates_and_renders(self) -> None:
        document = summarize.load_report(self.report)
        summaries = summarize.validate(document, self.report, require_full_matrix=False)
        self.assertEqual(len(summaries), len(CONSUMERS) * len(POINTS) * len(MODES))
        rendered = summarize.render(document, summaries)
        self.assertIn("SwiftQL consumer compile-time scalability", rendered)
        self.assertIn("whole-consumer build cost", rendered)
        self.assertIn("CI gate", rendered)

    def test_main_accepts_the_report(self) -> None:
        self.assertEqual(summarize.main([str(self.report)]), 0)

    def test_rejects_an_unknown_format_version(self) -> None:
        path = self.rewrite(lambda document: document.update({"formatVersion": 99}))
        with self.assertRaises(summarize.ValidationError):
            summarize.load_report(path)

    def test_rejects_a_missing_scale(self) -> None:
        def mutate(document: dict) -> None:
            document["measurements"] = [
                measurement
                for measurement in document["measurements"]
                if measurement["tableCount"] != 10
            ]
            for index, measurement in enumerate(document["measurements"], start=1):
                measurement["scheduleIndex"] = index

        self.assertRejected(mutate, "is missing measurements")

    def test_rejects_a_missing_repetition(self) -> None:
        def mutate(document: dict) -> None:
            document["measurements"] = document["measurements"][:-1]

        self.assertRejected(mutate, "is missing measurements")

    def test_rejects_a_non_contiguous_schedule(self) -> None:
        def mutate(document: dict) -> None:
            document["measurements"][0]["scheduleIndex"] = 10_000

        self.assertRejected(mutate, "scheduleIndex values must be contiguous")

    def test_rejects_a_full_matrix_report_that_omits_a_canonical_scale(self) -> None:
        document = summarize.load_report(self.report)
        with self.assertRaises(summarize.ValidationError) as context:
            summarize.validate(document, self.report, require_full_matrix=True)
        self.assertIn("full 1/10/100/500 matrix", str(context.exception))

    def test_rejects_an_inconsistent_declared_matrix(self) -> None:
        self.assertRejected(
            lambda document: document["workload"].update(
                {"recordedTableScales": [1, 10, 100]}
            ),
            "is missing measurements",
        )

    def test_rejects_a_scale_outside_the_canonical_matrix(self) -> None:
        self.assertRejected(
            lambda document: document["workload"].update(
                {"recordedTableScales": [1, 7]}
            ),
            "outside the canonical matrix",
        )

    def test_rejects_a_nonpositive_measurement(self) -> None:
        def mutate(document: dict) -> None:
            document["measurements"][0]["wallSeconds"] = 0.0

        self.assertRejected(mutate, "wallSeconds must be positive")

    def test_rejects_a_negative_user_time(self) -> None:
        def mutate(document: dict) -> None:
            document["measurements"][0]["userSeconds"] = -1.0

        self.assertRejected(mutate, "must be non-negative")

    def test_rejects_a_summary_that_disagrees_with_the_raw_measurements(self) -> None:
        def mutate(document: dict) -> None:
            key = next(iter(document["results"]))
            document["results"][key]["medianWallSeconds"] = 999.0

        self.assertRejected(mutate, "disagrees")

    def test_rejects_a_measurement_that_disagrees_with_its_raw_log(self) -> None:
        def mutate(document: dict) -> None:
            measurement = document["measurements"][0]
            measurement["wallSeconds"] = float(measurement["wallSeconds"]) + 5.0
            key = summarize.measurement_key(measurement)
            group = [
                item
                for item in document["measurements"]
                if summarize.measurement_key(item) == key
            ]
            walls = [float(item["wallSeconds"]) for item in group]
            median_wall = statistics.median(walls)
            document["results"][key].update(
                {
                    "medianWallSeconds": median_wall,
                    "minWallSeconds": min(walls),
                    "maxWallSeconds": max(walls),
                    "wallSpreadPercent": (max(walls) - min(walls)) / median_wall * 100.0,
                }
            )

        self.assertRejected(mutate, "disagrees with the report")

    def test_rejects_a_tampered_raw_log(self) -> None:
        log = self.directory / "Runs" / sorted(
            path.name for path in (self.directory / "Runs").iterdir()
        )[0]
        log.write_text(log.read_text(encoding="utf-8") + "tampered\n", encoding="utf-8")
        document = summarize.load_report(self.report)
        with self.assertRaises(summarize.ValidationError) as context:
            summarize.validate(document, self.report, require_full_matrix=False)
        self.assertIn("raw log hash mismatch", str(context.exception))

    def test_rejects_a_missing_raw_log(self) -> None:
        for path in (self.directory / "Runs").iterdir():
            path.unlink()
            break
        document = summarize.load_report(self.report)
        with self.assertRaises(summarize.ValidationError) as context:
            summarize.validate(document, self.report, require_full_matrix=False)
        self.assertIn("missing raw build log", str(context.exception))

    def test_rejects_a_no_op_build_that_recompiled(self) -> None:
        def mutate(document: dict) -> None:
            for measurement in document["measurements"]:
                if measurement["buildMode"] == "noop_incremental":
                    measurement["recompiledConsumerTarget"] = True
                    return

        self.assertRejected(mutate, "must not have recompiled")

    def test_rejects_a_duplicate_measurement(self) -> None:
        def mutate(document: dict) -> None:
            duplicate = copy.deepcopy(document["measurements"][0])
            duplicate["scheduleIndex"] = len(document["measurements"]) + 1
            document["measurements"].append(duplicate)

        self.assertRejected(mutate, "duplicate measurement")

    def test_rejects_a_dirty_revision_field_that_is_not_a_sha(self) -> None:
        self.assertRejected(
            lambda document: document["sources"].update({"swiftqlRevision": "abc"}),
            "not a full Git SHA",
        )

    def test_rejects_an_artifact_point_without_measurements(self) -> None:
        def mutate(document: dict) -> None:
            extra = copy.deepcopy(document["artifacts"][0])
            extra["tableCount"] = 100
            document["artifacts"].append(extra)

        self.assertRejected(mutate, "artifact points and measured points disagree")

    def test_rejects_a_missing_macro_expansion_reason(self) -> None:
        def mutate(document: dict) -> None:
            document["artifacts"][0]["macroExpansionUnavailableReason"] = None

        self.assertRejected(mutate, "macro-expansion size is unavailable")

    def test_rejects_a_nonpositive_artifact_size(self) -> None:
        def mutate(document: dict) -> None:
            document["artifacts"][0]["objectBytes"] = 0

        self.assertRejected(mutate, "must be a positive integer or null")

    def test_rejects_applicability_that_contradicts_the_build_modes(self) -> None:
        def mutate(document: dict) -> None:
            document["consumers"][0]["applicability"]["queryAxis"] = "not_applicable"

        self.assertRejected(mutate, "applicability disagrees with its build modes")

    def test_rejects_a_report_that_hides_whole_build_attribution(self) -> None:
        self.assertRejected(
            lambda document: document["workload"].update({"attribution": "macro_only"}),
            "whole-consumer build cost",
        )


# The two lines issue #670 cites from
# Runs/swiftql-t010-q001-clean_dependency_warm-rep-01.build.log: SwiftPM built
# the product in 9.83 s, but the process took 912.21 s of wall time for only
# 17.66 s of user CPU, so it waited for about fifteen minutes.
CITED_COMPLETE_LINE = "Build of product 'ConsumerLibrary' complete! (9.83s)"
CITED_TIME_LINE = "      912.21 real        17.66 user         0.49 sys"


def recompute_results(document: dict, key: str) -> None:
    group = [
        item
        for item in document["measurements"]
        if summarize.measurement_key(item) == key
    ]
    walls = [float(item["wallSeconds"]) for item in group]
    median_wall = statistics.median(walls)
    document["results"][key].update(
        {
            "medianWallSeconds": median_wall,
            "minWallSeconds": min(walls),
            "maxWallSeconds": max(walls),
            "wallSpreadPercent": (max(walls) - min(walls)) / median_wall * 100.0,
            "medianUserSeconds": statistics.median(
                [float(item["userSeconds"]) for item in group]
            ),
            "medianSystemSeconds": statistics.median(
                [float(item["systemSeconds"]) for item in group]
            ),
        }
    )


class SwiftPMDurationParserTests(unittest.TestCase):
    def test_parses_the_product_line_the_issue_cites(self) -> None:
        text = f"[5/6] Compiling Consumer Queries.swift\n{CITED_COMPLETE_LINE}\n{CITED_TIME_LINE}\n"
        self.assertEqual(summarize.parse_swiftpm_duration(text), 9.83)
        self.assertEqual(summarize.TIME_LINE.findall(text), [("912.21", "17.66", "0.49")])

    def test_parses_a_line_without_a_product_clause(self) -> None:
        self.assertEqual(
            summarize.parse_swiftpm_duration("Build complete! (0.31s)\n"),
            0.31,
        )

    def test_rejects_a_missing_line(self) -> None:
        for text in (
            "Build of product 'ConsumerLibrary' complete!\n",
            "Compiling Consumer Queries.swift (9.83s)\n",
            "",
        ):
            with self.assertRaises(summarize.ValidationError):
                summarize.parse_swiftpm_duration(text)

    def test_accepts_a_comma_decimal_mark(self) -> None:
        self.assertEqual(
            summarize.parse_swiftpm_duration(
                "Build of product 'ConsumerLibrary' complete! (9,83s)\n"
            ),
            9.83,
        )
        self.assertEqual(
            summarize.parse_swiftpm_duration("Build complete! (43,01 sec)\n"),
            43.01,
        )

    def test_strips_ansi_colour_codes(self) -> None:
        text = (
            "\x1b[1;32mBuild of product 'ConsumerLibrary' complete!\x1b[0m "
            "\x1b[2m(9.83s)\x1b[0m\n"
        )
        self.assertEqual(summarize.parse_swiftpm_duration(text), 9.83)

    def test_reads_a_line_after_a_carriage_return_progress_update(self) -> None:
        text = (
            "[5/6] Compiling Consumer Queries.swift\r"
            "Build of product 'ConsumerLibrary' complete! (9.83s)\r\n"
            f"{CITED_TIME_LINE}\n"
        )
        self.assertEqual(summarize.parse_swiftpm_duration(text), 9.83)

    def test_sums_the_durations_of_more_than_one_line(self) -> None:
        text = (
            "Build of product 'ConsumerLibrary' complete! (9.83s)\n"
            "Build of product 'OtherLibrary' complete! (1,17s)\n"
        )
        self.assertEqual(summarize.swiftpm_durations(text), [9.83, 1.17])
        self.assertAlmostEqual(summarize.parse_swiftpm_duration(text), 11.0)


class RejectionRuleTests(unittest.TestCase):
    def test_the_rule_is_fixed_and_documented(self) -> None:
        self.assertEqual(summarize.WALL_TO_SWIFTPM_FACTOR, 2.0)
        self.assertEqual(summarize.WALL_TO_SWIFTPM_ALLOWANCE_SECONDS, 2.0)
        self.assertAlmostEqual(summarize.wall_limit_seconds(9.83), 21.66)
        self.assertIn("2 x SwiftPM", summarize.rejection_rule_description())

    def test_the_invalid_ten_table_clean_cell_is_rejected(self) -> None:
        self.assertFalse(summarize.wall_is_consistent(912.21, 9.83))
        # Its healthy sibling repetition in the same cell stays.
        self.assertTrue(summarize.wall_is_consistent(13.35, 12.84))

    def test_healthy_recorded_samples_are_kept(self) -> None:
        # The largest checked-in ratio outside the three waited samples: a
        # sub-second no-op build with fixed SwiftPM start-up overhead.
        self.assertTrue(summarize.wall_is_consistent(0.97, 0.19))
        self.assertTrue(summarize.wall_is_consistent(10.04, 9.41))

    def test_the_limit_is_inclusive(self) -> None:
        self.assertTrue(summarize.wall_is_consistent(22.0, 10.0))
        self.assertFalse(summarize.wall_is_consistent(22.01, 10.0))


class RejectedSampleReportTests(unittest.TestCase):
    def setUp(self) -> None:
        self._directory = tempfile.TemporaryDirectory()
        self.directory = Path(self._directory.name)
        self.report = synthesize(self.directory)

    def tearDown(self) -> None:
        self._directory.cleanup()

    def install_cited_sample(self) -> dict:
        """Replace one clean 10-table sample with the cell issue #670 cites."""

        document = json.loads(self.report.read_text(encoding="utf-8"))
        measurement = next(
            item
            for item in document["measurements"]
            if item["consumer"] == "macro_consumer"
            and item["tableCount"] == 10
            and item["buildMode"] == "clean_dependency_warm"
            and item["repetition"] == 1
        )
        text = build_log(
            wall=912.21,
            user=17.66,
            system=0.49,
            peak=int(measurement["peakRSSBytes"]),
            recompiled=True,
            swiftpm=9.83,
        )
        self.assertIn(CITED_COMPLETE_LINE, text)
        (self.directory / measurement["rawLog"]).write_text(text, encoding="utf-8")
        measurement.update(
            {
                "wallSeconds": 912.21,
                "userSeconds": 17.66,
                "systemSeconds": 0.49,
                "rawLogSHA256": hashlib.sha256(text.encode("utf-8")).hexdigest(),
            }
        )
        recompute_results(document, summarize.measurement_key(measurement))
        self.report.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")
        return measurement

    def run_main(self, *arguments: str) -> tuple[int, str, str]:
        stdout = io.StringIO()
        stderr = io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            status = summarize.main([str(self.report), *arguments])
        return status, stdout.getvalue(), stderr.getvalue()

    def test_a_consistent_report_has_no_rejections(self) -> None:
        document = summarize.load_report(self.report)
        summarize.validate(document, self.report, require_full_matrix=False)
        self.assertEqual(summarize.rejected_samples(document, self.report), [])
        status, output, _ = self.run_main()
        self.assertEqual(status, 0)
        self.assertIn("None. Every wall time is consistent", output)

    def test_the_cited_sample_is_reported_and_fails_the_run(self) -> None:
        measurement = self.install_cited_sample()
        document = summarize.load_report(self.report)
        summarize.validate(document, self.report, require_full_matrix=False)
        rejections = summarize.rejected_samples(document, self.report)
        self.assertEqual(len(rejections), 1)
        self.assertEqual(rejections[0]["rawLog"], measurement["rawLog"])
        self.assertEqual(rejections[0]["wallSeconds"], 912.21)
        self.assertEqual(rejections[0]["userSeconds"], 17.66)
        self.assertEqual(rejections[0]["swiftpmSeconds"], 9.83)

        status, output, errors = self.run_main()
        self.assertEqual(status, 1)
        self.assertIn("912.21 s", output)
        self.assertIn("[R]", output)
        self.assertIn("1 rejected sample", errors)

    def test_the_median_without_rejected_samples_is_printed_too(self) -> None:
        measurement = self.install_cited_sample()
        document = summarize.load_report(self.report)
        summarize.validate(document, self.report, require_full_matrix=False)
        rejections = summarize.rejected_samples(document, self.report)
        key = summarize.measurement_key(measurement)
        medians = summarize.medians_without_rejected(
            document["measurements"], rejections
        )
        self.assertEqual(list(medians), [key])
        # The synthetic cell's other two walls are 3.00 s and 3.25 s.
        self.assertEqual(medians[key]["sampleCount"], 3)
        self.assertEqual(medians[key]["acceptedSampleCount"], 2)
        self.assertAlmostEqual(medians[key]["medianWallSeconds"], 3.25)
        self.assertAlmostEqual(medians[key]["medianWallSecondsWithoutRejected"], 3.125)

        status, output, _ = self.run_main("--allow-rejected-samples")
        self.assertEqual(status, 0)
        self.assertIn("Medians include every recorded sample", output)
        self.assertIn(
            "with rejected samples 3.25 s; without rejected samples 3.12 s from 2 of 3 samples",
            output,
        )

    def test_a_cell_with_every_sample_rejected_has_no_accepted_median(self) -> None:
        measurements = [
            {
                "consumer": "c",
                "tableCount": 1,
                "queryCount": 1,
                "buildMode": "noop_incremental",
                "rawLog": f"Runs/{index}.log",
                "wallSeconds": 900.0,
            }
            for index in range(2)
        ]
        medians = summarize.medians_without_rejected(measurements, measurements)
        self.assertIsNone(
            medians["c|1|1|noop_incremental"]["medianWallSecondsWithoutRejected"]
        )
        self.assertIn(
            "none (0 of 2 samples accepted)",
            summarize.render_rejections(
                [
                    dict(item, repetition=1, userSeconds=1.0, swiftpmSeconds=0.5, wallLimitSeconds=3.0)
                    for item in measurements
                ],
                measurements,
            ),
        )

    def test_rejected_samples_can_be_allowed_but_are_still_reported(self) -> None:
        self.install_cited_sample()
        status, output, errors = self.run_main("--allow-rejected-samples")
        self.assertEqual(status, 0)
        self.assertIn("Rejected samples", output)
        self.assertIn("SwiftPM 9.83 s", output)
        self.assertIn("warning:", errors)

    def test_a_log_without_the_swiftpm_line_fails_validation(self) -> None:
        document = json.loads(self.report.read_text(encoding="utf-8"))
        measurement = document["measurements"][0]
        log = self.directory / measurement["rawLog"]
        text = "".join(
            line
            for line in log.read_text(encoding="utf-8").splitlines(keepends=True)
            if "complete!" not in line
        )
        log.write_text(text, encoding="utf-8")
        measurement["rawLogSHA256"] = hashlib.sha256(text.encode("utf-8")).hexdigest()
        self.report.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")
        with self.assertRaises(summarize.ValidationError) as context:
            summarize.validate(
                summarize.load_report(self.report),
                self.report,
                require_full_matrix=False,
            )
        self.assertIn("complete!", str(context.exception))


class SwiftBuildLogTests(unittest.TestCase):
    def test_verbose_swiftbuild_logs_validate(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            directory = Path(name)
            report = synthesize(directory)
            document = json.loads(report.read_text(encoding="utf-8"))
            for measurement in document["measurements"]:
                lines = ["Building for debugging...", "[Planning deferred tasks]"]
                if measurement["recompiledConsumerTarget"]:
                    lines.append("Planning Swift module Consumer (arm64)")
                    lines.append(
                        "    builtin-SwiftDriver -- /usr/bin/swiftc "
                        "-parse-as-library -module-name Consumer -Onone"
                    )
                    lines.append("[4 / 7] Consumer")
                duration = f"{float(measurement['wallSeconds']) * 0.8:.2f}".replace(".", ",")
                lines.append(f"Build complete! ({duration} sec)")
                lines.append(
                    f"        {measurement['wallSeconds']:.2f} real         "
                    f"{measurement['userSeconds']:.2f} user         "
                    f"{measurement['systemSeconds']:.2f} sys"
                )
                lines.append(
                    f"          {measurement['peakRSSBytes']}  maximum resident set size"
                )
                text = "\n".join(lines) + "\n"
                (directory / measurement["rawLog"]).write_text(text, encoding="utf-8")
                measurement["rawLogSHA256"] = hashlib.sha256(
                    text.encode("utf-8")
                ).hexdigest()
            report.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")
            loaded = summarize.load_report(report)
            summarize.validate(loaded, report, require_full_matrix=False)
            self.assertEqual(summarize.rejected_samples(loaded, report), [])

    def test_a_swiftbuild_no_op_log_is_not_a_recompile(self) -> None:
        self.assertIsNone(
            summarize.RECOMPILE_MARKER.search(
                "Building for debugging...\n[Planning deferred tasks]\n"
                "Build complete! (0,26 sec)\n"
            )
        )
        self.assertIsNone(
            summarize.RECOMPILE_MARKER.search("swiftc -module-name ConsumerLibrary\n")
        )
        self.assertIsNotNone(
            summarize.RECOMPILE_MARKER.search("swiftc -module-name Consumer -Onone\n")
        )


class ComparisonTests(unittest.TestCase):
    def setUp(self) -> None:
        self._baseline = tempfile.TemporaryDirectory()
        self._candidate = tempfile.TemporaryDirectory()
        self.baseline_path = synthesize(Path(self._baseline.name))
        self.candidate_path = synthesize(Path(self._candidate.name))

    def tearDown(self) -> None:
        self._baseline.cleanup()
        self._candidate.cleanup()

    def test_compatible_reports_compare(self) -> None:
        self.assertEqual(
            summarize.main(
                [
                    "--baseline",
                    str(self.baseline_path),
                    "--candidate",
                    str(self.candidate_path),
                ]
            ),
            0,
        )

    def test_rejects_dependency_drift(self) -> None:
        document = json.loads(self.candidate_path.read_text(encoding="utf-8"))
        document["consumers"][0]["dependencies"] = {
            "grdb.swift": {"version": "6.29.3", "revision": "0" * 40}
        }
        self.candidate_path.write_text(
            json.dumps(document, indent=2) + "\n",
            encoding="utf-8",
        )
        baseline = summarize.load_report(self.baseline_path)
        candidate = summarize.load_report(self.candidate_path)
        baseline_summaries = summarize.validate(
            baseline,
            self.baseline_path,
            require_full_matrix=False,
        )
        candidate_summaries = summarize.validate(
            candidate,
            self.candidate_path,
            require_full_matrix=False,
        )
        with self.assertRaises(summarize.ValidationError) as context:
            summarize.compare(
                baseline,
                baseline_summaries,
                candidate,
                candidate_summaries,
            )
        self.assertIn("dependency pins, build modes, or applicability drifted", str(context.exception))

    def test_rejects_an_incompatible_environment(self) -> None:
        document = json.loads(self.candidate_path.read_text(encoding="utf-8"))
        document["environment"]["processor"] = "Something Else"
        self.candidate_path.write_text(
            json.dumps(document, indent=2) + "\n",
            encoding="utf-8",
        )
        self.assertEqual(
            summarize.main(
                [
                    "--baseline",
                    str(self.baseline_path),
                    "--candidate",
                    str(self.candidate_path),
                ]
            ),
            1,
        )

    def test_requires_both_comparison_paths(self) -> None:
        self.assertEqual(
            summarize.main(["--baseline", str(self.baseline_path)]),
            1,
        )


if __name__ == "__main__":
    unittest.main()
