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

            context.line("public let _table: any XLEncodable")

            context.line("public let _namespace: XLNamespace")
            context.line("private let _dependency: XLTableDeclaration")
            
            for property in properties {
                context.line(property.makeColumnPropertyDecl(kind: .reference))
            }

            context.block("public init(namespace: XLNamespace, dependency: XLTableDeclaration)") { context in
                context.line("_namespace = namespace")
                context.line("_dependency = dependency")
                context.line("_table = dependency")
                for property in properties {
                    context.line(property.name + " = " + property.makeInstance(kind: .reference, dependency: "dependency"))
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
                parameters.append("\(property.name): any XLExpression<\(property.qualifiedType)>")
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

            context.block("public struct Columns") { context in
                for property in properties {
                    if property.optional {
                        context.line("public var \(property.name) = SwiftQL.XLNullableColumnUpdate<\(property.type)>()")
                    }
                    else {
                        context.line("public var \(property.name) = SwiftQL.XLColumnUpdate<\(property.qualifiedType)>()")
                    }
                }
                context.block("public init()") { _ in
                }
            }

            context.line("public var _xlColumns: Columns")

            context.block("public subscript<Wrapped>(dynamicMember keyPath: Swift.WritableKeyPath<Columns, SwiftQL.XLColumnUpdate<Wrapped>>) -> Optional<any SwiftQL.XLExpression<Wrapped>>") { context in
                context.block("get") { context in
                    context.line("_xlColumns[keyPath: keyPath].expression")
                }
                context.block("set") { context in
                    context.line("_xlColumns[keyPath: keyPath].expression = newValue")
                }
            }

            // For a nullable column, `nil` assigned through this overload
            // means SQL NULL. Leaving the column out of the statement is what
            // never assigning it does.
            context.block("public subscript<Wrapped>(dynamicMember keyPath: Swift.WritableKeyPath<Columns, SwiftQL.XLNullableColumnUpdate<Wrapped>>) -> Optional<any SwiftQL.XLExpression<Wrapped>>") { context in
                context.block("get") { context in
                    context.line("_xlColumns[keyPath: keyPath].expression")
                }
                context.block("set") { context in
                    context.line("_xlColumns[keyPath: keyPath].expression = newValue")
                }
            }

            // Disfavored so a plain `Wrapped?` value, which both overloads
            // accept with identical rendered SQL, resolves to the wrapped
            // overload instead of being ambiguous. An expression whose type
            // is `Wrapped?` only matches this overload, so it still applies.
            context.line("@_disfavoredOverload")
            context.block("public subscript<Wrapped>(dynamicMember keyPath: Swift.WritableKeyPath<Columns, SwiftQL.XLNullableColumnUpdate<Wrapped>>) -> any SwiftQL.XLExpression<Optional<Wrapped>>") { context in
                context.block("get") { context in
                    context.line("_xlColumns[keyPath: keyPath].optionalExpression ?? SwiftQL.XLNullExpression<Wrapped>()")
                }
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
                    parameters.append("\(property.name): Optional<any XLExpression<\(property.qualifiedType)>> = nil")
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
                    // it routes through MetaUpdate's wrapped-type assignment
                    // for nullable and non-nullable columns alike -- no
                    // `toNullable()` lift is needed.
                    for property in mutableProperties {
                        context.block("if let value = \(property.name)") { context in
                            context.line("output.\(property.name) = SwiftQL._xlLegacyValueExpression(value)")
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
