//
//  MetaBuilder+Table.swift
//  SwiftQL
//
//  Emission of the `XLTable` conformance: the table name, the four result
//  shapes a table can be selected as, the writable-table surface, and the
//  `CREATE TABLE` declaration.
//
//  Split out of MetaBuilder.swift (issue #564).
//

import Foundation


extension MetaBuilder {

    func makeMetaTableExtension() -> String {
        var context = CodeWriter()

        context.block("extension \(structName): XLTable") { context in
            
            context.block("public static func sqlTableName() -> XLQualifiedTableName") { context in
                context.line("XLQualifiedTableName(name: XLName(\(quoted(tableName))))")
            }
            
            makeWriter(context: &context)

            // The four shapes a table can be selected as. Only the first
            // two omit `return`, which is cosmetic and is what the committed
            // expansion snapshots show.
            for shape in [
                ResultShape(
                    functionName: "makeSQLTable",
                    dependencyType: "XLTableDeclaration",
                    metaType: "MetaResult",
                    rowType: structName,
                    properties: properties,
                    parameterColumnKind: .reference,
                    rowColumnKind: .reference,
                    usesExplicitReturn: false
                ),
                ResultShape(
                    functionName: "makeSQLNamedResult",
                    dependencyType: "XLNamedTableDeclaration",
                    metaType: "MetaNamedResult",
                    rowType: structName,
                    properties: properties,
                    parameterColumnKind: .reference,
                    rowColumnKind: .reference,
                    usesExplicitReturn: false
                ),
                ResultShape(
                    functionName: "makeSQLNullableResult",
                    dependencyType: "XLTableDeclaration",
                    metaType: "MetaNullableResult",
                    rowType: "Nullable",
                    properties: optionalProperties,
                    parameterColumnKind: .reference,
                    rowColumnKind: .reference,
                    usesExplicitReturn: true
                ),
                ResultShape(
                    functionName: "makeSQLNullableNamedResult",
                    dependencyType: "XLNamedTableDeclaration",
                    metaType: "MetaNullableNamedResult",
                    rowType: "Nullable",
                    properties: optionalProperties,
                    parameterColumnKind: .reference,
                    rowColumnKind: .reference,
                    usesExplicitReturn: true
                ),
            ] {
                emitResultFactory(shape, into: &context)
            }

            makeCreate(context: &context)
        }
            
        return context.build()
    }
    
    private func makeWriter(context: inout CodeWriter) {
        
        context.block("public struct MetaWritableTable: XLMetaWritableTable") { context in

            context.line("public typealias Row = \(structName)")
            context.line("public typealias Dependency = XLEncodable & XLColumnDependency")
            context.line(makeDialectWitness(isStatic: false))

            context.line("public let _table: any XLEncodable")

            context.line("public let _namespace: XLNamespace")
            context.line("private let _dependency: XLTableDeclaration")
            
            for property in properties {
                context.line(property.makeColumnPropertyDecl(kind: .reference, dialect: dialectType))
            }

            context.block("public init(namespace: XLNamespace, dependency: XLTableDeclaration)") { context in
                context.line("_namespace = namespace")
                context.line("_dependency = dependency")
                context.line("_table = dependency")
                for property in properties {
                    context.line(property.name + " = " + property.makeInstance(kind: .reference, dialect: dialectType, dependency: "dependency"))
                }
            }
            
            context.block("public func makeSQL(context: inout XLBuilder)") { context in

            }
        }

        context.block("public struct MetaInsert: XLMetaInsert") { context in
            
            context.line("public typealias Row = \(structName)")
            
            for property in properties {
                context.line("private let \(property.name): any XLExpression<\(property.qualifiedType)>")
            }
            
            // Discrete parameters.
            var parameters: [String] = []
            for property in properties {
                parameters.append("\(property.name): \(dialectExpressionType(property.qualifiedType))")
            }
            context.block("public init(\(parameters.joined(separator: ", ")))") { context in
                for property in properties {
                    context.line("self.\(property.name) = \(property.name)")
                }
            }
            
            // Instance parameter.
            context.block("public init(_ instance: \(structName))") { context in
                for property in properties {
                    context.line("\(property.name) = SwiftQL._xlLegacyValueExpression(instance.\(property.name))")
                }
            }
            
            context.block("public func makeSQL(context: inout XLBuilder)") { context in
                
                context.block("context.parenthesis") { context in
                    context.block("$0.list(separator: \",\")") { context in
                        for property in properties {
                            context.block("$0.listItem") { context in
                                context.line("$0.name(XLName(\"\(property.alias)\"))")
                            }
                        }
                    }
                }
                
                context.block("context.unaryPrefix(\"VALUES\")") { context in
                    context.block("$0.parenthesis") { context in
                        context.block("$0.list(separator: \",\")") { context in
                            for property in properties {
                                context.block("$0.listItem") { context in
                                    context.line("\(property.name).writeSQL(context: &$0)")
                                }
                            }
                        }
                    }
                }
            }
        }
            
        // Column assignments route through key-path member lookup rather than
        // stored properties, because a nullable column needs three assignment
        // shapes on one name -- a wrapped-type expression, `nil` for SQL
        // NULL, and an optional-typed expression -- and a stored property has
        // exactly one setter type. Subscript overloads are the one place
        // Swift resolves an assignment against more than one type, and
        // @dynamicMemberLookup lets them keep the `row.column = value`
        // spelling. Participation in the SET clause is tracked by the typed
        // slots, separately from the value's own optionality.
        context.block("@dynamicMemberLookup public struct MetaUpdate: XLMetaUpdate") { context in

            context.line("public typealias Row = \(structName)")

            // Each slot knows its column's name, so a read of a column the
            // closure never assigned is the column's current value (issue
            // #828).
            context.block("public struct Columns") { context in
                for property in properties {
                    if property.optional {
                        context.line("public var \(property.name) = SwiftQL.XLNullableColumnUpdate<\(property.type)>(_xlColumn: SwiftQL.XLName(\"\(property.alias)\"))")
                    }
                    else {
                        context.line("public var \(property.name) = SwiftQL.XLColumnUpdate<\(property.qualifiedType)>(_xlColumn: SwiftQL.XLName(\"\(property.alias)\"))")
                    }
                }
                context.block("public init()") { _ in
                }
            }

            context.line("public var _xlColumns: Columns")

            // Issue #825: an assignment takes the model's dialect's
            // expressions. The slot stores the expression erased, so a read
            // casts it back to the dialect's expression type, which the
            // getter names. A value of no dialect, written to the slot
            // directly, reads inside an `XLTypeAffinityExpression`, which this
            // function converts with an `as` coercion: it compiles only when
            // the dialect's expression protocol includes that node, so a
            // dialect that does not is one compile error here, under a name
            // that states the requirement, rather than a read that fails.
            // The coercion is spelled `as` because the compiler's message for
            // a plain return of the wrong type is "failed to produce
            // diagnostic".
            context.block("private static func _xlDialectExpressionMustIncludeXLTypeAffinityExpression<Wrapped>(_ expression: SwiftQL.XLTypeAffinityExpression<Wrapped>) -> \(dialectExpressionType("Wrapped"))") { context in
                context.line("return expression as \(dialectExpressionType("Wrapped"))")
            }

            context.block("public subscript<Wrapped>(dynamicMember keyPath: Swift.WritableKeyPath<Columns, SwiftQL.XLColumnUpdate<Wrapped>>) -> Optional<\(dialectExpressionType("Wrapped"))>") { context in
                emitSlotRead(read: "_xlReadExpression", untyped: "_xlReadUntypedExpression", valueType: "Wrapped", isOptional: false, into: &context)
                context.block("set") { context in
                    context.line("_xlColumns[keyPath: keyPath].expression = newValue")
                }
            }

            // For a nullable column, `nil` assigned through this overload
            // means SQL NULL. Leaving the column out of the statement is what
            // never assigning it does. It takes a value of the wrapped type
            // and `nil`, which the optional-typed overload does not. Issue
            // #828: it is never read. A nullable column's value can be NULL,
            // so a read as the wrapped type would let it into a column that
            // is NOT NULL; with the getter unavailable, that is a compile
            // error, and a read resolves to the optional-typed overload,
            // which returns what was assigned. Disfavored so that a read, and
            // a plain `Wrapped?` value, which both overloads accept with
            // identical rendered SQL, resolve to the optional-typed overload.
            context.line("@_disfavoredOverload")
            context.block("public subscript<Wrapped>(dynamicMember keyPath: Swift.WritableKeyPath<Columns, SwiftQL.XLNullableColumnUpdate<Wrapped>>) -> Optional<\(dialectExpressionType("Wrapped"))>") { context in
                context.line("@available(*, unavailable, message: \"a nullable column can be NULL, so it is read only as an optional-typed expression\")")
                context.block("get") { context in
                    context.line("Swift.fatalError()")
                }
                context.block("set") { context in
                    context.line("_xlColumns[keyPath: keyPath].expression = newValue")
                }
            }

            context.block("public subscript<Wrapped>(dynamicMember keyPath: Swift.WritableKeyPath<Columns, SwiftQL.XLNullableColumnUpdate<Wrapped>>) -> \(dialectExpressionType("Optional<Wrapped>"))") { context in
                emitSlotRead(read: "_xlReadOptionalExpression", untyped: "_xlReadUntypedOptionalExpression", valueType: "Optional<Wrapped>", isOptional: true, into: &context)
                context.block("set") { context in
                    context.line("_xlColumns[keyPath: keyPath].optionalExpression = newValue")
                }
            }

            context.block("public init()") { context in
                context.line("_xlColumns = Columns()")
            }

            if !properties.isEmpty {
                var parameters: [String] = []
                for property in properties {
                    parameters.append("\(property.name): Optional<\(dialectExpressionType(property.qualifiedType))> = nil")
                }
                // A `nil` argument here means "leave this column out of the
                // statement", matching every other column and this
                // initializer's v1 behaviour. That is deliberately not what
                // `nil` means when assigned inside a `Setting` closure, where
                // the column is already part of the statement and `nil` is
                // the value it takes.
                context.block("public init(\(parameters.joined(separator: ", ")))") { context in
                    context.line("_xlColumns = Columns()")
                    for property in properties {
                        if property.optional {
                            context.block("if let \(property.name)") { context in
                                context.line("_xlColumns.\(property.name).optionalExpression = \(property.name)")
                            }
                        }
                        else {
                            context.line("_xlColumns.\(property.name).expression = \(property.name)")
                        }
                    }
                }
            }

            context.block("public func makeSQL(context: inout XLBuilder)") { context in
                context.block("context.unaryPrefix(\"SET\")") { context in
                    context.block("$0.list(separator: \",\")") { context in
                        for property in properties {
                            let assigned = property.optional
                                ? "let \(property.name) = _xlColumns.\(property.name)._xlAssignedExpression"
                                : "let \(property.name) = _xlColumns.\(property.name).expression"
                            context.block("if \(assigned)") { context in
                                context.block("$0.listItem") { context in
                                    context.block("$0.binaryOperator(\"=\", left: XLName(\"\(property.alias)\").makeSQL)") { context in
                                        context.line("\(property.name).writeSQL(context: &$0)")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
               
        context.block("public struct UpdateRequest") { context in
            
            context.line("public typealias Row = \(structName)")
            
            for property in mutableProperties {
                context.line("public var \(property.name): Optional<\(property.type)>")
            }
            
            context.block("public init()") { context in
                for property in mutableProperties {
                    context.line("self.\(property.name) = nil")
                }
            }
            
            if !mutableProperties.isEmpty {
                var parameters: [String] = []
                for property in mutableProperties {
                    parameters.append("\(property.name): Optional<\(property.type)> = nil")
                }
                context.block("public init(\(parameters.joined(separator: ", ")))") { context in
                    for property in mutableProperties {
                        context.line("self.\(property.name) = \(property.name)")
                    }
                }
            }
            
            context.block("public func apply(to entity: Row) -> Row") { context in
                if mutableProperties.isEmpty {
                    context.line("return entity")
                }
                else {
                    context.line("var output = entity")
                    for property in mutableProperties {
                        context.block("if let value = \(property.name)") { context in
                            context.line("output.\(property.name) = value")
                        }
                    }
                    context.line("return output")
                }
            }
            
            context.block("public func makeUpdate() -> MetaUpdate") { context in
                if mutableProperties.isEmpty {
                    context.line("return MetaUpdate()")
                }
                else {
                    context.line("var output = MetaUpdate()")
                    // The value here is always the column's wrapped type, so
                    // it is the wrapped-type expression of nullable and
                    // non-nullable columns alike -- no `toNullable()` lift is
                    // needed. It is written to the slot directly rather than
                    // through the subscript, which takes only the dialect's
                    // expressions (issue #825): the value may be of a type
                    // only a contextual codec encodes, which fails when the
                    // statement is built (issue #651).
                    for property in mutableProperties {
                        context.block("if let value = \(property.name)") { context in
                            context.line("output._xlColumns.\(property.name).expression = SwiftQL._xlLegacyValueExpression(value)")
                        }
                    }
                    context.line("return output")
                }
            }
        }
        
        context.block("public static func makeSQLInsert(namespace: XLNamespace, dependency: XLTableDeclaration) -> MetaWritableTable") { context in
            context.line("MetaWritableTable(namespace: namespace, dependency: dependency)")
        }
        
        context.block("public static func makeSQLUpdate(namespace: XLNamespace, dependency: XLTableDeclaration) -> MetaWritableTable") { context in
            context.line("MetaWritableTable(namespace: namespace, dependency: dependency)")
        }
    }
    
    ///
    /// Emits a `MetaUpdate` subscript's getter (issue #825): the stored
    /// expression cast back to the dialect's expression type, or, for a value
    /// of no dialect, that value inside an `XLTypeAffinityExpression`,
    /// converted by the generated `_xlDialectExpressionMustInclude...`
    /// function.
    ///
    /// The getter is statements that call the conversion. A closure, or a
    /// reference to the static function as a value, captures a generic
    /// model's metatypes, which Swift 6.3 warns about on Linux
    /// (SendableMetatypes) and the warnings gate refuses.
    ///
    private func emitSlotRead(
        read: String,
        untyped: String,
        valueType: String,
        isOptional: Bool,
        into context: inout CodeWriter
    ) {
        let conversion = "Self._xlDialectExpressionMustIncludeXLTypeAffinityExpression"
        context.block("get") { context in
            context.line("let slot = _xlColumns[keyPath: keyPath]")
            context.block("if let typed = slot.\(read)(as: \(dialectExpressionType(valueType)).self)") { context in
                context.line("return typed")
            }
            if isOptional {
                context.line("return \(conversion)(slot.\(untyped))")
            }
            else {
                context.block("guard let untyped = slot.\(untyped) else") { context in
                    context.line("return nil")
                }
                context.line("return \(conversion)(untyped)")
            }
        }
    }

    private func makeCreate(context: inout CodeWriter) {
        
        context.block("public struct MetaCreate: XLMetaCreate") { context in
            
            context.line("public typealias Table = \(structName)")
            
            context.line("public let name: XLQualifiedTableName")
            
            context.block("public init(name: XLQualifiedTableName)") { context in
                context.line("self.name = name")
            }
            
            context.block("public func makeSQL(context: inout XLBuilder)") { context in

                context.block("context.createTable(self.name)") { context in
                    for property in properties {
                        context.line("$0.column(name: XLName(\"\(property.alias)\"), nullable: \(property.optional))")
                    }
                }
            }
        }
        
        context.block("public struct MetaCreateAs: XLMetaCreate") { context in
            
            context.line("public typealias Table = \(structName)")
            
            context.line("public let name: XLQualifiedTableName")
            
            context.block("public init(name: XLQualifiedTableName)") { context in
                context.line("self.name = name")
            }
            
            context.block("public func makeSQL(context: inout XLBuilder)") { context in
                context.line("context.createTable(self.name)")
            }
        }
        
        context.block("public static func makeSQLCreate() -> MetaCreate") { context in
            context.line("MetaCreate(name: sqlTableName())")
        }
        
        context.block("public static func makeSQLCreateAs() -> MetaCreateAs") { context in
            context.line("MetaCreateAs(name: sqlTableName())")
        }
    }
}
