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
is generated, and a dialect's `imports` are added after `import Foundation`.
A dialect whose `access` is `internal` has every `public` modifier removed
from the code, so a test can declare a dialect without making its types
public. A dialect marked `disfavored` has `@_disfavoredOverload` added to every
function, initializer, and subscript, so that where two dialects' surfaces are
visible and nothing picks a dialect, such as a function called on a Swift
value, the other dialect's overload wins rather than the call being
ambiguous. Both rewrites are checked after they run, and a declaration they
did not reach stops the generator, so a template written in a form they do
not recognise fails loudly instead of generating the wrong access or an
ambiguous overload.

dialects.json is checked too: a key the generator does not know, or a value
it does not accept, stops it rather than falling back to a default.

Run with no arguments to write the generated files, and to delete a file
that says this generator wrote it but that nothing generates any more, such
as a removed dialect's. `--check` writes nothing, and exits with status 1 and
a list of the files that differ when any generated file is missing, stale, or
no longer generated, so CI catches a template changed without regenerating.
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
PUBLIC = re.compile(r"\bpublic\b *")
# A function, initializer, or subscript declaration, with any modifiers and
# attributes written before it on the same line.
DECLARATION = re.compile(
    r"^([ \t]*)((?:(?:@\w+(?:\([^)]*\))?|public|internal|static|class|final|mutating|nonmutating|override|prefix|postfix|infix|convenience|required) +)*(?:func|init|subscript)\b)",
    re.MULTILINE,
)
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
        body = DECLARATION.sub(r"\1@_disfavoredOverload\n\1\2", body)
        # A function the template already disfavours keeps one attribute.
        body = DUPLICATE_DISFAVOURED.sub(r"\1", body)
        check_disfavoured(template, body)
    if dialect.get("access", "public") == "internal":
        body = "".join(
            line if is_comment(line) else PUBLIC.sub("", line)
            for line in body.splitlines(keepends=True)
        )
        check_internal(template, body)
    return header(template, dialect) + body


def is_comment(line: str) -> bool:
    return line.lstrip().startswith("//")


def check_internal(template: Path, body: str) -> None:
    for number, line in enumerate(body.splitlines(), start=1):
        if not is_comment(line) and re.search(r"\bpublic\b", line):
            raise SystemExit(f"{relative(template)}: line {number} is still public: {line.strip()}")


def check_disfavoured(template: Path, body: str) -> None:
    lines = body.splitlines()
    for number, line in enumerate(lines):
        if is_comment(line) or not re.search(r"\b(?:func|init|subscript)\b(?:[\s<(]|$)", line):
            continue
        if not DECLARATION.match(line + "\n"):
            raise SystemExit(
                f"{relative(template)}: cannot tell whether line {number + 1} declares a function; "
                f"write its modifiers in a form generate.py recognises: {line.strip()}"
            )
        previous = number - 1
        while previous >= 0 and lines[previous].lstrip().startswith("@"):
            if lines[previous].strip() == "@_disfavoredOverload":
                break
            previous -= 1
        if previous < 0 or lines[previous].strip() != "@_disfavoredOverload":
            raise SystemExit(f"{relative(template)}: line {number + 1} is not disfavoured: {line.strip()}")


REQUIRED_KEYS = ("Expression", "Dialect", "DialectName", "filePrefix", "output")
OPTIONAL_KEYS = ("access", "disfavored", "imports")
ACCESS_LEVELS = ("public", "internal")
# The roots searched for a generated file that no dialect generates any more,
# such as the output of a dialect removed from dialects.json.
GENERATED_ROOTS = ("Sources", "Tests")
GENERATED_MARKER = f"by {GENERATOR.relative_to(SOURCE_ROOT).as_posix()}\n"


def load_dialects() -> List[Dict[str, str]]:
    """Reads dialects.json, refusing a key or value the generator does not use,
    so a misspelled option fails rather than silently taking its default."""
    dialects = json.loads(SPECIFICATION.read_text())["dialects"]
    for dialect in dialects:
        name = dialect.get("DialectName", "a dialect")
        missing = [key for key in REQUIRED_KEYS if key not in dialect]
        if missing:
            raise SystemExit(f"{relative(SPECIFICATION)}: {name} lacks {', '.join(missing)}")
        unknown = [key for key in dialect if key not in REQUIRED_KEYS + OPTIONAL_KEYS]
        if unknown:
            raise SystemExit(f"{relative(SPECIFICATION)}: {name} has unknown keys {', '.join(unknown)}")
        if dialect.get("access", "public") not in ACCESS_LEVELS:
            raise SystemExit(f"{relative(SPECIFICATION)}: {name}'s access must be one of {', '.join(ACCESS_LEVELS)}")
        if not isinstance(dialect.get("disfavored", False), bool):
            raise SystemExit(f"{relative(SPECIFICATION)}: {name}'s disfavored must be true or false")
        if not isinstance(dialect.get("imports", []), list):
            raise SystemExit(f"{relative(SPECIFICATION)}: {name}'s imports must be a list")
    # Each dialect's output directory holds its files and nothing else, so it
    # can move to its own target.
    outputs = [Path(dialect["output"]) for dialect in dialects]
    for index, output in enumerate(outputs):
        for other in outputs[index + 1:]:
            if output == other or output in other.parents or other in output.parents:
                raise SystemExit(f"{relative(SPECIFICATION)}: two dialects share the output {output} or {other}")
    return dialects


def expected_files(dialects: List[Dict[str, str]]) -> Dict[Path, str]:
    templates = sorted(TEMPLATE_DIRECTORY.glob("*" + TEMPLATE_SUFFIX))
    if not templates:
        raise SystemExit(f"no templates in {relative(TEMPLATE_DIRECTORY)}")
    files: Dict[Path, str] = {}
    for dialect in dialects:
        output = SOURCE_ROOT / dialect["output"]
        for template in templates:
            name = dialect["filePrefix"] + template.name[:-len(TEMPLATE_SUFFIX)] + ".swift"
            files[output / name] = render(template, dialect)
    return files


def says_generated(path: Path) -> bool:
    with path.open() as handle:
        header = "".join(handle.readline() for _ in range(5))
    return GENERATED_MARKER in header


def generated_files_on_disk(dialects: List[Dict[str, str]]) -> List[Path]:
    """Every Swift file under Sources or Tests whose header says this
    generator wrote it. A Swift file in a dialect's output directory without
    that header stops the generator: the directory holds only generated
    files, and the generator never deletes a file it did not write."""
    found = set()
    for dialect in dialects:
        directory = SOURCE_ROOT / dialect["output"]
        if not directory.is_dir():
            continue
        for path in directory.glob("*.swift"):
            if not says_generated(path):
                raise SystemExit(
                    f"{relative(path)} was not written by {relative(GENERATOR)}. "
                    f"{dialect['output']} holds only generated files; move the file out of it."
                )
    for root in GENERATED_ROOTS:
        for path in (SOURCE_ROOT / root).rglob("*.swift"):
            if ".build" in path.parts:
                continue
            if says_generated(path):
                found.add(path)
    return sorted(found)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--check",
        action="store_true",
        help="write nothing; fail when a generated file is missing, stale, or extra",
    )
    arguments = parser.parse_args()

    dialects = load_dialects()
    files = expected_files(dialects)
    extra = [path for path in generated_files_on_disk(dialects) if path not in files]
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
