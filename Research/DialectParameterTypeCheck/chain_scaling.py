#!/usr/bin/env python3
"""Generate stand-in surfaces that isolate the cost of one && chain (issue #789).

`measure-shipped.sh` found that the dialect parameter makes a single predicate
of N `&&`-joined comparisons slow to type-check, and that a mistake inside one
can exhaust the type checker's budget. This generator separates the causes. It
writes one small library per operator shape, each with SwiftQL's operator
counts -- six comparisons and two connectives, four optional variants each --
and one query per chain length.

Shapes:

  base         `any E<T>` operands, as SwiftQL ships today.
  generic      `any E<T, D>` operands, generic over the dialect D. No overload
               for a universal operand: the minimum the dialect parameter adds.
  mixed        `generic`, plus the two disfavored overloads per variant that
               let a universal value stand on either side.
  operands     Generic operand types, `<L: E, R: E>` with `L.D == R.D`, and a
               concrete node returned.
  operands-ret `operands`, with the chain returned as
               `any E<Optional<Bool>, SQLite>`.
  concrete     A concrete `X<T, D>` struct for every operand and result, the
               `concrete` surface of `generate.py`.
  dialect      The shipped design: one expression protocol per dialect,
               `SQLiteE<T>`, and non-generic operators over it, one copy per
               dialect, returning `some SQLiteE<R>`. A column conforms where
               its dialect is SQLite; a value and a node conform outright.
  dialect-ret  `dialect`, with the chain returned as
               `any SQLiteE<Optional<Bool>>`.
  dialect-two  `dialect` with a second dialect's copy of every operator
               visible as well, disfavoured, as in a module that uses two
               dialects.

The chains contain optional columns, so from four terms on their type is
`Optional<Bool>`, and the `-ret` shapes return that type. (An earlier version
of this file returned `Bool`, so its `-ret` rows timed the type checker's
error path, not the chain.)

Usage: chain_scaling.py <output-directory>
"""

import os
import sys

COMPARISONS = ["==", "!=", ">", "<", ">=", "<="]
CONNECTIVES = ["&&", "||"]
VARIANTS = [
    ("T", "T", "Bool"),
    ("T", "Optional<T>", "Optional<Bool>"),
    ("Optional<T>", "T", "Optional<Bool>"),
    ("Optional<T>", "Optional<T>", "Optional<Bool>"),
]
BOOLEAN_VARIANTS = [
    ("Bool", "Bool", "Bool"),
    ("Bool", "Optional<Bool>", "Optional<Bool>"),
    ("Optional<Bool>", "Bool", "Optional<Bool>"),
    ("Optional<Bool>", "Optional<Bool>", "Optional<Bool>"),
]
TERMS = [
    "text0 == text1",
    "count0 > count1",
    "amount0 <= amount0",
    "text2 == text2",
    "count1 != count0",
    "flag0 == flag0",
    "count2 >= count2",
    "text1 != text0",
]

PRELUDE = """
public struct B { public init() {} }
public protocol Enc { func make(_ b: inout B) }
public enum Uni {}
public enum SQLite {}
public protocol Lit {}
extension Int: Lit {}
extension String: Lit {}
extension Double: Lit {}
extension Bool: Lit {}
"""


def base_library():
    text = PRELUDE + """
public protocol E<T>: Enc { associatedtype T }
public struct Col<T>: E { public init() {}; public func make(_ b: inout B) {} }
public struct Node<T>: E { public init() {}; public func make(_ b: inout B) {} }
"""
    for name in COMPARISONS:
        for lhs, rhs, result in VARIANTS:
            text += f"public func {name}<T: Lit>(lhs: any E<{lhs}>, rhs: any E<{rhs}>) -> some E<{result}> {{ Node<{result}>() }}\n"
    for name in CONNECTIVES:
        for lhs, rhs, result in BOOLEAN_VARIANTS:
            text += f"public func {name}(lhs: any E<{lhs}>, rhs: any E<{rhs}>) -> some E<{result}> {{ Node<{result}>() }}\n"
    return text


DIALECT_PRELUDE = PRELUDE + """
public protocol E<T, D>: Enc { associatedtype T; associatedtype D = Uni }
public struct Col<T, D>: E { public init() {}; public func make(_ b: inout B) {} }
public struct Node<T, D>: E { public init() {}; public func make(_ b: inout B) {} }
"""


def generic_library(mixed):
    text = DIALECT_PRELUDE
    families = [(COMPARISONS, VARIANTS, "T: Lit, "), (CONNECTIVES, BOOLEAN_VARIANTS, "")]
    for names, variants, extra in families:
        for name in names:
            for lhs, rhs, result in variants:
                text += f"public func {name}<{extra}D>(lhs: any E<{lhs}, D>, rhs: any E<{rhs}, D>) -> some E<{result}, D> {{ Node<{result}, D>() }}\n"
                if mixed:
                    text += f"@_disfavoredOverload public func {name}<{extra}D>(lhs: any E<{lhs}, D>, rhs: any E<{rhs}, Uni>) -> some E<{result}, D> {{ Node<{result}, D>() }}\n"
                    text += f"@_disfavoredOverload public func {name}<{extra}D>(lhs: any E<{lhs}, Uni>, rhs: any E<{rhs}, D>) -> some E<{result}, D> {{ Node<{result}, D>() }}\n"
    return text


def operands_library():
    text = DIALECT_PRELUDE
    families = [(COMPARISONS, VARIANTS, "T: Lit, "), (CONNECTIVES, BOOLEAN_VARIANTS, "")]
    for names, variants, extra in families:
        for name in names:
            for lhs, rhs, result in variants:
                text += (
                    f"public func {name}<{extra}L: E, R: E>(lhs: L, rhs: R) -> Node<{result}, L.D> "
                    f"where L.T == {lhs}, R.T == {rhs}, L.D == R.D {{ Node<{result}, L.D>() }}\n"
                )
    return text


def concrete_library():
    text = PRELUDE + """
public struct X<T, D>: Enc { public init() {}; public func make(_ b: inout B) {} }
public typealias Col<T, D> = X<T, D>
"""
    families = [(COMPARISONS, VARIANTS, "T: Lit, "), (CONNECTIVES, BOOLEAN_VARIANTS, "")]
    for names, variants, extra in families:
        for name in names:
            for lhs, rhs, result in variants:
                text += f"public func {name}<{extra}D>(lhs: X<{lhs}, D>, rhs: X<{rhs}, D>) -> X<{result}, D> {{ X<{result}, D>() }}\n"
    return text


def dialect_library(names):
    text = PRELUDE + """
public protocol E<T>: Enc { associatedtype T }
public struct Col<T, D>: E { public init() {}; public func make(_ b: inout B) {} }
public struct Node<T>: E { public init() {}; public func make(_ b: inout B) {} }
extension Optional: Enc where Wrapped: Enc { public func make(_ b: inout B) {} }
extension Optional: E where Wrapped: E { public typealias T = Optional<Wrapped> }
extension Int: E { public typealias T = Int; public func make(_ b: inout B) {} }
extension String: E { public typealias T = String; public func make(_ b: inout B) {} }
extension Double: E { public typealias T = Double; public func make(_ b: inout B) {} }
extension Bool: E { public typealias T = Bool; public func make(_ b: inout B) {} }
"""
    for index, dialect in enumerate(names):
        disfavored = "@_disfavoredOverload " if index > 0 else ""
        if dialect != "SQLite":
            text += f"public enum {dialect} {{}}\n"
        text += (
            f"public protocol {dialect}E<T>: E {{}}\n"
            f"extension Col: {dialect}E where D == {dialect} {{}}\n"
            f"extension Node: {dialect}E {{}}\n"
            f"extension Int: {dialect}E {{}}\n"
            f"extension String: {dialect}E {{}}\n"
            f"extension Double: {dialect}E {{}}\n"
            f"extension Bool: {dialect}E {{}}\n"
            f"extension Optional: {dialect}E where Wrapped: {dialect}E {{}}\n"
        )
        families = [(COMPARISONS, VARIANTS, "<T: Lit>"), (CONNECTIVES, BOOLEAN_VARIANTS, "")]
        for operators, variants, generic in families:
            for name in operators:
                for lhs, rhs, result in variants:
                    text += f"{disfavored}public func {name}{generic}(lhs: any {dialect}E<{lhs}>, rhs: any {dialect}E<{rhs}>) -> some {dialect}E<{result}> {{ Node<{result}>() }}\n"
    return text


def query(dialect, count, result="any Enc"):
    suffix = ", SQLite" if dialect else ""
    columns = "".join(
        f"    let {name} = Col<{kind}{suffix}>()\n"
        for name, kind in [
            ("text0", "String"), ("text1", "String"), ("text2", "String?"),
            ("count0", "Int"), ("count1", "Int"), ("count2", "Int?"),
            ("amount0", "Double"), ("flag0", "Bool"),
        ]
    )
    terms = [TERMS[index % len(TERMS)] for index in range(count)]
    return (
        "import Lib\n"
        f"func gateQuery() -> {result} {{\n{columns}"
        f"    return {' && '.join(terms)}\n"
        "}\n"
    )


def main():
    output = sys.argv[1]
    shapes = {
        "base": (base_library(), False, "any Enc"),
        "generic": (generic_library(False), True, "any Enc"),
        "mixed": (generic_library(True), True, "any Enc"),
        "operands": (operands_library(), True, "any Enc"),
        "operands-ret": (operands_library(), True, "any E<Optional<Bool>, SQLite>"),
        "concrete": (concrete_library(), True, "X<Optional<Bool>, SQLite>"),
        "dialect": (dialect_library(["SQLite"]), True, "any Enc"),
        "dialect-ret": (dialect_library(["SQLite"]), True, "any SQLiteE<Optional<Bool>>"),
        "dialect-two": (dialect_library(["SQLite", "Second"]), True, "any Enc"),
    }
    for name, (library, dialect, result) in shapes.items():
        directory = os.path.join(output, name)
        os.makedirs(directory, exist_ok=True)
        with open(os.path.join(directory, "Lib.swift"), "w") as handle:
            handle.write(library)
        for count in (4, 8, 12, 16):
            with open(os.path.join(directory, f"chain-{count}.swift"), "w") as handle:
                handle.write(query(dialect, count, result))


if __name__ == "__main__":
    main()
