#!/usr/bin/env python3
"""Fail closed when SwiftQLCore crosses the GRDB- and Combine-free contract boundary.

SwiftPM plans build directories for unrelated root-package targets even when
`--target SwiftQLCore` is used. The compile check therefore copies the exact
core Swift sources into a generated dependency-free package before building.
"""

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


TARGET_NAME = "SwiftQLCore"
SOURCE_ROOTS = (
    "Sources/SwiftQLCore",
    "Tests/SwiftQLCoreTests",
    # Issue #682: the driver double that backs `XLDriverDatabase` must reach
    # SwiftQL through the driver contract alone.
    "Tests/SwiftQLDriverDatabaseTests",
    # Issue #702: a client opens a GRDB-backed database, registers a function,
    # and runs queries through SwiftQL without importing GRDB.
    "Tests/SwiftQLGRDBFreeClientTests",
)
# Test targets that prove a client needs only SwiftQL: they may depend on the
# SwiftQL target and nothing else (issues #682 and #702).
SWIFTQL_ONLY_TEST_TARGETS = (
    "SwiftQLDriverDatabaseTests",
    "SwiftQLGRDBFreeClientTests",
)
DEPENDENCY_FIELDS = (
    "target_dependencies",
    "product_dependencies",
)
FORBIDDEN_MODULE_PATTERN = r"(?:GRDB|GRDBSQLite|CSQLite)"
# An import may carry attributes and an access level (`internal import GRDB`,
# issue #702), and any module whose name starts with GRDB is forbidden.
IMPORT_PREFIX_PATTERN = (
    r"^[ \t]*(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^)]*\))?[ \t]+)*"
    r"(?:(?:public|package|internal|fileprivate|private)[ \t]+)?"
    r"import[ \t]+(?:(?:class|enum|func|let|protocol|struct|typealias|var)[ \t]+)?"
)
IMPORT_FORBIDDEN_PATTERN = re.compile(
    IMPORT_PREFIX_PATTERN + r"(?:GRDB[A-Za-z0-9_]*|CSQLite)(?:\b|\.)"
)
CAN_IMPORT_FORBIDDEN_PATTERN = re.compile(
    r"\bcanImport[ \t]*\([ \t]*" + FORBIDDEN_MODULE_PATTERN + r"[ \t]*\)"
)
QUALIFIED_FORBIDDEN_PATTERN = re.compile(
    r"\b" + FORBIDDEN_MODULE_PATTERN + r"[ \t]*\."
)
# The core is also free of Combine (issue #684): live queries cross the
# contract as `AsyncThrowingStream`, and the Combine surface is a leaf adapter
# in SwiftQL. Only imports and availability checks are matched, because the
# word "Combine" is ordinary prose in a comment. A module name that starts
# with either one, such as OpenCombineDispatch or OpenCombineFoundation, is
# matched too.
OBSERVATION_FRAMEWORK_PATTERN = r"(?:Combine|OpenCombine)[A-Za-z0-9_]*"
IMPORT_OBSERVATION_FRAMEWORK_PATTERN = re.compile(
    IMPORT_PREFIX_PATTERN + OBSERVATION_FRAMEWORK_PATTERN + r"(?:\b|\.)"
)
CAN_IMPORT_OBSERVATION_FRAMEWORK_PATTERN = re.compile(
    r"\bcanImport[ \t]*\([ \t]*" + OBSERVATION_FRAMEWORK_PATTERN + r"[ \t]*\)"
)
# SwiftQL's GRDB escape hatch (issue #702). A file that declares it reaches
# GRDB's types through SwiftQL without importing GRDB, and members of those
# types resolve without the import, so the patterns above would not see it.
SPI_FORBIDDEN_PATTERN = re.compile(r"@_spi[ \t]*\([ \t]*GRDB[ \t]*\)")
# Patterns forbidden in one source root only. The GRDB-free client target
# proves what a client of SwiftQL's public API needs, so it may not reach
# SwiftQL's internals, whose GRDB-typed values it could then use without an
# import (issue #702). The driver tests need `@testable` and keep it.
# The GRDB driver's types and `GRDBDatabase.driver` are `package` (issue
# #113), which every target in the package can reach without `@testable`,
# so the client target may not name them either.
ROOT_FORBIDDEN_PATTERNS = {
    "Tests/SwiftQLGRDBFreeClientTests": (
        (
            re.compile(r"@testable[ \t]+(?:[A-Za-z_@()]+[ \t]+)*import[ \t]+SwiftQL\b(?!Core)"),
            "forbidden testable SwiftQL import",
        ),
        (
            re.compile(
                r"\bGRDB(?:DatabaseDriver|DatabaseDriverConnection|RowHandle"
                r"|PhysicalStatement|RequestPhaseProbe|RequestPhaseConnection)\b"
                r"|\.driver\b"
            ),
            "forbidden package GRDB driver reference",
        ),
    ),
}
DETECTOR_FIXTURES = (
    "import GRDB",
    "@_spi(GRDB) import SwiftQL",
    "@_spi(GRDB) @testable import SwiftQL",
    "internal import GRDB",
    "public import GRDB",
    "package import GRDB",
    "@preconcurrency internal import GRDB",
    "import GRDBSQLite",
    "let code = GRDBSQLite.SQLITE_OK",
    "internal import Combine",
    "import struct GRDB.Row",
    "@preconcurrency import GRDB",
    "@_implementationOnly import GRDB",
    "@_exported import CSQLite",
    "#if canImport(GRDB)",
    "let row: GRDB.Row",
    "let code = CSQLite.SQLITE_OK",
    "import Combine",
    "@preconcurrency import OpenCombine",
    "import struct Combine.AnyPublisher",
    "#if canImport(Combine)",
    "import OpenCombineDispatch",
    "#elseif canImport(OpenCombineFoundation)",
)
# Lines the detector must leave alone: prose that names a forbidden framework.
DETECTOR_NEGATIVE_FIXTURES = (
    "/// Neither Combine nor OpenCombine is needed to conform.",
    "// The Combine surface is a leaf adapter.",
)
RESOLUTION_ONLY_DIRECTORIES = frozenset(("checkouts", "repositories"))
ISOLATED_PACKAGE_MANIFEST = """// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftQLCoreBoundaryBuild",
    // Mirrors the real package's floor. Without it the isolated build defaults
    // to macOS 10.13 and rejects `Regex`, which is macOS 13 or newer, so the
    // check passes only on Linux where the annotation does not apply.
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "SwiftQLCore", targets: ["SwiftQLCore"]),
    ],
    targets: [
        .target(name: "SwiftQLCore"),
    ]
)
"""


class BoundaryCheckError(Exception):
    """A deterministic contract-boundary failure."""


def run_swift(command, package_root, label):
    environment = os.environ.copy()
    environment["LANG"] = "C"
    environment["LC_ALL"] = "C"

    try:
        result = subprocess.run(
            command,
            cwd=str(package_root),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            encoding="utf-8",
            errors="replace",
            env=environment,
            check=False,
        )
    except OSError as error:
        raise BoundaryCheckError(
            "{} could not start: {}".format(label, error)
        ) from error

    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip()
        message = "{} failed with exit code {}".format(label, result.returncode)
        if detail:
            message = "{}:\n{}".format(message, detail)
        raise BoundaryCheckError(message)

    return result.stdout


def check_package_dependencies(swift, package_root):
    output = run_swift(
        (swift, "package", "describe", "--type", "json"),
        package_root,
        "swift package describe --type json",
    )

    try:
        description = json.loads(output)
    except (TypeError, ValueError) as error:
        raise BoundaryCheckError(
            "swift package describe did not return valid JSON"
        ) from error

    targets = description.get("targets") if isinstance(description, dict) else None
    if not isinstance(targets, list):
        raise BoundaryCheckError(
            "package description is missing its targets array"
        )

    matching_targets = [
        target
        for target in targets
        if isinstance(target, dict) and target.get("name") == TARGET_NAME
    ]
    if len(matching_targets) != 1:
        raise BoundaryCheckError(
            "package description must contain exactly one {} target; found {}".format(
                TARGET_NAME,
                len(matching_targets),
            )
        )

    target = matching_targets[0]
    dependency_failures = []
    for field in DEPENDENCY_FIELDS:
        if field not in target:
            # SwiftPM omits these keys when their arrays are empty.
            continue
        dependencies = target[field]
        if not isinstance(dependencies, list):
            raise BoundaryCheckError(
                "{}.{} must be an array when present".format(TARGET_NAME, field)
            )
        if dependencies:
            dependency_failures.append(
                "{}={}".format(
                    field,
                    json.dumps(dependencies, sort_keys=True, separators=(",", ":")),
                )
            )

    if dependency_failures:
        raise BoundaryCheckError(
            "{} must have no target or product dependencies; found {}".format(
                TARGET_NAME,
                "; ".join(sorted(dependency_failures)),
            )
        )

    for name in SWIFTQL_ONLY_TEST_TARGETS:
        matching = [
            target
            for target in targets
            if isinstance(target, dict) and target.get("name") == name
        ]
        if len(matching) != 1:
            raise BoundaryCheckError(
                "package description must contain exactly one {} target; found {}".format(
                    name,
                    len(matching),
                )
            )
        dependencies = {
            field: matching[0].get(field, [])
            for field in DEPENDENCY_FIELDS
        }
        if dependencies != {
            "target_dependencies": ["SwiftQL"],
            "product_dependencies": [],
        }:
            raise BoundaryCheckError(
                "{} must depend on the SwiftQL target alone; found {}".format(
                    name,
                    json.dumps(dependencies, sort_keys=True, separators=(",", ":")),
                )
            )

    products = description.get("products")
    if not isinstance(products, list):
        raise BoundaryCheckError(
            "package description is missing its products array"
        )
    matching_products = [
        product
        for product in products
        if isinstance(product, dict) and product.get("name") == TARGET_NAME
    ]
    if len(matching_products) != 1:
        raise BoundaryCheckError(
            "package description must export exactly one {} product; found {}".format(
                TARGET_NAME,
                len(matching_products),
            )
        )
    product = matching_products[0]
    if product.get("targets") != [TARGET_NAME] or not isinstance(
        product.get("type", {}).get("library"),
        list,
    ):
        raise BoundaryCheckError(
            "{} must be a library product containing only the {} target".format(
                TARGET_NAME,
                TARGET_NAME,
            )
        )


def forbidden_reference_kinds(line):
    kinds = []
    if IMPORT_FORBIDDEN_PATTERN.search(line):
        kinds.append("forbidden database-module import")
    if CAN_IMPORT_FORBIDDEN_PATTERN.search(line):
        kinds.append("forbidden database-module availability check")
    if QUALIFIED_FORBIDDEN_PATTERN.search(line):
        kinds.append("forbidden database-module qualified symbol")
    if SPI_FORBIDDEN_PATTERN.search(line):
        kinds.append("forbidden GRDB SPI import")
    if IMPORT_OBSERVATION_FRAMEWORK_PATTERN.search(line):
        kinds.append("forbidden Combine import")
    if CAN_IMPORT_OBSERVATION_FRAMEWORK_PATTERN.search(line):
        kinds.append("forbidden Combine availability check")
    return kinds


def check_detector_fixtures():
    missed = [
        fixture
        for fixture in DETECTOR_FIXTURES
        if not forbidden_reference_kinds(fixture)
    ]
    if missed:
        raise BoundaryCheckError(
            "internal source-reference detector missed fixtures: {}".format(
                ", ".join(repr(item) for item in missed)
            )
        )
    flagged = [
        fixture
        for fixture in DETECTOR_NEGATIVE_FIXTURES
        if forbidden_reference_kinds(fixture)
    ]
    if flagged:
        raise BoundaryCheckError(
            "internal source-reference detector flagged prose: {}".format(
                ", ".join(repr(item) for item in flagged)
            )
        )


def check_source_references(package_root):
    violations = []
    scanned_file_count = 0
    core_source_files = []

    for source_root_name in SOURCE_ROOTS:
        source_root = package_root / source_root_name
        if not source_root.is_dir():
            raise BoundaryCheckError(
                "required source root is missing: {}".format(source_root_name)
            )

        source_files = sorted(
            path for path in source_root.rglob("*.swift") if path.is_file()
        )
        if not source_files:
            raise BoundaryCheckError(
                "required source root contains no Swift files: {}".format(
                    source_root_name
                )
            )

        scanned_file_count += len(source_files)
        if source_root_name == "Sources/SwiftQLCore":
            core_source_files = source_files
        for source_file in source_files:
            relative_path = source_file.relative_to(package_root).as_posix()
            try:
                lines = source_file.read_text(encoding="utf-8").splitlines()
            except (OSError, UnicodeError) as error:
                raise BoundaryCheckError(
                    "could not read {}: {}".format(relative_path, error)
                ) from error

            for line_number, line in enumerate(lines, start=1):
                for kind in forbidden_reference_kinds(line):
                    violations.append(
                        (relative_path, line_number, kind)
                    )
                for pattern, kind in ROOT_FORBIDDEN_PATTERNS.get(source_root_name, ()):
                    if pattern.search(line):
                        violations.append(
                            (relative_path, line_number, kind)
                        )

    if violations:
        formatted = [
            "{}:{} ({})".format(path, line_number, kind)
            for path, line_number, kind in sorted(set(violations))
        ]
        raise BoundaryCheckError(
            "GRDB, CSQLite, and Combine references are forbidden in the core boundary:\n{}".format(
                "\n".join("- {}".format(item) for item in formatted)
            )
        )

    return scanned_file_count, core_source_files


def is_forbidden_artifact(name):
    return (
        name == "GRDB.build"
        or name == "GRDB.swiftmodule"
        or "CSQLite" in name
    )


def find_forbidden_artifacts(scratch_path):
    violations = set()

    for current_root, directory_names, file_names in os.walk(str(scratch_path)):
        current_path = Path(current_root)
        directory_names.sort()
        file_names.sort()

        retained_directories = []
        for directory_name in directory_names:
            if directory_name in RESOLUTION_ONLY_DIRECTORIES:
                continue

            relative_path = (current_path / directory_name).relative_to(scratch_path)
            if is_forbidden_artifact(directory_name):
                violations.add(relative_path.as_posix())
                continue
            retained_directories.append(directory_name)
        directory_names[:] = retained_directories

        for file_name in file_names:
            if is_forbidden_artifact(file_name):
                relative_path = (current_path / file_name).relative_to(scratch_path)
                violations.add(relative_path.as_posix())

    return sorted(violations)


def prepare_scratch_path(requested_path):
    if requested_path is None:
        temporary_directory = tempfile.TemporaryDirectory(
            prefix="swiftql-core-boundary-"
        )
        return Path(temporary_directory.name), temporary_directory

    scratch_path = Path(requested_path).expanduser().resolve()
    try:
        if scratch_path.exists():
            if not scratch_path.is_dir():
                raise BoundaryCheckError(
                    "scratch path is not a directory: {}".format(scratch_path)
                )
            if next(scratch_path.iterdir(), None) is not None:
                raise BoundaryCheckError(
                    "scratch path must be fresh and empty: {}".format(scratch_path)
                )
        else:
            scratch_path.mkdir(parents=True)
    except OSError as error:
        raise BoundaryCheckError(
            "could not prepare scratch path {}: {}".format(scratch_path, error)
        ) from error

    return scratch_path, None


def create_isolated_package(package_root, scratch_path, core_source_files):
    isolated_package = scratch_path / "isolated-package"
    isolated_sources = isolated_package / "Sources" / TARGET_NAME

    try:
        isolated_sources.mkdir(parents=True)
        (isolated_package / "Package.swift").write_text(
            ISOLATED_PACKAGE_MANIFEST,
            encoding="utf-8",
        )

        source_root = package_root / "Sources" / TARGET_NAME
        for source_file in core_source_files:
            relative_path = source_file.relative_to(source_root)
            destination = isolated_sources / relative_path
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(str(source_file), str(destination))
    except (OSError, ValueError) as error:
        raise BoundaryCheckError(
            "could not create isolated SwiftQLCore package: {}".format(error)
        ) from error

    return isolated_package


def check_isolated_build(
    swift,
    package_root,
    scratch_path,
    core_source_files,
):
    isolated_package = create_isolated_package(
        package_root,
        scratch_path,
        core_source_files,
    )
    build_scratch_path = scratch_path / "swiftpm-build"
    run_swift(
        (
            swift,
            "build",
            "--scratch-path",
            str(build_scratch_path),
            "--target",
            TARGET_NAME,
        ),
        isolated_package,
        "swift build --target {}".format(TARGET_NAME),
    )

    forbidden_artifacts = find_forbidden_artifacts(scratch_path)
    if forbidden_artifacts:
        raise BoundaryCheckError(
            "isolated {} build produced forbidden artifacts:\n{}".format(
                TARGET_NAME,
                "\n".join(
                    "- {}".format(path) for path in forbidden_artifacts
                ),
            )
        )


def parse_arguments():
    parser = argparse.ArgumentParser(
        description="Enforce the GRDB-free SwiftQLCore contract boundary."
    )
    parser.add_argument(
        "--scratch-path",
        help="Fresh, empty SwiftPM scratch path (a temporary path is used by default).",
    )
    return parser.parse_args()


def main():
    arguments = parse_arguments()
    package_root = Path(__file__).resolve().parents[2]
    if not (package_root / "Package.swift").is_file():
        print(
            "SwiftQLCore boundary check: FAIL\n"
            "package root does not contain Package.swift: {}".format(package_root),
            file=sys.stderr,
        )
        return 1

    swift = shutil.which("swift")
    if swift is None:
        print(
            "SwiftQLCore boundary check: FAIL\n"
            "Swift executable was not found on PATH",
            file=sys.stderr,
        )
        return 1

    temporary_directory = None
    try:
        check_detector_fixtures()
        check_package_dependencies(swift, package_root)
        print(
            "CHECK package graph: PASS "
            "(SwiftQLCore product exported; target/product dependencies: none; "
            "{} depend on SwiftQL alone)".format(", ".join(SWIFTQL_ONLY_TEST_TARGETS))
        )

        scanned_file_count, core_source_files = check_source_references(
            package_root
        )
        print(
            "CHECK database-module source references: PASS ({} Swift files)".format(
                scanned_file_count
            )
        )

        scratch_path, temporary_directory = prepare_scratch_path(
            arguments.scratch_path
        )
        print(
            "INFO isolated build: generated dependency-free Swift 5.9 package "
            "avoids unrelated root-package planning artifacts"
        )
        check_isolated_build(
            swift,
            package_root,
            scratch_path,
            core_source_files,
        )
        print(
            "CHECK isolated SwiftQLCore build: PASS "
            "(GRDB/CSQLite artifacts: none)"
        )
    except BoundaryCheckError as error:
        print("SwiftQLCore boundary check: FAIL", file=sys.stderr)
        print(str(error), file=sys.stderr)
        return 1
    finally:
        if temporary_directory is not None:
            temporary_directory.cleanup()

    print("SwiftQLCore boundary check: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
