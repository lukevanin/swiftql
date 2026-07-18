import Foundation


/// Failures while preparing or executing a static query through GRDB.
public enum GRDBStaticQueryError: Error, Equatable, Sendable, LocalizedError {

    case operationCardinalityMismatch(
        identity: XLQueryIdentity,
        expected: XLQueryCardinality,
        actual: XLQueryCardinality
    )

    case rowCountMismatch(
        identity: XLQueryIdentity,
        cardinality: XLQueryCardinality,
        actual: Int
    )

    case resultColumnCountMismatch(
        identity: XLQueryIdentity,
        row: Int,
        expected: Int,
        actual: Int
    )

    case nullForRequiredResult(
        identity: XLQueryIdentity,
        slot: XLStaticQueryResultSlot
    )

    case resultStorageMismatch(
        identity: XLQueryIdentity,
        slot: XLStaticQueryResultSlot,
        actual: XLValueStorageIdentifier
    )

    case parameterStorageMismatch(
        identity: XLQueryIdentity,
        parameter: XLStaticQueryParameterMetadata,
        actual: XLValueStorageIdentifier
    )

    case unsupportedParameterStorage(
        identity: XLQueryIdentity,
        parameter: XLStaticQueryParameterMetadata
    )

    case unsupportedResultStorage(
        identity: XLQueryIdentity,
        slot: XLStaticQueryResultSlot
    )

    case parameterNotFound(
        identity: XLQueryIdentity,
        parameter: XLQuerySlotIdentity
    )

    case resultNotFound(
        identity: XLQueryIdentity,
        result: XLQuerySlotIdentity
    )

    case parameterHasNoContextualCodec(
        identity: XLQueryIdentity,
        parameter: XLQuerySlotIdentity
    )

    case resultHasNoContextualCodec(
        identity: XLQueryIdentity,
        result: XLQuerySlotIdentity
    )

    case resultCodecUnavailable(
        identity: XLQueryIdentity,
        slot: XLStaticQueryResultSlot,
        codecIdentity: XLValueCodecIdentity
    )

    case resultCodecIdentityMismatch(
        identity: XLQueryIdentity,
        slot: XLStaticQueryResultSlot,
        expected: XLValueCodecIdentity,
        actual: XLValueCodecIdentity
    )

    case resultCodecDialectMismatch(
        identity: XLQueryIdentity,
        slot: XLStaticQueryResultSlot,
        codecIdentity: XLValueCodecIdentity,
        expectedDialectIdentifier: XLDialectIdentifier
    )

    public var errorDescription: String? {
        switch self {
        case .operationCardinalityMismatch(let identity, let expected, let actual):
            return "Static query \(identity) has \(actual.staticQueryDescription) cardinality and cannot execute as \(expected.staticQueryDescription)."
        case .rowCountMismatch(let identity, let cardinality, let actual):
            return "Static query \(identity) expected \(cardinality.staticQueryDescription) cardinality but returned \(actual) rows."
        case .resultColumnCountMismatch(let identity, let row, let expected, let actual):
            return "Static query \(identity) row \(row) returned \(actual) columns; its result layout requires \(expected)."
        case .nullForRequiredResult(let identity, let slot):
            return "Static query \(identity) returned NULL for required result \(slot.identity) at index \(slot.index)."
        case .resultStorageMismatch(let identity, let slot, let actual):
            return "Static query \(identity) result \(slot.identity) expects storage \(slot.storageIdentifier), not \(actual)."
        case .parameterStorageMismatch(let identity, let parameter, let actual):
            return "Static query \(identity) parameter \(parameter.identity) expects storage \(parameter.storageIdentifier), not \(actual)."
        case .unsupportedParameterStorage(let identity, let parameter):
            return "Static query \(identity) parameter \(parameter.identity) declares unsupported SQLite storage \(parameter.storageIdentifier)."
        case .unsupportedResultStorage(let identity, let slot):
            return "Static query \(identity) result \(slot.identity) declares unsupported SQLite storage \(slot.storageIdentifier)."
        case .parameterNotFound(let identity, let parameter):
            return "Static query \(identity) has no parameter identified by \(parameter)."
        case .resultNotFound(let identity, let result):
            return "Static query \(identity) has no result identified by \(result)."
        case .parameterHasNoContextualCodec(let identity, let parameter):
            return "Static query \(identity) parameter \(parameter) has no contextual codec."
        case .resultHasNoContextualCodec(let identity, let result):
            return "Static query \(identity) result \(result) has no contextual codec."
        case .resultCodecUnavailable(let identity, let slot, let codecIdentity):
            return "Static query \(identity) result \(slot.identity) requires unavailable codec \(codecIdentity.key)."
        case .resultCodecIdentityMismatch(let identity, let slot, let expected, let actual):
            return "Static query \(identity) result \(slot.identity) requires codec \(expected.key), but the prepared snapshot contains \(actual.key)."
        case .resultCodecDialectMismatch(let identity, let slot, let codecIdentity, let expectedDialectIdentifier):
            return "Static query \(identity) result \(slot.identity) codec \(codecIdentity.key) targets \(codecIdentity.dialectIdentifier), not \(expectedDialectIdentifier)."
        }
    }
}


private extension XLQueryCardinality {

    var staticQueryDescription: String {
        switch self {
        case .command:
            return "command"
        case .exactlyOne:
            return "exactly-one"
        case .zeroOrOne:
            return "zero-or-one"
        case .many:
            return "many"
        }
    }
}


/// One immutable, per-call value assignment for a static query capture.
///
/// The argument temporarily retains its source value until all copies of the
/// argument are released. Applying it is synchronous and copies only the
/// encoded dialect value into a fresh packet. The prepared query never stores
/// the argument or its source value.
public struct GRDBStaticQueryArgument {

    private let applyValue: (
        inout GRDBStaticQueryInvocationBuilder
    ) throws -> Void

    fileprivate init(
        applyValue: @escaping (
            inout GRDBStaticQueryInvocationBuilder
        ) throws -> Void
    ) {
        self.applyValue = applyValue
    }

    fileprivate func apply(
        to builder: inout GRDBStaticQueryInvocationBuilder
    ) throws {
        try applyValue(&builder)
    }
}


extension XLQueryCapture where Dialect == XLSQLiteDialect {

    /// Pairs a required invocation value with this value-free capture.
    public func argument(_ value: Input) -> GRDBStaticQueryArgument {
        GRDBStaticQueryArgument { builder in
            try builder.bind(value, to: self)
        }
    }

    /// Pairs a nullable invocation value with an optional SQL capture.
    /// `nil` remains a present SQL `NULL` argument.
    public func argument<Wrapped>(
        _ value: Input?
    ) -> GRDBStaticQueryArgument
    where Literal == Wrapped?, Wrapped: XLLiteral {
        GRDBStaticQueryArgument { builder in
            try builder.bind(value, to: self)
        }
    }
}


/// A short-lived assembler for one immutable static-query invocation packet.
///
/// Builders are created only by `GRDBPreparedStaticQuery.makeInvocationBindings`.
/// They own a fresh packet and never mutate the prepared handle.
public struct GRDBStaticQueryInvocationBuilder {

    private let query: GRDBPreparedStaticQuery

    private var packet: XLInvocationBindings<XLSQLiteValue>

    fileprivate init(query: GRDBPreparedStaticQuery) {
        self.query = query
        self.packet = XLInvocationBindings(layout: query.parameterLayout)
    }

    /// Encodes and adds one required capture value.
    public mutating func bind<Input, Literal>(
        _ value: Input,
        to capture: XLQueryCapture<Input, Literal, XLSQLiteDialect>
    ) throws where Literal: XLLiteral {
        let metadata = try query.validatedMetadata(for: capture)
        try requireUnbound(metadata.slot)
        let binding: XLInvocationBinding<XLSQLiteValue>
        switch capture.encoding {
        case .contextual:
            binding = try query.preparedParameter(
                Input.self,
                identifiedBy: capture.identity
            ).encode(value)
        case .intrinsic(let encode):
            binding = try XLInvocationBinding(
                slot: metadata.slot,
                value: encode(value)
            )
        }
        packet = try packet.binding(binding)
    }

    /// Encodes and adds one nullable capture value. `nil` is a present SQL
    /// `NULL` binding; it is never treated as an omitted argument.
    public mutating func bind<Input, Wrapped>(
        _ value: Input?,
        to capture: XLQueryCapture<Input, Wrapped?, XLSQLiteDialect>
    ) throws where Wrapped: XLLiteral {
        let metadata = try query.validatedMetadata(for: capture)
        try requireUnbound(metadata.slot)
        let binding: XLInvocationBinding<XLSQLiteValue>
        switch capture.encoding {
        case .contextual:
            binding = try query.preparedParameter(
                Input.self,
                identifiedBy: capture.identity
            ).encodeOptional(value)
        case .intrinsic(let encode):
            guard let value else {
                guard metadata.slot.nullability == .nullable else {
                    throw XLInvocationBindingError.nullForRequiredParameter(
                        slot: metadata.slot
                    )
                }
                binding = try XLInvocationBinding(
                    slot: metadata.slot,
                    value: .null
                )
                packet = try packet.binding(binding)
                return
            }
            binding = try XLInvocationBinding(
                slot: metadata.slot,
                value: encode(value)
            )
        }
        packet = try packet.binding(binding)
    }

    fileprivate func completedPacket() throws -> XLInvocationBindings<XLSQLiteValue> {
        try packet.validatingComplete()
    }

    private func requireUnbound(_ slot: XLParameterSlot) throws {
        guard packet.binding(at: slot.index) == nil else {
            throw XLInvocationBindingError.duplicateBinding(slot: slot)
        }
    }
}


/// A database-bound, concurrency-safe GRDB executor for one immutable static
/// query descriptor.
///
/// The handle retains the database's immutable coding configuration so typed
/// parameter and result codecs can be resolved from the same snapshot. Its raw
/// executor never retains a connection-owned SQLite statement.
public struct GRDBPreparedStaticQuery: Sendable {

    public let descriptor: XLStaticQueryDescriptor

    private let invocation: GRDBPreparedInvocation

    private let codingConfiguration: XLValueCodingConfiguration

    private let dialect: XLSQLiteDialect

    init(
        descriptor: XLStaticQueryDescriptor,
        invocation: GRDBPreparedInvocation,
        codingConfiguration: XLValueCodingConfiguration,
        dialect: XLSQLiteDialect
    ) {
        self.descriptor = descriptor
        self.invocation = invocation
        self.codingConfiguration = codingConfiguration
        self.dialect = dialect
    }

    public var identity: XLQueryIdentity {
        descriptor.identity
    }

    public var parameterLayout: XLParameterLayout {
        descriptor.statement.parameterLayout
    }

    /// Builds one fresh, immutable invocation packet from stable captures.
    ///
    /// The builder resolves contextual codecs only from this prepared handle's
    /// snapshotted configuration. Values and packets are local to this call.
    public func makeInvocationBindings(
        _ build: (inout GRDBStaticQueryInvocationBuilder) throws -> Void
    ) throws -> XLInvocationBindings<XLSQLiteValue> {
        var builder = GRDBStaticQueryInvocationBuilder(query: self)
        try build(&builder)
        return try builder.completedPacket()
    }

    /// Builds one fresh packet from immutable per-call capture arguments.
    public func makeInvocationBindings(
        _ arguments: GRDBStaticQueryArgument...
    ) throws -> XLInvocationBindings<XLSQLiteValue> {
        try makeInvocationBindings(arguments: arguments)
    }

    /// Builds one fresh packet from a dynamically assembled argument list.
    ///
    /// Application order does not affect the completed packet: bindings are
    /// canonicalized by the renderer-assigned logical parameter order.
    public func makeInvocationBindings(
        arguments: [GRDBStaticQueryArgument]
    ) throws -> XLInvocationBindings<XLSQLiteValue> {
        try makeInvocationBindings { builder in
            for argument in arguments {
                try argument.apply(to: &builder)
            }
        }
    }

    /// Resolves one typed parameter from the immutable database coding
    /// snapshot and verifies its complete durable identity.
    public func preparedParameter<Value>(
        _ type: Value.Type,
        identifiedBy identity: XLQuerySlotIdentity
    ) throws -> XLPreparedParameter<Value, XLSQLiteDialect> {
        guard let metadata = descriptor.parameters.first(where: {
            $0.identity == identity
        }) else {
            throw GRDBStaticQueryError.parameterNotFound(
                identity: descriptor.identity,
                parameter: identity
            )
        }
        guard let expected = metadata.slot.codecIdentity else {
            throw GRDBStaticQueryError.parameterHasNoContextualCodec(
                identity: descriptor.identity,
                parameter: identity
            )
        }
        let codec = try codingConfiguration.resolvedCodec(
            for: type,
            using: dialect,
            context: metadata.slot.codingContext,
            selection: XLValueCodecSelection(explicitCodecKey: expected.key)
        )
        guard codec.identity == expected else {
            throw XLInvocationBindingError.preparedCodecIdentityMismatch(
                slot: metadata.slot,
                expected: expected,
                actual: codec.identity
            )
        }
        let parameter = XLPreparedParameter(
            index: metadata.slot.index,
            key: metadata.slot.key,
            nullability: metadata.slot.nullability,
            codec: codec
        )
        guard parameter.slot == metadata.slot else {
            throw XLInvocationBindingError.parameterMetadataMismatch(
                expected: metadata.slot,
                actual: parameter.slot
            )
        }
        return parameter
    }

    /// Resolves one typed result codec from the immutable database coding
    /// snapshot and verifies its complete durable identity.
    public func resultCodec<Value>(
        _ type: Value.Type,
        identifiedBy identity: XLQuerySlotIdentity
    ) throws -> XLResolvedValueCodec<Value, XLSQLiteDialect> {
        guard let slot = descriptor.results.slots.first(where: {
            $0.identity == identity
        }) else {
            throw GRDBStaticQueryError.resultNotFound(
                identity: descriptor.identity,
                result: identity
            )
        }
        guard let expected = slot.codecIdentity else {
            throw GRDBStaticQueryError.resultHasNoContextualCodec(
                identity: descriptor.identity,
                result: identity
            )
        }
        let codec = try codingConfiguration.resolvedCodec(
            for: type,
            using: dialect,
            context: slot.codingContext,
            selection: XLValueCodecSelection(explicitCodecKey: expected.key)
        )
        guard codec.identity == expected else {
            throw GRDBStaticQueryError.resultCodecIdentityMismatch(
                identity: descriptor.identity,
                slot: slot,
                expected: expected,
                actual: codec.identity
            )
        }
        return codec
    }

    fileprivate func validatedMetadata<Input, Literal>(
        for capture: XLQueryCapture<Input, Literal, XLSQLiteDialect>
    ) throws -> XLStaticQueryParameterMetadata where Literal: XLLiteral {
        guard capture.dialectIdentifier == dialect.descriptor.identity else {
            throw XLQueryCaptureError.dialectMismatch(
                identity: capture.identity,
                expected: dialect.descriptor.identity,
                actual: capture.dialectIdentifier
            )
        }
        guard let metadata = descriptor.parameters.first(where: {
            $0.identity == capture.identity
        }) else {
            throw GRDBStaticQueryError.parameterNotFound(
                identity: descriptor.identity,
                parameter: capture.identity
            )
        }
        guard metadata.slot == capture.declaration.slot(at: metadata.slot.index),
              metadata.storageIdentifier == capture.storageIdentifier else {
            throw XLQueryCaptureError.descriptorMetadataMismatch(
                query: descriptor.identity,
                identity: capture.identity,
                expectedSlot: metadata.slot,
                expectedStorage: metadata.storageIdentifier,
                actualDeclaration: capture.declaration,
                actualStorage: capture.storageIdentifier
            )
        }
        return metadata
    }

    /// Executes a descriptor declared with command cardinality.
    public func execute(
        bindings: any XLInvocationBindingPacket
    ) throws {
        try requireCardinality(.command)
        try invocation.execute(bindings: validatedBindings(bindings))
    }

    /// Fetches the sole row and rejects both missing and excess rows.
    public func fetchExactlyOneValues(
        bindings: any XLInvocationBindingPacket
    ) throws -> [XLSQLiteValue] {
        try requireCardinality(.exactlyOne)
        let rows = try invocation.fetchAllValues(
            bindings: validatedBindings(bindings)
        )
        guard rows.count == 1, let row = rows.first else {
            throw GRDBStaticQueryError.rowCountMismatch(
                identity: descriptor.identity,
                cardinality: .exactlyOne,
                actual: rows.count
            )
        }
        try validate(row: row, at: 0)
        return row
    }

    /// Fetches zero or one row and rejects an excess-row result.
    public func fetchZeroOrOneValues(
        bindings: any XLInvocationBindingPacket
    ) throws -> [XLSQLiteValue]? {
        try requireCardinality(.zeroOrOne)
        let rows = try invocation.fetchAllValues(
            bindings: validatedBindings(bindings)
        )
        guard rows.count <= 1 else {
            throw GRDBStaticQueryError.rowCountMismatch(
                identity: descriptor.identity,
                cardinality: .zeroOrOne,
                actual: rows.count
            )
        }
        guard let row = rows.first else {
            return nil
        }
        try validate(row: row, at: 0)
        return row
    }

    /// Fetches every row from a descriptor declared with many cardinality.
    public func fetchAllValues(
        bindings: any XLInvocationBindingPacket
    ) throws -> [[XLSQLiteValue]] {
        try requireCardinality(.many)
        var rows: [[XLSQLiteValue]] = []
        try forEachValueRow(bindings: bindings) { row in
            rows.append(row)
            return .advance
        }
        return rows
    }

    /// Visits and validates every result row for a many-row descriptor while
    /// the underlying cursor remains inside its physical connection access.
    package func forEachValueRow(
        bindings: any XLInvocationBindingPacket,
        _ body: ([XLSQLiteValue]) throws -> XLRowStreamControl
    ) throws {
        try requireCardinality(.many)
        let packet = try validatedBindings(bindings)
        var index = 0
        try invocation.forEachValueRow(bindings: packet) { row in
            try validate(row: row, at: index)
            index += 1
            return try body(row)
        }
    }

    private func requireCardinality(
        _ expected: XLQueryCardinality
    ) throws {
        guard descriptor.cardinality == expected else {
            throw GRDBStaticQueryError.operationCardinalityMismatch(
                identity: descriptor.identity,
                expected: expected,
                actual: descriptor.cardinality
            )
        }
    }

    /// Validates the descriptor's complete parameter contract before the raw
    /// GRDB invocation performs its own driver-facing checks. This is required
    /// for intrinsic parameters whose slots intentionally have no contextual
    /// codec identity but still declare an exact dialect storage mapping.
    private func validatedBindings(
        _ bindings: any XLInvocationBindingPacket
    ) throws -> XLInvocationBindings<XLSQLiteValue> {
        guard let packet = bindings as? XLInvocationBindings<XLSQLiteValue> else {
            throw XLRequestBindingError.incompatibleInvocationPacket(
                requestType: String(reflecting: Self.self),
                expectedDialect: XLSQLiteDialect.identity,
                expectedValueType: String(reflecting: XLSQLiteValue.self),
                actualPacketType: String(reflecting: type(of: bindings))
            )
        }
        guard packet.layout == parameterLayout else {
            throw XLInvocationBindingError.packetLayoutMismatch(
                expected: parameterLayout,
                actual: packet.layout
            )
        }
        let validatedPacket = try packet.validatingComplete()

        for binding in validatedPacket.bindings {
            guard let parameter = descriptor.parameter(
                at: binding.slot.index
            ) else {
                throw XLInvocationBindingError.parameterNotInLayout(
                    slot: binding.slot
                )
            }
            if dialect.isNull(binding.value) {
                guard parameter.slot.nullability == .nullable else {
                    throw XLInvocationBindingError.nullForRequiredParameter(
                        slot: parameter.slot
                    )
                }
                continue
            }
            let actualStorage = dialect.stableStorageIdentifier(
                for: binding.value
            )
            guard actualStorage == parameter.storageIdentifier else {
                throw GRDBStaticQueryError.parameterStorageMismatch(
                    identity: descriptor.identity,
                    parameter: parameter,
                    actual: actualStorage
                )
            }
        }
        return validatedPacket
    }

    private func validate(
        row: [XLSQLiteValue],
        at rowIndex: Int
    ) throws {
        let slots = descriptor.results.slots
        guard row.count == slots.count else {
            throw GRDBStaticQueryError.resultColumnCountMismatch(
                identity: descriptor.identity,
                row: rowIndex,
                expected: slots.count,
                actual: row.count
            )
        }

        for (slot, value) in zip(slots, row) {
            if dialect.isNull(value) {
                guard slot.nullability == .nullable else {
                    throw GRDBStaticQueryError.nullForRequiredResult(
                        identity: descriptor.identity,
                        slot: slot
                    )
                }
                continue
            }
            let actualStorage = dialect.stableStorageIdentifier(for: value)
            guard actualStorage == slot.storageIdentifier else {
                throw GRDBStaticQueryError.resultStorageMismatch(
                    identity: descriptor.identity,
                    slot: slot,
                    actual: actualStorage
                )
            }
        }
    }
}


/// A GRDB prepared handle that decodes through a generated static row layout.
///
/// The driver-specific wrapper is intentionally separate from
/// ``XLTypedStaticQueryDescriptor`` so the descriptor and layout APIs remain
/// free of GRDB types.
public struct GRDBPreparedTypedStaticQuery<Row> {

    public let definition: XLTypedStaticQueryDescriptor<
        Row,
        XLSQLiteDialect
    >

    private let query: GRDBPreparedStaticQuery

    init(
        definition: XLTypedStaticQueryDescriptor<Row, XLSQLiteDialect>,
        query: GRDBPreparedStaticQuery
    ) {
        self.definition = definition
        self.query = query
    }

    public var descriptor: XLStaticQueryDescriptor {
        definition.descriptor
    }

    public var identity: XLQueryIdentity {
        query.identity
    }

    public var parameterLayout: XLParameterLayout {
        query.parameterLayout
    }

    public func makeInvocationBindings(
        _ build: (inout GRDBStaticQueryInvocationBuilder) throws -> Void
    ) throws -> XLInvocationBindings<XLSQLiteValue> {
        try query.makeInvocationBindings(build)
    }

    public func makeInvocationBindings(
        _ arguments: GRDBStaticQueryArgument...
    ) throws -> XLInvocationBindings<XLSQLiteValue> {
        try query.makeInvocationBindings(arguments: arguments)
    }

    public func makeInvocationBindings(
        arguments: [GRDBStaticQueryArgument]
    ) throws -> XLInvocationBindings<XLSQLiteValue> {
        try query.makeInvocationBindings(arguments: arguments)
    }

    public func fetchExactlyOne(
        bindings: any XLInvocationBindingPacket
    ) throws -> Row {
        try definition.layout.decode(
            query.fetchExactlyOneValues(bindings: bindings)
        )
    }

    public func fetchZeroOrOne(
        bindings: any XLInvocationBindingPacket
    ) throws -> Row? {
        guard let values = try query.fetchZeroOrOneValues(bindings: bindings)
        else {
            return nil
        }
        return try definition.layout.decode(values)
    }

    public func fetchAll(
        bindings: any XLInvocationBindingPacket
    ) throws -> [Row] {
        var rows: [Row] = []
        try query.forEachValueRow(bindings: bindings) { values in
            rows.append(try definition.layout.decode(values))
            return .advance
        }
        return rows
    }
}


extension GRDBDatabase {

    /// Prepares a typed static query only after its generated row layout has
    /// been proven equal to the descriptor's complete result metadata.
    public func prepareInvocation<Row>(
        with definition: XLTypedStaticQueryDescriptor<
            Row,
            XLSQLiteDialect
        >
    ) throws -> GRDBPreparedTypedStaticQuery<Row> {
        GRDBPreparedTypedStaticQuery(
            definition: definition,
            query: try prepareInvocation(with: definition.descriptor)
        )
    }
}
