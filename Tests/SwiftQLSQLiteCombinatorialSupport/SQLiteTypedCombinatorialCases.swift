import Foundation
import SwiftQL


@SQLTable(name: "Orders")
struct C191Order {
    let orderID: Int
    let customerID: String
    let employeeID: Int
    let shippedDate: String?
    let shipRegion: String?
}


@SQLTable(name: "Customers")
struct C191Customer {
    let customerID: String
    let companyName: String
    let contactName: String?
    let city: String?
}


@SQLTable(name: "Employees")
struct C191Employee {
    let employeeID: Int
    let lastName: String
    let reportsTo: Int?
}


@SQLTable(name: "Suppliers")
struct C191Supplier {
    let supplierID: Int
    let companyName: String
    let contactName: String?
    let city: String?
}


@SQLTable(name: "Order Details")
struct C191OrderDetail {
    let orderID: Int
    let productID: Int
    let unitPrice: Double
    let quantity: Int
    let discount: Double
}


@SQLResult
struct C191IntegerRow: Equatable {
    let value: Int
}


@SQLResult
struct C191NullableIntegerRow: Equatable {
    let value: Int?
}


@SQLResult
struct C191ContactLocation: Equatable {
    let city: String?
    let companyName: String
    let contactName: String?
    let relationship: String
}


@SQLResult
struct C191OrderSubtotal: Equatable {
    let orderID: Int
    let subtotal: Double
}


/// Single-column common-table projection for the issue #288 `in(_ table:)`
/// cases. SQLite's `expr IN table-name` form requires the referenced table to
/// expose exactly one column.
@SQLResult
struct C288EmployeeIdentifier: Equatable {
    let employeeID: Int
}


// MARK: - Issue #287 packed operator projections
//
// Each issue #287 case selects one column per overload under test, so a single
// prepared statement carries explicit evidence for a whole operator family and
// optionality shape. The Swift column types record which overloads return
// `Optional` results; the conformance runner compares raw storage values, so
// these types are compile-time evidence rather than a decoding path.

@SQLResult
struct C287RequiredOptionalPair: Equatable {
    let required: Bool
    let optional: Bool?
}


@SQLResult
struct C287BooleanLogicRow: Equatable {
    let required: Bool
    let rightOptional: Bool?
    let leftOptional: Bool?
    let bothOptional: Bool?
    let shortCircuit: Bool?
}


@SQLResult
struct C287ComparisonRow: Equatable {
    let less: Bool
    let lessOrEqual: Bool
    let greater: Bool
    let greaterOrEqual: Bool
}


@SQLResult
struct C287OptionalComparisonRow: Equatable {
    let less: Bool?
    let lessOrEqual: Bool?
    let greater: Bool?
    let greaterOrEqual: Bool?
    let nullOperand: Bool?
}


@SQLResult
struct C287EqualityRow: Equatable {
    let integerEqual: Bool
    let integerNotEqual: Bool
    let textEqual: Bool
}


@SQLResult
struct C287OptionalEqualityRow: Equatable {
    let rightOptional: Bool?
    let leftOptional: Bool?
    let bothOptional: Bool?
    let nullOperand: Bool?
    let bothNull: Bool?
}


public struct SQLiteCombinatorialDraftSelection: Equatable {
    public let dimensionID: String
    public let valueID: String

    public init(dimensionID: String, valueID: String) {
        self.dimensionID = dimensionID
        self.valueID = valueID
    }
}


public struct SQLiteCombinatorialDraftBinding: Equatable {
    public let key: XLBindingKey
    public let value: XLSQLiteValue

    public init(key: XLBindingKey, value: XLSQLiteValue) {
        self.key = key
        self.value = value
    }
}


/// Test-only typed use of SwiftQL's public parameter-declaration surface for
/// an indexed SQLite placeholder. SwiftQL has a named v1 convenience type;
/// indexed contextual parameters are otherwise expressed through the same
/// public `XLBindingReference` and immutable declaration contracts.
private struct C191IndexedIntegerBindingReference: XLBindingReference, Sendable {
    typealias T = Int

    let declaration: XLParameterDeclaration

    init(index: Int) {
        declaration = XLParameterDeclaration(
            key: .indexed(index),
            valueTypeIdentifier: XLValueTypeIdentifier(rawValue: "swift.int"),
            valueTypeName: String(reflecting: Int.self),
            nullability: .required,
            codecIdentity: nil,
            codingContext: XLValueCodingContext(
                site: .parameter,
                path: XLValueCodingPath("c191.indexed-integer")
            )
        )
    }

    func makeSQL(context: inout XLBuilder) {
        context.parameter(declaration)
    }
}


/// A fully typed SwiftQL construction before its deterministic manifest form
/// is rendered. Type erasure occurs only after the complete public DSL
/// statement has been built.
public struct SQLiteCombinatorialCaseDraft {
    public let id: String
    public let templateID: String
    public let strength: String
    public let selections: [SQLiteCombinatorialDraftSelection]
    public let inventoryFeatureIDs: [String]
    public let northwindAnchorCaseIDs: [String]
    public let requiredCapabilities: [String]
    public let statement: any XLEncodable
    public let bindings: [SQLiteCombinatorialDraftBinding]
    public let semanticOracleID: String?

    init(
        id: String,
        templateID: String,
        strength: String,
        selections: [SQLiteCombinatorialDraftSelection],
        inventoryFeatureIDs: [String],
        northwindAnchorCaseIDs: [String],
        requiredCapabilities: [String] = [],
        statement: any XLEncodable,
        bindings: [SQLiteCombinatorialDraftBinding] = [],
        semanticOracleID: String? = nil
    ) {
        self.id = id
        self.templateID = templateID
        self.strength = strength
        self.selections = selections
        self.inventoryFeatureIDs = inventoryFeatureIDs.sorted()
        self.northwindAnchorCaseIDs = northwindAnchorCaseIDs.sorted()
        self.requiredCapabilities = requiredCapabilities.sorted()
        self.statement = statement
        self.bindings = bindings
        self.semanticOracleID = semanticOracleID
    }
}


public enum SQLiteTypedCombinatorialCases {

    public static let dimensionOrder = [
        "projection",
        "source",
        "join",
        "predicate",
        "grouping",
        "having",
        "ordering",
        "limit",
        "offset",
    ]

    public static let dimensionValues: [(id: String, values: [String])] = [
        ("projection", ["order-id", "nullable-region", "aggregate-count"]),
        ("source", ["table-auto", "table-alias", "subquery-alias"]),
        ("join", ["none", "inner", "left", "cross"]),
        (
            "predicate",
            [
                "none",
                "literal",
                "named-binding",
                "repeated-binding",
                "empty-in",
                "in-list",
                "injection-binding",
                "null-comparison",
                "precedence",
            ]
        ),
        ("grouping", ["none", "customer-id"]),
        ("having", ["none", "count-greater-than-one"]),
        ("ordering", ["none", "ascending", "descending", "collated"]),
        ("limit", ["none", "five"]),
        ("offset", ["none", "two"]),
    ]

    public static let requiredHigherOrderAssignments: [[String: String]] = [
        [
            "projection": "nullable-region",
            "source": "table-alias",
            "join": "left",
            "predicate": "null-comparison",
            "grouping": "customer-id",
            "having": "count-greater-than-one",
            "ordering": "collated",
            "limit": "five",
            "offset": "two",
        ],
        [
            "projection": "aggregate-count",
            "source": "subquery-alias",
            "join": "inner",
            "predicate": "repeated-binding",
            "grouping": "customer-id",
            "having": "count-greater-than-one",
            "ordering": "descending",
            "limit": "five",
            "offset": "two",
        ],
        [
            "projection": "order-id",
            "source": "table-auto",
            "join": "cross",
            "predicate": "injection-binding",
            "grouping": "none",
            "having": "none",
            "ordering": "none",
            "limit": "none",
            "offset": "none",
        ],
    ]

    /// Builds one SELECT-family case from a complete, constraint-valid
    /// assignment. Every public clause stage is selected independently; the
    /// planner owns the two SQL legality constraints and this factory fails
    /// closed if an illegal HAVING or OFFSET assignment reaches construction.
    public static func selectCase(
        assignment: [String: String],
        strength: String = "pairwise"
    ) -> SQLiteCombinatorialCaseDraft {
        for dimension in dimensionOrder {
            precondition(
                assignment[dimension] != nil,
                "Missing combinatorial dimension: \(dimension)"
            )
        }

        let projection = assignment["projection"]!
        let sourceID = assignment["source"]!
        let joinID = assignment["join"]!
        let predicateID = assignment["predicate"]!
        let groupingID = assignment["grouping"]!
        let havingID = assignment["having"]!
        let orderingID = assignment["ordering"]!
        let limitID = assignment["limit"]!
        let offsetID = assignment["offset"]!

        precondition(
            havingID == "none" || groupingID != "none",
            "HAVING requires GROUP BY"
        )
        precondition(
            offsetID == "none" || limitID != "none",
            "OFFSET requires LIMIT"
        )

        let schema = XLSchema()
        let orders = orderSource(schema: schema, sourceID: sourceID)
        let (predicate, bindings) = predicate(
            orders: orders,
            predicateID: predicateID
        )
        let ordering = ordering(orders: orders, orderingID: orderingID)

        let statement: any XLEncodable
        switch projection {
        case "order-id":
            statement = completeSelect(
                select: select(orders.orderID),
                schema: schema,
                orders: orders,
                joinID: joinID,
                predicate: predicate,
                groupingID: groupingID,
                havingID: havingID,
                ordering: ordering,
                orderingID: orderingID,
                limitID: limitID,
                offsetID: offsetID
            )
        case "nullable-region":
            statement = completeSelect(
                select: select(orders.shipRegion),
                schema: schema,
                orders: orders,
                joinID: joinID,
                predicate: predicate,
                groupingID: groupingID,
                havingID: havingID,
                ordering: ordering,
                orderingID: orderingID,
                limitID: limitID,
                offsetID: offsetID
            )
        case "aggregate-count":
            statement = completeSelect(
                select: select(orders.orderID.count()),
                schema: schema,
                orders: orders,
                joinID: joinID,
                predicate: predicate,
                groupingID: groupingID,
                havingID: havingID,
                ordering: ordering,
                orderingID: orderingID,
                limitID: limitID,
                offsetID: offsetID
            )
        default:
            preconditionFailure("Unknown projection: \(projection)")
        }

        let selections = dimensionOrder.map {
            SQLiteCombinatorialDraftSelection(
                dimensionID: $0,
                valueID: assignment[$0]!
            )
        }
        let features = selectFeatureIDs(
            assignment: assignment,
            bindings: bindings
        )
        let anchors = northwindAnchorIDs(assignment: assignment)

        return SQLiteCombinatorialCaseDraft(
            id: stableSelectCaseID(assignment: assignment),
            templateID: selectTemplateID(assignment: assignment),
            strength: strength,
            selections: selections,
            inventoryFeatureIDs: features,
            northwindAnchorCaseIDs: anchors,
            statement: statement,
            bindings: bindings,
            semanticOracleID: semanticOracleID(assignment: assignment)
        )
    }

    /// Typed CTE/compound cases deliberately keep each operator as a distinct
    /// compile-time result-builder branch. Recursive definitions always use
    /// UNION ALL for termination, while the outer compound exercises every
    /// currently public set operator.
    public static func compoundAndCTECases() -> [SQLiteCombinatorialCaseDraft] {
        let shapes = ["ordinary-required", "ordinary-nullable", "recursive-required"]
        let operators = ["union", "union-all", "intersect", "except"]
        return shapes.flatMap { shape in
            operators.map { operation in
                let features: [String]
                if operation == "intersect" || operation == "except" {
                    features = [
                        "syntax.compound.current-set-operators",
                        "syntax.compound.intersect-except-prepare-gap",
                        "syntax.cte.recursive",
                    ]
                } else {
                    features = [
                        "syntax.compound.current-set-operators",
                        "syntax.cte.recursive",
                    ]
                }
                return SQLiteCombinatorialCaseDraft(
                    id: "c191.v1.cte.\(shape).\(operation)",
                    templateID: "cte.\(shape).\(operation)",
                    strength: "targeted-two-way",
                    selections: [
                        .init(dimensionID: "cte-shape", valueID: shape),
                        .init(dimensionID: "compound-operator", valueID: operation),
                    ],
                    inventoryFeatureIDs: features,
                    northwindAnchorCaseIDs: [],
                    statement: cteCompoundStatement(shape: shape, operation: operation),
                    semanticOracleID: "oracle.c191.cte-compound"
                )
            }
        }
    }

    /// Two real adaptations of the #254 Northwind compound and CTE cases.
    /// Constant-only CTE templates above intentionally carry no Northwind
    /// anchors; these statements are the cases that actually consume the
    /// pinned tables and independent semantic contracts.
    public static func northwindAdaptationCases() -> [SQLiteCombinatorialCaseDraft] {
        [northwindCompoundCase(), northwindCTECase()]
    }

    private static func northwindCompoundCase() -> SQLiteCombinatorialCaseDraft {
        let statement = sql { schema in
            let customers = schema.table(C191Customer.self)
            let suppliers = schema.table(C191Supplier.self)
            let customerRow = C191ContactLocation.columns(
                city: customers.city,
                companyName: customers.companyName,
                contactName: customers.contactName,
                relationship: "Customers"
            )
            let supplierRow = C191ContactLocation.columns(
                city: suppliers.city,
                companyName: suppliers.companyName,
                contactName: suppliers.contactName,
                relationship: "Suppliers"
            )
            Select(customerRow)
            From(customers)
            Union()
            Select(supplierRow)
            From(suppliers)
            OrderBy(
                customerRow.city.ascending(),
                customerRow.companyName.ascending(),
                customerRow.relationship.ascending(),
                customerRow.contactName.ascending()
            )
        }

        return SQLiteCombinatorialCaseDraft(
            id: "c191.v1.northwind.compound-customer-supplier-cities",
            templateID: "northwind.compound-customer-supplier-cities",
            strength: "targeted",
            selections: [
                .init(
                    dimensionID: "northwind-adaptation",
                    valueID: "compound-customer-supplier-cities"
                ),
            ],
            inventoryFeatureIDs: [
                "syntax.compound.current-set-operators",
                "syntax.select.core",
            ],
            northwindAnchorCaseIDs: [
                "northwind.compound.customer-supplier-cities",
            ],
            statement: statement,
            semanticOracleID: "oracle.c191.northwind.customer-supplier-cities"
        )
    }

    private static func northwindCTECase() -> SQLiteCombinatorialCaseDraft {
        let statement = sql { schema in
            let subtotals = schema.commonTableExpression { schema in
                let details = schema.table(C191OrderDetail.self)
                let discountedLine = details.unitPrice
                    * details.quantity.toDouble()
                    * (1.0 - details.discount)
                Select(C191OrderSubtotal.columns(
                    orderID: details.orderID,
                    subtotal: discountedLine.sumOrNull().coalesce(0)
                ))
                From(details)
                GroupBy(details.orderID)
            }
            let rows = schema.table(subtotals)
            With(subtotals)
            Select(rows)
            From(rows)
            Where(rows.orderID == 10_248)
            OrderBy(rows.orderID.ascending())
        }

        return SQLiteCombinatorialCaseDraft(
            id: "c191.v1.northwind.cte-order-subtotals",
            templateID: "northwind.cte-order-subtotals",
            strength: "targeted",
            selections: [
                .init(
                    dimensionID: "northwind-adaptation",
                    valueID: "cte-order-subtotals"
                ),
            ],
            inventoryFeatureIDs: [
                "syntax.cte.recursive",
                "syntax.expression.aggregate-functions",
                "syntax.select.core",
            ],
            northwindAnchorCaseIDs: [
                "northwind.cte.order-subtotals",
            ],
            statement: statement,
            semanticOracleID: "oracle.c191.northwind.cte-order-subtotals"
        )
    }

    /// Issue #288: finite typed evidence for both query-backed IN entry points
    /// against the pinned Northwind fixture.
    ///
    /// `in(expression:)` is exercised in its result-builder and its functional
    /// form, and `in(_ table:)` against an ordinary common table expression.
    /// Each entry point pairs a non-empty inner result with an empty one so the
    /// outer statement's row behaviour is proven rather than only its
    /// rendering. Nullable IN operands stay with #70 and `NOT IN` stays with
    /// #84; neither is constructed here.
    public static func inSubqueryCases() -> [SQLiteCombinatorialCaseDraft] {
        [
            inQueryBuilderCase(id: "in-query-builder-nonempty", employeeID: 5),
            inQueryBuilderCase(id: "in-query-builder-empty", employeeID: -1),
            inQueryFunctionalCase(),
            inCommonTableCase(id: "in-table-nonempty", employeeID: 4),
            inCommonTableCase(id: "in-table-empty", employeeID: -1),
        ]
    }

    /// `XLExpression.in(expression:)` in its `@XLQueryExpressionBuilder` form.
    /// The bound placeholder lives inside the subquery, so the rendered
    /// parameter layout proves that nested query bindings reach the outer
    /// statement's slot list.
    private static func inQueryBuilderCase(
        id: String,
        employeeID: Int
    ) -> SQLiteCombinatorialCaseDraft {
        let employeeBinding = XLNamedBindingReference<Int>(
            name: "in_subquery_employee_id"
        )
        let statement = sql { schema in
            let orders = schema.table(C191Order.self)
            Select(orders.orderID)
            From(orders)
            Where(
                orders.employeeID.in { inner in
                    let employees = inner.table(C191Employee.self)
                    Select(employees.employeeID)
                    From(employees)
                    Where(employees.employeeID == employeeBinding)
                }
            )
            OrderBy(orders.orderID.ascending())
            Limit(5)
        }

        return inSubqueryCase(
            id: id,
            statement: statement,
            bindings: [
                .init(
                    key: .named("in_subquery_employee_id"),
                    value: .integer(Int64(employeeID))
                ),
            ]
        )
    }

    /// `XLExpression.in(expression:)` in its functional form, over a text
    /// operand so the entry point is proven for more than one storage class.
    private static func inQueryFunctionalCase() -> SQLiteCombinatorialCaseDraft {
        let customerBinding = XLNamedBindingReference<String>(
            name: "in_subquery_customer_id"
        )
        let schema = XLSchema()
        let orders = schema.table(C191Order.self)
        let customers = schema.table(C191Customer.self)
        let statement = select(orders.orderID)
            .from(orders)
            .where(
                orders.customerID.in {
                    select(customers.customerID)
                        .from(customers)
                        .where(customers.customerID == customerBinding)
                }
            )
            .orderBy(orders.orderID.ascending())
            .limit(5)

        return inSubqueryCase(
            id: "in-query-functional-nonempty",
            statement: statement,
            bindings: [
                .init(
                    key: .named("in_subquery_customer_id"),
                    value: .text("VINET")
                ),
            ]
        )
    }

    /// `XLExpression.in(_ table:)` against an ordinary common table
    /// expression, which renders SQLite's `expr IN table-name` form.
    private static func inCommonTableCase(
        id: String,
        employeeID: Int
    ) -> SQLiteCombinatorialCaseDraft {
        let employeeBinding = XLNamedBindingReference<Int>(
            name: "in_table_employee_id"
        )
        let statement = sql { schema in
            let matchingEmployees = schema.commonTableExpression { inner in
                let employees = inner.table(C191Employee.self)
                Select(C288EmployeeIdentifier.columns(
                    employeeID: employees.employeeID
                ))
                From(employees)
                Where(employees.employeeID == employeeBinding)
            }
            let orders = schema.table(C191Order.self)
            With(matchingEmployees)
            Select(orders.orderID)
            From(orders)
            Where(orders.employeeID.in(matchingEmployees))
            OrderBy(orders.orderID.ascending())
            Limit(5)
        }

        return inSubqueryCase(
            id: id,
            statement: statement,
            bindings: [
                .init(
                    key: .named("in_table_employee_id"),
                    value: .integer(Int64(employeeID))
                ),
            ]
        )
    }

    private static func inSubqueryCase(
        id: String,
        statement: any XLEncodable,
        bindings: [SQLiteCombinatorialDraftBinding]
    ) -> SQLiteCombinatorialCaseDraft {
        SQLiteCombinatorialCaseDraft(
            id: "c288.v1.subquery.\(id)",
            templateID: "subquery.\(id)",
            strength: "targeted",
            selections: [.init(dimensionID: "in-subquery-case", valueID: id)],
            inventoryFeatureIDs: [
                "syntax.expression.current-operators",
                "syntax.select.core",
                "syntax.subquery.table-and-in-prepare-gap",
            ],
            northwindAnchorCaseIDs: [],
            statement: statement,
            bindings: bindings,
            semanticOracleID: "oracle.c288.subquery.\(id)"
        )
    }

    /// Issue #287, part one: every public Boolean, comparison, and equality
    /// operator overload named by `syntax.expression.operator-prepare-gap`.
    ///
    /// Overloads are packed by family and optionality shape rather than given
    /// one case each. A packed case still prepares and executes every overload
    /// it names — each appears as its own result column — and keeps the corpus
    /// inside its declared bound. Arithmetic, unary, optional-coalescing, and
    /// text overloads follow in part two.
    ///
    /// Values are chosen so no column can pass by accident: every family
    /// includes a NULL operand *and* a non-NULL one, so an overload that
    /// silently dropped its operand would change at least one column.
    public static func booleanComparisonEqualityCases()
        -> [SQLiteCombinatorialCaseDraft] {
        let boolTrue = XLNamedBindingReference<Bool>(name: "bool_true")
        let boolFalse = XLNamedBindingReference<Bool>(name: "bool_false")
        let boolNull = XLNamedBindingReference<Bool?>(name: "bool_null")
        let intLeft = XLNamedBindingReference<Int>(name: "int_left")
        let intRight = XLNamedBindingReference<Int>(name: "int_right")
        let intOptional = XLNamedBindingReference<Int?>(name: "int_optional")
        let intOptionalB = XLNamedBindingReference<Int?>(name: "int_optional_b")
        let intNull = XLNamedBindingReference<Int?>(name: "int_null")
        let textLeft = XLNamedBindingReference<String>(name: "text_left")

        let trueBinding = SQLiteCombinatorialDraftBinding(
            key: .named("bool_true"),
            value: .integer(1)
        )
        let falseBinding = SQLiteCombinatorialDraftBinding(
            key: .named("bool_false"),
            value: .integer(0)
        )
        let nullBoolBinding = SQLiteCombinatorialDraftBinding(
            key: .named("bool_null"),
            value: .null
        )
        let leftBinding = SQLiteCombinatorialDraftBinding(
            key: .named("int_left"),
            value: .integer(7)
        )
        let rightBinding = SQLiteCombinatorialDraftBinding(
            key: .named("int_right"),
            value: .integer(3)
        )
        let optionalBinding = SQLiteCombinatorialDraftBinding(
            key: .named("int_optional"),
            value: .integer(3)
        )
        let optionalBBinding = SQLiteCombinatorialDraftBinding(
            key: .named("int_optional_b"),
            value: .integer(5)
        )
        let nullIntBinding = SQLiteCombinatorialDraftBinding(
            key: .named("int_null"),
            value: .null
        )
        let textBinding = SQLiteCombinatorialDraftBinding(
            key: .named("text_left"),
            value: .text("alfa")
        )

        return [
            // NOT over both operand shapes. The optional column is also the
            // three-valued `NOT NULL IS NULL` assertion.
            issue287Case(
                id: "boolean-not-shapes",
                featureID: "syntax.expression.operator-prepare-gap",
                statement: select(C287RequiredOptionalPair.columns(
                    required: !boolTrue,
                    optional: !boolNull
                )),
                bindings: [trueBinding, nullBoolBinding]
            ),
            // AND over all four shapes, plus SQLite's asymmetric three-valued
            // rule: NULL AND false is false, while NULL AND true is NULL.
            issue287Case(
                id: "boolean-and-shapes",
                featureID: "syntax.expression.operator-prepare-gap",
                statement: select(C287BooleanLogicRow.columns(
                    required: boolTrue && boolFalse,
                    rightOptional: boolTrue && boolNull,
                    leftOptional: boolNull && boolTrue,
                    bothOptional: boolNull && boolNull,
                    shortCircuit: boolNull && boolFalse
                )),
                bindings: [trueBinding, falseBinding, nullBoolBinding]
            ),
            // OR over all four shapes, plus the dual rule: NULL OR true is
            // true, while NULL OR false is NULL.
            issue287Case(
                id: "boolean-or-shapes",
                featureID: "syntax.expression.operator-prepare-gap",
                statement: select(C287BooleanLogicRow.columns(
                    required: boolTrue || boolFalse,
                    rightOptional: boolTrue || boolNull,
                    leftOptional: boolNull || boolFalse,
                    bothOptional: boolNull || boolNull,
                    shortCircuit: boolFalse || boolNull
                )),
                bindings: [trueBinding, falseBinding, nullBoolBinding]
            ),
            issue287Case(
                id: "comparison-required",
                featureID: "syntax.expression.operator-prepare-gap",
                statement: select(C287ComparisonRow.columns(
                    less: intLeft < intRight,
                    lessOrEqual: intLeft <= intRight,
                    greater: intLeft > intRight,
                    greaterOrEqual: intLeft >= intRight
                )),
                bindings: [leftBinding, rightBinding]
            ),
            issue287Case(
                id: "comparison-right-optional",
                featureID: "syntax.expression.operator-prepare-gap",
                statement: select(C287OptionalComparisonRow.columns(
                    less: intLeft < intOptional,
                    lessOrEqual: intLeft <= intOptional,
                    greater: intLeft > intOptional,
                    greaterOrEqual: intLeft >= intOptional,
                    nullOperand: intLeft > intNull
                )),
                bindings: [leftBinding, optionalBinding, nullIntBinding]
            ),
            // Equal operands on the boundary, so `<` and `<=` cannot agree.
            issue287Case(
                id: "comparison-left-optional",
                featureID: "syntax.expression.operator-prepare-gap",
                statement: select(C287OptionalComparisonRow.columns(
                    less: intOptional < intRight,
                    lessOrEqual: intOptional <= intRight,
                    greater: intOptional > intRight,
                    greaterOrEqual: intOptional >= intRight,
                    nullOperand: intNull > intRight
                )),
                bindings: [optionalBinding, rightBinding, nullIntBinding]
            ),
            issue287Case(
                id: "comparison-both-optional",
                featureID: "syntax.expression.operator-prepare-gap",
                statement: select(C287OptionalComparisonRow.columns(
                    less: intOptional < intOptionalB,
                    lessOrEqual: intOptional <= intOptionalB,
                    greater: intOptional > intOptionalB,
                    greaterOrEqual: intOptional >= intOptionalB,
                    nullOperand: intOptional > intNull
                )),
                bindings: [optionalBinding, optionalBBinding, nullIntBinding]
            ),
            issue287Case(
                id: "equality-required",
                featureID: "syntax.expression.operator-prepare-gap",
                statement: select(C287EqualityRow.columns(
                    integerEqual: intLeft == intRight,
                    integerNotEqual: intLeft != intRight,
                    textEqual: textLeft == textLeft
                )),
                bindings: [leftBinding, rightBinding, textBinding]
            ),
            // The optional `==` overloads render SQLite `IS`, which is never
            // NULL even though the Swift result type is `Optional<Bool>`. The
            // last two columns pin that deviation.
            issue287Case(
                id: "equality-optional-shapes",
                featureID: "syntax.expression.operator-prepare-gap",
                statement: select(C287OptionalEqualityRow.columns(
                    rightOptional: intLeft == intOptional,
                    leftOptional: intOptional == intRight,
                    bothOptional: intOptional == intOptionalB,
                    nullOperand: intLeft == intNull,
                    bothNull: intNull == intNull
                )),
                bindings: [
                    leftBinding,
                    rightBinding,
                    optionalBinding,
                    optionalBBinding,
                    nullIntBinding,
                ]
            ),
            // The same deviation for `IS NOT`.
            issue287Case(
                id: "inequality-optional-shapes",
                featureID: "syntax.expression.operator-prepare-gap",
                statement: select(C287OptionalEqualityRow.columns(
                    rightOptional: intLeft != intOptional,
                    leftOptional: intOptional != intRight,
                    bothOptional: intOptional != intOptionalB,
                    nullOperand: intLeft != intNull,
                    bothNull: intNull != intNull
                )),
                bindings: [
                    leftBinding,
                    rightBinding,
                    optionalBinding,
                    optionalBBinding,
                    nullIntBinding,
                ]
            ),
        ]
    }

    private static func issue287Case(
        id: String,
        featureID: String,
        statement: any XLEncodable,
        bindings: [SQLiteCombinatorialDraftBinding]
    ) -> SQLiteCombinatorialCaseDraft {
        SQLiteCombinatorialCaseDraft(
            id: "c287.v1.expression.\(id)",
            templateID: "expression.\(id)",
            strength: "targeted",
            selections: [.init(dimensionID: "operator-case", valueID: id)],
            inventoryFeatureIDs: [featureID],
            northwindAnchorCaseIDs: [],
            statement: statement,
            bindings: bindings,
            semanticOracleID: "oracle.c287.expression.\(id)"
        )
    }

    /// Bounded hand-selected expression cases fill public, already-adopted
    /// function/operator/cast gaps. They are not an invitation to grow this
    /// issue into the deferred expression grammar.
    public static func adoptedExpressionCases() -> [SQLiteCombinatorialCaseDraft] {
        let namedInteger = XLNamedBindingReference<Int>(name: "integer_value")
        let namedReal = XLNamedBindingReference<Double>(name: "real_value")
        let namedText = XLNamedBindingReference<String>(name: "text_value")
        let indexedInteger = C191IndexedIntegerBindingReference(index: 0)

        let issue191Cases = [
            expressionCase(
                id: "indexed-binding",
                featureID: "binding.indexed",
                statement: select(indexedInteger),
                bindings: [.init(key: .indexed(0), value: .integer(191))]
            ),
            expressionCase(
                id: "numeric-abs",
                featureID: "syntax.expression.numeric-comparable-functions",
                statement: select(namedInteger.abs()),
                bindings: [.init(key: .named("integer_value"), value: .integer(-7))]
            ),
            expressionCase(
                id: "numeric-round",
                featureID: "syntax.expression.numeric-comparable-functions",
                statement: select(namedReal.rounded(to: 2)),
                bindings: [.init(key: .named("real_value"), value: .real(3.14159))]
            ),
            expressionCase(
                id: "numeric-floor",
                featureID: "syntax.expression.numeric-comparable-functions",
                statement: select(namedReal.floor()),
                bindings: [.init(key: .named("real_value"), value: .real(3.9))],
                requiredCapabilities: ["function:FLOOR"]
            ),
            expressionCase(
                id: "comparable-min",
                featureID: "syntax.expression.numeric-comparable-functions",
                statement: select(min(namedInteger, 191)),
                bindings: [.init(key: .named("integer_value"), value: .integer(254))]
            ),
            expressionCase(
                id: "string-printf",
                featureID: "syntax.expression.string-functions",
                statement: select(printf(format: "%s-%d", namedText, namedInteger)),
                bindings: [
                    .init(key: .named("text_value"), value: .text("case")),
                    .init(key: .named("integer_value"), value: .integer(191)),
                ]
            ),
            expressionCase(
                id: "cast-text-integer",
                featureID: "syntax.expression.type-casts",
                statement: select(namedText.toInt()),
                bindings: [.init(key: .named("text_value"), value: .text("42"))]
            ),
            expressionCase(
                id: "cast-text-blob",
                featureID: "syntax.expression.type-casts",
                statement: select(namedText.toData()),
                bindings: [.init(key: .named("text_value"), value: .text("blob"))]
            ),
            expressionCase(
                id: "date-unixepoch",
                featureID: "syntax.expression.date-functions",
                statement: select(namedText.toUnixTimestamp()),
                bindings: [
                    .init(
                        key: .named("text_value"),
                        value: .text("2026-07-19T12:00:00Z")
                    ),
                ],
                requiredCapabilities: ["function:UNIXEPOCH"]
            ),
            expressionCase(
                id: "json-valid",
                featureID: "syntax.expression.json-functions",
                statement: select(namedText.validJSON()),
                bindings: [
                    .init(key: .named("text_value"), value: .text("{\"ok\":true}")),
                ],
                requiredCapabilities: ["sqlite-json-functions"]
            ),
            expressionCase(
                id: "json-array-length",
                featureID: "syntax.expression.json-functions",
                statement: select(namedText.jsonArrayLength()),
                bindings: [
                    .init(key: .named("text_value"), value: .text("[1,2,3]")),
                ],
                requiredCapabilities: ["sqlite-json-functions"]
            ),
            expressionCase(
                id: "operator-arithmetic-precedence",
                featureID: "syntax.expression.operator-prepare-gap",
                statement: select((namedInteger + 7) * 2),
                bindings: [.init(key: .named("integer_value"), value: .integer(3))]
            ),
            expressionCase(
                id: "operator-glob",
                featureID: "syntax.expression.operator-prepare-gap",
                statement: select(namedText.glob("A*")),
                bindings: [.init(key: .named("text_value"), value: .text("ALFKI"))]
            ),
        ]
        return issue191Cases + issue286ExpressionCases()
    }

    /// The bounded issue #286 extension closes measured overload gaps without
    /// introducing raw-SQL generated inputs or expanding into new syntax.
    private static func issue286ExpressionCases() -> [SQLiteCombinatorialCaseDraft] {
        let namedBoolean = XLNamedBindingReference<Bool>(name: "boolean_value")
        let namedOptionalBoolean = XLNamedBindingReference<Bool?>(
            name: "optional_boolean_value"
        )
        let namedInteger = XLNamedBindingReference<Int>(name: "integer_value")
        let namedOptionalInteger = XLNamedBindingReference<Int?>(
            name: "optional_integer_value"
        )
        let namedReal = XLNamedBindingReference<Double>(name: "real_value")
        let namedOptionalReal = XLNamedBindingReference<Double?>(
            name: "optional_real_value"
        )
        let namedText = XLNamedBindingReference<String>(name: "text_value")
        let namedOptionalText = XLNamedBindingReference<String?>(
            name: "optional_text_value"
        )
        let namedBlob = XLNamedBindingReference<Data>(name: "blob_value")
        let namedOptionalBlob = XLNamedBindingReference<Data?>(
            name: "optional_blob_value"
        )

        return issue286AggregateCases() + [
            issue286ExpressionCase(
                id: "numeric-round-no-places",
                featureID: "syntax.expression.numeric-comparable-functions",
                statement: select(namedReal.rounded()),
                bindings: [.init(key: .named("real_value"), value: .real(3.6))]
            ),
            issue286ExpressionCase(
                id: "numeric-round-optional",
                featureID: "syntax.expression.numeric-comparable-functions",
                statement: select(namedOptionalReal.rounded()),
                bindings: [.init(key: .named("optional_real_value"), value: .null)]
            ),
            issue286ExpressionCase(
                id: "comparable-max",
                featureID: "syntax.expression.numeric-comparable-functions",
                statement: select(max(namedInteger, 191)),
                bindings: [.init(key: .named("integer_value"), value: .integer(254))]
            ),
            issue286ExpressionCase(
                id: "string-printf-array",
                featureID: "syntax.expression.string-functions",
                statement: select(
                    printf(
                        format: "%s-%d",
                        [namedText, namedInteger]
                    )
                ),
                bindings: [
                    .init(key: .named("text_value"), value: .text("case")),
                    .init(key: .named("integer_value"), value: .integer(286)),
                ]
            ),
            issue286ExpressionCase(
                id: "json-array-length-path",
                featureID: "syntax.expression.json-functions",
                statement: select(namedText.jsonArrayLength(path: "$.items")),
                bindings: [
                    .init(
                        key: .named("text_value"),
                        value: .text("{\"items\":[1,2,3]}")
                    ),
                ],
                requiredCapabilities: ["sqlite-json-functions"]
            ),
            issue286ExpressionCase(
                id: "cast-bool-integer",
                featureID: "syntax.expression.type-casts",
                statement: select(namedBoolean.toInt()),
                bindings: [.init(key: .named("boolean_value"), value: .integer(1))]
            ),
            issue286ExpressionCase(
                id: "cast-optional-bool-integer",
                featureID: "syntax.expression.type-casts",
                statement: select(namedOptionalBoolean.toInt()),
                bindings: [
                    .init(key: .named("optional_boolean_value"), value: .null),
                ]
            ),
            issue286ExpressionCase(
                id: "cast-integer-real",
                featureID: "syntax.expression.type-casts",
                statement: select(namedInteger.toDouble()),
                bindings: [.init(key: .named("integer_value"), value: .integer(42))]
            ),
            issue286ExpressionCase(
                id: "cast-integer-text",
                featureID: "syntax.expression.type-casts",
                statement: select(namedInteger.toString()),
                bindings: [.init(key: .named("integer_value"), value: .integer(42))]
            ),
            issue286ExpressionCase(
                id: "cast-optional-integer-real",
                featureID: "syntax.expression.type-casts",
                statement: select(namedOptionalInteger.toDouble()),
                bindings: [
                    .init(key: .named("optional_integer_value"), value: .null),
                ]
            ),
            issue286ExpressionCase(
                id: "cast-optional-integer-text",
                featureID: "syntax.expression.type-casts",
                statement: select(namedOptionalInteger.toString()),
                bindings: [
                    .init(key: .named("optional_integer_value"), value: .null),
                ]
            ),
            issue286ExpressionCase(
                id: "cast-real-integer",
                featureID: "syntax.expression.type-casts",
                statement: select(namedReal.toInt()),
                bindings: [.init(key: .named("real_value"), value: .real(42.75))]
            ),
            issue286ExpressionCase(
                id: "cast-real-text",
                featureID: "syntax.expression.type-casts",
                statement: select(namedReal.toString()),
                bindings: [.init(key: .named("real_value"), value: .real(42.5))]
            ),
            issue286ExpressionCase(
                id: "cast-optional-real-integer",
                featureID: "syntax.expression.type-casts",
                statement: select(namedOptionalReal.toInt()),
                bindings: [.init(key: .named("optional_real_value"), value: .null)]
            ),
            issue286ExpressionCase(
                id: "cast-optional-real-text",
                featureID: "syntax.expression.type-casts",
                statement: select(namedOptionalReal.toString()),
                bindings: [.init(key: .named("optional_real_value"), value: .null)]
            ),
            issue286ExpressionCase(
                id: "cast-text-real",
                featureID: "syntax.expression.type-casts",
                statement: select(namedText.toDouble()),
                bindings: [.init(key: .named("text_value"), value: .text("42.5"))]
            ),
            issue286ExpressionCase(
                id: "cast-optional-text-integer",
                featureID: "syntax.expression.type-casts",
                statement: select(namedOptionalText.toInt()),
                bindings: [.init(key: .named("optional_text_value"), value: .null)]
            ),
            issue286ExpressionCase(
                id: "cast-optional-text-real",
                featureID: "syntax.expression.type-casts",
                statement: select(namedOptionalText.toDouble()),
                bindings: [.init(key: .named("optional_text_value"), value: .null)]
            ),
            issue286ExpressionCase(
                id: "cast-optional-text-blob",
                featureID: "syntax.expression.type-casts",
                statement: select(namedOptionalText.toData()),
                bindings: [.init(key: .named("optional_text_value"), value: .null)]
            ),
            issue286ExpressionCase(
                id: "cast-blob-text",
                featureID: "syntax.expression.type-casts",
                statement: select(namedBlob.toString()),
                bindings: [
                    .init(key: .named("blob_value"), value: .blob(Data("blob".utf8))),
                ]
            ),
            issue286ExpressionCase(
                id: "cast-optional-blob-text",
                featureID: "syntax.expression.type-casts",
                statement: select(namedOptionalBlob.toString()),
                bindings: [.init(key: .named("optional_blob_value"), value: .null)]
            ),
        ]
    }

    private static func issue286AggregateCases() -> [SQLiteCombinatorialCaseDraft] {
        let cases: [(String, any XLEncodable)] = [
            (
                "aggregate-count-distinct",
                sql { schema in
                    let orders = schema.table(C191Order.self)
                    Select(orders.employeeID.count(distinct: true))
                    From(orders)
                }
            ),
            (
                "aggregate-min-distinct",
                sql { schema in
                    let orders = schema.table(C191Order.self)
                    Select(orders.employeeID.minOrNull(distinct: true))
                    From(orders)
                }
            ),
            (
                "aggregate-max-distinct",
                sql { schema in
                    let orders = schema.table(C191Order.self)
                    Select(orders.employeeID.maxOrNull(distinct: true))
                    From(orders)
                }
            ),
            (
                "aggregate-average-distinct",
                sql { schema in
                    let orders = schema.table(C191Order.self)
                    Select(orders.employeeID.toDouble().averageOrNull(distinct: true))
                    From(orders)
                }
            ),
            (
                "aggregate-sum-distinct",
                sql { schema in
                    let orders = schema.table(C191Order.self)
                    Select(orders.employeeID.sumOrNull(distinct: true))
                    From(orders)
                }
            ),
            (
                "aggregate-group-concat-distinct",
                sql { schema in
                    let orders = schema.table(C191Order.self)
                    Select(orders.customerID.groupConcatOrNull(distinct: true))
                    From(orders)
                }
            ),
        ]
        return cases.map { id, statement in
            issue286ExpressionCase(
                id: id,
                featureID: "syntax.expression.aggregate-functions",
                statement: statement,
                bindings: []
            )
        }
    }

    private static func expressionCase(
        id: String,
        featureID: String,
        statement: any XLEncodable,
        bindings: [SQLiteCombinatorialDraftBinding],
        requiredCapabilities: [String] = []
    ) -> SQLiteCombinatorialCaseDraft {
        SQLiteCombinatorialCaseDraft(
            id: "c191.v1.expression.\(id)",
            templateID: "expression.\(id)",
            strength: "targeted",
            selections: [.init(dimensionID: "expression-case", valueID: id)],
            inventoryFeatureIDs: [featureID],
            northwindAnchorCaseIDs: [],
            requiredCapabilities: requiredCapabilities,
            statement: statement,
            bindings: bindings,
            semanticOracleID: "oracle.c191.expression.\(id)"
        )
    }

    private static func issue286ExpressionCase(
        id: String,
        featureID: String,
        statement: any XLEncodable,
        bindings: [SQLiteCombinatorialDraftBinding],
        requiredCapabilities: [String] = []
    ) -> SQLiteCombinatorialCaseDraft {
        SQLiteCombinatorialCaseDraft(
            id: "c286.v1.expression.\(id)",
            templateID: "expression.\(id)",
            strength: "targeted",
            selections: [.init(dimensionID: "expression-case", valueID: id)],
            inventoryFeatureIDs: [featureID],
            northwindAnchorCaseIDs: [],
            requiredCapabilities: requiredCapabilities,
            statement: statement,
            bindings: bindings,
            semanticOracleID: "oracle.c286.expression.\(id)"
        )
    }

    private static func orderSource(
        schema: XLSchema,
        sourceID: String
    ) -> C191Order.MetaNamedResult {
        switch sourceID {
        case "table-auto":
            return schema.table(C191Order.self)
        case "table-alias":
            return schema.table(C191Order.self, as: "orders_case")
        case "subquery-alias":
            return subquery(alias: "orders_case") { nestedSchema in
                let source = nestedSchema.table(C191Order.self, as: "source_orders")
                return select(source).from(source)
            }
        default:
            preconditionFailure("Unknown source: \(sourceID)")
        }
    }

    private static func completeSelect<Row>(
        select: XLQuerySelectStatement<Row>,
        schema: XLSchema,
        orders: C191Order.MetaNamedResult,
        joinID: String,
        predicate: (any XLExpression<Bool>)?,
        groupingID: String,
        havingID: String,
        ordering: (any XLOrderingTerm)?,
        orderingID: String,
        limitID: String,
        offsetID: String
    ) -> any XLEncodable {
        let table = joined(
            select.from(orders),
            schema: schema,
            orders: orders,
            joinID: joinID
        )

        if let predicate {
            let filtered = table.where(predicate)
            return completePostWhere(
                base: filtered,
                orders: orders,
                groupingID: groupingID,
                havingID: havingID,
                orderingID: orderingID,
                limitID: limitID,
                offsetID: offsetID,
                ordered: {
                    filtered.orderBy(require(ordering, name: "ordering"))
                },
                limited: { filtered.limit(5) },
                grouped: { filtered.groupBy(orders.customerID) }
            )
        }

        return completePostWhere(
            base: table,
            orders: orders,
            groupingID: groupingID,
            havingID: havingID,
            orderingID: orderingID,
            limitID: limitID,
            offsetID: offsetID,
            ordered: {
                table.orderBy(require(ordering, name: "ordering"))
            },
            limited: { table.limit(5) },
            grouped: { table.groupBy(orders.customerID) }
        )
    }

    /// Continues from either the FROM/JOIN stage or the WHERE stage without
    /// erasing the concrete query type used by each public SwiftQL transition.
    /// The closures keep GROUP BY, ORDER BY, and LIMIT attached to that exact
    /// stage; only the fully constructed statement is erased for manifest use.
    private static func completePostWhere<Row>(
        base: any XLEncodable,
        orders: C191Order.MetaNamedResult,
        groupingID: String,
        havingID: String,
        orderingID: String,
        limitID: String,
        offsetID: String,
        ordered: () -> XLQueryOrderByStatement<Row>,
        limited: () -> XLQueryLimitStatement<Row>,
        grouped: () -> XLQueryGroupByStatement<Row>
    ) -> any XLEncodable {
        switch (groupingID, havingID) {
        case ("none", "none"):
            return completeOrderingAndPagination(
                base: base,
                orderingID: orderingID,
                limitID: limitID,
                offsetID: offsetID,
                ordered: ordered,
                limited: limited
            )
        case ("customer-id", "none"):
            let grouped = grouped()
            return completeOrderingAndPagination(
                base: grouped,
                orderingID: orderingID,
                limitID: limitID,
                offsetID: offsetID,
                ordered: {
                    grouped.orderBy(require(ordering(orders: orders, orderingID: orderingID), name: "ordering"))
                },
                limited: { grouped.limit(5) }
            )
        case ("customer-id", "count-greater-than-one"):
            let having = grouped().having(orders.orderID.count() > 1)
            return completeOrderingAndPagination(
                base: having,
                orderingID: orderingID,
                limitID: limitID,
                offsetID: offsetID,
                ordered: {
                    having.orderBy(require(ordering(orders: orders, orderingID: orderingID), name: "ordering"))
                },
                limited: { having.limit(5) }
            )
        case ("none", _):
            preconditionFailure("HAVING requires GROUP BY")
        default:
            preconditionFailure(
                "Unknown GROUP BY/HAVING selection: \(groupingID)/\(havingID)"
            )
        }
    }

    /// Applies every legal ORDER BY/LIMIT/OFFSET tail through public staging.
    /// OFFSET is constructible only from the concrete LIMIT statement type.
    private static func completeOrderingAndPagination<Row>(
        base: any XLEncodable,
        orderingID: String,
        limitID: String,
        offsetID: String,
        ordered: () -> XLQueryOrderByStatement<Row>,
        limited: () -> XLQueryLimitStatement<Row>
    ) -> any XLEncodable {
        switch (orderingID, limitID, offsetID) {
        case ("none", "none", "none"):
            return base
        case ("none", "five", "none"):
            return limited()
        case ("none", "five", "two"):
            return limited().offset(2)
        case ("none", "none", _):
            preconditionFailure("OFFSET requires LIMIT")
        case (_, "none", "none"):
            return ordered()
        case (_, "five", "none"):
            return ordered().limit(5)
        case (_, "five", "two"):
            return ordered().limit(5).offset(2)
        case (_, "none", _):
            preconditionFailure("OFFSET requires LIMIT")
        default:
            preconditionFailure(
                "Unknown ORDER BY/LIMIT/OFFSET selection: \(orderingID)/\(limitID)/\(offsetID)"
            )
        }
    }

    private static func joined<Row>(
        _ table: XLQueryTableStatement<Row>,
        schema: XLSchema,
        orders: C191Order.MetaNamedResult,
        joinID: String
    ) -> XLQueryTableStatement<Row> {
        switch joinID {
        case "none":
            return table
        case "inner":
            let customers = schema.table(C191Customer.self, as: "customers_join")
            return table.innerJoin(
                customers,
                on: orders.customerID == customers.customerID
            )
        case "left":
            let employees = schema.nullableTable(C191Employee.self, as: "employees_join")
            return table.leftJoin(
                employees,
                on: orders.employeeID == employees.employeeID
            )
        case "cross":
            let customers = schema.table(C191Customer.self, as: "customers_cross")
            return table.crossJoin(customers)
        default:
            preconditionFailure("Unknown join: \(joinID)")
        }
    }

    private static func predicate(
        orders: C191Order.MetaNamedResult,
        predicateID: String
    ) -> ((any XLExpression<Bool>)?, [SQLiteCombinatorialDraftBinding]) {
        switch predicateID {
        case "none":
            return (nil, [])
        case "literal":
            return (orders.orderID == 10_248, [])
        case "named-binding":
            let value = XLNamedBindingReference<Int>(name: "minimum_order_id")
            return (
                orders.orderID >= value,
                [.init(key: .named("minimum_order_id"), value: .integer(10_248))]
            )
        case "repeated-binding":
            let value = XLNamedBindingReference<Int>(name: "repeated_employee_id")
            return (
                (orders.employeeID >= value) && (orders.employeeID <= value),
                [.init(key: .named("repeated_employee_id"), value: .integer(5))]
            )
        case "empty-in":
            let values: [any XLExpression<Int>] = []
            return (orders.orderID.in(values), [])
        case "in-list":
            return (orders.orderID.in([10_248, 10_249, 10_250]), [])
        case "injection-binding":
            let value = XLNamedBindingReference<String>(name: "customer_input")
            return (
                orders.customerID == value,
                [
                    .init(
                        key: .named("customer_input"),
                        value: .text("VINET' OR 1=1 --")
                    ),
                ]
            )
        case "null-comparison":
            return (orders.shipRegion.isNull(), [])
        case "precedence":
            return (
                ((orders.orderID > 10_248) && (orders.employeeID == 1)) ||
                    (orders.customerID == "VINET"),
                []
            )
        default:
            preconditionFailure("Unknown predicate: \(predicateID)")
        }
    }

    private static func ordering(
        orders: C191Order.MetaNamedResult,
        orderingID: String
    ) -> (any XLOrderingTerm)? {
        switch orderingID {
        case "none":
            return nil
        case "ascending":
            return orders.orderID.ascending()
        case "descending":
            return orders.orderID.descending()
        case "collated":
            return orders.customerID.collate(.nocase).ascending()
        default:
            preconditionFailure("Unknown ordering: \(orderingID)")
        }
    }

    private static func cteCompoundStatement(
        shape: String,
        operation: String
    ) -> any XLEncodable {
        switch shape {
        case "ordinary-required":
            return ordinaryRequiredCTE(operation: operation)
        case "ordinary-nullable":
            return ordinaryNullableCTE(operation: operation)
        case "recursive-required":
            return recursiveRequiredCTE(operation: operation)
        default:
            preconditionFailure("Unknown CTE shape: \(shape)")
        }
    }

    private static func ordinaryRequiredCTE(operation: String) -> any XLEncodable {
        switch operation {
        case "union":
            return sql { schema in
                let seed = schema.commonTableExpression(alias: "required_seed") { _ in
                    Select(C191IntegerRow.columns(value: 1))
                }
                let row = schema.table(seed, as: "required_rows")
                With(seed)
                Select(row)
                From(row)
                Union()
                Select(C191IntegerRow.columns(value: 2))
            }
        case "union-all":
            return sql { schema in
                let seed = schema.commonTableExpression(alias: "required_seed") { _ in
                    Select(C191IntegerRow.columns(value: 1))
                }
                let row = schema.table(seed, as: "required_rows")
                With(seed)
                Select(row)
                From(row)
                UnionAll()
                Select(C191IntegerRow.columns(value: 2))
            }
        case "intersect":
            return sql { schema in
                let seed = schema.commonTableExpression(alias: "required_seed") { _ in
                    Select(C191IntegerRow.columns(value: 1))
                }
                let row = schema.table(seed, as: "required_rows")
                With(seed)
                Select(row)
                From(row)
                Intersect()
                Select(C191IntegerRow.columns(value: 1))
            }
        case "except":
            return sql { schema in
                let seed = schema.commonTableExpression(alias: "required_seed") { _ in
                    Select(C191IntegerRow.columns(value: 1))
                }
                let row = schema.table(seed, as: "required_rows")
                With(seed)
                Select(row)
                From(row)
                Except()
                Select(C191IntegerRow.columns(value: 2))
            }
        default:
            preconditionFailure("Unknown compound operator: \(operation)")
        }
    }

    private static func ordinaryNullableCTE(operation: String) -> any XLEncodable {
        switch operation {
        case "union":
            return sql { schema in
                let seed = schema.commonTableExpression(alias: "nullable_seed") { _ in
                    Select(C191NullableIntegerRow.columns(value: Optional(1)))
                }
                let row = schema.table(seed, as: "nullable_rows")
                With(seed)
                Select(row)
                From(row)
                Union()
                Select(C191NullableIntegerRow.columns(value: Optional<Int>.none))
            }
        case "union-all":
            return sql { schema in
                let seed = schema.commonTableExpression(alias: "nullable_seed") { _ in
                    Select(C191NullableIntegerRow.columns(value: Optional(1)))
                }
                let row = schema.table(seed, as: "nullable_rows")
                With(seed)
                Select(row)
                From(row)
                UnionAll()
                Select(C191NullableIntegerRow.columns(value: Optional<Int>.none))
            }
        case "intersect":
            return sql { schema in
                let seed = schema.commonTableExpression(alias: "nullable_seed") { _ in
                    Select(C191NullableIntegerRow.columns(value: Optional(1)))
                }
                let row = schema.table(seed, as: "nullable_rows")
                With(seed)
                Select(row)
                From(row)
                Intersect()
                Select(C191NullableIntegerRow.columns(value: Optional(1)))
            }
        case "except":
            return sql { schema in
                let seed = schema.commonTableExpression(alias: "nullable_seed") { _ in
                    Select(C191NullableIntegerRow.columns(value: Optional(1)))
                }
                let row = schema.table(seed, as: "nullable_rows")
                With(seed)
                Select(row)
                From(row)
                Except()
                Select(C191NullableIntegerRow.columns(value: Optional<Int>.none))
            }
        default:
            preconditionFailure("Unknown compound operator: \(operation)")
        }
    }

    private static func recursiveRequiredCTE(operation: String) -> any XLEncodable {
        switch operation {
        case "union":
            return sql { schema in
                let sequence = integerSequence(in: schema)
                let row = schema.table(sequence, as: "recursive_rows")
                With(sequence)
                Select(row)
                From(row)
                Union()
                Select(C191IntegerRow.columns(value: 2))
            }
        case "union-all":
            return sql { schema in
                let sequence = integerSequence(in: schema)
                let row = schema.table(sequence, as: "recursive_rows")
                With(sequence)
                Select(row)
                From(row)
                UnionAll()
                Select(C191IntegerRow.columns(value: 2))
            }
        case "intersect":
            return sql { schema in
                let sequence = integerSequence(in: schema)
                let row = schema.table(sequence, as: "recursive_rows")
                With(sequence)
                Select(row)
                From(row)
                Intersect()
                Select(C191IntegerRow.columns(value: 2))
            }
        case "except":
            return sql { schema in
                let sequence = integerSequence(in: schema)
                let row = schema.table(sequence, as: "recursive_rows")
                With(sequence)
                Select(row)
                From(row)
                Except()
                Select(C191IntegerRow.columns(value: 2))
            }
        default:
            preconditionFailure("Unknown compound operator: \(operation)")
        }
    }

    private static func integerSequence(
        in schema: XLSchema
    ) -> C191IntegerRow.MetaCommonTable {
        schema.recursiveCommonTableExpression(
            C191IntegerRow.self,
            alias: "integer_sequence"
        ) { _, sequence in
            Select(C191IntegerRow.columns(value: 1))
            UnionAll()
            Select(C191IntegerRow.columns(value: sequence.value + 1))
            From(sequence)
            Where(sequence.value < 3)
        }
    }

    private static func stableSelectCaseID(assignment: [String: String]) -> String {
        let defaults = [
            "projection": "order-id",
            "source": "table-auto",
            "join": "none",
            "predicate": "none",
            "grouping": "none",
            "having": "none",
            "ordering": "none",
            "limit": "none",
            "offset": "none",
        ]
        let dimensionTags = [
            "projection": "p",
            "source": "s",
            "join": "j",
            "predicate": "w",
            "grouping": "g",
            "having": "h",
            "ordering": "o",
            "limit": "l",
            "offset": "x",
        ]
        var components = ["c191", "v1", "select"]
        for dimension in dimensionOrder {
            let value = assignment[dimension]!
            if defaults[dimension] != value {
                components.append("\(dimensionTags[dimension]!)-\(value)")
            }
        }
        if components.count == 3 {
            components.append("base")
        }
        let identifier = components.joined(separator: ".")
        precondition(identifier.count <= 180, "Generated case ID exceeds 180 characters")
        return identifier
    }

    private static func selectTemplateID(
        assignment: [String: String]
    ) -> String {
        var clauses = ["select"]
        if assignment["predicate"] != "none" {
            clauses.append("where")
        }
        if assignment["grouping"] != "none" {
            clauses.append("group-by")
        }
        if assignment["having"] != "none" {
            clauses.append("having")
        }
        if assignment["ordering"] != "none" {
            clauses.append("order-by")
        }
        if assignment["limit"] != "none" {
            clauses.append("limit")
        }
        if assignment["offset"] != "none" {
            clauses.append("offset")
        }
        if clauses.count == 1 {
            clauses.append("base")
        }
        return clauses.joined(separator: ".")
    }

    private static func selectFeatureIDs(
        assignment: [String: String],
        bindings: [SQLiteCombinatorialDraftBinding]
    ) -> [String] {
        var features: Set<String> = ["syntax.select.core"]
        if assignment["source"] == "subquery-alias" {
            features.insert("syntax.subquery.table-and-in-prepare-gap")
        }
        if assignment["join"] != "none" {
            features.insert("syntax.join.current-inner-left-cross")
        }
        if assignment["grouping"] != "none" ||
            assignment["having"] != "none" ||
            assignment["projection"] == "aggregate-count" {
            features.insert("syntax.expression.aggregate-functions")
        }
        if assignment["ordering"] != "none" {
            features.insert("syntax.select.ordering-terms")
        }
        if assignment["predicate"] != "none" {
            features.insert("syntax.expression.current-operators")
        }
        if !bindings.isEmpty {
            features.insert("binding.named")
        }
        if assignment["predicate"] == "repeated-binding" {
            features.insert("binding.repeated-named")
        }
        return features.sorted()
    }

    private static func northwindAnchorIDs(
        assignment: [String: String]
    ) -> [String] {
        var anchors: Set<String> = []
        if assignment["projection"] == "nullable-region" ||
            assignment["predicate"] == "null-comparison" {
            anchors.insert("northwind.select.nullable-shipping")
        }
        if assignment["join"] == "left" {
            anchors.insert("northwind.join.left-null-manager")
        }
        if assignment["join"] == "inner" {
            anchors.insert("northwind.join.customer-order-employee-product")
        }
        if assignment["projection"] == "aggregate-count" ||
            assignment["grouping"] != "none" ||
            assignment["having"] != "none" {
            anchors.insert("northwind.aggregate.grouped-having")
        }
        if assignment["limit"] != "none" && assignment["offset"] != "none" {
            anchors.insert("northwind.select.deterministic-pagination")
        }
        return anchors.sorted()
    }

    private static func semanticOracleID(
        assignment: [String: String]
    ) -> String? {
        if assignment == requiredHigherOrderAssignments[0] {
            return "oracle.c191.left-null-grouped-pagination"
        }
        if assignment == requiredHigherOrderAssignments[1] {
            return "oracle.c191.repeated-binding-aggregate"
        }
        if assignment == requiredHigherOrderAssignments[2] {
            return "oracle.c191.injection-binding"
        }
        return nil
    }

    private static func require<T>(_ value: T?, name: String) -> T {
        guard let value else {
            preconditionFailure("Template requires \(name)")
        }
        return value
    }
}
