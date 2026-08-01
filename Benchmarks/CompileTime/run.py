#!/usr/bin/env python3
"""Generate and measure SwiftQL's consumer compile-time scalability matrix.

The harness writes isolated downstream consumer packages whose table and query
declaration counts scale independently, then measures each consumer's build in
its own process. It records whole-consumer cost. It never attributes a share of
a whole-build measurement to macro expansion.
"""

from __future__ import annotations

import argparse
import dataclasses
import datetime as dt
import hashlib
import json
import math
import os
import platform
import re
import shlex
import shutil
import statistics
import subprocess
import sys
import time
from pathlib import Path
from typing import Callable, Sequence


SCRIPT_DIRECTORY = Path(__file__).resolve().parent
CONSUMER_TEMPLATE_DIRECTORY = SCRIPT_DIRECTORY / "Consumers"

REPORT_FORMAT_VERSION = 1
CANONICAL_SCALES = (1, 10, 100, 500)
BASELINE_TABLE_COUNT = 1
BASELINE_QUERY_COUNT = 1
BUILD_MODES = (
    "clean_dependency_warm",
    "noop_incremental",
    "one_query_edit",
)
DEFAULT_REPETITION_COUNT = 3
BUILD_CONFIGURATION = "debug"
PRODUCT_NAME = "ConsumerLibrary"
TARGET_NAME = "Consumer"
BASE_EDIT_TOKEN = "base"

# Every consumer declares the same six-column shape so the compared
# declarations differ in API, not in width or nullability.
COLUMNS: tuple[tuple[str, str, str], ...] = (
    # (swift property, sqlite column, sqlite declared type)
    ("id", "id", "INTEGER"),
    ("name", "name", "TEXT"),
    ("category", "category", "TEXT"),
    ("quantity", "quantity", "INTEGER"),
    ("weight", "weight", "REAL"),
    ("note", "note", "TEXT"),
)
SWIFT_TYPES = {
    "id": "Int",
    "name": "String",
    "category": "String",
    "quantity": "Int",
    "weight": "Double",
    "note": "String?",
}
NULLABLE_PROPERTIES = frozenset({"note"})


class HarnessError(RuntimeError):
    """A benchmark precondition or subprocess failed."""


# --------------------------------------------------------------------------
# Consumer specifications
# --------------------------------------------------------------------------


@dataclasses.dataclass(frozen=True)
class ConsumerSpec:
    identifier: str
    template_name: str
    requires_swiftql_checkout: bool
    scales_query_declarations: bool
    generator: str
    applicability_note: str

    @property
    def build_modes(self) -> tuple[str, ...]:
        if self.scales_query_declarations:
            return BUILD_MODES
        return tuple(mode for mode in BUILD_MODES if mode != "one_query_edit")

    @property
    def query_axis_status(self) -> str:
        return "applicable" if self.scales_query_declarations else "not_applicable"


CONSUMER_SPECS: tuple[ConsumerSpec, ...] = (
    ConsumerSpec(
        identifier="control_raw_sqlite",
        template_name="ControlRawSQLite",
        requires_swiftql_checkout=False,
        scales_query_declarations=True,
        generator="control_raw_sqlite",
        applicability_note=(
            "Dependency-free control: hand-written structs, hand-written SQL "
            "text, and hand-written sqlite3 C stepping and column mapping."
        ),
    ),
    ConsumerSpec(
        identifier="swiftql",
        template_name="SwiftQL",
        requires_swiftql_checkout=True,
        scales_query_declarations=True,
        generator="swiftql",
        applicability_note=(
            "@SQLTable declarations and @SQLQuery specification functions on a "
            "GRDBDatabase extension."
        ),
    ),
    ConsumerSpec(
        identifier="grdb",
        template_name="GRDB",
        requires_swiftql_checkout=False,
        scales_query_declarations=True,
        generator="grdb",
        applicability_note=(
            "Codable FetchableRecord/TableRecord structs and query-interface "
            "request functions."
        ),
    ),
    ConsumerSpec(
        identifier="sqlite_swift",
        template_name="SQLiteSwift",
        requires_swiftql_checkout=False,
        scales_query_declarations=True,
        generator="sqlite_swift",
        applicability_note=(
            "Table/Expression declarations and typed query functions that map "
            "each row explicitly."
        ),
    ),
    ConsumerSpec(
        identifier="lighter",
        template_name="Lighter",
        requires_swiftql_checkout=False,
        scales_query_declarations=False,
        generator="lighter",
        applicability_note=(
            "Lighter has no user-written table or query declarations. Its "
            "Enlighter build-tool plugin emits record types from a schema "
            "file, so the table axis scales schema.sql and the query axis and "
            "the one-query-edit mode do not exist."
        ),
    ),
)

CONSUMERS_BY_IDENTIFIER = {spec.identifier: spec for spec in CONSUMER_SPECS}


# --------------------------------------------------------------------------
# Deterministic source generation
# --------------------------------------------------------------------------


def table_name(index: int) -> str:
    return f"entity_{index}"


def table_type(index: int) -> str:
    return f"Entity{index}"


def query_name(index: int) -> str:
    return f"consumerQuery{index}"


def query_table_index(query_index: int, table_count: int) -> int:
    """Spread queries evenly and deterministically across the declared tables."""

    return (query_index - 1) % table_count + 1


def query_edit_token(query_index: int, edit_token: str) -> str:
    """Only query 1 carries the editable literal; the rest are fixed."""

    return edit_token if query_index == 1 else f"fixed{query_index}"


def create_table_sql(index: int) -> str:
    columns = ", ".join(
        f"{column} {declared}"
        + (" NOT NULL" if swift not in NULLABLE_PROPERTIES else "")
        + (" PRIMARY KEY" if swift == "id" else "")
        for swift, column, declared in COLUMNS
    )
    return f"CREATE TABLE {table_name(index)} ({columns});"


def select_column_list() -> str:
    return ", ".join(column for _, column, _ in COLUMNS)


def generate_control_raw_sqlite(
    table_count: int,
    query_count: int,
    edit_token: str,
) -> dict[str, str]:
    tables = ["import Foundation", ""]
    for index in range(1, table_count + 1):
        properties = "\n".join(
            f"    public var {swift}: {SWIFT_TYPES[swift]}" for swift, _, _ in COLUMNS
        )
        parameters = ", ".join(
            f"{swift}: {SWIFT_TYPES[swift]}" for swift, _, _ in COLUMNS
        )
        assignments = "\n".join(
            f"        self.{swift} = {swift}" for swift, _, _ in COLUMNS
        )
        tables.append(
            f"public struct {table_type(index)}: Sendable {{\n"
            f"{properties}\n\n"
            f"    public init({parameters}) {{\n"
            f"{assignments}\n"
            f"    }}\n"
            f"}}\n\n"
            f"public enum {table_type(index)}SQL {{\n"
            f'    public static let tableName = "{table_name(index)}"\n'
            f"    public static let selectAll =\n"
            f'        "SELECT {select_column_list()} FROM {table_name(index)}"\n'
            f"}}\n"
        )

    queries = ["import Foundation", "import SQLite3", ""]
    for index in range(1, query_count + 1):
        target = query_table_index(index, table_count)
        token = query_edit_token(index, edit_token)
        statement = (
            f"SELECT {select_column_list()} FROM {table_name(target)} "
            f"WHERE name = ? AND category = '{token}'"
        )
        reads = []
        for position, (swift, _, _) in enumerate(COLUMNS):
            if swift in NULLABLE_PROPERTIES:
                reads.append(
                    f"            {swift}: sqlite3_column_type(statement, {position})"
                    f" == SQLITE_NULL\n"
                    f"                ? nil\n"
                    f"                : String(cString: sqlite3_column_text("
                    f"statement, {position}))"
                )
            elif SWIFT_TYPES[swift] == "Int":
                reads.append(
                    f"            {swift}: Int(sqlite3_column_int64("
                    f"statement, {position}))"
                )
            elif SWIFT_TYPES[swift] == "Double":
                reads.append(
                    f"            {swift}: sqlite3_column_double("
                    f"statement, {position})"
                )
            else:
                reads.append(
                    f"            {swift}: String(cString: sqlite3_column_text("
                    f"statement, {position}))"
                )
        joined_reads = ",\n".join(reads)
        queries.append(
            f"public func {query_name(index)}(\n"
            f"    _ handle: OpaquePointer,\n"
            f"    name: String\n"
            f") throws -> [{table_type(target)}] {{\n"
            f"    var statement: OpaquePointer?\n"
            f"    let prepared = sqlite3_prepare_v2(\n"
            f"        handle,\n"
            f'        "{statement}",\n'
            f"        -1,\n"
            f"        &statement,\n"
            f"        nil\n"
            f"    )\n"
            f"    guard prepared == SQLITE_OK else {{\n"
            f"        throw ConsumerError.prepareFailed(prepared)\n"
            f"    }}\n"
            f"    defer {{ sqlite3_finalize(statement) }}\n"
            f"    sqlite3_bind_text(statement, 1, name, -1, "
            f"consumerTransientDestructor)\n"
            f"    var rows: [{table_type(target)}] = []\n"
            f"    while true {{\n"
            f"        let step = sqlite3_step(statement)\n"
            f"        if step == SQLITE_DONE {{ break }}\n"
            f"        guard step == SQLITE_ROW else {{\n"
            f"            throw ConsumerError.stepFailed(step)\n"
            f"        }}\n"
            f"        rows.append({table_type(target)}(\n"
            f"{joined_reads}\n"
            f"        ))\n"
            f"    }}\n"
            f"    return rows\n"
            f"}}\n"
        )

    return {
        "Sources/Consumer/Tables.swift": "\n".join(tables),
        "Sources/Consumer/Queries.swift": "\n".join(queries),
    }


def generate_swiftql(
    table_count: int,
    query_count: int,
    edit_token: str,
) -> dict[str, str]:
    tables = ["import Foundation", "import SwiftQL", ""]
    for index in range(1, table_count + 1):
        properties = "\n".join(
            f"    public var {swift}: {SWIFT_TYPES[swift]}" for swift, _, _ in COLUMNS
        )
        tables.append(
            f'@SQLTable(name: "{table_name(index)}")\n'
            f"public struct {table_type(index)} {{\n"
            f"{properties}\n"
            f"}}\n"
        )

    queries = ["import Foundation", "import SwiftQL", "", "extension GRDBDatabase {", ""]
    for index in range(1, query_count + 1):
        target = query_table_index(index, table_count)
        token = query_edit_token(index, edit_token)
        queries.append(
            f"    @SQLQuery\n"
            f"    public func {query_name(index)}(\n"
            f"        name: String\n"
            f"    ) -> [{table_type(target)}] {{\n"
            f"        sqlResult {{ schema in\n"
            f"            let entity = schema.table({table_type(target)}.self)\n"
            f"            Select(entity)\n"
            f"            From(entity)\n"
            f'            Where(entity.name == name && entity.category == "{token}")\n'
            f"        }}\n"
            f"    }}\n"
        )
    queries.append("}")

    return {
        "Sources/Consumer/Tables.swift": "\n".join(tables),
        "Sources/Consumer/Queries.swift": "\n".join(queries) + "\n",
    }


def generate_grdb(
    table_count: int,
    query_count: int,
    edit_token: str,
) -> dict[str, str]:
    tables = ["import Foundation", "import GRDB", ""]
    for index in range(1, table_count + 1):
        properties = "\n".join(
            f"    public var {swift}: {SWIFT_TYPES[swift]}" for swift, _, _ in COLUMNS
        )
        column_constants = "\n".join(
            f'        public static let {swift} = Column("{column}")'
            for swift, column, _ in COLUMNS
        )
        tables.append(
            f"public struct {table_type(index)}: Codable, FetchableRecord, "
            f"PersistableRecord, Sendable {{\n"
            f'    public static let databaseTableName = "{table_name(index)}"\n\n'
            f"{properties}\n\n"
            f"    public enum Columns {{\n"
            f"{column_constants}\n"
            f"    }}\n"
            f"}}\n"
        )

    queries = ["import Foundation", "import GRDB", ""]
    for index in range(1, query_count + 1):
        target = query_table_index(index, table_count)
        token = query_edit_token(index, edit_token)
        type_name = table_type(target)
        queries.append(
            f"public func {query_name(index)}(\n"
            f"    _ database: Database,\n"
            f"    name: String\n"
            f") throws -> [{type_name}] {{\n"
            f"    try {type_name}\n"
            f"        .filter({type_name}.Columns.name == name)\n"
            f'        .filter({type_name}.Columns.category == "{token}")\n'
            f"        .fetchAll(database)\n"
            f"}}\n"
        )

    return {
        "Sources/Consumer/Tables.swift": "\n".join(tables),
        "Sources/Consumer/Queries.swift": "\n".join(queries),
    }


def generate_sqlite_swift(
    table_count: int,
    query_count: int,
    edit_token: str,
) -> dict[str, str]:
    tables = ["import Foundation", "import SQLite", ""]
    for index in range(1, table_count + 1):
        properties = "\n".join(
            f"    public var {swift}: {SWIFT_TYPES[swift]}" for swift, _, _ in COLUMNS
        )
        parameters = ", ".join(
            f"{swift}: {SWIFT_TYPES[swift]}" for swift, _, _ in COLUMNS
        )
        assignments = "\n".join(
            f"        self.{swift} = {swift}" for swift, _, _ in COLUMNS
        )
        expressions = "\n".join(
            f"    public static let {swift} = "
            f'SQLite.Expression<{SWIFT_TYPES[swift]}>("{column}")'
            for swift, column, _ in COLUMNS
        )
        tables.append(
            f"public struct {table_type(index)}: Sendable {{\n"
            f"{properties}\n\n"
            f"    public init({parameters}) {{\n"
            f"{assignments}\n"
            f"    }}\n"
            f"}}\n\n"
            f"public enum {table_type(index)}Table {{\n"
            f'    public static let table = Table("{table_name(index)}")\n'
            f"{expressions}\n"
            f"}}\n"
        )

    queries = ["import Foundation", "import SQLite", ""]
    for index in range(1, query_count + 1):
        target = query_table_index(index, table_count)
        token = query_edit_token(index, edit_token)
        type_name = table_type(target)
        reads = ",\n".join(
            f"            {swift}: row[{type_name}Table.{swift}]"
            for swift, _, _ in COLUMNS
        )
        queries.append(
            f"public func {query_name(index)}(\n"
            f"    _ connection: Connection,\n"
            f"    name: String\n"
            f") throws -> [{type_name}] {{\n"
            f"    let query = {type_name}Table.table\n"
            f"        .filter({type_name}Table.name == name)\n"
            f'        .filter({type_name}Table.category == "{token}")\n'
            f"    return try connection.prepare(query).map {{ row in\n"
            f"        {type_name}(\n"
            f"{reads}\n"
            f"        )\n"
            f"    }}\n"
            f"}}\n"
        )

    return {
        "Sources/Consumer/Tables.swift": "\n".join(tables),
        "Sources/Consumer/Queries.swift": "\n".join(queries),
    }


def generate_lighter(
    table_count: int,
    query_count: int,
    edit_token: str,
) -> dict[str, str]:
    del query_count, edit_token  # Lighter has no declared-query axis.
    statements = [create_table_sql(index) for index in range(1, table_count + 1)]
    return {"Sources/Consumer/schema.sql": "\n".join(statements) + "\n"}


GENERATORS: dict[str, Callable[[int, int, str], dict[str, str]]] = {
    "control_raw_sqlite": generate_control_raw_sqlite,
    "swiftql": generate_swiftql,
    "grdb": generate_grdb,
    "sqlite_swift": generate_sqlite_swift,
    "lighter": generate_lighter,
}


def generate_sources(
    spec: ConsumerSpec,
    table_count: int,
    query_count: int,
    edit_token: str,
) -> dict[str, str]:
    if table_count < 1 or query_count < 1:
        raise HarnessError("table and query counts must be at least 1")
    return GENERATORS[spec.generator](table_count, query_count, edit_token)


# --------------------------------------------------------------------------
# Shared utilities
# --------------------------------------------------------------------------


def utc_timestamp() -> str:
    return (
        dt.datetime.now(dt.timezone.utc)
        .isoformat(timespec="microseconds")
        .replace("+00:00", "Z")
    )


def display_command(arguments: Sequence[str]) -> str:
    return shlex.join(str(argument) for argument in arguments)


def capture_command(arguments: Sequence[str], *, cwd: Path | None = None) -> str:
    command = [str(argument) for argument in arguments]
    completed = subprocess.run(
        command,
        cwd=cwd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if completed.returncode != 0:
        stderr = completed.stderr.decode("utf-8", errors="replace").strip()
        detail = f"\n{stderr}" if stderr else ""
        raise HarnessError(
            f"command exited with status {completed.returncode}: "
            f"{display_command(command)}{detail}"
        )
    return completed.stdout.decode("utf-8", errors="strict").strip()


def optional_command(arguments: Sequence[str]) -> str:
    try:
        return capture_command(arguments)
    except (HarnessError, OSError):
        return "unavailable"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file_handle:
        for block in iter(lambda: file_handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def ensure_empty_workspace(workspace: Path) -> None:
    if workspace.exists():
        if workspace.is_symlink() or not workspace.is_dir():
            raise HarnessError(f"workspace is not a directory: {workspace}")
        if any(workspace.iterdir()):
            raise HarnessError(
                f"workspace must be empty; refusing to delete files: {workspace}"
            )
        return
    workspace.mkdir(parents=True)


def inspect_swiftql_checkout(checkout: Path, allow_dirty: bool) -> tuple[str, bool]:
    if not checkout.is_dir():
        raise HarnessError(f"SwiftQL checkout is not a directory: {checkout}")
    root = Path(capture_command(("git", "rev-parse", "--show-toplevel"), cwd=checkout))
    if root.resolve() != checkout:
        raise HarnessError(
            f"--swiftql-checkout must be the repository root, found {root}"
        )
    revision = capture_command(("git", "rev-parse", "HEAD"), cwd=checkout)
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise HarnessError(f"SwiftQL revision is not a full Git SHA: {revision!r}")
    dirty = bool(
        capture_command(
            ("git", "status", "--porcelain=v1", "--untracked-files=normal"),
            cwd=checkout,
        )
    )
    if dirty and not allow_dirty:
        raise HarnessError(
            "SwiftQL checkout has uncommitted changes; commit them or pass "
            "--allow-dirty to record the non-reproducible state"
        )
    return revision, dirty


def swift_string_literal(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def resolved_dependencies(path: Path) -> dict[str, dict[str, str]]:
    if not path.is_file():
        raise HarnessError(f"missing pinned resolution: {path}")
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise HarnessError(f"could not read {path}: {error}") from error
    if document.get("version") not in (2, 3) or not isinstance(
        document.get("pins"), list
    ):
        raise HarnessError(f"unsupported Package.resolved structure: {path}")

    dependencies: dict[str, dict[str, str]] = {}
    for pin in document["pins"]:
        if not isinstance(pin, dict) or not isinstance(pin.get("state"), dict):
            raise HarnessError(f"invalid pin in {path}")
        identity = pin.get("identity")
        version = pin["state"].get("version")
        revision = pin["state"].get("revision")
        if not isinstance(identity, str) or not identity:
            raise HarnessError(f"dependency without identity in {path}")
        if not isinstance(version, str) or not version:
            raise HarnessError(f"dependency {identity!r} lacks an exact version")
        if not isinstance(revision, str) or not re.fullmatch(
            r"[0-9a-f]{40}", revision
        ):
            raise HarnessError(f"dependency {identity!r} lacks a full revision")
        if identity in dependencies:
            raise HarnessError(f"duplicate dependency {identity!r} in {path}")
        dependencies[identity] = {"version": version, "revision": revision}
    return dict(sorted(dependencies.items()))


# --------------------------------------------------------------------------
# Workspace preparation
# --------------------------------------------------------------------------


def pinned_dependencies(spec: ConsumerSpec) -> dict[str, dict[str, str]]:
    """The consumer's checked-in pins, or an empty map when it has none.

    `control_raw_sqlite` has no external dependencies, so SwiftPM writes no
    `Package.resolved` for it and there is nothing to pin or to drift.
    """

    resolved = CONSUMER_TEMPLATE_DIRECTORY / spec.template_name / "Package.resolved"
    if not resolved.is_file():
        return {}
    return resolved_dependencies(resolved)


def prepare_consumer(
    workspace: Path,
    spec: ConsumerSpec,
    swiftql_checkout: Path,
) -> Path:
    template = CONSUMER_TEMPLATE_DIRECTORY / spec.template_name
    if not template.is_dir():
        raise HarnessError(f"consumer template is missing: {template}")
    # The directory name becomes the root package's SwiftPM identity. The
    # suffix keeps it from colliding with a dependency of the same name, which
    # otherwise makes SwiftPM silently resolve the dependency to the consumer
    # itself.
    destination = workspace / "Consumers" / f"{spec.identifier}-consumer"
    shutil.copytree(template, destination)

    manifest = destination / "Package.swift"
    manifest_text = manifest.read_text(encoding="utf-8")
    placeholder = "__SWIFTQL_CHECKOUT__"
    if spec.requires_swiftql_checkout:
        if manifest_text.count(placeholder) != 1:
            raise HarnessError(
                f"{manifest} must contain exactly one {placeholder} placeholder"
            )
        manifest_text = manifest_text.replace(
            placeholder,
            swift_string_literal(str(swiftql_checkout)),
        )
        manifest.write_text(manifest_text, encoding="utf-8")
    elif placeholder in manifest_text:
        raise HarnessError(f"unexpected SwiftQL placeholder in {manifest}")
    return destination


def write_generated_sources(
    consumer_root: Path,
    spec: ConsumerSpec,
    table_count: int,
    query_count: int,
    edit_token: str,
    *,
    rewrite_unchanged: bool = False,
) -> tuple[dict[str, str], list[str]]:
    """Write generated files and return (relative path -> SHA-256, files written).

    A file whose content already matches is left alone unless `rewrite_unchanged`
    is set. Rewriting an unchanged file still changes its modification time,
    which makes the compiler rebuild it, so a one-line edit would otherwise
    invalidate declarations it never touched.
    """

    sources = generate_sources(spec, table_count, query_count, edit_token)
    digests: dict[str, str] = {}
    written: list[str] = []
    for relative, text in sorted(sources.items()):
        path = consumer_root / relative
        digests[relative] = sha256_text(text)
        if not rewrite_unchanged and path.is_file():
            try:
                if path.read_text(encoding="utf-8") == text:
                    continue
            except OSError:
                pass
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        written.append(relative)
    return digests, written


def generated_source_bytes(
    spec: ConsumerSpec,
    table_count: int,
    query_count: int,
) -> int:
    sources = generate_sources(spec, table_count, query_count, BASE_EDIT_TOKEN)
    return sum(len(text.encode("utf-8")) for text in sources.values())


# --------------------------------------------------------------------------
# Building and measuring
# --------------------------------------------------------------------------


BUILD_ARGUMENTS = (
    "swift",
    "build",
    "--configuration",
    BUILD_CONFIGURATION,
    "--product",
    PRODUCT_NAME,
)

RECOMPILE_MARKER = re.compile(
    rf"(Compiling {TARGET_NAME}\b|Emitting module {TARGET_NAME}\b)"
)

TIME_LINE = re.compile(
    r"^\s*([0-9]+\.[0-9]+)\s+real\s+([0-9]+\.[0-9]+)\s+user\s+"
    r"([0-9]+\.[0-9]+)\s+sys\s*$",
    re.MULTILINE,
)
PEAK_RSS_LINE = re.compile(
    r"^\s*(\d+)\s+maximum resident set size\s*$",
    re.MULTILINE,
)


def macos_time_available() -> bool:
    return platform.system() == "Darwin" and Path("/usr/bin/time").is_file()


def build_environment() -> dict[str, str]:
    environment = dict(os.environ)
    environment.update({"LANG": "C", "LC_ALL": "C"})
    return environment


def run_untimed_build(consumer_root: Path) -> None:
    completed = subprocess.run(
        [str(argument) for argument in BUILD_ARGUMENTS],
        cwd=consumer_root,
        env=build_environment(),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    if completed.returncode != 0:
        output = completed.stdout.decode("utf-8", errors="replace").strip()
        raise HarnessError(
            f"consumer build failed in {consumer_root}:\n{output}"
        )


def show_bin_path(consumer_root: Path) -> Path:
    return Path(
        capture_command(
            (
                "swift",
                "build",
                "--configuration",
                BUILD_CONFIGURATION,
                "--show-bin-path",
            ),
            cwd=consumer_root,
        )
    )


def directory_bytes(root: Path, suffix: str) -> int | None:
    if not root.is_dir():
        return None
    total = 0
    found = False
    for path in root.rglob(f"*{suffix}"):
        if path.is_file():
            total += path.stat().st_size
            found = True
    return total if found else None


def optional_file_bytes(path: Path) -> int | None:
    if path.is_file():
        return path.stat().st_size
    if path.is_dir():
        return sum(item.stat().st_size for item in path.rglob("*") if item.is_file())
    return None


def collect_artifacts(consumer_root: Path, spec: ConsumerSpec) -> dict[str, object]:
    """Measure build outputs outside every timed interval."""

    binary_directory = show_bin_path(consumer_root)
    plugin_outputs = consumer_root / ".build" / "plugins" / "outputs"
    plugin_generated = directory_bytes(plugin_outputs, ".swift")
    if spec.generator == "lighter" and plugin_generated is None:
        raise HarnessError(
            f"Enlighter produced no generated Swift for {spec.identifier}"
        )
    return {
        "swiftmoduleBytes": optional_file_bytes(
            binary_directory / "Modules" / f"{TARGET_NAME}.swiftmodule"
        ),
        "objectBytes": directory_bytes(
            binary_directory / f"{TARGET_NAME}.build", ".o"
        ),
        "staticLibraryBytes": optional_file_bytes(
            binary_directory / f"lib{PRODUCT_NAME}.a"
        ),
        "pluginGeneratedSwiftBytes": plugin_generated,
        "macroExpansionBytes": None,
        "macroExpansionUnavailableReason": (
            "the pinned toolchain exposes no supported flag that writes macro "
            "expansion buffers to a stable machine-readable location during a "
            "SwiftPM build; whole-consumer cost is reported instead"
        ),
    }


def parse_time_output(text: str) -> tuple[float, float, float]:
    matches = TIME_LINE.findall(text)
    if len(matches) != 1:
        raise HarnessError(
            "could not find one real/user/sys line in /usr/bin/time output"
        )
    wall, user, system = (float(value) for value in matches[0])
    if wall <= 0.0 or user < 0.0 or system < 0.0:
        raise HarnessError(
            f"non-positive build timing: real={wall} user={user} sys={system}"
        )
    return wall, user, system


def parse_peak_rss(text: str) -> int:
    matches = PEAK_RSS_LINE.findall(text)
    if len(matches) != 1:
        raise HarnessError(
            "could not find one maximum resident set size value in "
            "/usr/bin/time output"
        )
    value = int(matches[0])
    if value <= 0:
        raise HarnessError(f"peak RSS must be positive, found {value}")
    return value


@dataclasses.dataclass(frozen=True)
class MeasurementRequest:
    spec: ConsumerSpec
    consumer_root: Path
    table_count: int
    query_count: int
    build_mode: str
    repetition: int
    schedule_index: int
    runs_directory: Path
    output_directory: Path
    total_measurements: int


def measure_build(request: MeasurementRequest) -> dict[str, object]:
    stem = (
        f"{request.spec.identifier}-t{request.table_count:03d}"
        f"-q{request.query_count:03d}-{request.build_mode}"
        f"-rep-{request.repetition:02d}"
    )
    log_path = request.runs_directory / f"{stem}.build.log"

    use_macos_time = macos_time_available()
    command: list[str] = [str(argument) for argument in BUILD_ARGUMENTS]
    if use_macos_time:
        command = ["/usr/bin/time", "-l", *command]

    print(
        f"[{request.schedule_index:03d}/{request.total_measurements:03d}] "
        f"{request.spec.identifier} tables={request.table_count} "
        f"queries={request.query_count} {request.build_mode} "
        f"repetition {request.repetition}",
        flush=True,
    )
    started_at = utc_timestamp()
    completed = subprocess.run(
        command,
        cwd=request.consumer_root,
        env=build_environment(),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    finished_at = utc_timestamp()
    log_path.write_bytes(completed.stdout)
    text = completed.stdout.decode("utf-8", errors="replace")
    if completed.returncode != 0:
        raise HarnessError(
            f"{stem} build exited with {completed.returncode}; "
            f"raw output: {log_path}\n{text.strip()}"
        )

    recompiled = RECOMPILE_MARKER.search(text) is not None
    if request.build_mode == "noop_incremental" and recompiled:
        raise HarnessError(
            f"{stem} recompiled the consumer target during a no-op build"
        )
    if request.build_mode != "noop_incremental" and not recompiled:
        raise HarnessError(
            f"{stem} did not recompile the consumer target; the build mode did "
            f"not invalidate the module"
        )

    if use_macos_time:
        wall, user, system = parse_time_output(text)
        peak_rss: int | None = parse_peak_rss(text)
        rss_reason: str | None = None
        timing_method = "usr_bin_time_l_macos"
    else:
        raise HarnessError(
            "/usr/bin/time -l is unavailable on this platform; the harness "
            "records wall, user, system, and peak RSS together and refuses to "
            "emit a partial measurement"
        )

    return {
        "consumer": request.spec.identifier,
        "tableCount": request.table_count,
        "queryCount": request.query_count,
        "buildMode": request.build_mode,
        "repetition": request.repetition,
        "scheduleIndex": request.schedule_index,
        "startedAt": started_at,
        "finishedAt": finished_at,
        "wallSeconds": wall,
        "userSeconds": user,
        "systemSeconds": system,
        "peakRSSBytes": peak_rss,
        "peakRSSUnavailableReason": rss_reason,
        "timingMethod": timing_method,
        "recompiledConsumerTarget": recompiled,
        "rawLog": str(log_path.relative_to(request.output_directory)),
        "rawLogSHA256": sha256_file(log_path),
    }


# --------------------------------------------------------------------------
# Matrix definition
# --------------------------------------------------------------------------


def matrix_points(
    table_scales: Sequence[int],
    query_scales: Sequence[int],
) -> list[tuple[int, int]]:
    """Scale tables and queries independently around the shared baseline."""

    points: list[tuple[int, int]] = [(BASELINE_TABLE_COUNT, BASELINE_QUERY_COUNT)]
    for tables in table_scales:
        point = (tables, BASELINE_QUERY_COUNT)
        if point not in points:
            points.append(point)
    for queries in query_scales:
        point = (BASELINE_TABLE_COUNT, queries)
        if point not in points:
            points.append(point)
    return points


def consumer_points(
    spec: ConsumerSpec,
    table_scales: Sequence[int],
    query_scales: Sequence[int],
) -> list[tuple[int, int]]:
    points = matrix_points(table_scales, query_scales)
    if spec.scales_query_declarations:
        return points
    return [point for point in points if point[1] == BASELINE_QUERY_COUNT]


# --------------------------------------------------------------------------
# Statistics
# --------------------------------------------------------------------------


def summarize_measurements(
    measurements: Sequence[dict[str, object]],
) -> dict[str, object]:
    walls = [float(measurement["wallSeconds"]) for measurement in measurements]
    users = [float(measurement["userSeconds"]) for measurement in measurements]
    systems = [float(measurement["systemSeconds"]) for measurement in measurements]
    peaks = [
        int(measurement["peakRSSBytes"])
        for measurement in measurements
        if isinstance(measurement["peakRSSBytes"], int)
    ]
    median_wall = statistics.median(walls)
    spread = (max(walls) - min(walls)) / median_wall * 100.0
    return {
        "repetitionCount": len(measurements),
        "medianWallSeconds": median_wall,
        "minWallSeconds": min(walls),
        "maxWallSeconds": max(walls),
        "wallSpreadPercent": spread,
        "medianUserSeconds": statistics.median(users),
        "medianSystemSeconds": statistics.median(systems),
        "maxPeakRSSBytes": max(peaks) if len(peaks) == len(measurements) else None,
    }


def build_results(measurements: Sequence[dict[str, object]]) -> dict[str, object]:
    grouped: dict[str, list[dict[str, object]]] = {}
    for measurement in measurements:
        key = (
            f"{measurement['consumer']}|{measurement['tableCount']}|"
            f"{measurement['queryCount']}|{measurement['buildMode']}"
        )
        grouped.setdefault(key, []).append(measurement)
    return {key: summarize_measurements(group) for key, group in sorted(grouped.items())}


# --------------------------------------------------------------------------
# Environment metadata
# --------------------------------------------------------------------------


def integer_from_optional_command(arguments: Sequence[str]) -> int | None:
    value = optional_command(arguments)
    try:
        return int(value)
    except ValueError:
        return None


def environment_metadata() -> dict[str, object]:
    product_version = optional_command(("sw_vers", "-productVersion"))
    build_version = optional_command(("sw_vers", "-buildVersion"))
    if product_version == "unavailable":
        operating_system = platform.platform()
    else:
        suffix = "" if build_version == "unavailable" else f" ({build_version})"
        operating_system = f"macOS {product_version}{suffix}"
    return {
        "model": optional_command(("sysctl", "-n", "hw.model")),
        "processor": optional_command(("sysctl", "-n", "machdep.cpu.brand_string")),
        "coreCount": os.cpu_count(),
        "memoryBytes": integer_from_optional_command(("sysctl", "-n", "hw.memsize")),
        "architecture": platform.machine(),
        "operatingSystem": operating_system,
        "xcode": optional_command(("xcodebuild", "-version")),
        "swift": optional_command(("swift", "--version")),
        "python": platform.python_version(),
        "git": optional_command(("git", "--version")),
    }


# --------------------------------------------------------------------------
# Command line
# --------------------------------------------------------------------------


def parse_scale_list(value: str) -> tuple[int, ...]:
    scales: list[int] = []
    for item in value.split(","):
        item = item.strip()
        if not item:
            continue
        try:
            scale = int(item)
        except ValueError as error:
            raise argparse.ArgumentTypeError(f"not an integer: {item!r}") from error
        if scale < 1:
            raise argparse.ArgumentTypeError(f"scale must be at least 1: {scale}")
        if scale in scales:
            raise argparse.ArgumentTypeError(f"duplicate scale: {scale}")
        scales.append(scale)
    if not scales:
        raise argparse.ArgumentTypeError("at least one scale is required")
    return tuple(sorted(scales))


def parse_consumer_list(value: str) -> tuple[str, ...]:
    identifiers: list[str] = []
    for item in value.split(","):
        item = item.strip()
        if not item:
            continue
        if item not in CONSUMERS_BY_IDENTIFIER:
            raise argparse.ArgumentTypeError(f"unknown consumer: {item!r}")
        if item in identifiers:
            raise argparse.ArgumentTypeError(f"duplicate consumer: {item!r}")
        identifiers.append(item)
    if not identifiers:
        raise argparse.ArgumentTypeError("at least one consumer is required")
    return tuple(identifiers)


def create_argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Generate isolated downstream consumer packages whose table and "
            "query declaration counts scale independently, then measure their "
            "builds. The workspace must be new or empty."
        )
    )
    parser.add_argument("--workspace", type=Path, required=True)
    parser.add_argument("--swiftql-checkout", type=Path, required=True)
    parser.add_argument(
        "--output",
        type=Path,
        help="report path (default: <workspace>/compile-time-results.json)",
    )
    parser.add_argument(
        "--tables",
        type=parse_scale_list,
        default=CANONICAL_SCALES,
        help="table scales to record (default: 1,10,100,500)",
    )
    parser.add_argument(
        "--queries",
        type=parse_scale_list,
        default=CANONICAL_SCALES,
        help="query scales to record (default: 1,10,100,500)",
    )
    parser.add_argument(
        "--consumers",
        type=parse_consumer_list,
        default=tuple(spec.identifier for spec in CONSUMER_SPECS),
        help="consumers to record (default: every consumer)",
    )
    parser.add_argument(
        "--repetitions",
        type=int,
        default=DEFAULT_REPETITION_COUNT,
        help="independent build processes per point and mode (default: 3)",
    )
    parser.add_argument(
        "--cooldown-seconds",
        type=float,
        default=30.0,
        help="idle delay after each dependency warm-up build (default: 30)",
    )
    parser.add_argument(
        "--allow-dirty",
        action="store_true",
        help="allow and explicitly record a dirty SwiftQL checkout",
    )
    parser.add_argument(
        "--prepare-only",
        action="store_true",
        help="generate and compile-check every consumer without timing",
    )
    parser.add_argument(
        "--bootstrap-resolved",
        action="store_true",
        help=(
            "maintenance mode: resolve each consumer and copy the resulting "
            "Package.resolved back into its checked-in template"
        ),
    )
    return parser


def bootstrap_resolved(
    workspace: Path,
    swiftql_checkout: Path,
    identifiers: Sequence[str],
) -> int:
    for identifier in identifiers:
        spec = CONSUMERS_BY_IDENTIFIER[identifier]
        consumer_root = prepare_consumer(workspace, spec, swiftql_checkout)
        write_generated_sources(
            consumer_root,
            spec,
            1,
            1,
            BASE_EDIT_TOKEN,
            rewrite_unchanged=True,
        )
        print(f"+ swift package resolve ({spec.identifier})", flush=True)
        capture_command(("swift", "package", "resolve"), cwd=consumer_root)
        resolved = consumer_root / "Package.resolved"
        template_resolved = (
            CONSUMER_TEMPLATE_DIRECTORY / spec.template_name / "Package.resolved"
        )
        if resolved.is_file():
            shutil.copyfile(resolved, template_resolved)
            print(f"  wrote {template_resolved}")
        elif template_resolved.exists():
            raise HarnessError(
                f"{spec.identifier} resolved nothing but a template "
                f"Package.resolved exists: {template_resolved}"
            )
        else:
            print(f"  {spec.identifier} has no external dependencies")
    return 0


def main(arguments: Sequence[str] | None = None) -> int:
    options = create_argument_parser().parse_args(arguments)
    try:
        if options.repetitions < 1:
            raise HarnessError("--repetitions must be at least 1")
        if (
            not math.isfinite(options.cooldown_seconds)
            or options.cooldown_seconds < 0
        ):
            raise HarnessError("--cooldown-seconds must be finite and non-negative")

        workspace = options.workspace.expanduser().resolve()
        swiftql_checkout = options.swiftql_checkout.expanduser().resolve()
        output = (
            options.output.expanduser().resolve()
            if options.output is not None
            else workspace / "compile-time-results.json"
        )
        output_directory = output.parent
        runs_directory = output_directory / "Runs"

        ensure_empty_workspace(workspace)
        swiftql_revision, swiftql_dirty = inspect_swiftql_checkout(
            swiftql_checkout,
            options.allow_dirty,
        )

        if options.bootstrap_resolved:
            return bootstrap_resolved(workspace, swiftql_checkout, options.consumers)

        if not options.prepare_only:
            if output.exists():
                raise HarnessError(f"refusing to overwrite report: {output}")
            if runs_directory.exists() and any(runs_directory.iterdir()):
                raise HarnessError(
                    f"refusing to mix outputs with existing files: {runs_directory}"
                )

        selected = [CONSUMERS_BY_IDENTIFIER[name] for name in options.consumers]
        prepared: dict[str, Path] = {}
        for spec in selected:
            prepared[spec.identifier] = prepare_consumer(
                workspace,
                spec,
                swiftql_checkout,
            )

        plan: list[tuple[ConsumerSpec, int, int]] = []
        for spec in selected:
            for table_count, query_count in consumer_points(
                spec,
                options.tables,
                options.queries,
            ):
                plan.append((spec, table_count, query_count))

        total_measurements = sum(
            len(spec.build_modes) * options.repetitions for spec, _, _ in plan
        )

        if options.prepare_only:
            for spec, table_count, query_count in plan:
                consumer_root = prepared[spec.identifier]
                write_generated_sources(
                    consumer_root,
                    spec,
                    table_count,
                    query_count,
                    BASE_EDIT_TOKEN,
                    rewrite_unchanged=True,
                )
                print(
                    f"+ compile check {spec.identifier} tables={table_count} "
                    f"queries={query_count}",
                    flush=True,
                )
                run_untimed_build(consumer_root)
            print("Every selected consumer generated and compiled.")
            return 0

        output_directory.mkdir(parents=True, exist_ok=True)
        runs_directory.mkdir(exist_ok=True)

        measurements: list[dict[str, object]] = []
        artifacts: list[dict[str, object]] = []
        schedule_index = 0

        for spec, table_count, query_count in plan:
            consumer_root = prepared[spec.identifier]
            expected = pinned_dependencies(spec)

            # Warm-up and correctness: generate the point, build it untimed,
            # and collect every build artifact before any timing starts.
            source_digests, _ = write_generated_sources(
                consumer_root,
                spec,
                table_count,
                query_count,
                BASE_EDIT_TOKEN,
                rewrite_unchanged=True,
            )
            print(
                f"+ warm and validate {spec.identifier} tables={table_count} "
                f"queries={query_count}",
                flush=True,
            )
            run_untimed_build(consumer_root)
            if expected and resolved_dependencies(
                consumer_root / "Package.resolved"
            ) != expected:
                raise HarnessError(
                    f"SwiftPM rewrote the pinned resolution for {spec.identifier}"
                )
            artifacts.append(
                {
                    "consumer": spec.identifier,
                    "tableCount": table_count,
                    "queryCount": query_count,
                    "generatedSourceBytes": generated_source_bytes(
                        spec,
                        table_count,
                        query_count,
                    ),
                    "generatedSourceSHA256": dict(sorted(source_digests.items())),
                    **collect_artifacts(consumer_root, spec),
                }
            )
            if options.cooldown_seconds:
                time.sleep(options.cooldown_seconds)

            for repetition in range(1, options.repetitions + 1):
                for build_mode in spec.build_modes:
                    if build_mode == "clean_dependency_warm":
                        # Rewriting every generated file invalidates the whole
                        # consumer module while the dependency and macro-plugin
                        # builds stay warm.
                        _, written = write_generated_sources(
                            consumer_root,
                            spec,
                            table_count,
                            query_count,
                            BASE_EDIT_TOKEN,
                            rewrite_unchanged=True,
                        )
                        expected_files = len(
                            generate_sources(
                                spec,
                                table_count,
                                query_count,
                                BASE_EDIT_TOKEN,
                            )
                        )
                        if len(written) != expected_files:
                            raise HarnessError(
                                f"clean mode rewrote {len(written)} of "
                                f"{expected_files} generated files"
                            )
                    elif build_mode == "one_query_edit":
                        _, written = write_generated_sources(
                            consumer_root,
                            spec,
                            table_count,
                            query_count,
                            f"edit{repetition}",
                        )
                        if written != ["Sources/Consumer/Queries.swift"]:
                            raise HarnessError(
                                f"a one-query edit touched {written!r} instead "
                                f"of only the query file"
                            )
                    schedule_index += 1
                    measurements.append(
                        measure_build(
                            MeasurementRequest(
                                spec=spec,
                                consumer_root=consumer_root,
                                table_count=table_count,
                                query_count=query_count,
                                build_mode=build_mode,
                                repetition=repetition,
                                schedule_index=schedule_index,
                                runs_directory=runs_directory,
                                output_directory=output_directory,
                                total_measurements=total_measurements,
                            )
                        )
                    )

        consumer_documents = []
        for spec in selected:
            consumer_documents.append(
                {
                    "identifier": spec.identifier,
                    "template": spec.template_name,
                    "dependencies": pinned_dependencies(spec),
                    "buildModes": list(spec.build_modes),
                    "applicability": {
                        "tableAxis": "applicable",
                        "queryAxis": spec.query_axis_status,
                        "oneQueryEdit": (
                            "applicable"
                            if "one_query_edit" in spec.build_modes
                            else "not_applicable"
                        ),
                        "note": spec.applicability_note,
                    },
                }
            )

        result = {
            "formatVersion": REPORT_FORMAT_VERSION,
            "generatedAt": utc_timestamp(),
            "provenance": {"harness": "independently_implemented"},
            "workload": {
                "identifier": "consumer_compile_time_scalability",
                "canonicalScales": list(CANONICAL_SCALES),
                "recordedTableScales": list(options.tables),
                "recordedQueryScales": list(options.queries),
                "baselineTableCount": BASELINE_TABLE_COUNT,
                "baselineQueryCount": BASELINE_QUERY_COUNT,
                "buildModes": list(BUILD_MODES),
                "configuration": BUILD_CONFIGURATION,
                "product": PRODUCT_NAME,
                "target": TARGET_NAME,
                "repetitionCount": options.repetitions,
                "timer": "usr_bin_time_l",
                "processIsolation": "one_swift_build_process_per_measurement",
                "dependencyState": "dependency_warm",
                "cleanModeDefinition": (
                    "every generated consumer source file is rewritten, which "
                    "invalidates the whole consumer module while dependency and "
                    "macro-plugin builds stay warm; it is not an empty cache"
                ),
                "postWarmupCooldownSeconds": options.cooldown_seconds,
                "columnCount": len(COLUMNS),
                "attribution": "whole_consumer_build",
            },
            "sources": {
                "swiftqlRevision": swiftql_revision,
                "swiftqlDirty": swiftql_dirty,
            },
            "environment": environment_metadata(),
            "consumers": consumer_documents,
            "artifacts": artifacts,
            "measurements": measurements,
            "results": build_results(measurements),
            "durationUnit": "seconds_per_build",
        }
        output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
        print(f"Wrote compile-time report: {output}")
        return 0
    except (HarnessError, OSError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
