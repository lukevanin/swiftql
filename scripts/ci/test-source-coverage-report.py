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
MEMBERSHIP_SCRIPT = Path(__file__).with_name("check-source-target-membership.py")
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
        source_commit: str = "0123456789abcdef0123456789abcdef01234567",
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
            source_commit,
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

    def commit_fixture(self) -> str:
        subprocess.run(
            [
                "git",
                "-C",
                str(self.root),
                "-c",
                "user.name=Coverage Fixture",
                "-c",
                "user.email=coverage-fixture@example.invalid",
                "commit",
                "-q",
                "--allow-empty",
                "-m",
                "fixture",
            ],
            check=True,
            capture_output=True,
        )
        return subprocess.run(
            ["git", "-C", str(self.root), "rev-parse", "HEAD"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()

    def capture(
        self,
        output_name: str,
        entries: Optional[Sequence[Dict[str, Any]]] = None,
    ) -> None:
        """A report at the fixture repository's committed HEAD."""
        self.run_report(
            entries
            if entries is not None
            else [file_entry(self.sql_macros), file_entry(self.swiftql)],
            output_name,
            source_commit=self.commit_fixture(),
        )

    def run_verifier(
        self,
        capture_name: str,
        output_name: str = "reproducibility.json",
    ) -> subprocess.CompletedProcess[str]:
        capture = self.root / capture_name
        return subprocess.run(
            [
                str(VERIFY_SCRIPT),
                str(capture),
                str(capture / output_name),
                "--repository-root",
                str(self.root),
                "--config",
                str(self.config),
            ],
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

    def track_documentation_catalog_snapshot(self) -> Path:
        relative = "Sources/SwiftQL/SwiftQL.docc/Tutorials/Resources/Step-01-01.swift"
        snapshot = self.make_source(relative)
        subprocess.run(
            ["git", "-C", str(self.root), "add", "--", relative],
            check=True,
            capture_output=True,
        )
        return snapshot

    def test_documentation_catalog_resources_are_not_production_sources(
        self,
    ) -> None:
        snapshot = self.track_documentation_catalog_snapshot()
        self.run_report(
            [
                file_entry(self.sql_macros, (8, 4), (4, 2)),
                file_entry(self.swiftql, (10, 5), (2, 1)),
            ],
            "catalog",
        )
        report = json.loads(
            (self.root / "catalog/first-party-coverage.json").read_text(
                encoding="utf-8"
            )
        )
        manifest = (self.root / "catalog/included-sources.txt").read_text(
            encoding="utf-8"
        )
        self.assertEqual(report["filtering"]["included_source_files"], 2)
        self.assertNotIn("Step-01-01.swift", manifest)
        self.assertTrue(snapshot.is_file())

    def test_documentation_catalog_resource_with_coverage_data_is_ignored(
        self,
    ) -> None:
        snapshot = self.track_documentation_catalog_snapshot()
        self.run_report(
            [
                file_entry(self.sql_macros, (8, 4), (4, 2)),
                file_entry(self.swiftql, (10, 5), (2, 1)),
                file_entry(snapshot, (100, 100), (50, 50)),
            ],
            "catalog-covered",
        )
        report = json.loads(
            (self.root / "catalog-covered/first-party-coverage.json").read_text(
                encoding="utf-8"
            )
        )
        self.assertEqual(report["overall"]["lines"]["count"], 18)
        self.assertEqual(report["overall"]["lines"]["covered"], 9)
        self.assertEqual(report["filtering"]["included_source_files"], 2)
        self.assertEqual(
            report["filtering"]["excluded_raw_file_entries_by_category"],
            {"documentation_catalog": 1},
        )

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
        self.assertIn(
            "files inside target roots that git does not track", result.stderr
        )

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

    def test_source_outside_target_roots_is_left_to_membership_check(self) -> None:
        # Membership moved to check-source-target-membership.py, which runs on
        # pull requests. The post-merge report excludes such a file and keeps
        # the first-party totals unchanged.
        unknown = self.make_source("Sources/NewProductionTarget/New.swift")
        self.run_report(
            [
                file_entry(self.sql_macros),
                file_entry(self.swiftql),
                file_entry(unknown, (100, 0), (50, 0)),
            ],
            "unknown-target",
        )
        report = self.read_normalized_report("unknown-target")
        self.assertEqual(report["overall"]["lines"]["count"], 20)
        self.assertEqual(
            report["filtering"]["excluded_raw_file_entries_by_category"],
            {"other_repository_sources": 1},
        )

    def test_verifier_accepts_capture_matching_git_and_config(self) -> None:
        self.capture("selection")
        success = self.run_verifier("selection")
        self.assertEqual(success.returncode, 0, success.stderr)
        self.assertIn("SWIFTQL_SOURCE_COVERAGE_SELECTION_VERIFIED", success.stdout)
        evidence = json.loads(
            (self.root / "selection/reproducibility.json").read_text(
                encoding="utf-8"
            )
        )
        self.assertEqual(evidence["schema_version"], 2)
        self.assertEqual(evidence["coverage_captures"], 1)
        self.assertTrue(evidence["source_commit_matches_checkout"])
        self.assertTrue(evidence["package_resolution_matches_checkout"])
        self.assertTrue(evidence["target_topology_matches_config"])
        self.assertTrue(evidence["included_source_sets_match"])
        self.assertTrue(evidence["allowed_uninstrumented_source_sets_match"])
        self.assertEqual(
            (self.root / "selection/derived-included-sources.txt").read_bytes(),
            (self.root / "selection/included-sources.txt").read_bytes(),
        )
        self.assertEqual(
            (
                self.root / "selection/derived-allowed-uninstrumented-sources.txt"
            ).read_bytes(),
            (self.root / "selection/allowed-uninstrumented-sources.txt").read_bytes(),
        )

    def test_verifier_ignores_dynamic_hit_counters(self) -> None:
        # Hit counters were never part of the identity: the concurrent suite
        # can merge a different number of hits. Only static counts must stay
        # internally consistent.
        self.capture(
            "dynamic",
            [
                file_entry(self.sql_macros, (8, 0), (4, 0)),
                file_entry(self.swiftql, (10, 10), (2, 2)),
            ],
        )
        success = self.run_verifier("dynamic")
        self.assertEqual(success.returncode, 0, success.stderr)

    def test_verifier_derives_allowed_uninstrumented_sources_from_config(
        self,
    ) -> None:
        self.make_source("Sources/SwiftQL/Allowed.swift")
        subprocess.run(
            ["git", "-C", str(self.root), "add", "--", "Sources/SwiftQL/Allowed.swift"],
            check=True,
            capture_output=True,
        )
        self.write_config(allowed=["Sources/SwiftQL/Allowed.swift"])
        self.capture("allowed")
        success = self.run_verifier("allowed")
        self.assertEqual(success.returncode, 0, success.stderr)
        self.assertEqual(
            (
                self.root / "allowed/derived-allowed-uninstrumented-sources.txt"
            ).read_text(encoding="utf-8"),
            "SwiftQL\tSources/SwiftQL/Allowed.swift\n",
        )

    def test_verifier_rejects_capture_of_an_older_commit(self) -> None:
        self.capture("older")
        self.make_source("Sources/SwiftQL/Added.swift")
        subprocess.run(
            ["git", "-C", str(self.root), "add", "--", "Sources/SwiftQL/Added.swift"],
            check=True,
            capture_output=True,
        )
        self.commit_fixture()
        failure = self.run_verifier("older")
        self.assertNotEqual(failure.returncode, 0)
        self.assertIn("is not the checked-out commit", failure.stderr)

    def test_verifier_rejects_manifest_that_disagrees_with_git(self) -> None:
        # A capture of the original sources, relabelled as a capture of a
        # later commit that tracks one more source. Its manifests are
        # internally consistent, so only the derived selection can catch it --
        # the case a second full run used to catch.
        self.capture("forged")
        added = self.make_source("Sources/SwiftQL/Added.swift")
        subprocess.run(
            ["git", "-C", str(self.root), "add", "--", "Sources/SwiftQL/Added.swift"],
            check=True,
            capture_output=True,
        )
        self.capture(
            "complete",
            [
                file_entry(self.sql_macros),
                file_entry(self.swiftql),
                file_entry(added),
            ],
        )
        head = self.read_normalized_report("complete")["source_commit"]
        self.replace_report_value("forged", ("source_commit",), head)

        failure = self.run_verifier("forged")
        self.assertNotEqual(failure.returncode, 0)
        self.assertIn(
            "included source manifest does not match the selection derived "
            "from git ls-files and the coverage config",
            failure.stderr,
        )
        self.assertNotIn("Traceback", failure.stderr)
        success = self.run_verifier("complete")
        self.assertEqual(success.returncode, 0, success.stderr)

    def test_verifier_rejects_target_reassignment_in_config(self) -> None:
        self.capture("target")
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
        failure = self.run_verifier("target")
        self.assertNotEqual(failure.returncode, 0)
        self.assertIn("target topology does not match the coverage config", failure.stderr)

    def test_verifier_rejects_allowance_that_git_does_not_track(self) -> None:
        self.capture("untracked-allowance")
        self.write_config(allowed=["Sources/SwiftQL/Missing.swift"])
        failure = self.run_verifier("untracked-allowance")
        self.assertNotEqual(failure.returncode, 0)
        self.assertIn("allows uninstrumented sources git does not track", failure.stderr)
        self.assertNotIn("Traceback", failure.stderr)

    def test_verifier_rejects_manifest_report_disagreement(self) -> None:
        allowed = self.make_source("Sources/SwiftQL/Allowed.swift")
        subprocess.run(
            ["git", "-C", str(self.root), "add", "--", "Sources/SwiftQL/Allowed.swift"],
            check=True,
            capture_output=True,
        )
        self.write_config(allowed=[str(allowed.relative_to(self.root))])
        self.capture("manifest")
        original = (self.root / "manifest/first-party-coverage.json").read_bytes()
        disagreements = {
            "included": (
                ("targets", "SwiftQL", "files", 0, "path"),
                "Sources/SwiftQL/AQuery.swift",
                "included-source manifest does not match report target topology",
            ),
            "allowed": (
                ("targets", "SwiftQL", "allowed_uninstrumented_source_files", 0),
                "Sources/SwiftQL/AlternativeAllowed.swift",
                "allowed-source manifest does not match report target topology",
            ),
        }
        for name, (path, value, message) in disagreements.items():
            with self.subTest(name=name):
                (self.root / "manifest/first-party-coverage.json").write_bytes(original)
                self.replace_report_value("manifest", path, value)
                failure = self.run_verifier("manifest", f"failure-{name}.json")
                self.assertNotEqual(failure.returncode, 0)
                self.assertIn(message, failure.stderr)
                self.assertNotIn("Traceback", failure.stderr)

    def test_verifier_rejects_inconsistent_static_totals(self) -> None:
        self.capture("static")
        # A self-consistent metric (count, covered, uncovered, percent) whose
        # count no longer equals the sum of the target's files.
        self.replace_report_value(
            "static",
            ("targets", "SwiftQL", "totals", "lines"),
            {"count": 11, "covered": 5, "uncovered": 6, "percent": 45.45},
        )
        failure = self.run_verifier("static")
        self.assertNotEqual(failure.returncode, 0)
        self.assertIn("totals.lines.count does not match its files", failure.stderr)

    def test_verifier_rejects_provenance_that_disagrees_with_checkout(
        self,
    ) -> None:
        self.capture("provenance")
        original = (self.root / "provenance/first-party-coverage.json").read_bytes()
        mutations = {
            "source-commit": (
                ("source_commit",),
                "fedcba9876543210fedcba9876543210fedcba98",
                "is not the checked-out commit",
            ),
            "package-resolution": (
                ("package_resolved_sha256",),
                "0" * 64,
                "Package.resolved digest does not match the checkout",
            ),
        }
        for name, (path, value, message) in mutations.items():
            with self.subTest(name=name):
                (self.root / "provenance/first-party-coverage.json").write_bytes(
                    original
                )
                self.replace_report_value("provenance", path, value)
                failure = self.run_verifier("provenance", f"failure-{name}.json")
                self.assertNotEqual(failure.returncode, 0)
                self.assertIn(message, failure.stderr)
                self.assertNotIn("Traceback", failure.stderr)

        (self.root / "provenance/first-party-coverage.json").write_bytes(original)
        (self.root / "Package.resolved").write_text(
            '{"pins":[{"identity":"changed"}],"version":2}\n', encoding="utf-8"
        )
        failure = self.run_verifier("provenance", "failure-resolved-file.json")
        self.assertNotEqual(failure.returncode, 0)
        self.assertIn("Package.resolved digest does not match the checkout", failure.stderr)

    def test_verifier_rejects_malformed_schema(self) -> None:
        self.capture("schema")
        original = (self.root / "schema/first-party-coverage.json").read_bytes()
        missing_fields = {
            "source-commit": ("source_commit",),
            "toolchain-field": ("toolchain", "xcode"),
            "raw-report-field": ("raw_llvm_report", "type"),
            "filtering-field": ("filtering", "rule"),
        }
        for name, path in missing_fields.items():
            with self.subTest(name=name):
                (self.root / "schema/first-party-coverage.json").write_bytes(original)
                self.delete_report_value("schema", path)
                failure = self.run_verifier("schema", f"failure-{name}.json")
                self.assertNotEqual(failure.returncode, 0)
                self.assertIn("error: source coverage reproducibility", failure.stderr)
                self.assertNotIn("Traceback", failure.stderr)

    def test_verifier_rejects_malformed_nested_reports(self) -> None:
        self.capture("malformed")
        original = (self.root / "malformed/first-party-coverage.json").read_bytes()
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
                (self.root / "malformed/first-party-coverage.json").write_bytes(original)
                self.replace_report_value("malformed", path, value)
                failure = self.run_verifier("malformed", f"failure-{name}.json")
                self.assertNotEqual(failure.returncode, 0)
                self.assertIn("error: source coverage reproducibility", failure.stderr)
                self.assertNotIn("Traceback", failure.stderr)

    def test_verifier_rejects_dirty_reports(self) -> None:
        self.capture("dirty")
        self.replace_report_value("dirty", ("source_tree_state",), "dirty")
        failure = self.run_verifier("dirty")
        self.assertNotEqual(failure.returncode, 0)
        self.assertIn("did not capture a clean tree", failure.stderr)


class CoverageWorkflowTests(unittest.TestCase):
    def test_coverage_artifact_retains_complete_raw_report(self) -> None:
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
        self.assertIn("path: ${{ runner.temp }}/swiftql-coverage\n", workflow)
        self.assertIn(
            "files: ${{ runner.temp }}/swiftql-coverage/llvm-coverage.lcov",
            workflow,
        )
        # The second instrumented run is gone; the selection is derived.
        self.assertNotIn("swiftql-coverage-run-", workflow)

    def test_coverage_artifact_names_the_exact_tested_commit(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn(
            "name: swiftql-source-coverage-${{ github.sha }}-${{ github.run_attempt }}",
            workflow,
        )
        self.assertIn('test "$(git rev-parse HEAD)" = "$GITHUB_SHA"', workflow)

    def test_baseline_fixture_jobs_checkout_historical_source_commit(self) -> None:
        # Only the release-tooling job needs full history: it reads the
        # historical baseline commit with `git ls-tree`.
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertEqual(workflow.count("fetch-depth: 0"), 1)

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


class SourceTargetMembershipTests(unittest.TestCase):
    # A throwaway git repository stands in for the checkout: each test tracks a
    # fake file list and runs the real membership check against it.
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory(
            prefix="swiftql-source-membership-test."
        )
        self.root = Path(self.temporary_directory.name) / "repo"
        self.root.mkdir()
        subprocess.run(
            ["git", "-C", str(self.root), "init", "-q"],
            check=True,
            capture_output=True,
        )
        self.config = self.root / "coverage-config.json"
        self.write_config()
        self.track(
            "Sources/SwiftQL/Query.swift",
            "Sources/SwiftQL/SwiftQL.docc/Resources/Snapshot.swift",
            "Sources/SwiftQLCLI/main.swift",
            "Sources/NotSwift/Resource.json",
            "Tests/SQLTests/QueryTests.swift",
        )

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def write_config(
        self, excluded: Optional[Sequence[Dict[str, Any]]] = None
    ) -> None:
        self.config.write_text(
            json.dumps(
                {
                    "schema_version": 1,
                    "targets": [
                        {
                            "name": "SwiftQL",
                            "source_root": "Sources/SwiftQL",
                            "allowed_uninstrumented_sources": [],
                        }
                    ],
                    "excluded_source_roots": list(excluded)
                    if excluded is not None
                    else [
                        {
                            "source_root": "Sources/SwiftQLCLI",
                            "reason": "Executable target.",
                        }
                    ],
                }
            ),
            encoding="utf-8",
        )

    def track(self, *relative_paths: str) -> None:
        for relative_path in relative_paths:
            path = self.root / relative_path
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("func fixture() {}\n", encoding="utf-8")
        subprocess.run(
            ["git", "-C", str(self.root), "add", "--", *relative_paths],
            check=True,
            capture_output=True,
        )

    def run_check(self) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [
                sys.executable,
                str(MEMBERSHIP_SCRIPT),
                "--repository-root",
                str(self.root),
                "--config",
                str(self.config),
            ],
            text=True,
            capture_output=True,
            check=False,
        )

    def test_sources_inside_configured_roots_pass(self) -> None:
        result = self.run_check()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("2 tracked Swift sources", result.stdout)

    def test_added_source_outside_configured_roots_fails(self) -> None:
        self.track("Sources/NewProductionTarget/New.swift")
        result = self.run_check()
        self.assertEqual(result.returncode, 1)
        self.assertIn("outside the configured target roots", result.stderr)
        self.assertIn("Sources/NewProductionTarget/New.swift", result.stderr)
        self.assertNotIn("untracked", result.stderr)
        # The error names the config that was checked, not the default one.
        self.assertIn(str(self.config), result.stderr)

    def test_untracked_source_outside_configured_roots_is_ignored(self) -> None:
        path = self.root / "Sources/Scratch/Local.swift"
        path.parent.mkdir(parents=True)
        path.write_text("func local() {}\n", encoding="utf-8")
        result = self.run_check()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_stale_excluded_root_fails(self) -> None:
        self.write_config(
            [
                {"source_root": "Sources/SwiftQLCLI", "reason": "Executable target."},
                {"source_root": "Sources/RemovedCLI", "reason": "Executable target."},
            ]
        )
        result = self.run_check()
        self.assertEqual(result.returncode, 1)
        self.assertIn("Sources/RemovedCLI", result.stderr)

    def test_malformed_excluded_roots_fail(self) -> None:
        cases = {
            "missing-reason": [{"source_root": "Sources/SwiftQLCLI"}],
            "outside-sources": [
                {"source_root": "Tests/SQLTests", "reason": "Not a source root."}
            ],
            "overlaps-target": [
                {"source_root": "Sources/SwiftQL/Nested", "reason": "Overlap."}
            ],
        }
        for name, excluded in cases.items():
            with self.subTest(name=name):
                self.write_config(excluded)
                result = self.run_check()
                self.assertEqual(result.returncode, 1)
                self.assertIn("error: source target membership", result.stderr)

    def test_release_tooling_job_runs_membership_check_on_pull_requests(
        self,
    ) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        release_tooling = workflow.split("\n  release-tooling:\n", maxsplit=1)[1]
        release_tooling, later_jobs = release_tooling.split(
            "\n  swift-series:\n", maxsplit=1
        )
        command = "python3 scripts/ci/check-source-target-membership.py"
        self.assertIn(command, release_tooling)
        self.assertNotIn("github.event_name", release_tooling)
        # The coverage capture no longer re-runs a check the pull request
        # already passed.
        self.assertNotIn(command, later_jobs)


if __name__ == "__main__":
    unittest.main()
