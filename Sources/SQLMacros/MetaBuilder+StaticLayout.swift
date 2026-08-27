//
//  MetaBuilder+StaticLayout.swift
//  SwiftQL
//
//  Emission of the static row layout and the per-property codec metadata:
//  the declaration-level codec-key table and one `staticResultField(_:...)`
//  overload per `@SQLCodec`-annotated property.
//
//  Split out of MetaBuilder.swift (issue #564).
//

import Foundation


extension MetaBuilder {

    func makeColumnsFunction() -> String {
        var context = CodeWriter()
        var columnParameters: [String] = []
        for property in properties {
            columnParameters.append("\(property.name): any SwiftQL.XLExpression<\(property.qualifiedType)>")
        }
        context.block("public static func columns(\(columnParameters.joined(separator: ", "))) -> MetaResult") { context in
            context.block("return Self.makeSQLAnonymousResult", opening: "(", closing: ")") { context in
                context.line("namespace: XLNamespace.table(),")
                context.line("dependency: XLSelectResultDependency(),")
                context.block("iterator: Self.SQLReader", opening: "(", closing: ").readRow") { context in
                    for (index, property) in properties.enumerated() {
                        let suffix = index + 1 == properties.count ? "" : ","
                        context.line("\(property.name): \(property.name)\(suffix)")
                    }
                }
            }
        }
        return context.build()
    }

    // Generate the static layout factory as a nominal member for the same
    // Swift 5.9 cross-file lookup reason as `columns(...)`. The caller supplies
    // one `XLStaticRowFieldSource` value per property, allowing each use to
    // select its own expression and codec without constructing the model or
    // SQLReader.
    //
    // A property's argument is either an ordinary scalar field (any
    // `XLStaticSelectFieldProtocol` value, e.g. from `staticResultField` or
    // `.intrinsic`) or another generated type's own `staticRowLayout(using:...)`
    // result -- a nested `@SQLTable`/`@SQLResult` composite property. The macro
    // never has to tell those apart: both conform to `XLStaticRowFieldSource`,
    // and `grouped(at:alias:)` reports how many flat SQL slots it occupies
    // through its runtime `count`, so the generated code below only ever
    // accumulates a running slot offset -- it does not need to know any
    // property's arity at expansion time. A scalar property always
    // contributes exactly one slot; a nested composite property contributes
    // every one of its own flattened slots, re-aliased with its property name
    // as a prefix so the flattened SQL output columns stay unique.

    func makeStaticRowLayoutFunction() -> String {
        var context = CodeWriter()
        var allocator = GeneratedIdentifierAllocator(
            used: generatedIdentifierReservations
        )
        let dialect = allocator.allocate("_SwiftQLStaticDialect")
        let fieldGroups = properties.indices.map { index in
            allocator.allocate("_swiftQLStaticField\(index)")
        }
        let offset = allocator.allocate("_swiftQLStaticOffset")
        let reader = allocator.allocate("_swiftQLStaticReader")
        let row = allocator.allocate("_swiftQLStaticRow")

        var parameters = ["using _: \(dialect).Type"]
        for property in properties {
            parameters.append(
                "\(property.name): some SwiftQL.XLStaticRowFieldSource<\(property.qualifiedType), \(dialect)>"
            )
        }

        // A running offset is reassigned only when a third or later property
        // needs it, so it is generated as an immutable binding otherwise --
        // avoiding an unused-mutation warning in the generated code.
        let offsetIsMutable = properties.count > 2

        context.block(
            "public static func staticRowLayout<\(dialect)>(\(parameters.joined(separator: ", "))) throws -> SwiftQL.XLStaticRowLayout<Self, \(dialect)> where \(dialect): SwiftQL.XLValueCodingDialect"
        ) { context in
            for (index, property) in properties.enumerated() {
                if index == 0 {
                    context.line(
                        "let \(fieldGroups[index]) = try \(property.name).grouped(at: 0, alias: \(quoted(property.alias)))"
                    )
                }
                else {
                    context.line(
                        "let \(fieldGroups[index]) = try \(property.name).grouped(at: \(offset), alias: \(quoted(property.alias)))"
                    )
                }
                if index < properties.count - 1 {
                    if index == 0 {
                        context.line("\(offsetIsMutable ? "var" : "let") \(offset) = \(fieldGroups[index]).count")
                    }
                    else {
                        context.line("\(offset) += \(fieldGroups[index]).count")
                    }
                }
            }

            context.block("return try SwiftQL.XLStaticRowLayout", opening: "(", closing: ")") { context in
                if fieldGroups.isEmpty {
                    context.line("fields: [],")
                }
                else {
                    // A single `.flatMap` over the per-property field arrays copies each
                    // element once; chaining `+` between them would instead recopy every
                    // earlier array on each concatenation (quadratic in property count).
                    context.line(
                        "fields: [" + fieldGroups.map { "\($0).fields" }.joined(separator: ", ") + "].flatMap { $0 },"
                    )
                }
                context.block(
                    "decode: { \(reader) in",
                    opening: "",
                    closing: "},"
                ) { context in
                    context.declaration("Self") { context in
                        for (index, property) in properties.enumerated() {
                            context.item { context in
                                context.line(
                                    "\(property.name): try \(fieldGroups[index]).read(from: \(reader))"
                                )
                            }
                        }
                    }
                }
                context.block(
                    "encode: { \(row) in",
                    opening: "",
                    closing: "}"
                ) { context in
                    if fieldGroups.isEmpty {
                        context.line("[]")
                    }
                    else {
                        let terms = zip(fieldGroups, properties).map { field, property in
                            "\(field).encode(\(row).\(property.name))"
                        }
                        if terms.count == 1 {
                            context.line("try \(terms[0])")
                        }
                        else {
                            // See the `fields:` array above: a single `.flatMap` over the
                            // per-property encoded arrays avoids the quadratic recopying
                            // that chaining `+` between them would cause.
                            context.line("try [\(terms.joined(separator: ", "))].flatMap { $0 }")
                        }
                    }
                }
            }
        }
        return context.build()
    }

    // Issue #66: stable, declaration-level codec metadata. Every generated type carries this
    // dictionary regardless of whether any property selects an explicit codec, so it is always a
    // reliable, directly inspectable surface (asserted by macro-expansion snapshot tests) rather
    // than a member that only sometimes exists. Only properties annotated with `@SQLCodec(_:)`
    // are present; every other property is left to the query/database-default precedence already
    // implemented by `XLValueCodingConfiguration`. Entries are keyed by SQL column alias, matching
    // the alias-based identity `XLStaticQueryResultSlot`/`XLValueCodingPath` already use elsewhere.
    //
    // Generated as a computed property, not a stored one: a generic `@SQLTable`/`@SQLResult`
    // type (e.g. `SQLScalarResult<T>`) cannot declare a `static let` -- Swift does not support
    // static stored properties on generic types -- so a computed property is the only form that
    // works uniformly for both generic and non-generic generated types.

    func makeCodecKeysDeclaration() -> String {
        var context = CodeWriter()
        let entries = properties.compactMap { property -> (alias: String, expression: String)? in
            guard let codecKeyExpression = property.codecKeyExpression else {
                return nil
            }
            return (property.alias, codecKeyExpression)
        }
        context.block(
            "public static var _swiftQLPropertyCodecKeys: [String: SwiftQL.XLValueCodecKey]"
        ) { context in
            if entries.isEmpty {
                context.line("[:]")
            }
            else {
                context.block("[", opening: "", closing: "]") { context in
                    for entry in entries {
                        context.line("\(quoted(entry.alias)): \(entry.expression),")
                    }
                }
            }
        }
        return context.build()
    }

    // Issue #66: one generated static convenience per property carrying `@SQLCodec(_:)`, named
    // `staticResultField(<property>:...)` so a caller building a `staticRowLayout(using:...)`
    // argument for that property never repeats the codec key. The wrapper is metadata-only -- it
    // supplies `selection: .explicit(...)` and otherwise forwards straight to
    // `XLValueCodingConfiguration.staticResultField(...)`, so runtime resolution (unknown codec,
    // wrong Swift value type, wrong dialect) still runs through the existing precedence and
    // `XLValueCodecError`/`XLQueryCodecSelectionError` machinery. Because `XLStaticSelectField`
    // pairs `decode`/`encode` on one codec, this single generated factory backs projection
    // (`layout.decode`/`readRow`) and write paths (`layout.encode`) alike.
    func makeCodecResultFieldFunctions() -> [String] {
        var allocator = GeneratedIdentifierAllocator(
            used: generatedIdentifierReservations
        )
        var functions: [String] = []
        for property in properties {
            guard let codecKeyExpression = property.codecKeyExpression else {
                continue
            }
            let storage = allocator.allocate("_SwiftQLCodecStorage")
            let valueType = property.optional ? "\(property.type)?" : property.type
            let storageType = property.optional ? "\(storage)?" : storage
            var context = CodeWriter()
            context.block(
                "public static func staticResultField<\(storage)>("
                    + "\(property.name) expression: any SwiftQL.XLEncodable, "
                    + "storedAs storageType: \(storageType).Type, "
                    + "identifiedBy identity: SwiftQL.XLQuerySlotIdentity, "
                    + "using dialect: SwiftQL.XLSQLiteDialect, "
                    + "context: SwiftQL.XLValueCodingContext? = nil, "
                    + "configuration: SwiftQL.XLValueCodingConfiguration"
                    + ") throws -> SwiftQL.XLStaticSelectField<\(valueType), \(storageType), SwiftQL.XLSQLiteDialect> "
                    + "where \(storage): SwiftQL.XLLiteral"
            ) { context in
                context.block(
                    "return try configuration.staticResultField",
                    opening: "(",
                    closing: ")"
                ) { context in
                    context.line("\(valueType).self,")
                    context.line("selecting: expression,")
                    context.line("storedAs: storageType,")
                    context.line("identifiedBy: identity,")
                    context.line("using: dialect,")
                    context.line("context: context,")
                    context.line("selection: .explicit(\(codecKeyExpression))")
                }
            }
            functions.append(context.build())
        }
        return functions
    }

    // Build table meta data, used to select from concrete tables and views which are defined by the database schema.
}
