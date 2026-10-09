#!/usr/bin/env python3
"""Fail closed when SwiftQLCore crosses the GRDB- and Combine-free contract boundary.

SwiftPM plans build directories for unrelated root-package targets even when
`--target SwiftQLCore` is used. The compile check therefore copies the exact
core Swift sources into a generated dependency-free package before building.

The query modules above the core keep the same boundary (issue #790): none of
SwiftQLQuery, SwiftQLRuntime, or SwiftQLSQLite imports GRDB or CSQLite, only
SwiftQLRuntime imports Combine or OpenCombine, and the package graph gives the
SwiftQLSQLite product no path to GRDB, so a client of it never builds GRDB.
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
    # Issue #790: the query surface, the runtime, and SQLite's surface and
    # runtime. A model or query file imports SwiftQLSQLite and nothing of GRDB.
    "Sources/SwiftQLQuery",
    "Sources/SwiftQLRuntime",
    "Sources/SwiftQLSQLite",
    "Tests/SwiftQLCoreTests",
    # Issue #682: the driver double that backs `XLDriverDatabase` must reach
    # SwiftQL through the driver contract alone.
    "Tests/SwiftQLDriverDatabaseTests",
    # Issue #702: a client opens a GRDB-backed database, registers a function,
    # and runs queries through SwiftQL without importing GRDB.
    "Tests/SwiftQLGRDBFreeClientTests",
)
# Test targets that prove what a client needs, and the one target each may
# depend on. The driver double needs only SwiftQLSQLite, the syntax and
# runtime with no GRDB driver (issues #682 and #790); the GRDB-free client
# opens a GRDB database through SwiftQL (issue #702).
SINGLE_DEPENDENCY_TEST_TARGETS = {
    "SwiftQLDriverDatabaseTests": "SwiftQLSQLite",
    "SwiftQLGRDBFreeClientTests": "SwiftQL",
}
# Test targets built without package access, so the compiler hides the
# package's `package` declarations from them, as it does from a client
# (issue #113). The GRDB driver's types are `package`, so without this the
# GRDB-free client could reach them.
NO_PACKAGE_ACCESS_TEST_TARGETS = (
    "SwiftQLGRDBFreeClientTests",
)
# Issue #790: the SwiftQLSQLite product, and every target it reaches, has no
# path to these products, so a client of it never resolves them into its
# build. The graph is read from `swift package describe`.
GRDB_FREE_PRODUCTS = ("SwiftQLQuery", "SwiftQLRuntime", "SwiftQLSQLite")
GRDB_PRODUCTS = frozenset(("GRDB", "GRDBSQLite"))
# The only packages whose products those targets may depend on: swift-syntax
# for the macros, and OpenCombine for the runtime's bridges on Linux. A
# product of any other package could bring GRDB in transitively, so it fails
# the check until it is reviewed and listed here.
GRDB_FREE_PRODUCT_PACKAGES = frozenset(("swift-syntax", "OpenCombine"))
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
# The kinds of reference a source root may make anyway. SwiftQLRuntime holds
# the Combine/OpenCombine bridges over the runtime contracts, so it is the one
# query module that imports Combine (issue #790, decision D8).
ROOT_ALLOWED_KINDS = {
    "Sources/SwiftQLRuntime": frozenset((
        "forbidden Combine import",
        "forbidden Combine availability check",
    )),
}
# SwiftQL's GRDB escape hatch (issue #702). A file that declares it reaches
# GRDB's types through SwiftQL without importing GRDB, and members of those
# types resolve without the import, so the patterns above would not see it.
SPI_FORBIDDEN_PATTERN = re.compile(r"@_spi[ \t]*\([ \t]*GRDB[ \t]*\)")
# Patterns forbidden in one source root only. The GRDB-free client target
# proves what a client of SwiftQL's public API needs, so it may not reach
# SwiftQL's internals, whose GRDB-typed values it could then use without an
# import (issue #702). The driver tests need `@testable` and keep it.
# The target is also built without package access (issue #113), so the
# compiler hides SwiftQL's `package` symbols from it.
ROOT_FORBIDDEN_PATTERNS = {
    "Tests/SwiftQLGRDBFreeClientTests": (
        (
            # Any SwiftQL module but the core: SwiftQL, or a module it
            # re-exports, whose internals include the GRDB driver's or reach
            # it (issue #790).
            re.compile(r"@testable[ \t]+(?:[A-Za-z_@()]+[ \t]+)*import[ \t]+SwiftQL(?!Core\b)[A-Za-z0-9_]*\b"),
            "forbidden testable SwiftQL import",
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


def check_package_access(swift, package_root):
    """Each target in NO_PACKAGE_ACCESS_TEST_TARGETS keeps `packageAccess:
    false` in Package.swift (issue #113). `swift package describe` does not
    report the setting, so the manifest is read with `dump-package`. The same
    manifest names the package of every product dependency, which the
    GRDB-free products are checked against (issue #790)."""
    output = run_swift(
        (swift, "package", "dump-package"),
        package_root,
        "swift package dump-package",
    )
    try:
        manifest = json.loads(output)
    except (TypeError, ValueError) as error:
        raise BoundaryCheckError(
            "swift package dump-package did not return valid JSON"
        ) from error
    targets = manifest.get("targets") if isinstance(manifest, dict) else None
    if not isinstance(targets, list):
        raise BoundaryCheckError("the dumped manifest is missing its targets array")
    for name in NO_PACKAGE_ACCESS_TEST_TARGETS:
        matching = [
            target
            for target in targets
            if isinstance(target, dict) and target.get("name") == name
        ]
        if len(matching) != 1:
            raise BoundaryCheckError(
                "the manifest must contain exactly one {} target; found {}".format(
                    name, len(matching)
                )
            )
        if matching[0].get("packageAccess") is not False:
            raise BoundaryCheckError(
                "{} must be built with packageAccess: false, so the package's "
                "`package` declarations stay hidden from it; found {}".format(
                    name, json.dumps(matching[0].get("packageAccess"))
                )
            )

    check_grdb_free_product_packages(targets)


def check_grdb_free_product_packages(manifest_targets):
    """Every product dependency of a target that GRDB_FREE_PRODUCTS reach
    comes from a package in GRDB_FREE_PRODUCT_PACKAGES (issue #790)."""
    by_name = {
        target.get("name"): target
        for target in manifest_targets
        if isinstance(target, dict)
    }
    for product_name in GRDB_FREE_PRODUCTS:
        pending = [product_name]
        reached = set()
        while pending:
            name = pending.pop()
            if name in reached:
                continue
            reached.add(name)
            for dependency in by_name[name].get("dependencies", []):
                if not isinstance(dependency, dict):
                    continue
                if "product" in dependency:
                    product, package = dependency["product"][0], dependency["product"][1]
                    if package not in GRDB_FREE_PRODUCT_PACKAGES:
                        raise BoundaryCheckError(
                            "the {} product reaches {}, which depends on product {} of package {}; "
                            "only {} may be reached".format(
                                product_name, name, product, package,
                                ", ".join(sorted(GRDB_FREE_PRODUCT_PACKAGES)),
                            )
                        )
                if "target" in dependency:
                    pending.append(dependency["target"][0])
                if "byName" in dependency:
                    dependency_name = dependency["byName"][0]
                    if dependency_name not in by_name:
                        raise BoundaryCheckError(
                            "the {} product reaches {}, which depends on {} by name, "
                            "a product rather than a target of this package; name it "
                            "with .product(name:package:) so its package can be checked".format(
                                product_name, name, dependency_name
                            )
                        )
                    pending.append(dependency_name)


def check_grdb_free_products(targets, products):
    """No target that a product in GRDB_FREE_PRODUCTS reaches depends on a
    GRDB product (issue #790)."""
    by_name = {
        target.get("name"): target
        for target in targets
        if isinstance(target, dict)
    }
    for product_name in GRDB_FREE_PRODUCTS:
        matching = [
            product
            for product in products
            if isinstance(product, dict) and product.get("name") == product_name
        ]
        if len(matching) != 1 or matching[0].get("targets") != [product_name]:
            raise BoundaryCheckError(
                "package description must export a {} product of the {} target alone".format(
                    product_name, product_name
                )
            )
        pending = [product_name]
        reached = set()
        while pending:
            name = pending.pop()
            if name in reached:
                continue
            reached.add(name)
            target = by_name.get(name)
            if target is None:
                raise BoundaryCheckError(
                    "{} reaches an unknown target {}".format(product_name, name)
                )
            grdb = sorted(GRDB_PRODUCTS.intersection(target.get("product_dependencies", [])))
            if grdb:
                raise BoundaryCheckError(
                    "the {} product reaches {}, which depends on {}; it must not reach GRDB".format(
                        product_name, name, ", ".join(grdb)
                    )
                )
            pending.extend(target.get("target_dependencies", []))


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

    for name, dependency in SINGLE_DEPENDENCY_TEST_TARGETS.items():
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
            "target_dependencies": [dependency],
            "product_dependencies": [],
        }:
            raise BoundaryCheckError(
                "{} must depend on the {} target alone; found {}".format(
                    name,
                    dependency,
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

    check_grdb_free_products(targets, products)


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

            allowed = ROOT_ALLOWED_KINDS.get(source_root_name, frozenset())
            for line_number, line in enumerate(lines, start=1):
                for kind in forbidden_reference_kinds(line):
                    if kind in allowed:
                        continue
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
            "{}; {} reach no GRDB product)".format(
                ", ".join(
                    "{} depends on {} alone".format(name, dependency)
                    for name, dependency in SINGLE_DEPENDENCY_TEST_TARGETS.items()
                ),
                ", ".join(GRDB_FREE_PRODUCTS),
            )
        )
        check_package_access(swift, package_root)
        print(
            "CHECK package access: PASS ({} built with packageAccess: false; "
            "{} reach products of {} only)".format(
                ", ".join(NO_PACKAGE_ACCESS_TEST_TARGETS),
                ", ".join(GRDB_FREE_PRODUCTS),
                ", ".join(sorted(GRDB_FREE_PRODUCT_PACKAGES)),
            )
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
