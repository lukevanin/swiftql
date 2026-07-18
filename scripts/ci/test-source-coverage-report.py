#!/usr/bin/env python3

"""Fixture tests for the first-party source coverage reporter."""

from __future__ import annotations

import hashlib
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence


SCRIPT = Path(__file__).with_name("source-coverage-report.py")
VERIFY_SCRIPT = Path(__file__).with_name(
    "verify-source-coverage-reproducibility.sh"
)
RUN_SCRIPT = Path(__file__).with_name("run-source-coverage.sh")
WORKFLOW = SCRIPT.parents[2] / ".github/workflows/swift.yml"
INITIAL_BASELINE = (
    SCRIPT.parents[2]
    / "Coverage/Baselines/2026-07-17-xcode-16.2-swift-6.0"
)


def metric(count: int, covered: int) -> Dict[str, Any]:
    return {
        "count": count,
        "covered": covered,
        "notcovered": count - covered,
        "percent": 0 if count == 0 else (covered * 100.0) / count,
    }


def file_entry(
    path: Path, lines: Sequence[int] = (10, 5), functions: Sequence[int] = (2, 1)
) -> Dict[str, Any]:
    return {
        "filename": str(path),
        "summary": {
            "lines": metric(lines[0], lines[1]),
            "functions": metric(functions[0], functions[1]),
            "regions": metric(lines[0] + functions[0], lines[1] + functions[1]),
        },
    }


class SourceCoverageReportTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory(
            prefix="swiftql-source-coverage-test."
        )
        self.root = Path(self.temporary_directory.name) / "repo"
        self.root.mkdir()
        (self.root / "Package.resolved").write_text(
            '{"pins":[],"version":2}\n', encoding="utf-8"
        )
        self.sql_macros = self.make_source("Sources/SQLMacros/Macro.swift")
        self.swiftql = self.make_source("Sources/SwiftQL/Query.swift")
        self.test_source = self.make_source("Tests/SQLTests/QueryTests.swift")
        self.dependency = self.make_source(
            ".build/checkouts/Dependency/Sources/Dependency.swift"
        )
        self.generated = self.make_source(
            ".build/arm64/debug/SwiftQLPackageTests.derived/runner.swift"
        )
        self.benchmark = self.make_source(
            "Benchmarks/Sources/SwiftQLBenchmarks/Runner.swift"
        )
        self.integration_fixture = self.make_source(
            "IntegrationTests/Swift5Client/Sources/SwiftQLSwift5Client/main.swift"
        )
        self.config = self.root / "coverage-config.json"
        self.write_config()
        subprocess.run(
            ["git", "-C", str(self.root), "init", "-q"],
            check=True,
            capture_output=True,
        )
        subprocess.run(
            [
                "git",
                "-C",
                str(self.root),
                "add",
                "--",
                "Sources/SQLMacros/Macro.swift",
                "Sources/SwiftQL/Query.swift",
            ],
            check=True,
            capture_output=True,
        )

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def make_source(self, relative_path: str) -> Path:
        path = self.root / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("func coveredFixture() {}\n", encoding="utf-8")
        return path

    def write_config(
        self,
        allowed: Optional[List[str]] = None,
        targets: Optional[Sequence[Dict[str, Any]]] = None,
    ) -> None:
        configured_targets = list(targets) if targets is not None else [
            {
                "name": "SQLMacros",
                "source_root": "Sources/SQLMacros",
                "allowed_uninstrumented_sources": [],
            },
            {
                "name": "SwiftQL",
                "source_root": "Sources/SwiftQL",
                "allowed_uninstrumented_sources": allowed or [],
            },
        ]
        self.config.write_text(
            json.dumps(
                {
                    "schema_version": 1,
                    "targets": configured_targets,
                }
            ),
            encoding="utf-8",
        )

    def write_raw_report(
        self,
        entries: Sequence[Dict[str, Any]],
        name: str = "coverage.json",
        document: Optional[Dict[str, Any]] = None,
    ) -> Path:
        path = self.root / name
        path.write_text(
            json.dumps(
                document
                or {
                    "type": "llvm.coverage.json.export",
                    "version": "fixture",
                    "data": [{"files": list(entries)}],
                },
            ),
            encoding="utf-8",
        )
        return path

    def run_report(
        self,
        entries: Sequence[Dict[str, Any]],
        output_name: str = "output",
        expect_success: bool = True,
        document: Optional[Dict[str, Any]] = None,
    ) -> subprocess.CompletedProcess[str]:
        raw_report = self.write_raw_report(
            entries, f"{output_name}-raw.json", document=document
        )
        command = [
            sys.executable,
            str(SCRIPT),
            "--llvm-json",
            str(raw_report),
            "--repository-root",
            str(self.root),
            "--config",
            str(self.config),
            "--output-directory",
            str(self.root / output_name),
            "--source-commit",
            "0123456789abcdef0123456789abcdef01234567",
            "--xcode-version",
            "Xcode fixture",
            "--swift-version",
            "Swift fixture",
            "--sdk-version",
            "SDK fixture",
            "--llvm-cov-version",
            "llvm-cov fixture",
            "--llvm-profdata-version",
            "llvm-profdata fixture",
            "--platform",
            "platform fixture",
            "--architecture",
            "architecture fixture",
            "--runner-image",
            "runner fixture",
            "--source-tree-state",
            "clean",
            "--coverage-command",
            "swift test --enable-code-coverage",
        ]
        result = subprocess.run(command, text=True, capture_output=True, check=False)
        if expect_success and result.returncode != 0:
            self.fail(f"report failed: {result.stderr}")
        if not expect_success and result.returncode == 0:
            self.fail("report unexpectedly succeeded")
        return result

    def run_verifier(
        self,
        first_name: str,
        second_name: str,
        output_name: str = "reproducibility.json",
    ) -> subprocess.CompletedProcess[str]:
        first = self.root / first_name
        second = self.root / second_name
        return subprocess.run(
            [str(VERIFY_SCRIPT), str(first), str(second), str(first / output_name)],
            text=True,
            capture_output=True,
            check=False,
        )

    def read_normalized_report(self, output_name: str) -> Dict[str, Any]:
        return json.loads(
            (self.root / output_name / "first-party-coverage.json").read_text(
                encoding="utf-8"
            )
        )

    def write_normalized_report(
        self, output_name: str, report: Dict[str, Any]
    ) -> None:
        (self.root / output_name / "first-party-coverage.json").write_text(
            json.dumps(report, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )

    def replace_report_value(
        self, output_name: str, path: Sequence[Any], value: Any
    ) -> None:
        report = self.read_normalized_report(output_name)
        container: Any = report
        for component in path[:-1]:
            container = container[component]
        container[path[-1]] = value
        self.write_normalized_report(output_name, report)

    def delete_report_value(self, output_name: str, path: Sequence[Any]) -> None:
        report = self.read_normalized_report(output_name)
        container: Any = report
        for component in path[:-1]:
            container = container[component]
        del container[path[-1]]
        self.write_normalized_report(output_name, report)

    def test_filters_dependencies_tests_generated_sources_and_benchmarks(self) -> None:
        outside_dependency = (
            Path(self.temporary_directory.name)
            / "dependency/Sources/SwiftQL/Lookalike.swift"
        )
        entries = [
            file_entry(self.dependency, (100, 100), (50, 50)),
            file_entry(outside_dependency, (100, 100), (50, 50)),
            file_entry(self.test_source, (100, 100), (50, 50)),
            file_entry(self.generated, (100, 100), (50, 50)),
            file_entry(self.benchmark, (100, 100), (50, 50)),
            file_entry(self.integration_fixture, (100, 100), (50, 50)),
            file_entry(Path("<macro expansion>"), (100, 100), (50, 50)),
            file_entry(
                Path("@__swiftmacro_7SwiftQL5QueryfMp_.swift"),
                (100, 100),
                (50, 50),
            ),
            file_entry(self.sql_macros, (8, 4), (4, 2)),
            file_entry(self.swiftql, (10, 5), (2, 1)),
        ]
        self.run_report(entries)
        report = json.loads(
            (self.root / "output/first-party-coverage.json").read_text(
                encoding="utf-8"
            )
        )
        self.assertEqual(report["overall"]["lines"]["count"], 18)
        self.assertEqual(report["overall"]["lines"]["covered"], 9)
        self.assertEqual(report["filtering"]["included_source_files"], 2)
        manifest = (self.root / "output/included-sources.txt").read_text(
            encoding="utf-8"
        )
        self.assertIn("Sources/SQLMacros/Macro.swift", manifest)
        self.assertIn("Sources/SwiftQL/Query.swift", manifest)
        self.assertNotIn("Dependency.swift", manifest)
        self.assertNotIn("QueryTests.swift", manifest)
        self.assertNotIn("runner.swift", manifest)
        self.assertNotIn("Runner.swift", manifest)
        self.assertNotIn("SwiftQLSwift5Client", manifest)
        self.assertNotIn("Lookalike.swift", manifest)
        self.assertNotIn("macro expansion", manifest)
        self.assertNotIn("@__swiftmacro_", manifest)

    def test_large_dependency_input_cannot_change_first_party_totals(self) -> None:
        outside_root = Path(self.temporary_directory.name) / "dependencies"
        dependency_entries = [
            file_entry(
                outside_root / f"Dependency{index}/Sources/SwiftQL/Fake.swift",
                (1_000, 1_000),
                (500, 500),
            )
            for index in range(1_000)
        ]
        self.run_report(
            dependency_entries
            + [file_entry(self.sql_macros, (8, 4)), file_entry(self.swiftql, (10, 5))],
            "large-dependencies",
        )
        report = json.loads(
            (self.root / "large-dependencies/first-party-coverage.json").read_text(
                encoding="utf-8"
            )
        )
        self.assertEqual(report["overall"]["lines"]["count"], 18)
        self.assertEqual(report["overall"]["lines"]["covered"], 9)
        self.assertEqual(
            report["filtering"]["excluded_raw_file_entries"], 1_000
        )

    def test_output_is_deterministic_when_raw_entries_are_reordered(self) -> None:
        entries = [file_entry(self.swiftql), file_entry(self.sql_macros)]
        self.run_report(entries, "first")
        self.run_report(list(reversed(entries)), "second")
        for filename in (
            "first-party-coverage.json",
            "included-sources.txt",
            "allowed-uninstrumented-sources.txt",
            "summary.md",
        ):
            self.assertEqual(
                (self.root / "first" / filename).read_bytes(),
                (self.root / "second" / filename).read_bytes(),
            )

    def test_unexpected_missing_production_source_fails(self) -> None:
        result = self.run_report(
            [file_entry(self.sql_macros)], "missing", expect_success=False
        )
        self.assertIn("disappeared from LLVM coverage", result.stderr)
        self.assertIn("Sources/SwiftQL/Query.swift", result.stderr)

    def test_explicit_uninstrumented_source_is_reported(self) -> None:
        self.write_config(["Sources/SwiftQL/Query.swift"])
        self.run_report([file_entry(self.sql_macros)], "allowed")
        manifest = (
            self.root / "allowed/allowed-uninstrumented-sources.txt"
        ).read_text(encoding="utf-8")
        self.assertEqual(manifest, "SwiftQL\tSources/SwiftQL/Query.swift\n")

    def test_stale_uninstrumented_allowance_fails(self) -> None:
        self.write_config(["Sources/SwiftQL/Query.swift"])
        result = self.run_report(
            [file_entry(self.sql_macros), file_entry(self.swiftql)],
            "stale",
            expect_success=False,
        )
        self.assertIn("allowances are stale", result.stderr)

    def test_duplicate_first_party_entry_fails(self) -> None:
        result = self.run_report(
            [
                file_entry(self.sql_macros),
                file_entry(self.swiftql),
                file_entry(self.swiftql),
            ],
            "duplicate",
            expect_success=False,
        )
        self.assertIn("duplicate first-party coverage entry", result.stderr)

    def test_canonical_traversal_alias_is_detected_as_a_duplicate(self) -> None:
        alias = self.root / "Sources/SwiftQL/../SwiftQL/Query.swift"
        result = self.run_report(
            [
                file_entry(self.sql_macros),
                file_entry(self.swiftql),
                file_entry(alias),
            ],
            "traversal-alias",
            expect_success=False,
        )
        self.assertIn("duplicate first-party coverage entry", result.stderr)

    def test_symlink_alias_is_detected_as_a_duplicate(self) -> None:
        alias_directory = self.root / "Sources/Alias"
        alias_directory.symlink_to(self.root / "Sources/SwiftQL", target_is_directory=True)
        result = self.run_report(
            [
                file_entry(self.sql_macros),
                file_entry(self.swiftql),
                file_entry(alias_directory / "Query.swift"),
            ],
            "symlink-alias",
            expect_success=False,
        )
        self.assertIn("duplicate first-party coverage entry", result.stderr)

    def test_untracked_file_inside_configured_root_fails(self) -> None:
        untracked = self.make_source("Sources/SwiftQL/Untracked.swift")
        result = self.run_report(
            [
                file_entry(self.sql_macros),
                file_entry(self.swiftql),
                file_entry(untracked),
            ],
            "untracked-source",
            expect_success=False,
        )
        self.assertIn("untracked files inside target roots", result.stderr)

    def test_malformed_llvm_schema_fails_closed(self) -> None:
        valid_files = [file_entry(self.sql_macros), file_entry(self.swiftql)]
        cases = {
            "wrong-type": {
                "type": "not.llvm.coverage",
                "version": "fixture",
                "data": [{"files": valid_files}],
            },
            "empty-version": {
                "type": "llvm.coverage.json.export",
                "version": "",
                "data": [{"files": valid_files}],
            },
            "multiple-data": {
                "type": "llvm.coverage.json.export",
                "version": "fixture",
                "data": [{"files": valid_files}, {"files": []}],
            },
            "missing-files": {
                "type": "llvm.coverage.json.export",
                "version": "fixture",
                "data": [{}],
            },
        }
        for name, document in cases.items():
            with self.subTest(name=name):
                result = self.run_report(
                    [], name, expect_success=False, document=document
                )
                self.assertIn("error: source coverage report", result.stderr)

    def test_unknown_repository_source_target_fails(self) -> None:
        unknown = self.make_source("Sources/NewProductionTarget/New.swift")
        result = self.run_report(
            [
                file_entry(self.sql_macros),
                file_entry(self.swiftql),
                file_entry(unknown),
            ],
            "unknown-target",
            expect_success=False,
        )
        self.assertIn("untracked files inside target roots", result.stderr)
        self.assertIn("Sources/NewProductionTarget/New.swift", result.stderr)

    def test_reproducibility_verifier_accepts_equal_reports(self) -> None:
        entries = [file_entry(self.sql_macros), file_entry(self.swiftql)]
        self.run_report(entries, "repro-first")
        self.run_report(entries, "repro-second")
        success = self.run_verifier("repro-first", "repro-second")
        self.assertEqual(success.returncode, 0, success.stderr)
        evidence = json.loads(
            (
                self.root
                / "repro-first/reproducibility.json"
            ).read_text(encoding="utf-8")
        )
        self.assertTrue(evidence["included_source_sets_match"])
        self.assertTrue(evidence["reproducibility_identity_matches"])
        self.assertTrue(evidence["normalized_reports_match"])
        self.assertTrue(evidence["dynamic_coverage_metrics_match"])

    def test_reproducibility_verifier_accepts_dynamic_counter_drift(self) -> None:
        self.run_report(
            [
                file_entry(self.sql_macros, (8, 4), (4, 2)),
                file_entry(self.swiftql, (10, 5), (2, 1)),
            ],
            "dynamic-first",
        )
        self.run_report(
            [
                file_entry(self.sql_macros, (8, 4), (4, 2)),
                file_entry(self.swiftql, (10, 4), (2, 1)),
            ],
            "dynamic-second",
        )
        self.assertNotEqual(
            self.read_normalized_report("dynamic-first"),
            self.read_normalized_report("dynamic-second"),
        )
        self.assertNotEqual(
            (self.root / "dynamic-first/summary.md").read_bytes(),
            (self.root / "dynamic-second/summary.md").read_bytes(),
        )
        success = self.run_verifier("dynamic-first", "dynamic-second")
        self.assertEqual(success.returncode, 0, success.stderr)
        evidence = json.loads(
            (
                self.root
                / "dynamic-first/reproducibility.json"
            ).read_text(encoding="utf-8")
        )
        self.assertTrue(evidence["reproducibility_identity_matches"])
        self.assertFalse(evidence["normalized_reports_match"])
        self.assertFalse(evidence["dynamic_coverage_metrics_match"])

    def test_reproducibility_verifier_rejects_added_or_removed_source(self) -> None:
        entries = [file_entry(self.sql_macros), file_entry(self.swiftql)]
        self.run_report(entries, "source-first")
        added = self.make_source("Sources/SwiftQL/Added.swift")
        subprocess.run(
            [
                "git",
                "-C",
                str(self.root),
                "add",
                "--",
                "Sources/SwiftQL/Added.swift",
            ],
            check=True,
            capture_output=True,
        )
        self.run_report(entries + [file_entry(added)], "source-second")
        failure = self.run_verifier("source-first", "source-second")
        self.assertNotEqual(failure.returncode, 0)
        self.assertIn("included source manifests differ", failure.stderr)
        reverse_failure = self.run_verifier(
            "source-second",
            "source-first",
            "removed-source.json",
        )
        self.assertNotEqual(reverse_failure.returncode, 0)
        self.assertIn("included source manifests differ", reverse_failure.stderr)

    def test_reproducibility_verifier_rejects_target_reassignment(self) -> None:
        entries = [file_entry(self.sql_macros), file_entry(self.swiftql)]
        self.run_report(entries, "target-first")
        self.write_config(
            targets=[
                {
                    "name": "SQLMacros",
                    "source_root": "Sources/SwiftQL",
                    "allowed_uninstrumented_sources": [],
                },
                {
                    "name": "SwiftQL",
                    "source_root": "Sources/SQLMacros",
                    "allowed_uninstrumented_sources": [],
                },
            ]
        )
        self.run_report(entries, "target-second")
        failure = self.run_verifier("target-first", "target-second")
        self.assertNotEqual(failure.returncode, 0)
        self.assertIn("included source manifests differ", failure.stderr)

    def test_reproducibility_verifier_rejects_manifest_report_disagreement(
        self,
    ) -> None:
        allowed = self.make_source("Sources/SwiftQL/Allowed.swift")
        subprocess.run(
            [
                "git",
                "-C",
                str(self.root),
                "add",
                "--",
                "Sources/SwiftQL/Allowed.swift",
            ],
            check=True,
            capture_output=True,
        )
        self.write_config(allowed=["Sources/SwiftQL/Allowed.swift"])
        entries = [file_entry(self.sql_macros), file_entry(self.swiftql)]
        output_names = ("manifest-first", "manifest-second")
        for output_name in output_names:
            self.run_report(entries, output_name)
        originals = {
            output_name: (
                self.root / output_name / "first-party-coverage.json"
            ).read_bytes()
            for output_name in output_names
        }
        disagreements = {
            "included": (
                ("targets", "SwiftQL", "files", 0, "path"),
                "Sources/SwiftQL/AQuery.swift",
                "included-source manifest does not match report target topology",
            ),
            "allowed": (
                (
                    "targets",
                    "SwiftQL",
                    "allowed_uninstrumented_source_files",
                    0,
                ),
                "Sources/SwiftQL/AlternativeAllowed.swift",
                "allowed-source manifest does not match report target topology",
            ),
        }
        for name, (path, value, message) in disagreements.items():
            with self.subTest(name=name):
                for output_name in output_names:
                    (
                        self.root / output_name / "first-party-coverage.json"
                    ).write_bytes(originals[output_name])
                    self.replace_report_value(output_name, path, value)
                failure = self.run_verifier(
                    "manifest-first",
                    "manifest-second",
                    f"failure-{name}-manifest.json",
                )
                self.assertNotEqual(failure.returncode, 0)
                self.assertIn(message, failure.stderr)
                self.assertNotIn("Traceback", failure.stderr)

    def test_reproducibility_verifier_rejects_static_total_drift(self) -> None:
        self.run_report(
            [file_entry(self.sql_macros), file_entry(self.swiftql, (10, 5))],
            "static-first",
        )
        self.run_report(
            [file_entry(self.sql_macros), file_entry(self.swiftql, (11, 5))],
            "static-second",
        )
        failure = self.run_verifier("static-first", "static-second")
        self.assertNotEqual(failure.returncode, 0)
        self.assertIn("reproducibility identities differ", failure.stderr)
        self.assertIn("overall", failure.stderr)
        self.assertIn("targets", failure.stderr)

    def test_reproducibility_verifier_rejects_provenance_or_filtering_drift(
        self,
    ) -> None:
        entries = [file_entry(self.sql_macros), file_entry(self.swiftql)]
        self.run_report(entries, "provenance-first")
        self.run_report(entries, "provenance-second")
        original = (
            self.root / "provenance-second/first-party-coverage.json"
        ).read_bytes()
        mutations = {
            "source-commit": (
                ("source_commit",),
                "fedcba9876543210fedcba9876543210fedcba98",
            ),
            "toolchain": (("toolchain", "runner_image"), "different runner"),
            "coverage-command": (
                ("coverage_command",),
                "swift test --enable-code-coverage --different",
            ),
            "package-resolution": (
                ("package_resolved_sha256",),
                "0" * 64,
            ),
            "filtering": (
                ("filtering", "rule"),
                "A different first-party filtering rule.",
            ),
        }
        for name, (path, value) in mutations.items():
            with self.subTest(name=name):
                (
                    self.root / "provenance-second/first-party-coverage.json"
                ).write_bytes(original)
                self.replace_report_value("provenance-second", path, value)
                failure = self.run_verifier(
                    "provenance-first",
                    "provenance-second",
                    f"failure-{name}.json",
                )
                self.assertNotEqual(failure.returncode, 0)
                self.assertIn("reproducibility identities differ", failure.stderr)
                self.assertNotIn("Traceback", failure.stderr)

    def test_reproducibility_verifier_rejects_identically_malformed_schema(
        self,
    ) -> None:
        entries = [file_entry(self.sql_macros), file_entry(self.swiftql)]
        output_names = ("schema-first", "schema-second")
        for output_name in output_names:
            self.run_report(entries, output_name)
        originals = {
            output_name: (
                self.root / output_name / "first-party-coverage.json"
            ).read_bytes()
            for output_name in output_names
        }
        missing_fields = {
            "source-commit": ("source_commit",),
            "toolchain-field": ("toolchain", "xcode"),
            "raw-report-field": ("raw_llvm_report", "type"),
            "filtering-field": ("filtering", "rule"),
        }
        for name, path in missing_fields.items():
            with self.subTest(name=name):
                for output_name in output_names:
                    (
                        self.root / output_name / "first-party-coverage.json"
                    ).write_bytes(originals[output_name])
                    self.delete_report_value(output_name, path)
                failure = self.run_verifier(
                    "schema-first",
                    "schema-second",
                    f"failure-{name}.json",
                )
                self.assertNotEqual(failure.returncode, 0)
                self.assertIn("error: source coverage reproducibility", failure.stderr)
                self.assertNotIn("Traceback", failure.stderr)

    def test_reproducibility_verifier_rejects_malformed_nested_reports(
        self,
    ) -> None:
        entries = [file_entry(self.sql_macros), file_entry(self.swiftql)]
        self.run_report(entries, "malformed-first")
        self.run_report(entries, "malformed-second")
        original = (
            self.root / "malformed-second/first-party-coverage.json"
        ).read_bytes()
        malformations = {
            "targets-array": (("targets",), []),
            "target-files-object": (("targets", "SwiftQL", "files"), {}),
            "file-entry-string": (
                ("targets", "SwiftQL", "files", 0),
                "not a file report",
            ),
            "metric-count-string": (
                ("targets", "SwiftQL", "files", 0, "lines", "count"),
                "10",
            ),
            "overall-array": (("overall",), []),
            "largest-gap-string": (("largest_uncovered_files", 0), "not a gap"),
        }
        for name, (path, value) in malformations.items():
            with self.subTest(name=name):
                (
                    self.root / "malformed-second/first-party-coverage.json"
                ).write_bytes(original)
                self.replace_report_value("malformed-second", path, value)
                failure = self.run_verifier(
                    "malformed-first",
                    "malformed-second",
                    f"failure-{name}.json",
                )
                self.assertNotEqual(failure.returncode, 0)
                self.assertIn("error: source coverage reproducibility", failure.stderr)
                self.assertNotIn("Traceback", failure.stderr)

    def test_reproducibility_verifier_rejects_dirty_reports(self) -> None:
        entries = [file_entry(self.sql_macros), file_entry(self.swiftql)]
        self.run_report(entries, "dirty-first")
        self.run_report(entries, "dirty-second")
        self.replace_report_value(
            "dirty-second", ("source_tree_state",), "dirty"
        )
        failure = self.run_verifier("dirty-first", "dirty-second")
        self.assertNotEqual(failure.returncode, 0)
        self.assertIn("did not capture a clean tree", failure.stderr)


class CoverageWorkflowTests(unittest.TestCase):
    def test_coverage_artifact_retains_complete_raw_reports_for_both_runs(
        self,
    ) -> None:
        run_script = RUN_SCRIPT.read_text(encoding="utf-8")
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn(
            'cp "$raw_coverage_json" "$output_directory/llvm-coverage.json"',
            run_script,
        )
        self.assertIn(
            '> "$output_directory/llvm-coverage.lcov"',
            run_script,
        )
        self.assertIn(
            "${{ runner.temp }}/swiftql-coverage-run-1",
            workflow,
        )
        self.assertIn(
            "${{ runner.temp }}/swiftql-coverage-run-2",
            workflow,
        )

    def test_pull_request_capture_uses_durable_head_commit(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn(
            "COVERAGE_SOURCE_SHA: ${{ github.event.pull_request.head.sha || github.sha }}",
            workflow,
        )
        self.assertIn("ref: ${{ env.COVERAGE_SOURCE_SHA }}", workflow)
        self.assertIn(
            'test "$(git rev-parse HEAD)" = "$COVERAGE_SOURCE_SHA"', workflow
        )
        self.assertIn(
            "name: swiftql-source-coverage-${{ env.COVERAGE_SOURCE_SHA }}-",
            workflow,
        )

    def test_baseline_fixture_jobs_checkout_historical_source_commit(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertEqual(workflow.count("fetch-depth: 0"), 2)

    def test_checked_in_initial_baseline_is_internally_consistent(self) -> None:
        report = json.loads(
            (INITIAL_BASELINE / "first-party-coverage.json").read_text(
                encoding="utf-8"
            )
        )
        reproducibility = json.loads(
            (INITIAL_BASELINE / "reproducibility.json").read_text(
                encoding="utf-8"
            )
        )
        included = (INITIAL_BASELINE / "included-sources.txt").read_bytes()
        included_lines = included.decode("utf-8").splitlines()
        repeated = (
            INITIAL_BASELINE / "repeated-included-sources.txt"
        ).read_bytes()
        allowed = (
            INITIAL_BASELINE / "allowed-uninstrumented-sources.txt"
        ).read_text(encoding="utf-8").splitlines()

        self.assertEqual(
            report["source_commit"],
            "9152d8409aa55df5bc96e9c74411b3c4fb166429",
        )
        self.assertEqual(report["source_tree_state"], "clean")
        self.assertEqual(report["source_commit"], reproducibility["source_commit"])
        self.assertTrue(reproducibility["normalized_reports_match"])
        self.assertEqual(included, repeated)
        included_sha256 = hashlib.sha256(included).hexdigest()
        self.assertEqual(
            included_sha256,
            report["filtering"]["included_sources_sha256"],
        )
        self.assertEqual(
            included_sha256, reproducibility["included_sources_sha256"]
        )
        self.assertEqual(
            report["package_resolved_sha256"],
            reproducibility["package_resolved_sha256"],
        )
        self.assertEqual(
            len(included_lines),
            report["filtering"]["included_source_files"],
        )
        self.assertEqual(
            len(allowed),
            report["filtering"]["allowed_uninstrumented_source_files"],
        )
        self.assertEqual(set(report["targets"]), {"SQLMacros", "SwiftQL"})

        baseline_tree_result = subprocess.run(
            [
                "git",
                "-C",
                str(SCRIPT.parents[2]),
                "ls-tree",
                "-r",
                "--name-only",
                report["source_commit"],
                "--",
                "Sources/SQLMacros",
                "Sources/SwiftQL",
            ],
            check=True,
            text=True,
            capture_output=True,
        )
        baseline_sources = {
            path
            for path in baseline_tree_result.stdout.splitlines()
            if path.endswith(".swift")
        }
        accounted_lines = included_lines + allowed
        accounted_sources = set()
        for line in accounted_lines:
            target, source = line.split("\t", maxsplit=1)
            expected_target = (
                "SQLMacros"
                if source.startswith("Sources/SQLMacros/")
                else "SwiftQL"
            )
            self.assertEqual(target, expected_target)
            self.assertNotIn(source, accounted_sources)
            accounted_sources.add(source)
        self.assertEqual(accounted_sources, baseline_sources)
        self.assertFalse(list(INITIAL_BASELINE.glob("llvm-coverage.*")))


if __name__ == "__main__":
    unittest.main()
