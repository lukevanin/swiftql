#!/usr/bin/env python3

"""Generate each dialect's expression surface from one set of templates.

Issue #789. An operator or a function that composes expressions is declared
once for each dialect, on that dialect's expression protocol, rather than once
generically over the dialect: generic operators make the type checker's work
grow exponentially with the length of an `&&` chain, and per-dialect overloads
keep it linear. `Research/DialectParameterTypeCheckCost.md` has the
measurements.

The operations every dialect shares are written once, as the templates in
`Templates/`. `dialects.json` lists the dialects. For each dialect, every
template is rendered into that dialect's `output` directory, which holds
nothing else, so the directory can move to another target without its
contents changing. A function only one dialect has is written by hand, on
that dialect's expression protocol, and is not generated.

A template is Swift with these placeholders:

    {{Expression}}   the dialect's expression protocol, such as XLSQLiteExpression
    {{Dialect}}      the dialect's type, such as XLSQLiteDialect
    {{DialectName}}  the dialect's name in prose, such as SQLite

The template's leading comment is replaced with a header that says the file
is generated, and a dialect's `imports` are added after `import Foundation`. A dialect whose `access` is `internal` has every `public`
modifier removed, so a test can declare a dialect without making its types
public. A dialect marked `disfavored` has `@_disfavoredOverload` added to every
function, so that where two dialects' surfaces are visible and nothing picks a
dialect, such as a function called on a Swift value, the other dialect's
overload wins rather than the call being ambiguous.

Run with no arguments to write the generated files. `--check` writes nothing,
and exits with status 1 and a list of the files that differ when any
generated file is missing, stale, or no longer generated, so CI catches a
template changed without regenerating.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Dict, List, Mapping


sys.dont_write_bytecode = True

GENERATOR = Path(__file__).resolve()
GENERATOR_DIRECTORY = GENERATOR.parent
SOURCE_ROOT = GENERATOR_DIRECTORY.parent.parent
TEMPLATE_DIRECTORY = GENERATOR_DIRECTORY / "Templates"
SPECIFICATION = GENERATOR_DIRECTORY / "dialects.json"
TEMPLATE_SUFFIX = ".swift.template"
PLACEHOLDER = re.compile(r"\{\{([A-Za-z]+)\}\}")
PUBLIC_MODIFIER = re.compile(r"\bpublic +(?=(?:(?:static|prefix|postfix|infix) +)*(?:func|protocol|struct|enum|class|var|let|init|typealias|subscript)\b)")
FUNCTION = re.compile(r"^([ \t]*)((?:public +)?(?:static +)?(?:(?:prefix|postfix|infix) +)?func\b)", re.MULTILINE)
DUPLICATE_DISFAVOURED = re.compile(r"([ \t]*@_disfavoredOverload\n)(?:[ \t]*@_disfavoredOverload\n)+")


def relative(path: Path) -> str:
    return path.relative_to(SOURCE_ROOT).as_posix()


def header(template: Path, dialect: Mapping[str, str]) -> str:
    return (
        "//\n"
        f"//  {dialect['filePrefix']}{template.name[:-len(TEMPLATE_SUFFIX)]}.swift\n"
        "//\n"
        f"//  Generated for {dialect['DialectName']} by {relative(GENERATOR)}\n"
        f"//  from {relative(template)}.\n"
        "//  Do not edit: edit the template, then run\n"
        f"//  `python3 {relative(GENERATOR)}`.\n"
        "//\n"
    )


def strip_leading_comment(text: str) -> str:
    lines = text.splitlines(keepends=True)
    index = 0
    while index < len(lines) and lines[index].startswith("//"):
        index += 1
    return "".join(lines[index:])


def render(template: Path, dialect: Mapping[str, str]) -> str:
    def substitute(match: re.Match) -> str:
        name = match.group(1)
        if name not in dialect:
            raise SystemExit(f"{relative(template)}: unknown placeholder {{{{{name}}}}}")
        return dialect[name]

    body = PLACEHOLDER.sub(substitute, strip_leading_comment(template.read_text()))
    imports = "".join(f"import {module}\n" for module in dialect.get("imports", []))
    if imports:
        if "import Foundation\n" not in body:
            raise SystemExit(f"{relative(template)}: no `import Foundation` to add imports after")
        body = body.replace("import Foundation\n", "import Foundation\n" + imports, 1)
    if dialect.get("disfavored"):
        body = FUNCTION.sub(r"\1@_disfavoredOverload\n\1\2", body)
        # A function the template already disfavours keeps one attribute.
        body = DUPLICATE_DISFAVOURED.sub(r"\1", body)
    if dialect.get("access", "public") == "internal":
        body = PUBLIC_MODIFIER.sub("", body)
    return header(template, dialect) + body


def load_dialects() -> List[Dict[str, str]]:
    dialects = json.loads(SPECIFICATION.read_text())["dialects"]
    required = ("Expression", "Dialect", "DialectName", "filePrefix", "output")
    for dialect in dialects:
        missing = [key for key in required if key not in dialect]
        if missing:
            raise SystemExit(f"{relative(SPECIFICATION)}: a dialect lacks {', '.join(missing)}")
    return dialects


def expected_files() -> Dict[Path, str]:
    templates = sorted(TEMPLATE_DIRECTORY.glob("*" + TEMPLATE_SUFFIX))
    if not templates:
        raise SystemExit(f"no templates in {relative(TEMPLATE_DIRECTORY)}")
    files: Dict[Path, str] = {}
    for dialect in load_dialects():
        output = SOURCE_ROOT / dialect["output"]
        for template in templates:
            name = dialect["filePrefix"] + template.name[:-len(TEMPLATE_SUFFIX)] + ".swift"
            files[output / name] = render(template, dialect)
    return files


def output_directories() -> List[Path]:
    return [SOURCE_ROOT / dialect["output"] for dialect in load_dialects()]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--check",
        action="store_true",
        help="write nothing; fail when a generated file is missing, stale, or extra",
    )
    arguments = parser.parse_args()

    files = expected_files()
    extra = [
        path
        for directory in output_directories()
        if directory.is_dir()
        for path in sorted(directory.glob("*.swift"))
        if path not in files
    ]
    stale = [
        path
        for path, contents in files.items()
        if not path.is_file() or path.read_text() != contents
    ]

    if arguments.check:
        if not stale and not extra:
            print(f"The generated dialect surface is up to date ({len(files)} files).")
            return 0
        for path in stale:
            print(f"stale or missing: {relative(path)}")
        for path in extra:
            print(f"not generated by any template: {relative(path)}")
        print(f"Run `python3 {relative(GENERATOR)}` and commit the result.")
        return 1

    for path in stale:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(files[path])
        print(f"wrote {relative(path)}")
    for path in extra:
        path.unlink()
        print(f"removed {relative(path)}")
    if not stale and not extra:
        print(f"The generated dialect surface is up to date ({len(files)} files).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
