//
//  V2NameCollisionFixture.swift
//  SwiftQL
//
//  Compile-only fixture for issue #702. A client file that imports SwiftQL
//  beside GRDB, Foundation, and SwiftUI, and the Apple frameworks an app
//  commonly imports with them (Combine, Observation, os, and SwiftData),
//  names every proposed v2 type, and every public type SwiftQL already spells
//  without a prefix, unqualified.
//  Swift rejects a type name two imported modules declare as ambiguous, so a
//  proposed name that collides stops the package building.
//
//  The proposed names live in `SwiftQLV2Names`, a module of their own, so the
//  lookup here is a cross-module lookup, as it will be once #33 renames the
//  types themselves. Foundation and GRDB are imported on every platform, and
//  the Apple frameworks where they exist.
//
//  A type the Swift standard library declares is shadowed rather than
//  ambiguous, so this file cannot catch it; `SwiftQLV2NameInventoryTests`
//  does.
//

import Foundation
import GRDB
import SwiftQL
import SwiftQLV2Names
#if canImport(SwiftUI)
import SwiftUI
#endif
#if canImport(Combine)
import Combine
#endif
#if canImport(Observation)
import Observation
#endif
#if canImport(os)
import os
#endif
#if canImport(SwiftData)
import SwiftData
#endif


/// Each member names one type unqualified. A member is spelled `Check_` and
/// the type's name: no public type name has an underscore, so a member can
/// never shadow a type another member names.
enum V2NameCollisionFixture {

    // MARK: - Proposed v2 names for today's `XL` types

    typealias Check_AnyStaticSelectField = AnyStaticSelectField
    typealias Check_AsyncRequest = AsyncRequest
    typealias Check_AsyncStreamPublisher = AsyncStreamPublisher
    typealias Check_AsyncWriteRequest = AsyncWriteRequest
    typealias Check_BetweenExpression = BetweenExpression
    typealias Check_BinaryOperatorExpression = BinaryOperatorExpression
    typealias Check_BindingContext = BindingContext
    typealias Check_BindingKey = BindingKey
    typealias Check_BindingPlaceholder = BindingPlaceholder
    typealias Check_BindingReference = BindingReference
    typealias Check_BlockingDatabaseDriver = BlockingDatabaseDriver
    typealias Check_Boolean = Boolean
    typealias Check_Builder = Builder
    typealias Check_Collation = Collation
    typealias Check_CollationName = CollationName
    typealias Check_ColumnDefinitionsBuilder = ColumnDefinitionsBuilder
    typealias Check_ColumnDependency = ColumnDependency
    typealias Check_ColumnReadError = ColumnReadError
    typealias Check_ColumnReader = ColumnReader
    typealias Check_ColumnReference = ColumnReference
    typealias Check_ColumnResult = ColumnResult
    typealias Check_ColumnUpdate = ColumnUpdate
    typealias Check_CommonTableDependency = CommonTableDependency
    typealias Check_CommonTableMaterialization = CommonTableMaterialization
    typealias Check_CommonTablePrefix = CommonTablePrefix
    typealias Check_CommonTablesBuilder = CommonTablesBuilder
    typealias Check_ComparisonExpression = ComparisonExpression
    typealias Check_ComparisonOperator = ComparisonOperator
    typealias Check_ConcatenationExpression = ConcatenationExpression
    typealias Check_ConditionalFunction = ConditionalFunction
    typealias Check_ConflictResolution = ConflictResolution
    typealias Check_ContextualBindingReference = ContextualBindingReference
    typealias Check_CreateExpressionBuilder = CreateExpressionBuilder
    typealias Check_CreateStatement = CreateStatement
    typealias Check_CreateTableAsStatement = CreateTableAsStatement
    typealias Check_CreateTableStatement = CreateTableStatement
    typealias Check_CreateTableStatementComponents = CreateTableStatementComponents
    typealias Check_CustomFunction = CustomFunction
    typealias Check_CustomFunctionDefinition = CustomFunctionDefinition
    typealias Check_CustomFunctionEvaluator = CustomFunctionEvaluator
    typealias Check_CustomFunctionRegistration = CustomFunctionRegistration
    typealias Check_CustomFunctionResultError = CustomFunctionResultError
    typealias Check_CustomType = CustomType
    typealias Check_DatabaseContractError = DatabaseContractError
    typealias Check_DatabaseDriver = DatabaseDriver
    typealias Check_DatabaseDriverConnection = DatabaseDriverConnection
    typealias Check_DatabaseErrorCode = DatabaseErrorCode
    typealias Check_DatabaseIdentifier = DatabaseIdentifier
    typealias Check_DateFunctionModifiers = DateFunctionModifiers
    typealias Check_DateModifier = DateModifier
    typealias Check_DateModifierTerm = DateModifierTerm
    typealias Check_DateTextCodec = DateTextCodec
    typealias Check_DateTextCodecError = DateTextCodecError
    typealias Check_DateTextFormat = DateTextFormat
    typealias Check_DateUnit = DateUnit
    typealias Check_DeclaredQuery = DeclaredQuery
    typealias Check_DeclaredQueryError = DeclaredQueryError
    typealias Check_DeclaredQueryParameter = DeclaredQueryParameter
    typealias Check_DeleteExpressionBuilder = DeleteExpressionBuilder
    typealias Check_DeleteReturningStatement = DeleteReturningStatement
    typealias Check_DeleteStatement = DeleteStatement
    typealias Check_DeleteStatementComponents = DeleteStatementComponents
    typealias Check_DeleteTableStatement = DeleteTableStatement
    typealias Check_DeleteWhereStatement = DeleteWhereStatement
    typealias Check_DialectCapabilities = DialectCapabilities
    typealias Check_DialectDescriptor = DialectDescriptor
    typealias Check_DialectEncoder = DialectEncoder
    typealias Check_DialectIdentifier = DialectIdentifier
    typealias Check_DialectRequirement = DialectRequirement
    typealias Check_DialectValue = DialectValue
    typealias Check_DialectVersion = DialectVersion
    typealias Check_DriverDatabase = DriverDatabase
    typealias Check_DriverIdentifier = DriverIdentifier
    typealias Check_DriverScopeRefusal = DriverScopeRefusal
    typealias Check_Encoding = Encoding
    typealias Check_Enum = Enum
    typealias Check_ExcludedTableDependency = ExcludedTableDependency
    typealias Check_ExecutionResult = ExecutionResult
    typealias Check_FieldReader = FieldReader
    typealias Check_FromSubqueryDependency = FromSubqueryDependency
    typealias Check_FromTableDependency = FromTableDependency
    typealias Check_Function = Function
    typealias Check_IfExpression = IfExpression
    typealias Check_InTableExpression = InTableExpression
    typealias Check_InValueExpression = InValueExpression
    typealias Check_InsertExpressionBuilder = InsertExpressionBuilder
    typealias Check_InsertOnConflictStatement = InsertOnConflictStatement
    typealias Check_InsertOrAction = InsertOrAction
    typealias Check_InsertReturningStatement = InsertReturningStatement
    typealias Check_InsertSelectGroupByStatement = InsertSelectGroupByStatement
    typealias Check_InsertSelectHavingStatement = InsertSelectHavingStatement
    typealias Check_InsertSelectLimitStatement = InsertSelectLimitStatement
    typealias Check_InsertSelectOffsetStatement = InsertSelectOffsetStatement
    typealias Check_InsertSelectOrderByStatement = InsertSelectOrderByStatement
    typealias Check_InsertSelectStatement = InsertSelectStatement
    typealias Check_InsertSelectTableStatement = InsertSelectTableStatement
    typealias Check_InsertSelectWhereStatement = InsertSelectWhereStatement
    typealias Check_InsertStatement = InsertStatement
    typealias Check_InsertStatementComponents = InsertStatementComponents
    typealias Check_InsertTableStatement = InsertTableStatement
    typealias Check_InsertTableValuesStatement = InsertTableValuesStatement
    typealias Check_InsertTarget = InsertTarget
    typealias Check_InvocationBinding = InvocationBinding
    typealias Check_InvocationBindingError = InvocationBindingError
    typealias Check_InvocationBindingPacket = InvocationBindingPacket
    typealias Check_InvocationBindings = InvocationBindings
    typealias Check_JSONCodecConfiguration = JSONCodecConfiguration
    typealias Check_JSONPath = JSONPath
    typealias Check_JSONValidationFlags = JSONValidationFlags
    typealias Check_JSONValueCodec = JSONValueCodec
    typealias Check_JSONValueCodecError = JSONValueCodecError
    typealias Check_LegacyDynamicValueExpression = LegacyDynamicValueExpression
    typealias Check_LikeEscapeExpression = LikeEscapeExpression
    typealias Check_ListBuilder = ListBuilder
    typealias Check_Literal = Literal
    typealias Check_LiteralValueDialect = LiteralValueDialect
    typealias Check_LogLevel = LogLevel
    typealias Check_LogicalParameterIndex = LogicalParameterIndex
    typealias Check_LogicalPreparedStatement = LogicalPreparedStatement
    typealias Check_LogicalResultIndex = LogicalResultIndex
    typealias Check_LoweredDeclaredQuery = LoweredDeclaredQuery
    typealias Check_MetaCommonTable = MetaCommonTable
    typealias Check_MetaCreate = MetaCreate
    typealias Check_MetaInsert = MetaInsert
    typealias Check_MetaNamedResult = MetaNamedResult
    typealias Check_MetaNullable = MetaNullable
    typealias Check_MetaNullableNamedResult = MetaNullableNamedResult
    typealias Check_MetaNullableResult = MetaNullableResult
    typealias Check_MetaResult = MetaResult
    typealias Check_MetaUpdate = MetaUpdate
    typealias Check_MetaWritableTable = MetaWritableTable
    typealias Check_Name = Name
    typealias Check_NamedBindingReference = NamedBindingReference
    typealias Check_NamedDependency = NamedDependency
    typealias Check_NamedTableDeclaration = NamedTableDeclaration
    typealias Check_NonFiniteRealValue = NonFiniteRealValue
    typealias Check_NullCoalesceExpression = NullCoalesceExpression
    typealias Check_NullExpression = NullExpression
    typealias Check_NullTest = NullTest
    typealias Check_NullTestExpression = NullTestExpression
    typealias Check_NullableColumnUpdate = NullableColumnUpdate
    #if canImport(Observation) && canImport(Darwin)
    @available(iOS 17, macOS 14, *)
    typealias Check_ObservableQuery = ObservableQuery
    #endif
    #if canImport(Observation) && canImport(Darwin)
    @available(iOS 17, macOS 14, *)
    typealias Check_ObservableQueryRow = ObservableQueryRow
    #endif
    typealias Check_ObservingDatabaseDriver = ObservingDatabaseDriver
    typealias Check_OrderingTerm = OrderingTerm
    typealias Check_OrderingTermsBuilder = OrderingTermsBuilder
    typealias Check_ParameterDeclaration = ParameterDeclaration
    typealias Check_ParameterLayout = ParameterLayout
    typealias Check_ParameterNullability = ParameterNullability
    typealias Check_ParameterOccurrence = ParameterOccurrence
    typealias Check_ParameterPlaceholderAssignment = ParameterPlaceholderAssignment
    typealias Check_ParameterSlot = ParameterSlot
    typealias Check_PlaceholderAssigner = PlaceholderAssigner
    typealias Check_PositionalPlaceholderAssigner = PositionalPlaceholderAssigner
    typealias Check_PostfixOperatorExpression = PostfixOperatorExpression
    typealias Check_PrefixOperatorExpression = PrefixOperatorExpression
    typealias Check_PreparedInvocation = PreparedInvocation
    typealias Check_PreparedParameter = PreparedParameter
    typealias Check_PreparedQuery = PreparedQuery
    typealias Check_PreparedQueryCacheKey = PreparedQueryCacheKey
    typealias Check_PreparedStaticQuery = PreparedStaticQuery
    typealias Check_PreparedTypedStaticQuery = PreparedTypedStaticQuery
    typealias Check_PublisherAsyncBridge = PublisherAsyncBridge
    typealias Check_QualifiedName = QualifiedName
    typealias Check_QualifiedSelectColumnName = QualifiedSelectColumnName
    typealias Check_QualifiedTableAliasColumnName = QualifiedTableAliasColumnName
    typealias Check_QualifiedTableName = QualifiedTableName
    typealias Check_QueryCapture = QueryCapture
    typealias Check_QueryCaptureError = QueryCaptureError
    typealias Check_QueryCardinality = QueryCardinality
    typealias Check_QueryCardinalityError = QueryCardinalityError
    typealias Check_QueryCodecSelection = QueryCodecSelection
    typealias Check_QueryCodecSelectionError = QueryCodecSelectionError
    typealias Check_QueryComponent = QueryComponent
    typealias Check_QueryDefinitionIdentity = QueryDefinitionIdentity
    typealias Check_QueryExpressionBuilder = QueryExpressionBuilder
    typealias Check_QueryGroupByStatement = QueryGroupByStatement
    typealias Check_QueryHavingStatement = QueryHavingStatement
    typealias Check_QueryIdentity = QueryIdentity
    typealias Check_QueryIdentityFormatVersion = QueryIdentityFormatVersion
    typealias Check_QueryLimitStatement = QueryLimitStatement
    typealias Check_QueryObserver = QueryObserver
    typealias Check_QueryOffsetStatement = QueryOffsetStatement
    typealias Check_QueryOrderByStatement = QueryOrderByStatement
    typealias Check_QueryPartialUnion = QueryPartialUnion
    typealias Check_QueryRowObserver = QueryRowObserver
    typealias Check_QuerySelectStatement = QuerySelectStatement
    typealias Check_QuerySlotIdentity = QuerySlotIdentity
    typealias Check_QueryStatement = QueryStatement
    typealias Check_QueryStatementComponents = QueryStatementComponents
    typealias Check_QueryTableStatement = QueryTableStatement
    typealias Check_QueryUnionStatement = QueryUnionStatement
    typealias Check_QueryWhereStatement = QueryWhereStatement
    typealias Check_RecursiveCommonTableConstructionError = RecursiveCommonTableConstructionError
    typealias Check_RecursiveCommonTableDraft = RecursiveCommonTableDraft
    typealias Check_RecursiveCommonTableReferenceLayout = RecursiveCommonTableReferenceLayout
    typealias Check_RegexMatchOperator = RegexMatchOperator
    typealias Check_RegexPattern = RegexPattern
    typealias Check_RegexPatternRegistry = RegexPatternRegistry
    typealias Check_RegexpFunction = RegexpFunction
    typealias Check_RegexpFunctionError = RegexpFunctionError
    typealias Check_RegexpLengthLimitError = RegexpLengthLimitError
    typealias Check_RegexpMatcher = RegexpMatcher
    typealias Check_RegexpPatternCache = RegexpPatternCache
    typealias Check_RenderOnceCache = RenderOnceCache
    typealias Check_Request = Request
    typealias Check_RequestBindingError = RequestBindingError
    typealias Check_RequestBuilder = RequestBuilder
    typealias Check_ResolvedValueCodec = ResolvedValueCodec
    typealias Check_ResultSet = ResultSet
    typealias Check_ResultSetError = ResultSetError
    typealias Check_ReturningRequestError = ReturningRequestError
    typealias Check_ReturningStatement = ReturningStatement
    typealias Check_RowReadable = RowReadable
    typealias Check_RowReader = RowReader
    typealias Check_RowStreamControl = RowStreamControl
    typealias Check_RowWritable = RowWritable
    typealias Check_SQLDialect = SQLDialect
    typealias Check_SQLValueEncodingError = SQLValueEncodingError
    typealias Check_SQLVocabulary = SQLVocabulary
    typealias Check_SQLiteDialect = SQLiteDialect
    typealias Check_SQLiteIdentifierFormattingOptions = SQLiteIdentifierFormattingOptions
    typealias Check_SQLiteNumericDateCodec = SQLiteNumericDateCodec
    typealias Check_SQLiteNumericDateCodecError = SQLiteNumericDateCodecError
    typealias Check_SQLiteStorageClass = SQLiteStorageClass
    typealias Check_SQLiteValue = SQLiteValue
    typealias Check_SQLiteValueReader = SQLiteValueReader
    typealias Check_ScalarCommonTable = ScalarCommonTable
    typealias Check_ScalarCommonTableReference = ScalarCommonTableReference
    typealias Check_ScalarExpressionBuilder = ScalarExpressionBuilder
    typealias Check_SchemaName = SchemaName
    typealias Check_SelectResultDependency = SelectResultDependency
    typealias Check_Separator = Separator
    typealias Check_SimpleSelectQueryStatement = SimpleSelectQueryStatement
    typealias Check_StatementAccess = StatementAccess
    typealias Check_StaticColumnReader = StaticColumnReader
    typealias Check_StaticFieldGroup = StaticFieldGroup
    typealias Check_StaticQueryDescriptor = StaticQueryDescriptor
    typealias Check_StaticQueryError = StaticQueryError
    typealias Check_StaticQueryParameterMetadata = StaticQueryParameterMetadata
    typealias Check_StaticQueryResultMetadata = StaticQueryResultMetadata
    typealias Check_StaticQueryResultSlot = StaticQueryResultSlot
    typealias Check_StaticRowField = StaticRowField
    typealias Check_StaticRowFieldSource = StaticRowFieldSource
    typealias Check_StaticRowLayout = StaticRowLayout
    typealias Check_StaticRowLayoutError = StaticRowLayoutError
    typealias Check_StaticRowMetadata = StaticRowMetadata
    typealias Check_StaticRowMetadataError = StaticRowMetadataError
    typealias Check_StaticRowReadError = StaticRowReadError
    typealias Check_StaticRowReadable = StaticRowReadable
    typealias Check_StaticSelectField = StaticSelectField
    typealias Check_StaticSelectFieldProtocol = StaticSelectFieldProtocol
    typealias Check_StaticStatementDefinition = StaticStatementDefinition
    typealias Check_StaticStatementDefinitionError = StaticStatementDefinitionError
    typealias Check_StaticStorageRetypableExpression = StaticStorageRetypableExpression
    typealias Check_SubqueryDependency = SubqueryDependency
    typealias Check_TableDeclaration = TableDeclaration
    typealias Check_TableStatement = TableStatement
    typealias Check_TransactionKind = TransactionKind
    typealias Check_TransactionScopeError = TransactionScopeError
    typealias Check_TransactionalDatabase = TransactionalDatabase
    typealias Check_TypeAffinityExpression = TypeAffinityExpression
    typealias Check_TypeCastExpression = TypeCastExpression
    typealias Check_TypedStaticQueryDescriptor = TypedStaticQueryDescriptor
    typealias Check_UUIDValueCodec = UUIDValueCodec
    typealias Check_UUIDValueCodecError = UUIDValueCodecError
    typealias Check_UnaryOperatorExpression = UnaryOperatorExpression
    typealias Check_UpdateExpressionBuilder = UpdateExpressionBuilder
    typealias Check_UpdateFromStatement = UpdateFromStatement
    typealias Check_UpdateFromTableDependency = UpdateFromTableDependency
    typealias Check_UpdateReturningStatement = UpdateReturningStatement
    typealias Check_UpdateSetStatement = UpdateSetStatement
    typealias Check_UpdateStatement = UpdateStatement
    typealias Check_UpdateStatementComponents = UpdateStatementComponents
    typealias Check_UpdateTableStatement = UpdateTableStatement
    typealias Check_UpdateWhereStatement = UpdateWhereStatement
    typealias Check_V1LiteralCodec = V1LiteralCodec
    typealias Check_ValidatedLogicalPreparedStatement = ValidatedLogicalPreparedStatement
    typealias Check_ValueCodec = ValueCodec
    typealias Check_ValueCodecError = ValueCodecError
    typealias Check_ValueCodecIdentity = ValueCodecIdentity
    typealias Check_ValueCodecKey = ValueCodecKey
    typealias Check_ValueCodecRegistry = ValueCodecRegistry
    typealias Check_ValueCodecSelection = ValueCodecSelection
    typealias Check_ValueCodecSelectionSource = ValueCodecSelectionSource
    typealias Check_ValueCodecTarget = ValueCodecTarget
    typealias Check_ValueCodingConfiguration = ValueCodingConfiguration
    typealias Check_ValueCodingContext = ValueCodingContext
    typealias Check_ValueCodingDialect = ValueCodingDialect
    typealias Check_ValueCodingPath = ValueCodingPath
    typealias Check_ValueCodingSite = ValueCodingSite
    typealias Check_ValueStorageIdentifier = ValueStorageIdentifier
    typealias Check_ValueTypeIdentifier = ValueTypeIdentifier
    typealias Check_WithStatement = WithStatement
    typealias Check_WriteRequest = WriteRequest
    typealias Check_SQLiteBuilder = SQLiteBuilder
    typealias Check_SQLiteColumnDefinitionsBuilder = SQLiteColumnDefinitionsBuilder
    typealias Check_SQLiteCommonTablesBuilder = SQLiteCommonTablesBuilder
    typealias Check_SQLiteEncoder = SQLiteEncoder
    typealias Check_SQLiteFormatter = SQLiteFormatter
    typealias Check_SQLiteListBuilder = SQLiteListBuilder
    typealias Check_SQLitePlaceholderAssigner = SQLitePlaceholderAssigner
    typealias Check_SQLiteVocabulary = SQLiteVocabulary

    // MARK: - Public types SwiftQL already spells without a prefix

    typealias Check_As = As
    typealias Check_Ascending = Ascending
    typealias Check_ConstantCase = ConstantCase
    typealias Check_ConstantCaseWhenThen = ConstantCaseWhenThen
    typealias Check_ConstantCaseWhenThenElse = ConstantCaseWhenThenElse
    typealias Check_Create = Create
    typealias Check_Delete = Delete
    typealias Check_Descending = Descending
    typealias Check_Except = Except
    typealias Check_From = From
    typealias Check_GRDBDatabase = GRDBDatabase
    typealias Check_GRDBDatabaseBuilder = GRDBDatabaseBuilder
    typealias Check_GRDBDatabaseConfiguration = GRDBDatabaseConfiguration
    typealias Check_GRDBLiveQueryRetryPolicy = GRDBLiveQueryRetryPolicy
    typealias Check_GRDBPreparedInvocation = GRDBPreparedInvocation
    typealias Check_GRDBPreparedStaticQuery = GRDBPreparedStaticQuery
    typealias Check_GRDBPreparedTypedStaticQuery = GRDBPreparedTypedStaticQuery
    typealias Check_GRDBStaticQueryArgument = GRDBStaticQueryArgument
    typealias Check_GRDBStaticQueryError = GRDBStaticQueryError
    typealias Check_GRDBStaticQueryInvocationBuilder = GRDBStaticQueryInvocationBuilder
    typealias Check_GroupBy = GroupBy
    typealias Check_Having = Having
    typealias Check_Insert = Insert
    typealias Check_InsertBuilder = InsertBuilder
    typealias Check_Intersect = Intersect
    typealias Check_Join = Join
    typealias Check_Limit = Limit
    typealias Check_Offset = Offset
    typealias Check_OnConflict = OnConflict
    typealias Check_OrderBy = OrderBy
    typealias Check_QueryBuilder = QueryBuilder
    typealias Check_Replace = Replace
    typealias Check_Returning = Returning
    typealias Check_SQLRow2 = SQLRow2
    typealias Check_SQLRow3 = SQLRow3
    typealias Check_SQLRow4 = SQLRow4
    typealias Check_SQLRow5 = SQLRow5
    typealias Check_SQLRow6 = SQLRow6
    typealias Check_SQLScalarResult = SQLScalarResult
    typealias Check_Select = Select
    typealias Check_Setting = Setting
    typealias Check_Union = Union
    typealias Check_UnionAll = UnionAll
    typealias Check_Update = Update
    typealias Check_Values = Values
    typealias Check_VariableCaseElse = VariableCaseElse
    typealias Check_VariableCaseWhenThen = VariableCaseWhenThen
    typealias Check_Where = Where
    typealias Check_With = With
}
