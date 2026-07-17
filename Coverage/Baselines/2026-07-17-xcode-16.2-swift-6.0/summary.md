# First-party Swift source coverage

- Source commit: `9152d8409aa55df5bc96e9c74411b3c4fb166429`
- Command: `xcrun swift test --scratch-path <scratch-path> --enable-code-coverage`
- Xcode: `Xcode 16.2 / Build version 16C5032a`
- Swift: `Apple Swift version 6.0.3 (swiftlang-6.0.3.1.10 clang-1600.0.30.1) / Target: arm64-apple-macosx15.0`
- SDK: `15.2`
- LLVM coverage: `/Applications/Xcode_16.2.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/llvm-cov / Apple LLVM version 16.0.0 /    (clang-1600.0.26.6)Optimized build.`
- Source tree: `clean`
- Filtering: only tracked `.swift` files under `Sources/SwiftQL` and `Sources/SQLMacros`; dependencies, tests, benchmarks, build products, and generated expansion files are excluded.
- This report is evidence only; it does not enforce a percentage threshold.

| Target | Instrumented sources | Allowed uninstrumented | Lines | Functions |
| --- | ---: | ---: | ---: | ---: |
| SQLMacros | 4 | 0 | 2164/2218 (97.57%) | 154/157 (98.09%) |
| SwiftQL | 45 | 2 | 2822/3628 (77.78%) | 703/939 (74.87%) |

## Largest uncovered files

This ranking identifies follow-up candidates; it is not a release gate.

| Source | Uncovered lines | Uncovered functions |
| --- | ---: | ---: |
| `Sources/SwiftQL/Statements/SQLInsertStatement.swift` | 96 | 32 |
| `Sources/SwiftQL/SQLDatabase.swift` | 59 | 12 |
| `Sources/SwiftQL/Builders/QueryBuilder.swift` | 56 | 13 |
| `Sources/SwiftQL/SQLStatements.swift` | 54 | 19 |
| `Sources/SwiftQL/Statements/SQLQueryStatement.swift` | 51 | 17 |
| `Sources/SwiftQL/Expression Builder/SQLInsertExpressionBuilder.swift` | 45 | 15 |
| `Sources/SwiftQL/Operators/RealOperators.swift` | 45 | 15 |
| `Sources/SwiftQL/SQLExpression.swift` | 44 | 13 |
| `Sources/SwiftQL/SQLMeta.swift` | 40 | 14 |
| `Sources/SwiftQL/Operators/IntegerOperators.swift` | 39 | 13 |

## Allowed uninstrumented sources

- `Sources/SwiftQL/SQL.swift`
- `Sources/SwiftQL/SQLScalarResult.swift`

These files have no executable regions in the current LLVM export. The explicit allowlist prevents other production sources from disappearing silently.
