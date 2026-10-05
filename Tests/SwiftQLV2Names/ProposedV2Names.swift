//
//  ProposedV2Names.swift
//  SwiftQL
//
//  The proposed v2 spelling of every public `XL` type (issues #702 and #33).
//
//  One typealias per type, from the name #33 is expected to give it to the
//  type it names today. The rule is mechanical: drop `XL`, and spell the
//  `XLite` family `SQLite`. `SwiftQLV2NameCollisionFixture` imports this
//  module beside SwiftQL, GRDB, Foundation, and SwiftUI, and the Apple
//  frameworks an app commonly imports with them (Combine, Observation, os,
//  and SwiftData), and names every alias unqualified, so a proposed name that
//  another of those modules declares stops the test build.
//  `SwiftQLV2NameInventoryTests` keeps the list complete: every public `XL`
//  type in SwiftQL and SwiftQLCore has exactly one line here, as an alias or
//  below.
//
//  Unresolved collisions. These names collide with a type another of those
//  modules declares, so they have no alias yet. #33 chooses their v2 names;
//  give each one its alias when it does. The format is read by
//  `SwiftQLV2NameInventoryTests`.
//
//  A name the Swift standard library declares is not ambiguous: a type from
//  any other module shadows the standard library's, so the fixture would
//  build and every client would silently get SwiftQL's `Result` or
//  `Equatable`. Those are marked "shadowed", and
//  `SwiftQLV2NameInventoryTests` checks every alias against the standard
//  library with the compiler, because the fixture cannot.
//
//  unresolved: XLAllColumns -> AllColumns (GRDB)
//  unresolved: XLBindable -> Bindable (SwiftUI)
//  unresolved: XLComparable -> Comparable (Swift, shadowed)
//  unresolved: XLDatabase -> Database (GRDB)
//  unresolved: XLDatabaseError -> DatabaseError (GRDB)
//  unresolved: XLEncodable -> Encodable (Swift, shadowed)
//  unresolved: XLEncoder -> Encoder (Swift, shadowed)
//  unresolved: XLEquatable -> Equatable (Swift, shadowed)
//  unresolved: XLExpression -> Expression (Foundation)
//  unresolved: XLFormatter -> Formatter (Foundation)
//  unresolved: XLLogger -> Logger (os)
//  unresolved: XLNamespace -> Namespace (SwiftUI)
//  unresolved: XLResult -> Result (Swift, shadowed)
//  unresolved: XLSchema -> Schema (SwiftData)
//  unresolved: XLTable -> Table (GRDB and SwiftUI)
//
//  Deprecated types are not carried into v2, so they have no alias either,
//  and the fixture does not name them.
//
//  deprecated: JoinKind (use Join.Kind)
//  deprecated: XLFromCommonTableDependency (use XLFromTableDependency)
//

import SwiftQL

public typealias AnyStaticSelectField = SwiftQL.XLAnyStaticSelectField
public typealias AsyncRequest = SwiftQL.XLAsyncRequest
public typealias AsyncStreamPublisher = SwiftQL.XLAsyncStreamPublisher
public typealias AsyncWriteRequest = SwiftQL.XLAsyncWriteRequest
public typealias BetweenExpression = SwiftQL.XLBetweenExpression
public typealias BinaryOperatorExpression = SwiftQL.XLBinaryOperatorExpression
public typealias BindingContext = SwiftQL.XLBindingContext
public typealias BindingKey = SwiftQLCore.XLBindingKey
public typealias BindingPlaceholder = SwiftQLCore.XLBindingPlaceholder
public typealias BindingReference = SwiftQL.XLBindingReference
public typealias BlockingDatabaseDriver = SwiftQLCore.XLBlockingDatabaseDriver
public typealias Boolean = SwiftQL.XLBoolean
public typealias Builder = SwiftQL.XLBuilder
public typealias Collation = SwiftQL.XLCollation
public typealias CollationName = SwiftQLCore.XLCollationName
public typealias ColumnDefinitionsBuilder = SwiftQL.XLColumnDefinitionsBuilder
public typealias ColumnDependency = SwiftQL.XLColumnDependency
public typealias ColumnReadError = SwiftQLCore.XLColumnReadError
public typealias ColumnReader = SwiftQL.XLColumnReader
public typealias ColumnReference = SwiftQL.XLColumnReference
public typealias ColumnResult = SwiftQL.XLColumnResult
public typealias ColumnUpdate = SwiftQL.XLColumnUpdate
public typealias CommonTableDependency = SwiftQL.XLCommonTableDependency
public typealias CommonTableMaterialization = SwiftQL.XLCommonTableMaterialization
public typealias CommonTablePrefix = SwiftQLCore.XLCommonTablePrefix
public typealias CommonTablesBuilder = SwiftQL.XLCommonTablesBuilder
public typealias ComparisonExpression = SwiftQL.XLComparisonExpression
public typealias ComparisonOperator = SwiftQLCore.XLComparisonOperator
public typealias ConcatenationExpression = SwiftQL.XLConcatenationExpression
public typealias ConditionalFunction = SwiftQLCore.XLConditionalFunction
public typealias ConflictResolution = SwiftQL.XLConflictResolution
public typealias ContextualBindingReference = SwiftQL.XLContextualBindingReference
public typealias CreateExpressionBuilder = SwiftQL.XLCreateExpressionBuilder
public typealias CreateStatement = SwiftQL.XLCreateStatement
public typealias CreateTableAsStatement = SwiftQL.XLCreateTableAsStatement
public typealias CreateTableStatement = SwiftQL.XLCreateTableStatement
public typealias CreateTableStatementComponents = SwiftQL.XLCreateTableStatementComponents
public typealias CustomFunction = SwiftQL.XLCustomFunction
public typealias CustomFunctionDefinition = SwiftQLCore.XLCustomFunctionDefinition
public typealias CustomFunctionEvaluator = SwiftQLCore.XLCustomFunctionEvaluator
public typealias CustomFunctionRegistration = SwiftQLCore.XLCustomFunctionRegistration
public typealias CustomFunctionResultError = SwiftQLCore.XLCustomFunctionResultError
public typealias CustomType = SwiftQL.XLCustomType
public typealias DatabaseContractError = SwiftQLCore.XLDatabaseContractError
public typealias DatabaseDriver = SwiftQLCore.XLDatabaseDriver
public typealias DatabaseDriverConnection = SwiftQLCore.XLDatabaseDriverConnection
public typealias DatabaseErrorCode = SwiftQLCore.XLDatabaseErrorCode
public typealias DatabaseIdentifier = SwiftQLCore.XLDatabaseIdentifier
public typealias DateFunctionModifiers = SwiftQL.XLDateFunctionModifiers
public typealias DateModifier = SwiftQL.XLDateModifier
public typealias DateModifierTerm = SwiftQLCore.XLDateModifierTerm
public typealias DateTextCodec = SwiftQL.XLDateTextCodec
public typealias DateTextCodecError = SwiftQL.XLDateTextCodecError
public typealias DateTextFormat = SwiftQL.XLDateTextFormat
public typealias DateUnit = SwiftQLCore.XLDateUnit
public typealias DeclaredQuery = SwiftQL.XLDeclaredQuery
public typealias DeclaredQueryError = SwiftQL.XLDeclaredQueryError
public typealias DeclaredQueryParameter = SwiftQL.XLDeclaredQueryParameter
public typealias DeleteExpressionBuilder = SwiftQL.XLDeleteExpressionBuilder
public typealias DeleteReturningStatement = SwiftQL.XLDeleteReturningStatement
public typealias DeleteStatement = SwiftQL.XLDeleteStatement
public typealias DeleteStatementComponents = SwiftQL.XLDeleteStatementComponents
public typealias DeleteTableStatement = SwiftQL.XLDeleteTableStatement
public typealias DeleteWhereStatement = SwiftQL.XLDeleteWhereStatement
public typealias DialectCapabilities = SwiftQLCore.XLDialectCapabilities
public typealias DialectDescriptor = SwiftQLCore.XLDialectDescriptor
public typealias DialectEncoder = SwiftQL.XLDialectEncoder
public typealias DialectIdentifier = SwiftQLCore.XLDialectIdentifier
public typealias DialectRequirement = SwiftQLCore.XLDialectRequirement
public typealias DialectValue = SwiftQLCore.XLDialectValue
public typealias DialectVersion = SwiftQLCore.XLDialectVersion
public typealias DriverDatabase = SwiftQL.XLDriverDatabase
public typealias DriverIdentifier = SwiftQLCore.XLDriverIdentifier
public typealias DriverScopeRefusal = SwiftQLCore.XLDriverScopeRefusal
public typealias Encoding = SwiftQL.XLEncoding
public typealias Enum = SwiftQL.XLEnum
public typealias ExcludedTableDependency = SwiftQL.XLExcludedTableDependency
public typealias ExecutionResult = SwiftQLCore.XLExecutionResult
public typealias FieldReader = SwiftQL.XLFieldReader
public typealias FromSubqueryDependency = SwiftQL.XLFromSubqueryDependency
public typealias FromTableDependency = SwiftQL.XLFromTableDependency
public typealias Function = SwiftQL.XLFunction
public typealias IfExpression = SwiftQL.XLIfExpression
public typealias InTableExpression = SwiftQL.XLInTableExpression
public typealias InValueExpression = SwiftQL.XLInValueExpression
public typealias InsertExpressionBuilder = SwiftQL.XLInsertExpressionBuilder
public typealias InsertOnConflictStatement = SwiftQL.XLInsertOnConflictStatement
public typealias InsertOrAction = SwiftQLCore.XLInsertOrAction
public typealias InsertReturningStatement = SwiftQL.XLInsertReturningStatement
public typealias InsertSelectGroupByStatement = SwiftQL.XLInsertSelectGroupByStatement
public typealias InsertSelectHavingStatement = SwiftQL.XLInsertSelectHavingStatement
public typealias InsertSelectLimitStatement = SwiftQL.XLInsertSelectLimitStatement
public typealias InsertSelectOffsetStatement = SwiftQL.XLInsertSelectOffsetStatement
public typealias InsertSelectOrderByStatement = SwiftQL.XLInsertSelectOrderByStatement
public typealias InsertSelectStatement = SwiftQL.XLInsertSelectStatement
public typealias InsertSelectTableStatement = SwiftQL.XLInsertSelectTableStatement
public typealias InsertSelectWhereStatement = SwiftQL.XLInsertSelectWhereStatement
public typealias InsertStatement = SwiftQL.XLInsertStatement
public typealias InsertStatementComponents = SwiftQL.XLInsertStatementComponents
public typealias InsertTableStatement = SwiftQL.XLInsertTableStatement
public typealias InsertTableValuesStatement = SwiftQL.XLInsertTableValuesStatement
public typealias InsertTarget = SwiftQLCore.XLInsertTarget
public typealias InvocationBinding = SwiftQLCore.XLInvocationBinding
public typealias InvocationBindingError = SwiftQLCore.XLInvocationBindingError
public typealias InvocationBindingPacket = SwiftQLCore.XLInvocationBindingPacket
public typealias InvocationBindings = SwiftQLCore.XLInvocationBindings
public typealias JSONCodecConfiguration = SwiftQL.XLJSONCodecConfiguration
public typealias JSONPath = SwiftQL.XLJSONPath
public typealias JSONValidationFlags = SwiftQL.XLJSONValidationFlags
public typealias JSONValueCodec = SwiftQL.XLJSONValueCodec
public typealias JSONValueCodecError = SwiftQL.XLJSONValueCodecError
public typealias LegacyDynamicValueExpression = SwiftQL.XLLegacyDynamicValueExpression
public typealias LikeEscapeExpression = SwiftQL.XLLikeEscapeExpression
public typealias ListBuilder = SwiftQL.XLListBuilder
public typealias Literal = SwiftQL.XLLiteral
public typealias LiteralValueDialect = SwiftQL.XLLiteralValueDialect
public typealias LogLevel = SwiftQL.XLLogLevel
public typealias LogicalParameterIndex = SwiftQLCore.XLLogicalParameterIndex
public typealias LogicalPreparedStatement = SwiftQLCore.XLLogicalPreparedStatement
public typealias LogicalResultIndex = SwiftQLCore.XLLogicalResultIndex
public typealias LoweredDeclaredQuery = SwiftQL.XLLoweredDeclaredQuery
public typealias MetaCommonTable = SwiftQL.XLMetaCommonTable
public typealias MetaCreate = SwiftQL.XLMetaCreate
public typealias MetaInsert = SwiftQL.XLMetaInsert
public typealias MetaNamedResult = SwiftQL.XLMetaNamedResult
public typealias MetaNullable = SwiftQL.XLMetaNullable
public typealias MetaNullableNamedResult = SwiftQL.XLMetaNullableNamedResult
public typealias MetaNullableResult = SwiftQL.XLMetaNullableResult
public typealias MetaResult = SwiftQL.XLMetaResult
public typealias MetaUpdate = SwiftQL.XLMetaUpdate
public typealias MetaWritableTable = SwiftQL.XLMetaWritableTable
public typealias Name = SwiftQL.XLName
public typealias NamedBindingReference = SwiftQL.XLNamedBindingReference
public typealias NamedDependency = SwiftQL.XLNamedDependency
public typealias NamedTableDeclaration = SwiftQL.XLNamedTableDeclaration
public typealias NonFiniteRealValue = SwiftQL.XLNonFiniteRealValue
public typealias NullCoalesceExpression = SwiftQL.XLNullCoalesceExpression
public typealias NullExpression = SwiftQL.XLNullExpression
public typealias NullTest = SwiftQLCore.XLNullTest
public typealias NullTestExpression = SwiftQL.XLNullTestExpression
public typealias NullableColumnUpdate = SwiftQL.XLNullableColumnUpdate
#if canImport(Observation) && canImport(Darwin)
@available(iOS 17, macOS 14, *)
public typealias ObservableQuery = SwiftQL.XLObservableQuery
#endif
#if canImport(Observation) && canImport(Darwin)
@available(iOS 17, macOS 14, *)
public typealias ObservableQueryRow = SwiftQL.XLObservableQueryRow
#endif
public typealias ObservingDatabaseDriver = SwiftQLCore.XLObservingDatabaseDriver
public typealias OrderingTerm = SwiftQL.XLOrderingTerm
public typealias OrderingTermsBuilder = SwiftQL.XLOrderingTermsBuilder
public typealias ParameterDeclaration = SwiftQLCore.XLParameterDeclaration
public typealias ParameterLayout = SwiftQLCore.XLParameterLayout
public typealias ParameterNullability = SwiftQLCore.XLParameterNullability
public typealias ParameterOccurrence = SwiftQLCore.XLParameterOccurrence
public typealias ParameterPlaceholderAssignment = SwiftQLCore.XLParameterPlaceholderAssignment
public typealias ParameterSlot = SwiftQLCore.XLParameterSlot
public typealias PlaceholderAssigner = SwiftQLCore.XLPlaceholderAssigner
public typealias PositionalPlaceholderAssigner = SwiftQLCore.XLPositionalPlaceholderAssigner
public typealias PostfixOperatorExpression = SwiftQL.XLPostfixOperatorExpression
public typealias PrefixOperatorExpression = SwiftQL.XLPrefixOperatorExpression
public typealias PreparedInvocation = SwiftQL.XLPreparedInvocation
public typealias PreparedParameter = SwiftQLCore.XLPreparedParameter
public typealias PreparedQuery = SwiftQL.XLPreparedQuery
public typealias PreparedQueryCacheKey = SwiftQL.XLPreparedQueryCacheKey
public typealias PreparedStaticQuery = SwiftQL.XLPreparedStaticQuery
public typealias PreparedTypedStaticQuery = SwiftQL.XLPreparedTypedStaticQuery
public typealias PublisherAsyncBridge = SwiftQL.XLPublisherAsyncBridge
public typealias QualifiedName = SwiftQL.XLQualifiedName
public typealias QualifiedSelectColumnName = SwiftQL.XLQualifiedSelectColumnName
public typealias QualifiedTableAliasColumnName = SwiftQL.XLQualifiedTableAliasColumnName
public typealias QualifiedTableName = SwiftQL.XLQualifiedTableName
public typealias QueryCapture = SwiftQL.XLQueryCapture
public typealias QueryCaptureError = SwiftQL.XLQueryCaptureError
public typealias QueryCardinality = SwiftQLCore.XLQueryCardinality
public typealias QueryCardinalityError = SwiftQL.XLQueryCardinalityError
public typealias QueryCodecSelection = SwiftQLCore.XLQueryCodecSelection
public typealias QueryCodecSelectionError = SwiftQLCore.XLQueryCodecSelectionError
public typealias QueryComponent = SwiftQL.XLQueryComponent
public typealias QueryDefinitionIdentity = SwiftQLCore.XLQueryDefinitionIdentity
public typealias QueryExpressionBuilder = SwiftQL.XLQueryExpressionBuilder
public typealias QueryGroupByStatement = SwiftQL.XLQueryGroupByStatement
public typealias QueryHavingStatement = SwiftQL.XLQueryHavingStatement
public typealias QueryIdentity = SwiftQLCore.XLQueryIdentity
public typealias QueryIdentityFormatVersion = SwiftQLCore.XLQueryIdentityFormatVersion
public typealias QueryLimitStatement = SwiftQL.XLQueryLimitStatement
public typealias QueryObserver = SwiftQL.XLQueryObserver
public typealias QueryOffsetStatement = SwiftQL.XLQueryOffsetStatement
public typealias QueryOrderByStatement = SwiftQL.XLQueryOrderByStatement
public typealias QueryPartialUnion = SwiftQL.XLQueryPartialUnion
public typealias QueryRowObserver = SwiftQL.XLQueryRowObserver
public typealias QuerySelectStatement = SwiftQL.XLQuerySelectStatement
public typealias QuerySlotIdentity = SwiftQLCore.XLQuerySlotIdentity
public typealias QueryStatement = SwiftQL.XLQueryStatement
public typealias QueryStatementComponents = SwiftQL.XLQueryStatementComponents
public typealias QueryTableStatement = SwiftQL.XLQueryTableStatement
public typealias QueryUnionStatement = SwiftQL.XLQueryUnionStatement
public typealias QueryWhereStatement = SwiftQL.XLQueryWhereStatement
public typealias RecursiveCommonTableConstructionError = SwiftQL.XLRecursiveCommonTableConstructionError
public typealias RecursiveCommonTableDraft = SwiftQL.XLRecursiveCommonTableDraft
public typealias RecursiveCommonTableReferenceLayout = SwiftQL.XLRecursiveCommonTableReferenceLayout
public typealias RegexMatchOperator = SwiftQLCore.XLRegexMatchOperator
public typealias RegexPattern = SwiftQLCore.XLRegexPattern
public typealias RegexPatternRegistry = SwiftQLCore.XLRegexPatternRegistry
public typealias RegexpFunction = SwiftQLCore.XLRegexpFunction
public typealias RegexpFunctionError = SwiftQLCore.XLRegexpFunctionError
public typealias RegexpLengthLimitError = SwiftQLCore.XLRegexpLengthLimitError
public typealias RegexpMatcher = SwiftQLCore.XLRegexpMatcher
public typealias RegexpPatternCache = SwiftQLCore.XLRegexpPatternCache
public typealias RenderOnceCache = SwiftQL.XLRenderOnceCache
public typealias Request = SwiftQL.XLRequest
public typealias RequestBindingError = SwiftQL.XLRequestBindingError
public typealias RequestBuilder = SwiftQL.XLRequestBuilder
public typealias ResolvedValueCodec = SwiftQLCore.XLResolvedValueCodec
public typealias ResultSet = SwiftQL.XLResultSet
public typealias ResultSetError = SwiftQL.XLResultSetError
public typealias ReturningRequestError = SwiftQL.XLReturningRequestError
public typealias ReturningStatement = SwiftQL.XLReturningStatement
public typealias RowReadable = SwiftQL.XLRowReadable
public typealias RowReader = SwiftQL.XLRowReader
public typealias RowStreamControl = SwiftQLCore.XLRowStreamControl
public typealias RowWritable = SwiftQL.XLRowWritable
public typealias SQLDialect = SwiftQLCore.XLSQLDialect
public typealias SQLValueEncodingError = SwiftQL.XLSQLValueEncodingError
public typealias SQLVocabulary = SwiftQLCore.XLSQLVocabulary
public typealias SQLiteDialect = SwiftQLCore.XLSQLiteDialect
public typealias SQLiteIdentifierFormattingOptions = SwiftQLCore.XLSQLiteIdentifierFormattingOptions
public typealias SQLiteNumericDateCodec = SwiftQL.XLSQLiteNumericDateCodec
public typealias SQLiteNumericDateCodecError = SwiftQL.XLSQLiteNumericDateCodecError
public typealias SQLiteStorageClass = SwiftQLCore.XLSQLiteStorageClass
public typealias SQLiteValue = SwiftQLCore.XLSQLiteValue
public typealias SQLiteValueReader = SwiftQL.XLSQLiteValueReader
public typealias ScalarCommonTable = SwiftQL.XLScalarCommonTable
public typealias ScalarCommonTableReference = SwiftQL.XLScalarCommonTableReference
public typealias ScalarExpressionBuilder = SwiftQL.XLScalarExpressionBuilder
public typealias SchemaName = SwiftQL.XLSchemaName
public typealias SelectResultDependency = SwiftQL.XLSelectResultDependency
public typealias Separator = SwiftQL.XLSeparator
public typealias SimpleSelectQueryStatement = SwiftQL.XLSimpleSelectQueryStatement
public typealias StatementAccess = SwiftQLCore.XLStatementAccess
public typealias StatementCacheStatistics = SwiftQLCore.XLStatementCacheStatistics
public typealias StatementCachingDriverConnection = SwiftQLCore.XLStatementCachingDriverConnection
public typealias StaticColumnReader = SwiftQL.XLStaticColumnReader
public typealias StaticFieldGroup = SwiftQL.XLStaticFieldGroup
public typealias StaticQueryDescriptor = SwiftQLCore.XLStaticQueryDescriptor
public typealias StaticQueryError = SwiftQLCore.XLStaticQueryError
public typealias StaticQueryParameterMetadata = SwiftQLCore.XLStaticQueryParameterMetadata
public typealias StaticQueryResultMetadata = SwiftQLCore.XLStaticQueryResultMetadata
public typealias StaticQueryResultSlot = SwiftQLCore.XLStaticQueryResultSlot
public typealias StaticRowField = SwiftQLCore.XLStaticRowField
public typealias StaticRowFieldSource = SwiftQL.XLStaticRowFieldSource
public typealias StaticRowLayout = SwiftQL.XLStaticRowLayout
public typealias StaticRowLayoutError = SwiftQL.XLStaticRowLayoutError
public typealias StaticRowMetadata = SwiftQLCore.XLStaticRowMetadata
public typealias StaticRowMetadataError = SwiftQLCore.XLStaticRowMetadataError
public typealias StaticRowReadError = SwiftQL.XLStaticRowReadError
public typealias StaticRowReadable = SwiftQL.XLStaticRowReadable
public typealias StaticSelectField = SwiftQL.XLStaticSelectField
public typealias StaticSelectFieldProtocol = SwiftQL.XLStaticSelectFieldProtocol
public typealias StaticStatementDefinition = SwiftQLCore.XLStaticStatementDefinition
public typealias StaticStatementDefinitionError = SwiftQLCore.XLStaticStatementDefinitionError
public typealias StaticStorageRetypableExpression = SwiftQL.XLStaticStorageRetypableExpression
public typealias SubqueryDependency = SwiftQL.XLSubqueryDependency
public typealias TableDeclaration = SwiftQL.XLTableDeclaration
public typealias TableStatement = SwiftQL.XLTableStatement
public typealias TransactionKind = SwiftQLCore.XLTransactionKind
public typealias TransactionScopeError = SwiftQL.XLTransactionScopeError
public typealias TransactionalDatabase = SwiftQL.XLTransactionalDatabase
public typealias TypeAffinityExpression = SwiftQL.XLTypeAffinityExpression
public typealias TypeCastExpression = SwiftQL.XLTypeCastExpression
public typealias TypedStaticQueryDescriptor = SwiftQL.XLTypedStaticQueryDescriptor
public typealias UUIDValueCodec = SwiftQL.XLUUIDValueCodec
public typealias UUIDValueCodecError = SwiftQL.XLUUIDValueCodecError
public typealias UnaryOperatorExpression = SwiftQL.XLUnaryOperatorExpression
public typealias UpdateExpressionBuilder = SwiftQL.XLUpdateExpressionBuilder
public typealias UpdateFromStatement = SwiftQL.XLUpdateFromStatement
public typealias UpdateFromTableDependency = SwiftQL.XLUpdateFromTableDependency
public typealias UpdateReturningStatement = SwiftQL.XLUpdateReturningStatement
public typealias UpdateSetStatement = SwiftQL.XLUpdateSetStatement
public typealias UpdateStatement = SwiftQL.XLUpdateStatement
public typealias UpdateStatementComponents = SwiftQL.XLUpdateStatementComponents
public typealias UpdateTableStatement = SwiftQL.XLUpdateTableStatement
public typealias UpdateWhereStatement = SwiftQL.XLUpdateWhereStatement
public typealias V1LiteralCodec = SwiftQL.XLV1LiteralCodec
public typealias ValidatedLogicalPreparedStatement = SwiftQLCore.XLValidatedLogicalPreparedStatement
public typealias ValueCodec = SwiftQLCore.XLValueCodec
public typealias ValueCodecError = SwiftQLCore.XLValueCodecError
public typealias ValueCodecIdentity = SwiftQLCore.XLValueCodecIdentity
public typealias ValueCodecKey = SwiftQLCore.XLValueCodecKey
public typealias ValueCodecRegistry = SwiftQLCore.XLValueCodecRegistry
public typealias ValueCodecSelection = SwiftQLCore.XLValueCodecSelection
public typealias ValueCodecSelectionSource = SwiftQLCore.XLValueCodecSelectionSource
public typealias ValueCodecTarget = SwiftQLCore.XLValueCodecTarget
public typealias ValueCodingConfiguration = SwiftQLCore.XLValueCodingConfiguration
public typealias ValueCodingContext = SwiftQLCore.XLValueCodingContext
public typealias ValueCodingDialect = SwiftQLCore.XLValueCodingDialect
public typealias ValueCodingPath = SwiftQLCore.XLValueCodingPath
public typealias ValueCodingSite = SwiftQLCore.XLValueCodingSite
public typealias ValueStorageIdentifier = SwiftQLCore.XLValueStorageIdentifier
public typealias ValueTypeIdentifier = SwiftQLCore.XLValueTypeIdentifier
public typealias WithStatement = SwiftQL.XLWithStatement
public typealias WriteRequest = SwiftQL.XLWriteRequest
public typealias SQLiteBuilder = SwiftQL.XLiteBuilder
public typealias SQLiteColumnDefinitionsBuilder = SwiftQL.XLiteColumnDefinitionsBuilder
public typealias SQLiteCommonTablesBuilder = SwiftQL.XLiteCommonTablesBuilder
public typealias SQLiteEncoder = SwiftQL.XLiteEncoder
public typealias SQLiteFormatter = SwiftQLCore.XLiteFormatter
public typealias SQLiteListBuilder = SwiftQL.XLiteListBuilder
public typealias SQLitePlaceholderAssigner = SwiftQLCore.XLitePlaceholderAssigner
public typealias SQLiteVocabulary = SwiftQLCore.XLiteVocabulary
