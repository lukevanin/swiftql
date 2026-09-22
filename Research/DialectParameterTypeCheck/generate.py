#!/usr/bin/env python3
"""Generate the dialect-parameter type-check harness.

Three surfaces are generated from the same operator inventory, which is read
out of the real SwiftQL sources so the overload count matches the shipped API:

  current  - `any XLExpression<T>` operands, `some XLExpression<U>` results.
  existent - `any XLExpr<T, D>` operands, `some XLExpr<U, D>` results, plus the
             raw-value overloads that an existential surface needs because a
             concrete type such as `String` cannot conform for every dialect.
  concrete - `XLExpr<T, D>` struct operands and results, plus the same
             raw-value overloads.

Each surface gets query files of N clauses that are byte-for-byte the same
shape, so the only difference the compiler sees is the surface.
"""

import os
import re
import sys

REPO = sys.argv[1]
ROOT = sys.argv[2]
OPERATOR_DIR = os.path.join(REPO, "Sources", "SwiftQL", "Operators")

DECL = re.compile(
    r"^public\s+(?P<fixity>prefix\s+|postfix\s+)?func\s+"
    r"(?P<name>==|!=|<=|>=|&&|\|\||[-+*/%<>!~])\s*"
    r"(?P<generics><[^(]*?>)?\s*"
    r"\((?P<params>[^)]*)\)\s*->\s*(?P<result>.+?)\s*(?P<where>where\s+.+?)?\s*\{\s*$"
)


MEMBER = re.compile(
    r"^\s+public\s+func\s+(?P<name>\w+)\s*"
    r"(?P<generics><[^(]*?>)?\s*"
    r"\((?P<params>[^)]*)\)\s*->\s*(?P<result>.+?)\s*(?P<where>where\s+.+?)?\s*\{\s*$"
)

FUNCTION_DIR = os.path.join(REPO, "Sources", "SwiftQL", "Functions")

# Only the vocabulary the harness itself defines. A member that names a type
# outside this set is skipped rather than stubbed, so no signature is invented.
KNOWN = {
    "any", "some", "where", "func", "public", "self", "Self", "inout",
    "XLExpression", "XLEquatable", "XLComparable", "Optional",
    "String", "Int", "Double", "Bool", "T", "V", "U", "Wrapped", "Element",
}


def known_vocabulary(text):
    for word in re.findall(r"[A-Za-z_][A-Za-z0-9_]*", text):
        if word in KNOWN:
            continue
        return False
    return True


def read_declarations():
    """Return every free operator declaration in Sources/SwiftQL/Operators."""
    declarations = []
    for name in sorted(os.listdir(OPERATOR_DIR)):
        if not name.endswith(".swift"):
            continue
        with open(os.path.join(OPERATOR_DIR, name)) as handle:
            for line in handle:
                line = line.rstrip("\n")
                if not line.startswith("public "):
                    # Indented declarations are members of an extension, not
                    # the free operator set this member pass reads.
                    continue
                match = DECL.match(line)
                if not match:
                    continue
                if "XLExpression" not in line:
                    # Plain Swift overloads such as `prefix func -(operand: Int)`.
                    continue
                declarations.append(match.groupdict())
    return declarations


def read_members():
    """Return every `extension XLExpression` member the harness can restate."""
    members = []
    for directory in (OPERATOR_DIR, FUNCTION_DIR):
        for name in sorted(os.listdir(directory)):
            if not name.endswith(".swift"):
                continue
            with open(os.path.join(directory, name)) as handle:
                inside = False
                for line in handle:
                    line = line.rstrip("\n")
                    if line.startswith("extension XLExpression"):
                        inside = line.rstrip(" {") in (
                            "extension XLExpression",
                        )
                        continue
                    if line.startswith("}"):
                        inside = False
                        continue
                    if not inside:
                        continue
                    match = MEMBER.match(line)
                    if not match:
                        continue
                    fields = match.groupdict()
                    if "..." in fields["params"]:
                        continue
                    if "=" in fields["params"]:
                        continue
                    signature = "{} {} {} {}".format(
                        fields["generics"] or "",
                        fields["params"],
                        fields["result"],
                        fields["where"] or "",
                    )
                    if not known_vocabulary(signature):
                        continue
                    if "XLExpression" not in fields["params"] + fields["result"]:
                        continue
                    members.append(fields)
    return members


def normalise(text):
    return re.sub(r"\s+", " ", text).strip()


ANY_EXPR = re.compile(r"any\s+XLExpression\s*<\s*(?P<arg>.+?)\s*>(?=[,)\s]|$)")
SOME_EXPR = re.compile(r"some\s+XLExpression\s*<\s*(?P<arg>.+?)\s*>\s*$")


def strip_optional(text):
    text = normalise(text)
    match = re.fullmatch(r"Optional<(.+)>", text)
    if match:
        return match.group(1), True
    if text.endswith("?"):
        return text[:-1], True
    return text, False


def operand_types(params):
    """Return [(label, type-argument)] for each `any XLExpression<...>` operand."""
    operands = []
    depth = 0
    current = ""
    for character in params:
        if character == "<":
            depth += 1
        elif character == ">":
            depth -= 1
        if character == "," and depth == 0:
            operands.append(current)
            current = ""
        else:
            current += character
    if current.strip():
        operands.append(current)
    result = []
    for operand in operands:
        label, _, type_text = operand.partition(":")
        match = ANY_EXPR.search(type_text)
        if not match:
            return None
        result.append((label.strip(), normalise(match.group("arg"))))
    return result


PRELUDE_COMMON = """\
// Generated by Research/DialectParameterTypeCheck/generate.py. Do not edit.
//
// A stand-in for the SwiftQL query surface that carries the same operator
// inventory and the same signature shapes as the shipped API, with the bodies
// removed. Only the surface under measurement is compiled into each module, so
// a query file sees one overload set and not two.

public struct XLBuilder {
    public init() {}
}

public protocol XLEncodable {
    func makeSQL(context: inout XLBuilder)
}
"""

PRELUDE_CURRENT = PRELUDE_COMMON + """
public protocol XLExpression<T>: XLEncodable {
    associatedtype T
}

public protocol XLEquatable: XLExpression {}

public protocol XLComparable: XLEquatable {}

public struct XLNode<T>: XLExpression {
    public init() {}
    public func makeSQL(context: inout XLBuilder) {}
}

public struct XLColumnReference<T>: XLExpression {
    public init() {}
    public func makeSQL(context: inout XLBuilder) {}
}

extension Bool: XLExpression, XLEquatable, XLComparable {
    public typealias T = Self
    public func makeSQL(context: inout XLBuilder) {}
}

extension Int: XLExpression, XLEquatable, XLComparable {
    public typealias T = Self
    public func makeSQL(context: inout XLBuilder) {}
}

extension Double: XLExpression, XLEquatable, XLComparable {
    public typealias T = Self
    public func makeSQL(context: inout XLBuilder) {}
}

extension String: XLExpression, XLEquatable, XLComparable {
    public typealias T = Self
    public func makeSQL(context: inout XLBuilder) {}
}

extension Optional: XLEncodable where Wrapped: XLEncodable {
    public func makeSQL(context: inout XLBuilder) {}
}

extension Optional: XLExpression where Wrapped: XLExpression {
    public typealias T = Self
}

@resultBuilder
public enum XLGateQueryBuilder {
    public static func buildBlock(
        _ clauses: any XLEncodable...
    ) -> [any XLEncodable] {
        clauses
    }
}

public struct XLGateScope {
    public init() {}
"""

SURFACE_ONLY_SQLITE = {
    "current": """
extension XLExpression {
    public func collate(_ collation: String) -> some XLExpression<T> { XLNode() }
}
""",
    "existential": """
extension XLExpr where Dialect == XLGateSQLite {
    public func collate(_ collation: String) -> some XLExpr<T, Dialect> {
        XLNode<T, Dialect>()
    }
}
""",
    "concrete": """
extension XLExpr where Dialect == XLGateSQLite {
    public func collate(_ collation: String) -> XLExpr<T, Dialect> {
        XLExpr<T, Dialect>()
    }
}
""",
}

PRELUDE_DIALECT = """
public protocol XLGateDialect {}

public enum XLGateSQLite: XLGateDialect {}

public enum XLGatePostgreSQL: XLGateDialect {}

public protocol XLEquatableValue {}

public protocol XLComparableValue: XLEquatableValue {}

extension Bool: XLComparableValue {}
extension Int: XLComparableValue {}
extension Double: XLComparableValue {}
extension String: XLComparableValue {}
extension Optional: XLEquatableValue where Wrapped: XLEquatableValue {}
extension Optional: XLComparableValue where Wrapped: XLComparableValue {}
"""

PRELUDE_EXISTENTIAL = PRELUDE_COMMON + PRELUDE_DIALECT + """
public protocol XLExpr<T, Dialect>: XLEncodable {
    associatedtype T
    associatedtype Dialect: XLGateDialect
}

public struct XLNode<T, Dialect: XLGateDialect>: XLExpr {
    public init() {}
    public func makeSQL(context: inout XLBuilder) {}
}

public struct XLColumnReference<T, Dialect: XLGateDialect>: XLExpr {
    public init() {}
    public func makeSQL(context: inout XLBuilder) {}
}

@resultBuilder
public enum XLGateQueryBuilder {
    public static func buildBlock(
        _ clauses: any XLEncodable...
    ) -> [any XLEncodable] {
        clauses
    }
}

public struct XLGateScope<Dialect: XLGateDialect> {
    public init() {}
"""

PRELUDE_CONCRETE = PRELUDE_COMMON + PRELUDE_DIALECT + """
public struct XLExpr<T, Dialect: XLGateDialect>: XLEncodable {
    public init() {}
    public func makeSQL(context: inout XLBuilder) {}
}

extension XLExpr: ExpressibleByUnicodeScalarLiteral where T == String {
    public init(unicodeScalarLiteral: Unicode.Scalar) { self.init() }
}

extension XLExpr: ExpressibleByExtendedGraphemeClusterLiteral where T == String {
    public init(extendedGraphemeClusterLiteral: Character) { self.init() }
}

extension XLExpr: ExpressibleByStringLiteral where T == String {
    public init(stringLiteral: String) { self.init() }
}

extension XLExpr: ExpressibleByIntegerLiteral where T == Int {
    public init(integerLiteral: Int) { self.init() }
}

extension XLExpr: ExpressibleByFloatLiteral where T == Double {
    public init(floatLiteral: Double) { self.init() }
}

extension XLExpr: ExpressibleByBooleanLiteral where T == Bool {
    public init(booleanLiteral: Bool) { self.init() }
}

@resultBuilder
public enum XLGateQueryBuilder {
    public static func buildBlock(
        _ clauses: any XLEncodable...
    ) -> [any XLEncodable] {
        clauses
    }
}

public struct XLGateScope<Dialect: XLGateDialect> {
    public init() {}
"""

# The columns every query file reads. Kept small enough to stay readable and
# wide enough that the clause rotation below never repeats one comparison.
COLUMNS = [
    ("text0", "String"),
    ("text1", "String"),
    ("text2", "Optional<String>"),
    ("count0", "Int"),
    ("count1", "Int"),
    ("count2", "Optional<Int>"),
    ("amount0", "Double"),
    ("amount1", "Optional<Double>"),
    ("flag0", "Bool"),
    ("flag1", "Optional<Bool>"),
]


def scope_members(kind):
    lines = []
    for name, type_name in COLUMNS:
        if kind == "current":
            lines.append(
                f"    public let {name} = XLColumnReference<{type_name}>()"
            )
        elif kind == "existential":
            lines.append(
                f"    public let {name} = XLColumnReference<{type_name}, Dialect>()"
            )
        else:
            lines.append(
                f"    public let {name} = XLExpr<{type_name}, Dialect>()"
            )
    lines.append("}")
    return "\n".join(lines)


def rewrite_signature(declaration, kind):
    """Return the declaration rendered for one surface, plus its raw variants."""
    generics = declaration["generics"] or ""
    params = declaration["params"]
    result = declaration["result"]
    clause = declaration["where"] or ""
    name = declaration["name"]
    fixity = (declaration["fixity"] or "").strip()
    fixity = f"{fixity} " if fixity else ""

    operands = operand_types(params)
    if operands is None:
        return []

    result_match = SOME_EXPR.search(normalise(result))
    if not result_match:
        return []
    result_argument = normalise(result_match.group("arg"))

    if kind == "current":
        rendered = (
            f"public {fixity}func {name}{generics}({params}) -> {result} "
            f"{clause}".strip()
        )
        return [rendered + " { XLNode() }"]

    # `XLEquatable` and `XLComparable` refine `XLExpression` today, so a
    # dialect surface names the value-level markers instead.
    clause = clause.replace("XLEquatable", "XLEquatableValue")
    clause = clause.replace("XLComparable", "XLComparableValue")

    # Both dialect surfaces add one generic parameter and rename the protocol.
    if generics:
        inner = generics[1:-1].strip()
        new_generics = f"<{inner}, D: XLGateDialect>"
    else:
        new_generics = "<D: XLGateDialect>"

    def operand_text(label, argument):
        if kind == "existential":
            return f"{label}: any XLExpr<{argument}, D>"
        return f"{label}: XLExpr<{argument}, D>"

    if kind == "existential":
        result_text = f"some XLExpr<{result_argument}, D>"
        body = " { XLNode<" + result_argument + ", D>() }"
    else:
        result_text = f"XLExpr<{result_argument}, D>"
        body = " { XLExpr<" + result_argument + ", D>() }"

    rendered = []
    expression_params = ", ".join(
        operand_text(label, argument) for label, argument in operands
    )
    rendered.append(
        f"public {fixity}func {name}{new_generics}({expression_params}) -> "
        f"{result_text} {clause}".strip()
        + body
    )

    # A raw Swift value cannot be lifted implicitly once the operand carries a
    # dialect, so a dialect surface needs one overload per side that takes the
    # value type directly. Unary operators have only one operand and need none.
    if len(operands) == 2:
        left, right = operands
        rendered.append(
            f"public {fixity}func {name}{new_generics}"
            f"({operand_text(left[0], left[1])}, {right[0]}: {right[1]}) -> "
            f"{result_text} {clause}".strip()
            + body
        )
        rendered.append(
            f"public {fixity}func {name}{new_generics}"
            f"({left[0]}: {left[1]}, {operand_text(right[0], right[1])}) -> "
            f"{result_text} {clause}".strip()
            + body
        )
    return rendered


def rewrite_member(member, kind):
    """Return the member rendered for one surface, plus its raw variants."""
    generics = member["generics"] or ""
    params = member["params"]
    result = member["result"]
    clause = member["where"] or ""
    name = member["name"]

    operands = operand_types(params)
    if operands is None:
        return []
    result_match = SOME_EXPR.search(normalise(result))
    if not result_match:
        return []
    result_argument = normalise(result_match.group("arg"))

    if kind == "current":
        return [
            f"    public func {name}{generics}({params}) -> {result} "
            f"{clause}".strip()
            + " { XLNode() }"
        ]

    clause = clause.replace("XLEquatable", "XLEquatableValue")
    clause = clause.replace("XLComparable", "XLComparableValue")

    def operand_text(label, argument):
        if kind == "existential":
            return f"{label}: any XLExpr<{argument}, Dialect>"
        return f"{label}: XLExpr<{argument}, Dialect>"

    if kind == "existential":
        result_text = f"some XLExpr<{result_argument}, Dialect>"
        body = " { XLNode<" + result_argument + ", Dialect>() }"
    else:
        result_text = f"XLExpr<{result_argument}, Dialect>"
        body = " { XLExpr<" + result_argument + ", Dialect>() }"

    rendered = []
    expression_params = ", ".join(
        operand_text(label, argument) for label, argument in operands
    )
    rendered.append(
        f"    public func {name}{generics}({expression_params}) -> "
        f"{result_text} {clause}".strip()
        + body
    )
    if len(operands) == 1:
        label, argument = operands[0]
        rendered.append(
            f"    public func {name}{generics}({label}: {argument}) -> "
            f"{result_text} {clause}".strip()
            + body
        )
    return rendered


def write_members(kind, members, seen):
    if kind == "current":
        header = "extension XLExpression {"
    elif kind == "existential":
        header = "extension XLExpr {"
    else:
        header = "extension XLExpr {"
    lines = [header]
    count = 0
    for member in members:
        for rendered in rewrite_member(member, kind):
            key = normalise(rendered.split("{")[0])
            if key in seen:
                continue
            seen.add(key)
            lines.append(rendered)
            count += 1
    lines.append("}")
    lines.append("")
    return lines, count


def write_surface(kind, declarations, members, path):
    if kind == "current":
        prelude = PRELUDE_CURRENT
    elif kind == "existential":
        prelude = PRELUDE_EXISTENTIAL
    else:
        prelude = PRELUDE_CONCRETE

    seen = set()
    lines = [prelude, scope_members(kind), ""]
    count = 0
    for declaration in declarations:
        for rendered in rewrite_signature(declaration, kind):
            key = normalise(rendered.split("{")[0])
            if key in seen:
                continue
            seen.add(key)
            lines.append(rendered)
            lines.append("")
            count += 1
    member_lines, member_count = write_members(kind, members, seen)
    lines.extend(member_lines)
    count += member_count
    lines.append(SURFACE_ONLY_SQLITE[kind])
    with open(path, "w") as handle:
        handle.write("\n".join(lines))
    return count


# One clause shape per entry. Each is written once and reused by every surface,
# so a query file differs only in the module it imports.
CLAUSE_SHAPES = [
    "scope.text0 == text",
    "scope.count0 > count",
    "scope.amount0 <= amount",
    "scope.text1 != text",
    "scope.count1 >= count",
    "(scope.text0 + scope.text1) == text",
    "(scope.count0 + scope.count1) > count",
    "(scope.count0 * scope.count1) < count",
    "scope.text2 == text",
    "scope.count2 >= count",
    "!(scope.flag0)",
    "scope.flag0 && (scope.count0 == count)",
    "(scope.text0 == text) || (scope.count1 != count)",
    "(scope.amount0 * scope.amount0) >= amount",
    "(scope.count0 - scope.count1) == count",
    "scope.flag1 && (scope.text1 == text)",
    "scope.text2.isNull()",
    "scope.text0.year() > count",
    "scope.count0.toString() == text",
    "scope.text1.toDouble() <= amount",
]


def write_query(kind, clauses, path):
    module = {
        "current": "GateCurrent",
        "existential": "GateExistential",
        "concrete": "GateConcrete",
    }[kind]
    scope = "XLGateScope()" if kind == "current" else "XLGateScope<XLGateSQLite>()"
    lines = [
        "// Generated by Research/DialectParameterTypeCheck/generate.py. Do not edit.",
        f"import {module}",
        "",
        "@XLGateQueryBuilder",
        "public func gateQuery(",
        "    text: String,",
        "    count: Int,",
        "    amount: Double",
        ") -> [any XLEncodable] {",
        f"    let scope = {scope}",
    ]
    for index in range(clauses):
        lines.append(f"    {CLAUSE_SHAPES[index % len(CLAUSE_SHAPES)]}")
    lines.append("}")
    with open(path, "w") as handle:
        handle.write("\n".join(lines) + "\n")


def main():
    declarations = read_declarations()
    members = read_members()
    output = os.path.join(ROOT, "generated")
    os.makedirs(output, exist_ok=True)
    counts = {}
    for kind in ("current", "existential", "concrete"):
        counts[kind] = write_surface(
            kind,
            declarations,
            members,
            os.path.join(output, f"{kind}-surface.swift"),
        )
        for clauses in (30, 120, 450):
            write_query(
                kind,
                clauses,
                os.path.join(output, f"{kind}-query-{clauses}.swift"),
            )
    print(f"operator declarations read: {len(declarations)}")
    print(f"member declarations read: {len(members)}")
    for kind, count in counts.items():
        print(f"{kind} surface overloads: {count}")


if __name__ == "__main__":
    main()
