//
//  MetaBuilder+ResultShape.swift
//  SwiftQL
//
//  The emitter families that differ by a name and a property set (issue #564).
//
//  An annotated model is selected in several shapes -- named or not, nullable
//  or not, from a table or from an anonymous result -- and each shape gets its
//  own generated type and factory. Written out, that is fourteen near-copies
//  across three families: four factories on the table extension, four
//  `Meta*Result` struct emissions differing by one type name and one property
//  set, and six anonymous-result factories. A fix that lands in three of four
//  copies is the failure mode, and it is invisible: the generated code still
//  compiles, and only the shape nobody updated behaves differently.
//

import Foundation


extension MetaBuilder {

    ///
    /// One `makeSQL…` factory: a shape the model can be selected as, and how
    /// its rows are read back.
    ///
    struct ResultShape {

        /// The factory's name, as `makeSQLNullableNamedResult`.
        let functionName: String

        /// The declaration the factory is given -- named or not.
        let dependencyType: String

        /// The generated metadata type the factory returns.
        let metaType: String

        /// The type the trailing closure constructs: the model itself, or its
        /// nested `Nullable`.
        let rowType: String

        let properties: [MetaProperty]

        /// How a column is spelled in the factory's own argument list.
        let parameterColumnKind: MetaProperty.ColumnKind

        /// How a column is spelled inside the row-reading closure. Not always
        /// the same as ``parameterColumnKind``: the anonymous factories pass
        /// their arguments in the enclosing model's kind but always read rows
        /// as results.
        let rowColumnKind: MetaProperty.ColumnKind

        /// Whether the constructed value is written with an explicit `return`.
        /// Cosmetic, and pinned by the committed expansion snapshots.
        let usesExplicitReturn: Bool
    }

    ///
    /// One generated `Meta*Result` metadata struct.
    ///
    struct MetaResultShape {

        /// The generated type's name, as `MetaNullableNamedResult`.
        let typeName: String

        /// The `XLMeta*` protocol it satisfies.
        let protocolName: String

        /// The row type it reads: the model, or its nested `Nullable`.
        let rowType: String

        /// The declaration it holds -- named or not.
        let dependencyType: String

        let properties: [MetaProperty]
    }

    /// The leading arguments every generated metadata value takes, followed by
    /// one argument per column.
    func metaFactoryArguments(
        _ properties: [MetaProperty],
        kind: MetaProperty.ColumnKind,
        dependency: String = "dependency"
    ) -> [String] {
        ["_namespace: namespace", "_dependency: \(dependency)"]
            + properties.map { property in
                property.name + ": "
                    + property.makeInstance(kind: kind, dependency: dependency)
            }
    }

    ///
    /// Emits one factory that builds its metadata value and reads a row from
    /// the columns it was given.
    ///
    /// The trailing closure takes no parameter when there are no columns to
    /// read from it -- `{ _ in` rather than `{` -- because an unused closure
    /// parameter is a warning in the generated code the author sees.
    ///
    /// Each column expression is bound before the metadata value is built, and
    /// the closure reads that binding. The closure runs once per row, so an
    /// expression written inside it was rebuilt for every column of every row.
    /// The expression is a pure value over `dependency` and a constant alias,
    /// so building it once per factory call is equivalent.
    ///
    /// The binding is declared as the erased `any XLExpression` the read takes,
    /// not as the concrete column type. A concrete binding is boxed into that
    /// existential again at every read, which allocates once per column per
    /// row. Erasing at the binding pays for the box once per factory call.
    ///
    /// Both are per-row costs that survived the `staticColumn` dispatch fix in
    /// issue #353, and neither changes which requirement a column selects: the
    /// binding keeps the column's concrete `T`, so a literal column still
    /// selects the constrained requirement.
    ///
    /// A factory that binds locals must return explicitly, because its body is
    /// then no longer a single expression.
    ///
    func emitResultFactory(_ shape: ResultShape, into context: inout CodeWriter) {
        let signature = "public static func \(shape.functionName)"
            + "(namespace: XLNamespace, dependency: \(shape.dependencyType))"
            + " -> \(shape.metaType)"
        var allocator = GeneratedIdentifierAllocator(
            used: generatedIdentifierReservations
        )
        let columnBindings = shape.properties.indices.map { index in
            allocator.allocate("_swiftQLRowColumn\(index)")
        }
        context.block(signature) { context in
            for (property, binding) in zip(shape.properties, columnBindings) {
                context.line(
                    "let \(binding): any SwiftQL.XLExpression<\(property.qualifiedType)>"
                        + " = \(property.makeInstance(kind: shape.rowColumnKind, dependency: "dependency"))"
                )
            }
            let arguments = metaFactoryArguments(
                shape.properties,
                kind: shape.parameterColumnKind
            )
            let usesExplicitReturn = shape.usesExplicitReturn
                || !columnBindings.isEmpty
            let construction = (usesExplicitReturn ? "return " : "")
                + shape.metaType + "(" + arguments.joined(separator: ", ") + ")"
            context.block(
                construction,
                opening: shape.properties.isEmpty ? " { _ in" : " {"
            ) { context in
                context.declaration(shape.rowType) { context in
                    for (property, binding) in zip(shape.properties, columnBindings) {
                        context.item { context in
                            context.line(
                                "\(property.name): try $0.staticColumn(\(binding), alias: \(quoted(property.alias)))"
                            )
                        }
                    }
                }
            }
        }
    }

    ///
    /// Emits one factory that takes the row iterator from its caller instead of
    /// reading rows itself.
    ///
    /// This is the shape a composed selection needs: the row's construction
    /// belongs to whatever assembled the selection, not to this model.
    ///
    func emitIteratorResultFactory(
        functionName: String,
        dependencyType: String,
        metaType: String,
        properties: [MetaProperty],
        columnKind: MetaProperty.ColumnKind,
        into context: inout CodeWriter
    ) {
        let signature = "public static func \(functionName)"
            + "(namespace: XLNamespace, dependency: \(dependencyType),"
            + " iterator: @escaping MetaRowIterator) -> \(metaType)"
        context.block(signature) { context in
            let arguments = metaFactoryArguments(properties, kind: columnKind)
                + ["_iterator: iterator"]
            context.line(
                "return " + metaType + "(" + arguments.joined(separator: ", ") + ")"
            )
        }
    }

    ///
    /// Emits one generated `Meta*Result` metadata struct.
    ///
    /// All four hold a namespace, a declaration, one column per property, and a
    /// row iterator; they differ in which declaration, which row type, and
    /// which property set.
    ///
    func emitMetaResultStruct(
        _ shape: MetaResultShape,
        columnKind: MetaProperty.ColumnKind,
        into context: inout CodeWriter
    ) {
        let conformances = ([shape.protocolName] + ["XLRowReadable", "XLEncodable"])
            .joined(separator: ", ")
        context.block("public struct \(shape.typeName): \(conformances)") { context in
            context.line("public typealias Row = \(shape.rowType)")
            context.line("public typealias RowIterator = (XLRowReader) throws -> \(shape.rowType)")
            context.line("public let _namespace: XLNamespace")
            context.line("public let _dependency: \(shape.dependencyType)")

            for property in shape.properties {
                context.line(property.makeColumnPropertyDecl(kind: columnKind))
            }

            context.line("public let _iterator: RowIterator")

            context.block("public func readRow(reader: XLRowReader) throws -> \(shape.rowType)") { context in
                context.line("try _iterator(reader)")
            }

            context.block("public func makeSQL(context: inout XLBuilder)") { context in
                context.line("_dependency.makeSQL(context: &context)")
            }
        }
    }
}
