#!/usr/bin/env python3

"""Validate and render SwiftQL's versioned SQLite conformance inventory."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import sys
from collections import Counter
from pathlib import Path, PurePosixPath
from typing import Any, Dict, Iterable, List, Mapping, Optional, Sequence, Set, Tuple
from urllib.parse import quote, urlparse


SCHEMA_VERSION = 1
INVENTORY_VERSION = "1.3.0"
COORDINATION_ISSUE = 190
REQUIRED_FAMILIES = {
    "select",
    "expression",
    "join",
    "subquery",
    "compound",
    "cte",
    "dml",
    "ddl",
}
REQUIRED_SUITE_STATUSES = {
    191: "completed",
    252: "completed",
    253: "completed",
    254: "completed",
    255: "completed",
    256: "planned",
}
FEATURE_KINDS = {"syntax", "adopted-behavior", "adapter-contract"}
FEATURE_STATUSES = {
    "supported",
    "partial",
    "capability-gated",
    "intentionally-unsupported",
    "unimplemented",
}
ADOPTION_STATUSES = {
    "already-covered",
    "adoptable-now",
    "syntax-gated",
    "adapter/API-gated",
    "intentionally-out-of-scope",
}
EVIDENCE_LAYERS = {
    "swift-typecheck",
    "rendering",
    "bindings",
    "prepare",
    "execution",
    "compile-fail",
    "structured-error",
    "runtime-metadata",
    "semantic-oracle",
    "observation",
}
REQUIRED_GLOBAL_EVIDENCE_LAYERS = {
    "swift-typecheck",
    "rendering",
    "bindings",
    "prepare",
    "execution",
    "compile-fail",
    "structured-error",
    "runtime-metadata",
    "semantic-oracle",
}
DEFERRAL_STATUSES = {"partial", "capability-gated", "unimplemented"}
DEFERRAL_ADOPTION_STATUSES = {
    "adoptable-now",
    "syntax-gated",
    "adapter/API-gated",
}

ID_PATTERN = re.compile(r"^[a-z0-9]+(?:[._-][a-z0-9]+)*$")
SHA_PATTERN = re.compile(r"^[0-9a-f]{40}$")
SEMVER_PATTERN = re.compile(r"^(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)$")
MILESTONE_PATTERN = re.compile(
    r"^v?(?:0|[1-9][0-9]*)(?:\.(?:0|[1-9][0-9]*)){0,2}$"
)
SPDX_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9.+-]*(?: WITH [A-Za-z0-9][A-Za-z0-9.+-]*)?$")

TOP_LEVEL_KEYS = {
    "schema_version",
    "inventory_version",
    "coordination_issue",
    "scope",
    "sqlite_environments",
    "evidence",
    "suites",
    "features",
}
SCOPE_KEYS = {"claim", "limits", "required_families"}
ENVIRONMENT_KEYS = {
    "id",
    "sqlite_version",
    "sqlite_source_id",
    "source",
    "captured_at",
    "toolchain",
    "architecture",
    "capabilities",
}
EVIDENCE_KEYS = {
    "id",
    "source_path",
    "test_case",
    "runner_path",
    "layers",
    "real_sqlite",
    "environment_ids",
}
SUITE_KEYS = {
    "id",
    "issue",
    "milestone",
    "status",
    "case_ids",
    "evidence_ids",
}
FEATURE_KEYS = {
    "id",
    "kind",
    "family",
    "title",
    "status",
    "adoption_status",
    "public_api",
    "sqlite_documentation_urls",
    "not_sqlite_syntax_reason",
    "minimum_sqlite_version",
    "reviewed_sqlite_release",
    "reviewed_sqlite_source_id",
    "required_capabilities",
    "schema_requirements",
    "evidence_ids",
    "deviations",
    "follow_up_issues",
    "deferral",
    "provenance",
}
PUBLIC_API_KEYS = {"symbol", "source_path", "source_tokens"}
DEFERRAL_KEYS = {"blocking_issue", "target_milestone", "reason"}
PROVENANCE_KEYS = {
    "repository",
    "commit",
    "path",
    "upstream_case",
    "license_spdx",
    "license_file_path",
    "license_file_url",
    "license_blob_sha",
    "license_disposition",
    "copied_material",
    "notice_path",
    "adaptation_notes",
}


class InventoryError(RuntimeError):
    """Raised when the inventory or generated report violates its contract."""


def _reject_duplicate_keys(pairs: Sequence[Tuple[str, Any]]) -> Dict[str, Any]:
    result: Dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise InventoryError(f"duplicate JSON object key: {key}")
        result[key] = value
    return result


def _reject_json_constant(value: str) -> None:
    raise InventoryError(f"non-standard JSON numeric constant: {value}")


def load_inventory(path: Path) -> Mapping[str, Any]:
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as error:
        raise InventoryError(f"could not read inventory {path}: {error}") from error
    try:
        value = json.loads(
            text,
            object_pairs_hook=_reject_duplicate_keys,
            parse_constant=_reject_json_constant,
        )
    except json.JSONDecodeError as error:
        raise InventoryError(
            f"invalid JSON in {path}:{error.lineno}:{error.colno}: {error.msg}"
        ) from error
    if not isinstance(value, dict):
        raise InventoryError("inventory must be a JSON object")
    return value


def object_value(value: Any, path: str) -> Mapping[str, Any]:
    if not isinstance(value, dict):
        raise InventoryError(f"{path} must be an object")
    return value


def exact_keys(value: Mapping[str, Any], required: Set[str], path: str) -> None:
    actual = set(value)
    missing = sorted(required - actual)
    unknown = sorted(actual - required)
    if missing:
        raise InventoryError(f"{path} is missing required keys: {', '.join(missing)}")
    if unknown:
        raise InventoryError(f"{path} has unknown keys: {', '.join(unknown)}")


def array_value(value: Any, path: str, *, nonempty: bool = False) -> List[Any]:
    if not isinstance(value, list):
        raise InventoryError(f"{path} must be an array")
    if nonempty and not value:
        raise InventoryError(f"{path} must not be empty")
    return value


def text_value(value: Any, path: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise InventoryError(f"{path} must be a non-empty string")
    if value != value.strip():
        raise InventoryError(f"{path} must not have leading or trailing whitespace")
    return value


def optional_text(value: Any, path: str) -> Optional[str]:
    if value is None:
        return None
    return text_value(value, path)


def integer_value(value: Any, path: str) -> int:
    if type(value) is not int or value <= 0:
        raise InventoryError(f"{path} must be a positive integer")
    return value


def boolean_value(value: Any, path: str) -> bool:
    if type(value) is not bool:
        raise InventoryError(f"{path} must be a boolean")
    return value


def id_value(value: Any, path: str) -> str:
    identifier = text_value(value, path)
    if not ID_PATTERN.fullmatch(identifier):
        raise InventoryError(
            f"{path} must be a stable lowercase identifier using '.', '-', or '_'"
        )
    return identifier


def enum_value(value: Any, allowed: Set[str], path: str) -> str:
    result = text_value(value, path)
    if result not in allowed:
        raise InventoryError(
            f"{path} has invalid value {result!r}; expected one of: "
            + ", ".join(sorted(allowed))
        )
    return result


def text_array(
    value: Any,
    path: str,
    *,
    nonempty: bool = False,
    identifiers: bool = False,
) -> List[str]:
    raw = array_value(value, path, nonempty=nonempty)
    result: List[str] = []
    for index, item in enumerate(raw):
        item_path = f"{path}[{index}]"
        result.append(id_value(item, item_path) if identifiers else text_value(item, item_path))
    duplicate = first_duplicate(result)
    if duplicate is not None:
        raise InventoryError(f"{path} contains duplicate value: {duplicate}")
    return result


def integer_array(value: Any, path: str) -> List[int]:
    raw = array_value(value, path)
    result = [integer_value(item, f"{path}[{index}]") for index, item in enumerate(raw)]
    duplicate = first_duplicate(result)
    if duplicate is not None:
        raise InventoryError(f"{path} contains duplicate value: {duplicate}")
    return result


def first_duplicate(values: Iterable[Any]) -> Optional[Any]:
    seen: Set[Any] = set()
    for value in values:
        if value in seen:
            return value
        seen.add(value)
    return None


def semver(value: Any, path: str) -> str:
    result = text_value(value, path)
    if not SEMVER_PATTERN.fullmatch(result):
        raise InventoryError(f"{path} must use numeric major.minor.patch form")
    return result


def milestone(value: Any, path: str) -> str:
    result = text_value(value, path)
    if not MILESTONE_PATTERN.fullmatch(result):
        raise InventoryError(f"{path} must be a version milestone such as v1.3")
    return result


def https_url(value: Any, path: str, *, sqlite_documentation: bool = False) -> str:
    result = text_value(value, path)
    parsed = urlparse(result)
    if parsed.scheme != "https" or not parsed.netloc or parsed.username or parsed.password:
        raise InventoryError(f"{path} must be an absolute HTTPS URL")
    if sqlite_documentation and parsed.hostname not in {"sqlite.org", "www.sqlite.org"}:
        raise InventoryError(f"{path} must link to official sqlite.org documentation")
    return result


def captured_at(value: Any, path: str) -> str:
    result = text_value(value, path)
    try:
        if "T" in result:
            parsed = dt.datetime.fromisoformat(result.replace("Z", "+00:00"))
            if parsed.tzinfo is None:
                raise ValueError("timestamp has no timezone")
        else:
            dt.date.fromisoformat(result)
    except ValueError as error:
        raise InventoryError(
            f"{path} must be an ISO 8601 date or timezone-qualified timestamp"
        ) from error
    return result


def relative_path(
    value: Any,
    path: str,
    *,
    repository_root: Optional[Path] = None,
    must_exist: bool = False,
) -> str:
    result = text_value(value, path)
    if "\\" in result:
        raise InventoryError(f"{path} must use forward slashes")
    parsed = PurePosixPath(result)
    if parsed.is_absolute() or any(part in {"", ".", ".."} for part in parsed.parts):
        raise InventoryError(f"{path} must stay within the repository")
    normalized = parsed.as_posix()
    if normalized != result:
        raise InventoryError(f"{path} is not a normalized repository-relative path")
    if must_exist:
        assert repository_root is not None
        candidate = repository_root / normalized
        try:
            candidate.resolve().relative_to(repository_root.resolve())
        except (OSError, ValueError) as error:
            raise InventoryError(f"{path} resolves outside the repository: {result}") from error
        if not candidate.is_file():
            raise InventoryError(f"{path} does not identify an existing file: {result}")
    return normalized


def require_unique_ids(records: Sequence[Mapping[str, Any]], collection: str) -> None:
    identifiers = [record["id"] for record in records]
    duplicate = first_duplicate(identifiers)
    if duplicate is not None:
        raise InventoryError(f"duplicate {collection} id: {duplicate}")


def swift_code_without_comments_and_literals(source: str) -> str:
    """Blank Swift comments and string literals while preserving code positions."""

    result = list(source)
    length = len(source)
    index = 0

    def blank(start: int, end: int) -> None:
        for position in range(start, end):
            if result[position] not in {"\n", "\r"}:
                result[position] = " "

    while index < length:
        if source.startswith("//", index):
            end = source.find("\n", index + 2)
            if end == -1:
                end = length
            blank(index, end)
            index = end
            continue
        if source.startswith("/*", index):
            start = index
            index += 2
            depth = 1
            while index < length and depth:
                if source.startswith("/*", index):
                    depth += 1
                    index += 2
                elif source.startswith("*/", index):
                    depth -= 1
                    index += 2
                else:
                    index += 1
            blank(start, index)
            continue

        hash_count = 0
        while index + hash_count < length and source[index + hash_count] == "#":
            hash_count += 1
        quote_start = index + hash_count
        if quote_start < length and source[quote_start] == '"':
            quote_count = 3 if source.startswith('"""', quote_start) else 1
            delimiter = ('"' * quote_count) + ("#" * hash_count)
            start = index
            index = quote_start + quote_count
            while index < length:
                if source.startswith(delimiter, index):
                    index += len(delimiter)
                    break
                if hash_count == 0 and source[index] == "\\":
                    index += min(2, length - index)
                else:
                    index += 1
            blank(start, index)
            continue
        index += 1
    return "".join(result)


def matching_brace(source: str, opening: int) -> Optional[int]:
    depth = 0
    for index in range(opening, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return index
    return None


def named_swift_scopes(source: str, keyword: str, name: str) -> List[Tuple[int, int]]:
    declaration = re.compile(
        rf"\b{re.escape(keyword)}\s+{re.escape(name)}\b"
    )
    scopes: List[Tuple[int, int]] = []
    for match in declaration.finditer(source):
        opening = source.find("{", match.end())
        if opening == -1:
            continue
        closing = matching_brace(source, opening)
        if closing is not None:
            scopes.append((opening + 1, closing))
    return scopes


def declaration_is_directly_in_scope(
    source: str,
    start: int,
    declaration_start: int,
) -> bool:
    depth = 0
    for character in source[start:declaration_start]:
        if character == "{":
            depth += 1
        elif character == "}":
            depth -= 1
    return depth == 0


def validate_ordinary_test_reference(
    test_case: Any,
    source_path: str,
    path: str,
    repository_root: Path,
) -> str:
    reference = text_value(test_case, path)
    match = re.fullmatch(
        r"([A-Za-z_][A-Za-z0-9_]*)\.([A-Za-z_][A-Za-z0-9_]*)",
        reference,
    )
    if match is None:
        raise InventoryError(f"{path} must use Class.method form")
    class_name, method_name = match.groups()
    try:
        raw_source = (repository_root / source_path).read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as error:
        raise InventoryError(
            f"{path} could not inspect Swift source {source_path}: {error}"
        ) from error
    source = swift_code_without_comments_and_literals(raw_source)
    class_scopes = named_swift_scopes(source, "class", class_name)
    extension_scopes = named_swift_scopes(source, "extension", class_name)
    method_pattern = re.compile(rf"\bfunc\s+{re.escape(method_name)}\s*\(")
    if not class_scopes:
        raise InventoryError(
            f"{path} names class {class_name!r}, but that class is not declared in {source_path}"
        )
    method_is_scoped = False
    for start, end in class_scopes + extension_scopes:
        for method_match in method_pattern.finditer(source, start, end):
            if declaration_is_directly_in_scope(source, start, method_match.start()):
                method_is_scoped = True
                break
        if method_is_scoped:
            break
    if not method_is_scoped:
        raise InventoryError(
            f"{path} names method {method_name!r}, but no direct 'func {method_name}(' "
            f"declaration occurs in class {class_name!r} or its extensions in {source_path}"
        )
    return reference


PUBLIC_DECLARATION_PATTERN = re.compile(
    r"\b(?:public|open)\s+"
    r"(?:(?:final|indirect|static|class|prefix|postfix|infix|mutating|"
    r"nonmutating|override|required|convenience|distributed|nonisolated)\s+)*"
    r"(?:class|struct|enum|protocol|actor|typealias|func|var|let|operator|"
    r"precedencegroup)\s+"
    r"(`?[A-Za-z_][A-Za-z0-9_]*`?|[!%&*+\-./<=>?^|~]+)"
)
PUBLIC_TYPE_PATTERN = re.compile(
    r"\b(?:public|open)\s+"
    r"(?:(?:final|indirect|nonisolated)\s+)*"
    r"(class|struct|enum|protocol|actor)\s+"
    r"([A-Za-z_][A-Za-z0-9_]*)"
)
PROTOCOL_MEMBER_PATTERN = re.compile(
    r"\b(?:(?:static|class|mutating|nonmutating|prefix|postfix|infix)\s+)*"
    r"(?:associatedtype|typealias|func|var|let)\s+"
    r"(`?[A-Za-z_][A-Za-z0-9_]*`?|[!%&*+\-./<=>?^|~]+)"
)
ENUM_CASE_PATTERN = re.compile(r"\bcase\s+([A-Za-z_][A-Za-z0-9_]*)")
SOURCE_TOKEN_PATTERN = re.compile(
    r"(?:[A-Za-z_][A-Za-z0-9_]*|[!%&*+\-./<=>?^|~]+)"
)


def public_declaration_tokens(source: str) -> Set[str]:
    code = swift_code_without_comments_and_literals(source)
    tokens: Set[str] = set()
    for match in PUBLIC_DECLARATION_PATTERN.finditer(code):
        token = match.group(1).strip("`")
        token_end = match.end(1)
        if (
            token.endswith("<")
            and re.fullmatch(r"[!%&*+\-./<=>?^|~]+", token) is not None
            and token_end < len(code)
            and re.match(r"[A-Za-z_]", code[token_end]) is not None
        ):
            token = token[:-1]
        tokens.add(token)
    for type_match in PUBLIC_TYPE_PATTERN.finditer(code):
        kind, type_name = type_match.groups()
        tokens.add(type_name)
        opening = code.find("{", type_match.end())
        if opening == -1:
            continue
        closing = matching_brace(code, opening)
        if closing is None:
            continue
        member_pattern = (
            PROTOCOL_MEMBER_PATTERN if kind == "protocol" else ENUM_CASE_PATTERN
        )
        if kind not in {"protocol", "enum"}:
            continue
        for member_match in member_pattern.finditer(code, opening + 1, closing):
            if declaration_is_directly_in_scope(
                code, opening + 1, member_match.start()
            ):
                tokens.add(member_match.group(1).strip("`"))
    return tokens


def symbol_mentions_token(symbol: str, token: str) -> bool:
    if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", token):
        return re.search(rf"\b{re.escape(token)}\b", symbol) is not None
    operators: Set[str] = set()
    for candidate in re.findall(r"[!%&*+\-./<=>?^|~]+", symbol):
        operators.add(candidate)
        unqualified = candidate.lstrip(".")
        if unqualified:
            operators.add(unqualified)
            operators.update(part for part in unqualified.split("/") if part)
    return token in operators


def runner_references_source(
    runner_contents: str,
    source_path: str,
    repository_root: Path,
) -> bool:
    if source_path in runner_contents:
        return True
    basename = PurePosixPath(source_path).name
    if basename not in runner_contents:
        return False
    matches = []
    for candidate in repository_root.rglob(basename):
        if not candidate.is_file():
            continue
        try:
            relative = candidate.resolve().relative_to(repository_root.resolve())
        except (OSError, ValueError):
            continue
        matches.append(relative.as_posix())
        if len(matches) > 1:
            return False
    return matches == [source_path]


def validate_compile_fail_runner(
    runner_value: Any,
    source_path: str,
    test_case: Any,
    path: str,
    repository_root: Path,
) -> str:
    identifier = id_value(test_case, f"{path}.test_case")
    runner_path = relative_path(
        runner_value,
        f"{path}.runner_path",
        repository_root=repository_root,
        must_exist=True,
    )
    if not runner_path.startswith("scripts/ci/"):
        raise InventoryError(
            f"{path}.runner_path must identify a script under scripts/ci/"
        )
    runner = repository_root / runner_path
    try:
        runner.resolve().relative_to((repository_root / "scripts/ci").resolve())
    except (OSError, ValueError) as error:
        raise InventoryError(
            f"{path}.runner_path resolves outside scripts/ci/: {runner_path}"
        ) from error
    if not os.access(runner, os.X_OK):
        raise InventoryError(f"{path}.runner_path must be executable: {runner_path}")
    try:
        runner_contents = runner.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as error:
        raise InventoryError(
            f"{path}.runner_path could not be read as a script: {error}"
        ) from error
    if not runner_contents.startswith("#!"):
        raise InventoryError(f"{path}.runner_path must begin with a script shebang")
    if not runner_references_source(runner_contents, source_path, repository_root):
        raise InventoryError(
            f"{path}.runner_path does not reference evidence source_path {source_path}"
        )
    return identifier


def validate_scope(value: Any) -> Mapping[str, Any]:
    scope = object_value(value, "scope")
    exact_keys(scope, SCOPE_KEYS, "scope")
    text_value(scope["claim"], "scope.claim")
    text_array(scope["limits"], "scope.limits", nonempty=True)
    families = text_array(
        scope["required_families"],
        "scope.required_families",
        nonempty=True,
        identifiers=True,
    )
    if set(families) != REQUIRED_FAMILIES:
        missing = sorted(REQUIRED_FAMILIES - set(families))
        extra = sorted(set(families) - REQUIRED_FAMILIES)
        detail = []
        if missing:
            detail.append("missing " + ", ".join(missing))
        if extra:
            detail.append("unexpected " + ", ".join(extra))
        raise InventoryError(
            "scope.required_families must define the v1.3 syntax families ("
            + "; ".join(detail)
            + ")"
        )
    return scope


def validate_environments(value: Any) -> List[Mapping[str, Any]]:
    raw = array_value(value, "sqlite_environments", nonempty=True)
    result: List[Mapping[str, Any]] = []
    for index, item in enumerate(raw):
        path = f"sqlite_environments[{index}]"
        environment = object_value(item, path)
        exact_keys(environment, ENVIRONMENT_KEYS, path)
        id_value(environment["id"], f"{path}.id")
        semver(environment["sqlite_version"], f"{path}.sqlite_version")
        text_value(environment["sqlite_source_id"], f"{path}.sqlite_source_id")
        text_value(environment["source"], f"{path}.source")
        captured_at(environment["captured_at"], f"{path}.captured_at")
        text_value(environment["toolchain"], f"{path}.toolchain")
        text_value(environment["architecture"], f"{path}.architecture")
        text_array(environment["capabilities"], f"{path}.capabilities")
        result.append(environment)
    require_unique_ids(result, "SQLite environment")
    return result


def validate_evidence(
    value: Any,
    repository_root: Path,
    environment_ids: Set[str],
) -> List[Mapping[str, Any]]:
    raw = array_value(value, "evidence", nonempty=True)
    result: List[Mapping[str, Any]] = []
    for index, item in enumerate(raw):
        path = f"evidence[{index}]"
        evidence = object_value(item, path)
        exact_keys(evidence, EVIDENCE_KEYS, path)
        id_value(evidence["id"], f"{path}.id")
        source_path = relative_path(
            evidence["source_path"],
            f"{path}.source_path",
            repository_root=repository_root,
            must_exist=True,
        )
        layers = text_array(evidence["layers"], f"{path}.layers", nonempty=True)
        invalid_layers = sorted(set(layers) - EVIDENCE_LAYERS)
        if invalid_layers:
            raise InventoryError(
                f"{path}.layers has invalid values: {', '.join(invalid_layers)}"
            )
        runner_path = optional_text(evidence["runner_path"], f"{path}.runner_path")
        is_compile_fail = "compile-fail" in layers
        if is_compile_fail != (runner_path is not None):
            raise InventoryError(
                f"{path} must contain compile-fail evidence if and only if runner_path is non-null"
            )
        if runner_path is None:
            validate_ordinary_test_reference(
                evidence["test_case"],
                source_path,
                f"{path}.test_case",
                repository_root,
            )
        else:
            validate_compile_fail_runner(
                runner_path,
                source_path,
                evidence["test_case"],
                path,
                repository_root,
            )
        is_real_sqlite = boolean_value(evidence["real_sqlite"], f"{path}.real_sqlite")
        referenced_environments = text_array(
            evidence["environment_ids"],
            f"{path}.environment_ids",
            identifiers=True,
        )
        unknown = sorted(set(referenced_environments) - environment_ids)
        if unknown:
            raise InventoryError(
                f"{path}.environment_ids references unknown environments: {', '.join(unknown)}"
            )
        if is_real_sqlite and not referenced_environments:
            raise InventoryError(f"{path} is real SQLite evidence but has no environment_ids")
        if not is_real_sqlite and referenced_environments:
            raise InventoryError(f"{path} is not real SQLite evidence but has environment_ids")
        result.append(evidence)
    require_unique_ids(result, "evidence")
    represented_layers = {
        layer for evidence_item in result for layer in evidence_item["layers"]
    }
    missing_layers = sorted(REQUIRED_GLOBAL_EVIDENCE_LAYERS - represented_layers)
    if missing_layers:
        raise InventoryError(
            "evidence is missing required global layers: " + ", ".join(missing_layers)
        )
    return result


def validate_suites(value: Any) -> List[Mapping[str, Any]]:
    raw = array_value(value, "suites", nonempty=True)
    result: List[Mapping[str, Any]] = []
    seen_issues: Set[int] = set()
    for index, item in enumerate(raw):
        path = f"suites[{index}]"
        suite = object_value(item, path)
        exact_keys(suite, SUITE_KEYS, path)
        id_value(suite["id"], f"{path}.id")
        issue = integer_value(suite["issue"], f"{path}.issue")
        milestone(suite["milestone"], f"{path}.milestone")
        status = enum_value(suite["status"], {"planned", "completed"}, f"{path}.status")
        case_ids = text_array(suite["case_ids"], f"{path}.case_ids", identifiers=True)
        evidence_ids = text_array(
            suite["evidence_ids"], f"{path}.evidence_ids", identifiers=True
        )
        if issue in seen_issues:
            raise InventoryError(f"duplicate conformance suite issue: {issue}")
        seen_issues.add(issue)
        expected_status = REQUIRED_SUITE_STATUSES.get(issue)
        if expected_status is None:
            raise InventoryError(f"{path}.issue is not a registered v1.3 suite issue: {issue}")
        if status != expected_status:
            raise InventoryError(
                f"{path}.status must be {expected_status!r} for issue #{issue}"
            )
        if status == "planned" and evidence_ids:
            raise InventoryError(f"{path} is planned and must not claim suite evidence")
        if status == "completed" and (not case_ids or not evidence_ids):
            raise InventoryError(
                f"{path} is completed and must register non-empty case_ids and evidence_ids"
            )
        result.append(suite)
    require_unique_ids(result, "suite")
    if seen_issues != set(REQUIRED_SUITE_STATUSES):
        missing = sorted(set(REQUIRED_SUITE_STATUSES) - seen_issues)
        raise InventoryError(
            "suites must register issues #191 and #252-#256; missing: "
            + ", ".join(f"#{issue}" for issue in missing)
        )
    return result


def validate_public_api(
    value: Any,
    path: str,
    repository_root: Path,
) -> List[Mapping[str, Any]]:
    raw = array_value(value, path)
    result: List[Mapping[str, Any]] = []
    identities: List[Tuple[str, str, Tuple[str, ...]]] = []
    for index, item in enumerate(raw):
        item_path = f"{path}[{index}]"
        api = object_value(item, item_path)
        exact_keys(api, PUBLIC_API_KEYS, item_path)
        symbol = text_value(api["symbol"], f"{item_path}.symbol")
        source_path = relative_path(
            api["source_path"],
            f"{item_path}.source_path",
            repository_root=repository_root,
            must_exist=True,
        )
        if not source_path.startswith("Sources/") or not source_path.endswith(".swift"):
            raise InventoryError(
                f"{item_path}.source_path must identify a Swift file under Sources/"
            )
        source_tokens = text_array(
            api["source_tokens"], f"{item_path}.source_tokens", nonempty=True
        )
        for token_index, token in enumerate(source_tokens):
            if SOURCE_TOKEN_PATTERN.fullmatch(token) is None:
                raise InventoryError(
                    f"{item_path}.source_tokens[{token_index}] must be one Swift "
                    "identifier or operator"
                )
            if not symbol_mentions_token(symbol, token):
                raise InventoryError(
                    f"{item_path}.symbol does not explicitly name source token {token!r}"
                )
        try:
            source = (repository_root / source_path).read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError) as error:
            raise InventoryError(
                f"{item_path}.source_path could not be inspected: {error}"
            ) from error
        declared_tokens = public_declaration_tokens(source)
        undeclared = sorted(set(source_tokens) - declared_tokens)
        if undeclared:
            raise InventoryError(
                f"{item_path}.source_tokens are not public declarations in {source_path}: "
                + ", ".join(undeclared)
            )
        identities.append((symbol, source_path, tuple(source_tokens)))
        result.append(api)
    duplicate = first_duplicate(identities)
    if duplicate is not None:
        raise InventoryError(
            f"{path} contains duplicate symbol/source_path/source_tokens: {duplicate}"
        )
    return result


def validate_deferral(value: Any, path: str) -> Optional[Mapping[str, Any]]:
    if value is None:
        return None
    deferral = object_value(value, path)
    exact_keys(deferral, DEFERRAL_KEYS, path)
    integer_value(deferral["blocking_issue"], f"{path}.blocking_issue")
    milestone(deferral["target_milestone"], f"{path}.target_milestone")
    text_value(deferral["reason"], f"{path}.reason")
    return deferral


def validate_provenance(
    value: Any,
    path: str,
    repository_root: Path,
) -> List[Mapping[str, Any]]:
    raw = array_value(value, path)
    result: List[Mapping[str, Any]] = []
    identities: List[Tuple[str, str, str, str]] = []
    for index, item in enumerate(raw):
        item_path = f"{path}[{index}]"
        provenance = object_value(item, item_path)
        exact_keys(provenance, PROVENANCE_KEYS, item_path)
        repository = text_value(provenance["repository"], f"{item_path}.repository")
        commit = text_value(provenance["commit"], f"{item_path}.commit")
        if not SHA_PATTERN.fullmatch(commit):
            raise InventoryError(f"{item_path}.commit must be a full lowercase 40-hex SHA")
        upstream_path = relative_path(provenance["path"], f"{item_path}.path")
        upstream_case = text_value(provenance["upstream_case"], f"{item_path}.upstream_case")
        license_spdx = text_value(provenance["license_spdx"], f"{item_path}.license_spdx")
        if not SPDX_PATTERN.fullmatch(license_spdx):
            raise InventoryError(f"{item_path}.license_spdx is not a simple SPDX identifier")
        relative_path(provenance["license_file_path"], f"{item_path}.license_file_path")
        license_url = https_url(provenance["license_file_url"], f"{item_path}.license_file_url")
        if commit not in license_url:
            raise InventoryError(
                f"{item_path}.license_file_url must pin the provenance commit"
            )
        license_blob_sha = text_value(
            provenance["license_blob_sha"], f"{item_path}.license_blob_sha"
        )
        if not SHA_PATTERN.fullmatch(license_blob_sha):
            raise InventoryError(
                f"{item_path}.license_blob_sha must be a full lowercase 40-hex SHA"
            )
        text_value(provenance["license_disposition"], f"{item_path}.license_disposition")
        copied_material = boolean_value(
            provenance["copied_material"], f"{item_path}.copied_material"
        )
        notice_path = optional_text(provenance["notice_path"], f"{item_path}.notice_path")
        if notice_path is not None:
            relative_path(
                notice_path,
                f"{item_path}.notice_path",
                repository_root=repository_root,
                must_exist=True,
            )
        if copied_material and notice_path is None:
            raise InventoryError(
                f"{item_path}.notice_path is required when copied_material is true"
            )
        text_value(provenance["adaptation_notes"], f"{item_path}.adaptation_notes")
        identities.append((repository, commit, upstream_path, upstream_case))
        result.append(provenance)
    duplicate = first_duplicate(identities)
    if duplicate is not None:
        raise InventoryError(f"{path} contains duplicate upstream provenance: {duplicate}")
    return result


def validate_features(
    value: Any,
    repository_root: Path,
    environments: Sequence[Mapping[str, Any]],
    evidence: Sequence[Mapping[str, Any]],
) -> List[Mapping[str, Any]]:
    raw = array_value(value, "features", nonempty=True)
    evidence_by_id = {item["id"]: item for item in evidence}
    environment_by_id = {item["id"]: item for item in environments}
    reviewed_pairs = {
        (item["sqlite_version"], item["sqlite_source_id"]) for item in environments
    }
    result: List[Mapping[str, Any]] = []
    for index, item in enumerate(raw):
        path = f"features[{index}]"
        feature = object_value(item, path)
        exact_keys(feature, FEATURE_KEYS, path)
        identifier = id_value(feature["id"], f"{path}.id")
        kind = enum_value(feature["kind"], FEATURE_KINDS, f"{path}.kind")
        id_value(feature["family"], f"{path}.family")
        text_value(feature["title"], f"{path}.title")
        status = enum_value(feature["status"], FEATURE_STATUSES, f"{path}.status")
        adoption_status = enum_value(
            feature["adoption_status"], ADOPTION_STATUSES, f"{path}.adoption_status"
        )
        public_api = validate_public_api(feature["public_api"], f"{path}.public_api", repository_root)

        documentation = array_value(
            feature["sqlite_documentation_urls"], f"{path}.sqlite_documentation_urls"
        )
        documentation_urls = [
            https_url(url, f"{path}.sqlite_documentation_urls[{url_index}]", sqlite_documentation=True)
            for url_index, url in enumerate(documentation)
        ]
        duplicate_url = first_duplicate(documentation_urls)
        if duplicate_url is not None:
            raise InventoryError(
                f"{path}.sqlite_documentation_urls contains duplicate URL: {duplicate_url}"
            )
        syntax_reason = optional_text(
            feature["not_sqlite_syntax_reason"], f"{path}.not_sqlite_syntax_reason"
        )
        non_sqlite_exception = kind == "adopted-behavior" and syntax_reason is not None
        if documentation_urls and syntax_reason is not None:
            raise InventoryError(
                f"{path}.not_sqlite_syntax_reason must be null when SQLite documentation is present"
            )
        if not documentation_urls and not non_sqlite_exception:
            raise InventoryError(
                f"{path} must cite SQLite documentation or explain a non-SQLite adopted behavior"
            )

        minimum_version_value = feature["minimum_sqlite_version"]
        if minimum_version_value is None:
            if not non_sqlite_exception:
                raise InventoryError(
                    f"{path}.minimum_sqlite_version may be null only for non-SQLite adopted behavior"
                )
        else:
            semver(minimum_version_value, f"{path}.minimum_sqlite_version")
        reviewed_release = semver(
            feature["reviewed_sqlite_release"], f"{path}.reviewed_sqlite_release"
        )
        reviewed_source = text_value(
            feature["reviewed_sqlite_source_id"], f"{path}.reviewed_sqlite_source_id"
        )
        if (reviewed_release, reviewed_source) not in reviewed_pairs:
            raise InventoryError(
                f"{path} reviewed SQLite release/source is not a recorded environment"
            )

        required_capabilities = text_array(
            feature["required_capabilities"], f"{path}.required_capabilities"
        )
        text_array(feature["schema_requirements"], f"{path}.schema_requirements")
        referenced_evidence = text_array(
            feature["evidence_ids"], f"{path}.evidence_ids", identifiers=True
        )
        unknown_evidence = sorted(set(referenced_evidence) - set(evidence_by_id))
        if unknown_evidence:
            raise InventoryError(
                f"{path}.evidence_ids references unknown evidence: {', '.join(unknown_evidence)}"
            )
        deviations = text_array(feature["deviations"], f"{path}.deviations")
        follow_up_issues = integer_array(feature["follow_up_issues"], f"{path}.follow_up_issues")
        deferral = validate_deferral(feature["deferral"], f"{path}.deferral")
        provenance = validate_provenance(
            feature["provenance"], f"{path}.provenance", repository_root
        )

        if not provenance and kind == "adopted-behavior":
            raise InventoryError(
                f"{path}.provenance is required for an adopted behavior"
            )
        if status == "supported" and not public_api:
            raise InventoryError(f"{path} is supported but has no public_api")
        if status in DEFERRAL_STATUSES and deferral is None:
            raise InventoryError(f"{path}.status {status!r} requires deferral metadata")
        if adoption_status in DEFERRAL_ADOPTION_STATUSES and deferral is None:
            raise InventoryError(
                f"{path}.adoption_status {adoption_status!r} requires deferral metadata"
            )
        if deferral is not None and deferral["blocking_issue"] not in follow_up_issues:
            raise InventoryError(
                f"{path}.follow_up_issues must include deferral.blocking_issue"
            )
        if status == "supported" and deferral is not None:
            raise InventoryError(f"{path} is supported and must not have deferral metadata")
        if status == "capability-gated" and not required_capabilities:
            raise InventoryError(
                f"{path} is capability-gated but required_capabilities is empty"
            )
        if status == "intentionally-unsupported" and not deviations:
            raise InventoryError(
                f"{path} is intentionally unsupported but has no explicit deviation"
            )
        if adoption_status == "intentionally-out-of-scope" and not deviations:
            raise InventoryError(
                f"{path} is intentionally out of scope but has no explicit deviation"
            )
        if adoption_status == "already-covered" and status not in {
            "supported",
            "partial",
            "capability-gated",
        }:
            raise InventoryError(
                f"{path}.adoption_status 'already-covered' is inconsistent with status {status!r}"
            )
        if status == "supported" and adoption_status != "already-covered":
            raise InventoryError(
                f"{path} is supported but adoption_status is not 'already-covered'"
            )
        if (status == "intentionally-unsupported") != (
            adoption_status == "intentionally-out-of-scope"
        ):
            raise InventoryError(
                f"{path} must pair intentionally-unsupported with intentionally-out-of-scope"
            )

        if status == "supported":
            evidence_items = [evidence_by_id[evidence_id] for evidence_id in referenced_evidence]
            real_prepare = [
                item
                for item in evidence_items
                if item["real_sqlite"] and "prepare" in item["layers"]
            ]
            if not real_prepare:
                raise InventoryError(
                    f"{path} is supported but lacks referenced real-SQLite prepare evidence"
                )
            if kind == "syntax" and not any(
                "rendering" in item["layers"] for item in evidence_items
            ):
                raise InventoryError(
                    f"{path} is supported syntax but lacks rendering evidence"
                )
            proven_capabilities: Set[str] = set()
            for evidence_item in real_prepare:
                for environment_id in evidence_item["environment_ids"]:
                    proven_capabilities.update(environment_by_id[environment_id]["capabilities"])
            missing_capabilities = sorted(set(required_capabilities) - proven_capabilities)
            if missing_capabilities:
                raise InventoryError(
                    f"{path} supported claim lacks prepare-environment capabilities: "
                    + ", ".join(missing_capabilities)
                )

        result.append(feature)
    require_unique_ids(result, "feature")
    syntax_families = {item["family"] for item in result if item["kind"] == "syntax"}
    missing_families = sorted(REQUIRED_FAMILIES - syntax_families)
    if missing_families:
        raise InventoryError(
            "features are missing required syntax families: " + ", ".join(missing_families)
        )
    return result


def validate_cross_references(
    environments: Sequence[Mapping[str, Any]],
    evidence: Sequence[Mapping[str, Any]],
    suites: Sequence[Mapping[str, Any]],
    features: Sequence[Mapping[str, Any]],
) -> None:
    del environments  # Environment references are checked while validating evidence/features.
    evidence_ids = {item["id"] for item in evidence}
    feature_ids = {item["id"] for item in features}
    completed_suite_issues = {
        item["issue"] for item in suites if item["status"] == "completed"
    }
    referenced_evidence: Set[str] = set()
    for index, feature in enumerate(features):
        deferral = feature["deferral"]
        if (
            deferral is not None
            and deferral["blocking_issue"] in completed_suite_issues
        ):
            raise InventoryError(
                f"features[{index}].deferral.blocking_issue references completed "
                f"suite issue #{deferral['blocking_issue']}"
            )
        referenced_evidence.update(feature["evidence_ids"])
    for index, suite in enumerate(suites):
        path = f"suites[{index}]"
        unknown_cases = sorted(set(suite["case_ids"]) - feature_ids)
        if unknown_cases:
            raise InventoryError(
                f"{path}.case_ids references unknown features: {', '.join(unknown_cases)}"
            )
        unknown_evidence = sorted(set(suite["evidence_ids"]) - evidence_ids)
        if unknown_evidence:
            raise InventoryError(
                f"{path}.evidence_ids references unknown evidence: {', '.join(unknown_evidence)}"
            )
        if suite["status"] == "completed":
            referenced_evidence.update(suite["evidence_ids"])
    orphaned = sorted(evidence_ids - referenced_evidence)
    if orphaned:
        raise InventoryError(
            "evidence is not referenced by a feature or completed suite: "
            + ", ".join(orphaned)
        )


def validate_inventory(
    document: Mapping[str, Any], repository_root: Path
) -> Mapping[str, Any]:
    exact_keys(document, TOP_LEVEL_KEYS, "inventory")
    if document["schema_version"] != SCHEMA_VERSION or type(document["schema_version"]) is not int:
        raise InventoryError(f"schema_version must be integer {SCHEMA_VERSION}")
    if document["inventory_version"] != INVENTORY_VERSION:
        raise InventoryError(f"inventory_version must be {INVENTORY_VERSION!r}")
    if document["coordination_issue"] != COORDINATION_ISSUE or type(document["coordination_issue"]) is not int:
        raise InventoryError(f"coordination_issue must be integer {COORDINATION_ISSUE}")

    validate_scope(document["scope"])
    environments = validate_environments(document["sqlite_environments"])
    evidence = validate_evidence(
        document["evidence"], repository_root, {item["id"] for item in environments}
    )
    suites = validate_suites(document["suites"])
    features = validate_features(
        document["features"], repository_root, environments, evidence
    )
    validate_cross_references(environments, evidence, suites, features)
    return document


def markdown_text(value: Any) -> str:
    return str(value).replace("\\", "\\\\").replace("|", "\\|").replace("\n", " ")


def code(value: Any) -> str:
    return "`" + markdown_text(value).replace("`", "\\`") + "`"


def repository_link(path: str) -> str:
    return f"[{code(path)}](../../{quote(path, safe='/')})"


def issue_link(issue: int) -> str:
    return f"[#{issue}](https://github.com/lukevanin/swiftql/issues/{issue})"


def documentation_links(urls: Sequence[str], empty: str = "—") -> str:
    rendered = []
    for url in urls:
        parsed = urlparse(url)
        label = f"{parsed.hostname}{parsed.path}"
        if parsed.fragment:
            label += f"#{parsed.fragment}"
        rendered.append(f"[{code(label)}]({url})")
    return "<br>".join(rendered) if rendered else empty


def joined_codes(values: Iterable[Any], empty: str = "—") -> str:
    rendered = [code(value) for value in values]
    return ", ".join(rendered) if rendered else empty


def count_table(title: str, counts: Mapping[str, int]) -> List[str]:
    lines = [f"### {title}", "", "| Value | Features |", "| --- | ---: |"]
    for name in sorted(counts):
        lines.append(f"| {code(name)} | {counts[name]} |")
    lines.append("")
    return lines


def render_report(document: Mapping[str, Any]) -> str:
    scope = document["scope"]
    environments = sorted(document["sqlite_environments"], key=lambda item: item["id"])
    evidence = sorted(document["evidence"], key=lambda item: item["id"])
    suites = sorted(document["suites"], key=lambda item: (item["issue"], item["id"]))
    features = sorted(document["features"], key=lambda item: (item["family"], item["id"]))

    lines = [
        "<!-- Generated by scripts/ci/sqlite-conformance-inventory.py; do not edit. -->",
        "",
        "# SQLite conformance inventory",
        "",
        f"- Inventory version: {code(document['inventory_version'])}",
        f"- Coordination issue: {issue_link(document['coordination_issue'])}",
        "",
        "This report is generated deterministically from "
        "[`SQLiteConformanceInventory.json`](../../Tests/SwiftQLSQLiteConformanceFixtures/SQLiteConformanceInventory.json).",
        "",
        "## Claim and limits",
        "",
        markdown_text(scope["claim"]),
        "",
    ]
    lines.extend(f"- {markdown_text(limit)}" for limit in scope["limits"])
    lines.extend(
        [
            "",
            "A feature counts as supported only when it references explicit real-SQLite "
            "`prepare` evidence. Supported syntax also requires renderer evidence. "
            "Capability-gated and intentionally unsupported records are listed but never "
            "included in the supported count.",
            "",
            "## Summary",
            "",
            f"- Total feature records: **{len(features)}**",
            f"- Supported feature records: **{sum(item['status'] == 'supported' for item in features)}**",
            f"- SQLite environments: **{len(environments)}**",
            f"- Evidence records: **{len(evidence)}**",
            "",
        ]
    )
    lines.extend(count_table("Support status", Counter(item["status"] for item in features)))
    lines.extend(count_table("Adoption status", Counter(item["adoption_status"] for item in features)))
    lines.extend(count_table("Record kind", Counter(item["kind"] for item in features)))

    lines.extend(
        [
            "## SQLite environments",
            "",
            "| ID | SQLite | Source ID | Source | Captured | Toolchain | Architecture | Capabilities |",
            "| --- | --- | --- | --- | --- | --- | --- | --- |",
        ]
    )
    for environment in environments:
        lines.append(
            "| "
            + " | ".join(
                [
                    code(environment["id"]),
                    code(environment["sqlite_version"]),
                    code(environment["sqlite_source_id"]),
                    markdown_text(environment["source"]),
                    code(environment["captured_at"]),
                    markdown_text(environment["toolchain"]),
                    code(environment["architecture"]),
                    joined_codes(environment["capabilities"]),
                ]
            )
            + " |"
        )
    lines.extend(
        [
            "",
            "## Evidence suites",
            "",
            "| Suite | Issue | Milestone | Status | Cases | Evidence |",
            "| --- | --- | --- | --- | ---: | ---: |",
        ]
    )
    for suite in suites:
        lines.append(
            f"| {code(suite['id'])} | {issue_link(suite['issue'])} | "
            f"{code(suite['milestone'])} | {code(suite['status'])} | "
            f"{len(suite['case_ids'])} | {len(suite['evidence_ids'])} |"
        )

    lines.extend(
        [
            "",
            "## Feature inventory",
            "",
            "| Feature | Family | Kind | Support | Adoption | SQLite docs | Minimum SQLite | Public API | Evidence | Follow-ups |",
            "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |",
        ]
    )
    for feature in features:
        public_api = ", ".join(
            f"{code(api['symbol'])} [verified: {joined_codes(api['source_tokens'])}] "
            f"({repository_link(api['source_path'])})"
            for api in feature["public_api"]
        ) or "—"
        followups = ", ".join(issue_link(issue) for issue in feature["follow_up_issues"]) or "—"
        lines.append(
            "| "
            + " | ".join(
                [
                    f"{code(feature['id'])}<br>{markdown_text(feature['title'])}",
                    code(feature["family"]),
                    code(feature["kind"]),
                    code(feature["status"]),
                    code(feature["adoption_status"]),
                    documentation_links(feature["sqlite_documentation_urls"]),
                    code(feature["minimum_sqlite_version"])
                    if feature["minimum_sqlite_version"] is not None
                    else "N/A",
                    public_api,
                    joined_codes(feature["evidence_ids"]),
                    followups,
                ]
            )
            + " |"
        )

    constrained = [
        feature
        for feature in features
        if feature["required_capabilities"]
        or feature["schema_requirements"]
        or feature["deviations"]
        or feature["deferral"] is not None
        or feature["not_sqlite_syntax_reason"] is not None
    ]
    lines.extend(
        [
            "",
            "## Gates, deviations, and deferrals",
            "",
            "| Feature | Required capabilities | Schema requirements | Deviations or scope reason | Deferral |",
            "| --- | --- | --- | --- | --- |",
        ]
    )
    if not constrained:
        lines.append("| — | — | — | — | — |")
    for feature in constrained:
        reasons = list(feature["deviations"])
        if feature["not_sqlite_syntax_reason"] is not None:
            reasons.append(feature["not_sqlite_syntax_reason"])
        deferral = feature["deferral"]
        deferral_text = "—"
        if deferral is not None:
            deferral_text = (
                f"{issue_link(deferral['blocking_issue'])} for {code(deferral['target_milestone'])}: "
                f"{markdown_text(deferral['reason'])}"
            )
        lines.append(
            "| "
            + " | ".join(
                [
                    code(feature["id"]),
                    joined_codes(feature["required_capabilities"]),
                    "<br>".join(markdown_text(value) for value in feature["schema_requirements"]) or "—",
                    "<br>".join(markdown_text(value) for value in reasons) or "—",
                    deferral_text,
                ]
            )
            + " |"
        )

    lines.extend(
        [
            "",
            "## Evidence index",
            "",
            "| Evidence | Source and test case | Runner | Layers | Real SQLite | Environments |",
            "| --- | --- | --- | --- | --- | --- |",
        ]
    )
    for item in evidence:
        lines.append(
            "| "
            + " | ".join(
                [
                    code(item["id"]),
                    f"{repository_link(item['source_path'])}<br>{code(item['test_case'])}",
                    repository_link(item["runner_path"])
                    if item["runner_path"] is not None
                    else "—",
                    joined_codes(item["layers"]),
                    "yes" if item["real_sqlite"] else "no",
                    joined_codes(item["environment_ids"]),
                ]
            )
            + " |"
        )

    provenance_rows = [
        (feature["id"], provenance)
        for feature in features
        for provenance in feature["provenance"]
    ]
    lines.extend(
        [
            "",
            "## Pinned upstream provenance",
            "",
            "| Feature | Repository and revision | Upstream case | License | Adaptation |",
            "| --- | --- | --- | --- | --- |",
        ]
    )
    if not provenance_rows:
        lines.append("| — | — | — | — | — |")
    for feature_id, provenance in sorted(
        provenance_rows,
        key=lambda row: (
            row[0],
            row[1]["repository"],
            row[1]["path"],
            row[1]["upstream_case"],
        ),
    ):
        notice = (
            f"; notice {repository_link(provenance['notice_path'])}"
            if provenance["notice_path"] is not None
            else ""
        )
        copied = "copied material" if provenance["copied_material"] else "behavioral adaptation"
        license_text = (
            f"[{code(provenance['license_spdx'])}]({provenance['license_file_url']}) "
            f"({copied}; blob {code(provenance['license_blob_sha'])}{notice})<br>"
            f"{markdown_text(provenance['license_disposition'])}"
        )
        lines.append(
            "| "
            + " | ".join(
                [
                    code(feature_id),
                    f"{code(provenance['repository'])}@{code(provenance['commit'])}<br>{code(provenance['path'])}",
                    code(provenance["upstream_case"]),
                    license_text,
                    markdown_text(provenance["adaptation_notes"]),
                ]
            )
            + " |"
        )

    lines.extend(
        [
            "",
            "## Reproduce",
            "",
            "```sh",
            "python3 scripts/ci/sqlite-conformance-inventory.py check",
            "```",
            "",
        ]
    )
    return "\n".join(lines)


def resolve_from_root(path: Path, repository_root: Path) -> Path:
    return path if path.is_absolute() else repository_root / path


def parse_arguments(arguments: Optional[Sequence[str]] = None) -> argparse.Namespace:
    repository_root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "command",
        choices=("validate", "render", "check", "write"),
        nargs="?",
        default="check",
    )
    parser.add_argument("--repository-root", type=Path, default=repository_root)
    parser.add_argument(
        "--inventory",
        type=Path,
        default=Path("Tests/SwiftQLSQLiteConformanceFixtures/SQLiteConformanceInventory.json"),
    )
    parser.add_argument(
        "--report",
        type=Path,
        default=Path("Conformance/SQLite/REPORT.md"),
    )
    return parser.parse_args(arguments)


def run(arguments: Optional[Sequence[str]] = None) -> int:
    options = parse_arguments(arguments)
    repository_root = options.repository_root.resolve()
    inventory_path = resolve_from_root(options.inventory, repository_root)
    report_path = resolve_from_root(options.report, repository_root)
    try:
        document = validate_inventory(load_inventory(inventory_path), repository_root)
        report = render_report(document)
        if options.command == "validate":
            print(
                f"validated SQLite conformance inventory: "
                f"{len(document['features'])} features, "
                f"{len(document['evidence'])} evidence records"
            )
        elif options.command == "render":
            sys.stdout.write(report)
        elif options.command == "write":
            report_path.parent.mkdir(parents=True, exist_ok=True)
            report_path.write_text(report, encoding="utf-8")
            print(f"wrote {report_path}")
        else:
            try:
                committed = report_path.read_text(encoding="utf-8")
            except OSError as error:
                raise InventoryError(
                    f"could not read generated report {report_path}: {error}; "
                    "run sqlite-conformance-inventory.py write"
                ) from error
            if committed != report:
                raise InventoryError(
                    f"generated report is stale: {report_path}; "
                    "run sqlite-conformance-inventory.py write"
                )
            print(f"SQLite conformance report is current: {report_path}")
    except (InventoryError, OSError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(run())
