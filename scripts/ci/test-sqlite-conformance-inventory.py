#!/usr/bin/env python3

"""Adversarial fixtures for the SQLite conformance inventory tool."""

from __future__ import annotations

import copy
import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Any, Dict, List, Mapping, Optional


SCRIPT = Path(__file__).with_name("sqlite-conformance-inventory.py")
REPOSITORY_ROOT = SCRIPT.parents[2]
sys.dont_write_bytecode = True
SPEC = importlib.util.spec_from_file_location("sqlite_conformance_inventory", SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"could not import {SCRIPT}")
INVENTORY_TOOL = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(INVENTORY_TOOL)

FAMILIES = [
    "select",
    "expression",
    "join",
    "subquery",
    "compound",
    "cte",
    "dml",
    "ddl",
]
SOURCE_ID = "fixture SQLite source identity"
COMMIT = "a" * 40
LICENSE_BLOB_SHA = "b" * 40


class SQLiteConformanceInventoryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory(
            prefix="swiftql-sqlite-conformance-test."
        )
        self.root = Path(self.temporary_directory.name) / "repo"
        self.root.mkdir()
        self.make_file(
            "Sources/SwiftQL/Fixture.swift",
            """public struct Fixture {}
// public struct CommentedAPI {}
private struct PrivateAPI {}
public protocol FixtureProtocol {
    mutating func protocolRequirement()
}
public enum FixtureEnum {
    case fixtureCase
}
""",
        )
        self.make_file(
            "Tests/FixtureTests.swift",
            """final class FixtureTests {
    func testFixture() {}
    // func testCommentedLine() {}
    /* func testCommentedBlock() {} */
    func testOuter() {
        func testNested() {}
    }
}
extension FixtureTests {
    func testExtension() {}
}
final class OtherTests {
    func testOtherClass() {}
}
""",
        )
        self.make_file(
            "Tests/CompileFail/Invalid.swift",
            "let invalidCompileFailFixture = true\n",
        )
        runner = self.make_file(
            "scripts/ci/run-compile-fail.sh",
            "#!/bin/sh\n# Tests/CompileFail/Invalid.swift\nexit 0\n",
        )
        runner.chmod(0o755)
        self.inventory_path = self.root / "inventory.json"
        self.report_path = self.root / "Conformance/SQLite/REPORT.md"

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def make_file(self, relative_path: str, contents: str) -> Path:
        path = self.root / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents, encoding="utf-8")
        return path

    def environment(self) -> Dict[str, Any]:
        return {
            "id": "sqlite-fixture",
            "sqlite_version": "3.51.0",
            "sqlite_source_id": SOURCE_ID,
            "source": "fixture",
            "captured_at": "2026-07-19T12:00:00Z",
            "toolchain": "fixture toolchain",
            "architecture": "arm64",
            "capabilities": ["sqlite-parser"],
        }

    def evidence(
        self,
        identifier: str,
        layers: List[str],
        *,
        real_sqlite: bool,
        source_path: str = "Tests/FixtureTests.swift",
        test_case: str = "FixtureTests.testFixture",
        runner_path: Optional[str] = None,
    ) -> Dict[str, Any]:
        return {
            "id": identifier,
            "source_path": source_path,
            "test_case": test_case,
            "runner_path": runner_path,
            "layers": layers,
            "real_sqlite": real_sqlite,
            "environment_ids": ["sqlite-fixture"] if real_sqlite else [],
        }

    def feature(self, family: str, index: int) -> Dict[str, Any]:
        evidence_ids = ["evidence.real-prepare"]
        if index == 0:
            evidence_ids.extend(
                [
                    "evidence.compile-fail",
                    "evidence.render-only",
                    "evidence.fake-prepare",
                ]
            )
        return {
            "id": f"syntax.{family}.fixture",
            "kind": "syntax",
            "family": family,
            "title": f"{family.title()} fixture",
            "status": "supported",
            "adoption_status": "already-covered",
            "public_api": [
                {
                    "symbol": "Fixture",
                    "source_path": "Sources/SwiftQL/Fixture.swift",
                    "source_tokens": ["Fixture"],
                }
            ],
            "sqlite_documentation_urls": [
                "https://www.sqlite.org/lang_select.html"
            ],
            "not_sqlite_syntax_reason": None,
            "minimum_sqlite_version": "3.0.0",
            "reviewed_sqlite_release": "3.51.0",
            "reviewed_sqlite_source_id": SOURCE_ID,
            "required_capabilities": [],
            "schema_requirements": [],
            "evidence_ids": evidence_ids,
            "deviations": [],
            "follow_up_issues": [],
            "deferral": None,
            "provenance": [],
        }

    def provenance(self) -> Dict[str, Any]:
        return {
            "repository": "example/upstream",
            "commit": COMMIT,
            "path": "Tests/FixtureTests.swift",
            "upstream_case": "FixtureTests.testExample",
            "license_spdx": "MIT",
            "license_file_path": "LICENSE",
            "license_file_url": f"https://example.com/upstream/{COMMIT}/LICENSE",
            "license_blob_sha": LICENSE_BLOB_SHA,
            "license_disposition": "Behavior was adapted; no source copied.",
            "copied_material": False,
            "notice_path": None,
            "adaptation_notes": "Rewritten against the public SwiftQL contract.",
        }

    def valid_inventory(self) -> Dict[str, Any]:
        features = [self.feature(family, index) for index, family in enumerate(FAMILIES)]
        real_evidence = self.evidence(
            "evidence.real-prepare",
            [
                "swift-typecheck",
                "rendering",
                "bindings",
                "prepare",
                "execution",
                "structured-error",
                "runtime-metadata",
                "semantic-oracle",
            ],
            real_sqlite=True,
        )
        evidence = [
            real_evidence,
            self.evidence(
                "evidence.compile-fail",
                ["compile-fail"],
                real_sqlite=False,
                source_path="Tests/CompileFail/Invalid.swift",
                test_case="compile-fail.fixture",
                runner_path="scripts/ci/run-compile-fail.sh",
            ),
            self.evidence(
                "evidence.render-only", ["rendering"], real_sqlite=False
            ),
            self.evidence(
                "evidence.fake-prepare", ["prepare"], real_sqlite=False
            ),
        ]
        suites = [
            {
                "id": "suite.syntax-matrix",
                "issue": 191,
                "milestone": "v1.3",
                "status": "completed",
                "case_ids": [feature["id"] for feature in features],
                "evidence_ids": ["evidence.real-prepare"],
            },
            {
                "id": "suite.value-conformance",
                "issue": 252,
                "milestone": "v1.3",
                "status": "completed",
                "case_ids": [features[0]["id"]],
                "evidence_ids": ["evidence.real-prepare"],
            },
            {
                "id": "suite.transaction-conformance",
                "issue": 253,
                "milestone": "v1.3",
                "status": "completed",
                "case_ids": [features[-1]["id"]],
                "evidence_ids": ["evidence.real-prepare"],
            },
        ]
        for issue, name in [
            (254, "prepared-statement"),
            (255, "operator-property"),
            (256, "observation"),
            (286, "function-overload-conformance"),
        ]:
            status = "completed" if issue in {254, 255, 286} else "planned"
            suites.append(
                {
                    "id": f"suite.{name}",
                    "issue": issue,
                    "milestone": "v1.4.1" if issue == 286 else "v1.3",
                    "status": status,
                    "case_ids": (
                        [features[0]["id"]] if status == "completed" else []
                    ),
                    "evidence_ids": (
                        ["evidence.real-prepare"] if status == "completed" else []
                    ),
                }
            )
        return {
            "schema_version": 1,
            "inventory_version": "1.3.0",
            "coordination_issue": 190,
            "scope": {
                "claim": "Fixture-backed public SQLite conformance.",
                "limits": ["This is a deliberately small test inventory."],
                "required_families": list(FAMILIES),
            },
            "sqlite_environments": [self.environment()],
            "evidence": evidence,
            "suites": suites,
            "features": features,
        }

    def validate(self, inventory: Mapping[str, Any]) -> Mapping[str, Any]:
        return INVENTORY_TOOL.validate_inventory(inventory, self.root)

    def assert_invalid(
        self, inventory: Mapping[str, Any], expected_message: str
    ) -> None:
        with self.assertRaisesRegex(
            INVENTORY_TOOL.InventoryError, expected_message
        ):
            self.validate(inventory)

    def write_inventory(self, inventory: Mapping[str, Any]) -> None:
        self.inventory_path.write_text(
            json.dumps(inventory, indent=2) + "\n", encoding="utf-8"
        )

    def run_cli(
        self, command: str, *, expect_success: bool = True
    ) -> subprocess.CompletedProcess[str]:
        result = subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                command,
                "--repository-root",
                str(self.root),
                "--inventory",
                str(self.inventory_path),
                "--report",
                str(self.report_path),
            ],
            text=True,
            capture_output=True,
            check=False,
        )
        if expect_success and result.returncode != 0:
            self.fail(f"command failed: {result.stderr}")
        if not expect_success and result.returncode == 0:
            self.fail("command unexpectedly succeeded")
        return result

    def test_valid_fixture_and_repository_inventory_validate(self) -> None:
        self.validate(self.valid_inventory())
        repository_inventory = INVENTORY_TOOL.load_inventory(
            REPOSITORY_ROOT
            / "Tests/SwiftQLSQLiteConformanceFixtures/SQLiteConformanceInventory.json"
        )
        INVENTORY_TOOL.validate_inventory(repository_inventory, REPOSITORY_ROOT)

    def test_render_is_byte_identical_and_canonical_for_top_level_order(self) -> None:
        inventory = self.valid_inventory()
        first = INVENTORY_TOOL.render_report(self.validate(inventory))
        second = INVENTORY_TOOL.render_report(self.validate(copy.deepcopy(inventory)))
        reordered = copy.deepcopy(inventory)
        reordered["features"].reverse()
        reordered["evidence"].reverse()
        reordered["suites"].reverse()
        third = INVENTORY_TOOL.render_report(self.validate(reordered))
        self.assertEqual(first, second)
        self.assertEqual(first, third)
        self.assertTrue(first.endswith("\n"))
        self.assertIn("SQLite docs", first)
        self.assertIn("| Runner |", first)

    def test_write_then_check_succeeds_and_stale_report_fails(self) -> None:
        self.write_inventory(self.valid_inventory())
        self.run_cli("write")
        self.run_cli("check")
        self.report_path.write_text("stale\n", encoding="utf-8")
        result = self.run_cli("check", expect_success=False)
        self.assertIn("generated report is stale", result.stderr)

    def test_unknown_and_missing_keys_are_rejected(self) -> None:
        unknown = self.valid_inventory()
        unknown["features"][0]["surprise"] = True
        self.assert_invalid(unknown, "unknown keys: surprise")

        missing = self.valid_inventory()
        del missing["evidence"][0]["test_case"]
        self.assert_invalid(missing, "missing required keys: test_case")

        missing_runner_key = self.valid_inventory()
        del missing_runner_key["evidence"][0]["runner_path"]
        self.assert_invalid(missing_runner_key, "missing required keys: runner_path")

    def test_duplicate_json_keys_and_nonstandard_constants_are_rejected(self) -> None:
        duplicate = self.root / "duplicate.json"
        duplicate.write_text('{"schema_version":1,"schema_version":1}\n', encoding="utf-8")
        with self.assertRaisesRegex(INVENTORY_TOOL.InventoryError, "duplicate JSON object key"):
            INVENTORY_TOOL.load_inventory(duplicate)

        nonstandard = self.root / "nonstandard.json"
        nonstandard.write_text('{"schema_version":NaN}\n', encoding="utf-8")
        with self.assertRaisesRegex(INVENTORY_TOOL.InventoryError, "non-standard JSON"):
            INVENTORY_TOOL.load_inventory(nonstandard)

    def test_duplicate_ids_and_unknown_references_are_rejected(self) -> None:
        duplicate = self.valid_inventory()
        duplicate["evidence"].append(copy.deepcopy(duplicate["evidence"][0]))
        self.assert_invalid(duplicate, "duplicate evidence id")

        unknown = self.valid_inventory()
        unknown["features"][0]["evidence_ids"].append("evidence.missing")
        self.assert_invalid(unknown, "references unknown evidence")

        unknown_case = self.valid_inventory()
        unknown_case["suites"][0]["case_ids"].append("syntax.missing.fixture")
        self.assert_invalid(unknown_case, "references unknown features")

    def test_orphan_evidence_is_rejected(self) -> None:
        inventory = self.valid_inventory()
        inventory["evidence"].append(
            self.evidence("evidence.orphan", ["observation"], real_sqlite=False)
        )
        self.assert_invalid(inventory, "evidence is not referenced")

    def test_required_global_evidence_layer_is_enforced(self) -> None:
        inventory = self.valid_inventory()
        inventory["evidence"][0]["layers"].remove("runtime-metadata")
        self.assert_invalid(inventory, "missing required global layers: runtime-metadata")

    def test_ordinary_evidence_verifies_declared_class_and_method(self) -> None:
        renamed_method = self.valid_inventory()
        renamed_method["evidence"][0]["test_case"] = "FixtureTests.testRenamed"
        self.assert_invalid(renamed_method, "func testRenamed\\(")

        invented_class = self.valid_inventory()
        invented_class["evidence"][0]["test_case"] = "InventedTests.testFixture"
        self.assert_invalid(invented_class, "class 'InventedTests'.*not declared")

        malformed = self.valid_inventory()
        malformed["evidence"][0]["test_case"] = "testFixture"
        self.assert_invalid(malformed, "must use Class.method form")

        commented_line = self.valid_inventory()
        commented_line["evidence"][0]["test_case"] = (
            "FixtureTests.testCommentedLine"
        )
        self.assert_invalid(commented_line, "no direct 'func testCommentedLine")

        commented_block = self.valid_inventory()
        commented_block["evidence"][0]["test_case"] = (
            "FixtureTests.testCommentedBlock"
        )
        self.assert_invalid(commented_block, "no direct 'func testCommentedBlock")

        wrong_class = self.valid_inventory()
        wrong_class["evidence"][0]["test_case"] = "FixtureTests.testOtherClass"
        self.assert_invalid(wrong_class, "no direct 'func testOtherClass")

        nested_function = self.valid_inventory()
        nested_function["evidence"][0]["test_case"] = "FixtureTests.testNested"
        self.assert_invalid(nested_function, "no direct 'func testNested")

        extension_method = self.valid_inventory()
        extension_method["evidence"][0]["test_case"] = (
            "FixtureTests.testExtension"
        )
        self.validate(extension_method)

    def test_commented_repository_test_is_not_accepted_as_evidence(self) -> None:
        with self.assertRaisesRegex(
            INVENTORY_TOOL.InventoryError,
            "no direct 'func testSelectWhereInSubquery",
        ):
            INVENTORY_TOOL.validate_ordinary_test_reference(
                "XLExecutionTests.testSelectWhereInSubquery",
                "Tests/SQLTests/SQLExecutionTests.swift",
                "repository-commented-test",
                REPOSITORY_ROOT,
            )

    def test_public_api_requires_named_public_declaration_tokens(self) -> None:
        invented_symbol = self.valid_inventory()
        invented_symbol["features"][0]["public_api"][0]["symbol"] = "InventedAPI"
        self.assert_invalid(invented_symbol, "does not explicitly name source token")

        invented_token = self.valid_inventory()
        api = invented_token["features"][0]["public_api"][0]
        api["symbol"] = "InventedAPI"
        api["source_tokens"] = ["InventedAPI"]
        self.assert_invalid(invented_token, "are not public declarations")

        commented_declaration = self.valid_inventory()
        api = commented_declaration["features"][0]["public_api"][0]
        api["symbol"] = "CommentedAPI"
        api["source_tokens"] = ["CommentedAPI"]
        self.assert_invalid(commented_declaration, "are not public declarations")

        private_declaration = self.valid_inventory()
        api = private_declaration["features"][0]["public_api"][0]
        api["symbol"] = "PrivateAPI"
        api["source_tokens"] = ["PrivateAPI"]
        self.assert_invalid(private_declaration, "are not public declarations")

    def test_implicit_public_protocol_requirement_and_enum_case_are_supported(self) -> None:
        inventory = self.valid_inventory()
        inventory["features"][0]["public_api"] = [
            {
                "symbol": "FixtureProtocol.protocolRequirement",
                "source_path": "Sources/SwiftQL/Fixture.swift",
                "source_tokens": ["protocolRequirement"],
            },
            {
                "symbol": "FixtureEnum.fixtureCase",
                "source_path": "Sources/SwiftQL/Fixture.swift",
                "source_tokens": ["fixtureCase"],
            },
        ]
        self.validate(inventory)

    def test_generic_operator_declarations_exclude_the_generic_opener(self) -> None:
        source = """
public func +<T>(lhs: T, rhs: T) -> T { lhs }
public func <<T>(lhs: T, rhs: T) -> T { lhs }
public func <=<T>(lhs: T, rhs: T) -> Bool { true }
public static func ??<Wrapped>(lhs: Self, rhs: Wrapped) -> Wrapped { rhs }
"""
        self.assertEqual(
            INVENTORY_TOOL.public_declaration_tokens(source),
            {"+", "<", "<=", "??"},
        )

    def test_compile_fail_layer_and_runner_are_reciprocal(self) -> None:
        missing_runner = self.valid_inventory()
        missing_runner["evidence"][1]["runner_path"] = None
        self.assert_invalid(missing_runner, "if and only if runner_path is non-null")

        runner_on_ordinary_test = self.valid_inventory()
        runner_on_ordinary_test["evidence"][0]["runner_path"] = (
            "scripts/ci/run-compile-fail.sh"
        )
        self.assert_invalid(
            runner_on_ordinary_test, "if and only if runner_path is non-null"
        )

    def test_compile_fail_runner_must_exist_be_executable_and_match_source(self) -> None:
        missing = self.valid_inventory()
        missing["evidence"][1]["runner_path"] = "scripts/ci/missing.sh"
        self.assert_invalid(missing, "does not identify an existing file")

        mismatched_runner = self.make_file(
            "scripts/ci/mismatched-runner.sh",
            "#!/bin/sh\n# Tests/CompileFail/SomeOtherFixture.swift\nexit 0\n",
        )
        mismatched_runner.chmod(0o755)
        mismatched = self.valid_inventory()
        mismatched["evidence"][1]["runner_path"] = (
            "scripts/ci/mismatched-runner.sh"
        )
        self.assert_invalid(mismatched, "does not reference evidence source_path")

        non_executable_runner = self.make_file(
            "scripts/ci/non-executable.sh",
            "#!/bin/sh\n# Tests/CompileFail/Invalid.swift\nexit 0\n",
        )
        non_executable_runner.chmod(0o644)
        non_executable = self.valid_inventory()
        non_executable["evidence"][1]["runner_path"] = (
            "scripts/ci/non-executable.sh"
        )
        self.assert_invalid(non_executable, "runner_path must be executable")

        unstable_id = self.valid_inventory()
        unstable_id["evidence"][1]["test_case"] = "CompileFailTests.testFixture"
        self.assert_invalid(unstable_id, "stable lowercase identifier")

    def test_supported_claim_needs_real_prepare_and_syntax_rendering(self) -> None:
        no_real_prepare = self.valid_inventory()
        no_real_prepare["evidence"][0]["layers"].remove("prepare")
        self.assert_invalid(no_real_prepare, "lacks referenced real-SQLite prepare")

        no_rendering = self.valid_inventory()
        no_rendering["evidence"][0]["layers"].remove("rendering")
        target = no_rendering["features"][1]
        target["evidence_ids"] = ["evidence.real-prepare"]
        self.assert_invalid(no_rendering, "supported syntax but lacks rendering evidence")

    def test_supported_adapter_contract_does_not_require_rendering(self) -> None:
        inventory = self.valid_inventory()
        inventory["evidence"][0]["layers"].remove("rendering")
        target = copy.deepcopy(inventory["features"][1])
        target["id"] = "adapter.fixture-contract"
        target["kind"] = "adapter-contract"
        target["evidence_ids"] = ["evidence.real-prepare"]
        for feature in inventory["features"]:
            if "evidence.render-only" not in feature["evidence_ids"]:
                feature["evidence_ids"].append("evidence.render-only")
        inventory["features"].append(target)
        self.validate(inventory)

    def test_real_sqlite_environment_rules_are_enforced(self) -> None:
        no_environment = self.valid_inventory()
        no_environment["evidence"][0]["environment_ids"] = []
        self.assert_invalid(no_environment, "real SQLite evidence but has no environment_ids")

        invented_environment = self.valid_inventory()
        invented_environment["evidence"][0]["environment_ids"] = ["sqlite-invented"]
        self.assert_invalid(invented_environment, "references unknown environments")

        false_claim = self.valid_inventory()
        false_claim["evidence"][1]["environment_ids"] = ["sqlite-fixture"]
        self.assert_invalid(false_claim, "not real SQLite evidence but has environment_ids")

    def test_reviewed_release_and_source_must_match_an_environment(self) -> None:
        inventory = self.valid_inventory()
        inventory["features"][0]["reviewed_sqlite_source_id"] = "invented source"
        self.assert_invalid(inventory, "is not a recorded environment")

    def test_deferral_and_capability_gates_are_enforced(self) -> None:
        partial = self.valid_inventory()
        partial["features"][0]["status"] = "partial"
        self.assert_invalid(partial, "requires deferral metadata")

        gated = self.valid_inventory()
        feature = gated["features"][0]
        feature["status"] = "capability-gated"
        feature["deferral"] = {
            "blocking_issue": 113,
            "target_milestone": "v2",
            "reason": "The adapter needs a new capability.",
        }
        feature["follow_up_issues"] = [113]
        self.assert_invalid(gated, "required_capabilities is empty")

    def test_deferral_blocker_must_be_a_follow_up(self) -> None:
        inventory = self.valid_inventory()
        feature = inventory["features"][0]
        feature["status"] = "partial"
        feature["deferral"] = {
            "blocking_issue": 113,
            "target_milestone": "v2",
            "reason": "Deferred fixture.",
        }
        self.assert_invalid(inventory, "must include deferral.blocking_issue")

    def test_deferral_blocker_must_not_reference_a_completed_suite(self) -> None:
        inventory = self.valid_inventory()
        feature = inventory["features"][0]
        feature["status"] = "partial"
        feature["follow_up_issues"] = [191]
        feature["deferral"] = {
            "blocking_issue": 191,
            "target_milestone": "v1.4",
            "reason": "A completed suite cannot remain a live blocker.",
        }
        self.assert_invalid(
            inventory,
            "deferral.blocking_issue references completed suite issue #191",
        )

    def test_intentionally_out_of_scope_pair_and_reason_are_enforced(self) -> None:
        inventory = self.valid_inventory()
        feature = inventory["features"][0]
        feature["status"] = "intentionally-unsupported"
        feature["adoption_status"] = "intentionally-out-of-scope"
        self.assert_invalid(inventory, "has no explicit deviation")

        mismatched = self.valid_inventory()
        mismatched_feature = mismatched["features"][0]
        mismatched_feature["status"] = "partial"
        mismatched_feature["adoption_status"] = "intentionally-out-of-scope"
        mismatched_feature["deviations"] = ["Explicit scope exclusion."]
        mismatched_feature["follow_up_issues"] = [113]
        mismatched_feature["deferral"] = {
            "blocking_issue": 113,
            "target_milestone": "v2",
            "reason": "Deferred fixture.",
        }
        self.assert_invalid(mismatched, "must pair intentionally-unsupported")

    def test_non_sqlite_adopted_behavior_is_the_only_nullable_version_exception(self) -> None:
        inventory = self.valid_inventory()
        feature = copy.deepcopy(inventory["features"][0])
        feature["id"] = "behavior.soft-delete.fixture"
        feature["family"] = "adoption"
        feature["kind"] = "adopted-behavior"
        feature["sqlite_documentation_urls"] = []
        feature["not_sqlite_syntax_reason"] = "This is an ORM behavior, not SQLite syntax."
        feature["minimum_sqlite_version"] = None
        feature["provenance"] = [self.provenance()]
        inventory["features"].append(feature)
        self.validate(inventory)

        missing_reason = copy.deepcopy(inventory)
        missing_reason["features"][-1]["not_sqlite_syntax_reason"] = None
        self.assert_invalid(missing_reason, "must cite SQLite documentation")

        wrong_kind = copy.deepcopy(inventory)
        wrong_kind["features"][-1]["kind"] = "syntax"
        self.assert_invalid(wrong_kind, "must cite SQLite documentation")

    def test_provenance_requires_pinned_license_and_notice_for_copied_material(self) -> None:
        inventory = self.valid_inventory()
        feature = inventory["features"][0]
        feature["kind"] = "adopted-behavior"
        feature["provenance"] = [self.provenance()]
        feature["provenance"][0]["license_file_url"] = "https://example.com/LICENSE"
        self.assert_invalid(inventory, "must pin the provenance commit")

        copied = self.valid_inventory()
        feature = copied["features"][0]
        feature["kind"] = "adopted-behavior"
        feature["provenance"] = [self.provenance()]
        feature["provenance"][0]["copied_material"] = True
        self.assert_invalid(copied, "notice_path is required")

    def test_source_paths_must_exist_and_public_api_must_be_under_sources(self) -> None:
        missing = self.valid_inventory()
        missing["evidence"][0]["source_path"] = "Tests/Missing.swift"
        self.assert_invalid(missing, "does not identify an existing file")

        wrong_tree = self.valid_inventory()
        wrong_tree["features"][0]["public_api"][0]["source_path"] = "Tests/FixtureTests.swift"
        self.assert_invalid(wrong_tree, "must identify a Swift file under Sources")

        traversal = self.valid_inventory()
        traversal["evidence"][0]["source_path"] = "../outside.swift"
        self.assert_invalid(traversal, "must stay within the repository")

    def test_suite_snapshot_status_and_evidence_rules_are_enforced(self) -> None:
        planned_claim = self.valid_inventory()
        planned_suite = next(
            suite for suite in planned_claim["suites"] if suite["issue"] == 256
        )
        planned_suite["evidence_ids"] = ["evidence.real-prepare"]
        self.assert_invalid(planned_claim, "planned and must not claim suite evidence")

        incomplete = self.valid_inventory()
        incomplete["suites"][1]["evidence_ids"] = []
        self.assert_invalid(incomplete, "completed and must register non-empty")

        wrong_snapshot_status = self.valid_inventory()
        combinatorial_suite = next(
            suite
            for suite in wrong_snapshot_status["suites"]
            if suite["issue"] == 191
        )
        combinatorial_suite["status"] = "planned"
        self.assert_invalid(
            wrong_snapshot_status,
            "must be 'completed' for issue #191",
        )

        incomplete_northwind = self.valid_inventory()
        northwind_suite = next(
            suite
            for suite in incomplete_northwind["suites"]
            if suite["issue"] == 254
        )
        northwind_suite["evidence_ids"] = []
        self.assert_invalid(
            incomplete_northwind,
            "completed and must register non-empty case_ids and evidence_ids",
        )

    def test_all_required_syntax_families_are_enforced(self) -> None:
        inventory = self.valid_inventory()
        inventory["features"] = [
            feature for feature in inventory["features"] if feature["family"] != "ddl"
        ]
        inventory["suites"][0]["case_ids"] = [
            case_id
            for case_id in inventory["suites"][0]["case_ids"]
            if case_id != "syntax.ddl.fixture"
        ]
        inventory["suites"][2]["case_ids"] = [inventory["features"][-1]["id"]]
        self.assert_invalid(inventory, "missing required syntax families: ddl")


if __name__ == "__main__":
    unittest.main()
