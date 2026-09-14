import Foundation


/// The stable zero-based position of one logical parameter in a statement.
///
/// Rendering may encounter the same named parameter more than once. Those
/// occurrences share one logical index and one invocation value.
public struct XLLogicalParameterIndex:
    RawRepresentable,
    Comparable,
    Hashable,
    Sendable,
    CustomStringConvertible
{

    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: Int) {
        self.init(rawValue: rawValue)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var description: String {
        String(rawValue)
    }
}


/// Whether a parameter accepts the dialect's explicit SQL `NULL` value.
public enum XLParameterNullability: String, Hashable, Sendable {
    case required
    case nullable
}


/// Static parameter metadata before SQL traversal assigns a logical index.
///
/// Public contextual references declare this value without guessing how many
/// parameters precede them. The shared renderer recorder assigns the stable
/// first-encounter index by calling `slot(at:)`.
public struct XLParameterDeclaration: Hashable, Sendable {

    public let key: XLBindingKey

    public let valueTypeIdentifier: XLValueTypeIdentifier

    /// A diagnostic Swift type name. Stable identity uses
    /// `valueTypeIdentifier`, not this process-local spelling.
    public let valueTypeName: String

    public let nullability: XLParameterNullability

    public let codecIdentity: XLValueCodecIdentity?

    public let codingContext: XLValueCodingContext

    public init(
        key: XLBindingKey,
        valueTypeIdentifier: XLValueTypeIdentifier,
        valueTypeName: String,
        nullability: XLParameterNullability,
        codecIdentity: XLValueCodecIdentity?,
        codingContext: XLValueCodingContext
    ) {
        self.key = key
        self.valueTypeIdentifier = valueTypeIdentifier
        self.valueTypeName = valueTypeName
        self.nullability = nullability
        self.codecIdentity = codecIdentity
        self.codingContext = codingContext
    }

    public func slot(at index: XLLogicalParameterIndex) -> XLParameterSlot {
        XLParameterSlot(
            index: index,
            key: key,
            valueTypeIdentifier: valueTypeIdentifier,
            valueTypeName: valueTypeName,
            nullability: nullability,
            codecIdentity: codecIdentity,
            codingContext: codingContext
        )
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.key == rhs.key
            && lhs.valueTypeIdentifier == rhs.valueTypeIdentifier
            && lhs.nullability == rhs.nullability
            && lhs.codecIdentity == rhs.codecIdentity
            && lhs.codingContext == rhs.codingContext
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(key)
        hasher.combine(valueTypeIdentifier)
        hasher.combine(nullability)
        hasher.combine(codecIdentity)
        hasher.combine(codingContext)
    }
}


/// Immutable metadata for one logical parameter in a rendered statement.
public struct XLParameterSlot: Hashable, Sendable {

    public let index: XLLogicalParameterIndex

    public let key: XLBindingKey

    public let valueTypeIdentifier: XLValueTypeIdentifier

    /// A diagnostic Swift type name. Stable identity uses
    /// `valueTypeIdentifier`, not this process-local spelling.
    public let valueTypeName: String

    public let nullability: XLParameterNullability

    /// The codec selected when the prepared handle snapshots its coding
    /// configuration. Legacy declarations that have not selected a contextual
    /// codec may leave this `nil` while migrating through the compatibility shim.
    public let codecIdentity: XLValueCodecIdentity?

    public let codingContext: XLValueCodingContext

    public init(
        index: XLLogicalParameterIndex,
        key: XLBindingKey,
        valueTypeIdentifier: XLValueTypeIdentifier,
        valueTypeName: String,
        nullability: XLParameterNullability,
        codecIdentity: XLValueCodecIdentity?,
        codingContext: XLValueCodingContext
    ) {
        self.index = index
        self.key = key
        self.valueTypeIdentifier = valueTypeIdentifier
        self.valueTypeName = valueTypeName
        self.nullability = nullability
        self.codecIdentity = codecIdentity
        self.codingContext = codingContext
    }

    public var declaration: XLParameterDeclaration {
        XLParameterDeclaration(
            key: key,
            valueTypeIdentifier: valueTypeIdentifier,
            valueTypeName: valueTypeName,
            nullability: nullability,
            codecIdentity: codecIdentity,
            codingContext: codingContext
        )
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.index == rhs.index
            && lhs.key == rhs.key
            && lhs.valueTypeIdentifier == rhs.valueTypeIdentifier
            && lhs.nullability == rhs.nullability
            && lhs.codecIdentity == rhs.codecIdentity
            && lhs.codingContext == rhs.codingContext
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(index)
        hasher.combine(key)
        hasher.combine(valueTypeIdentifier)
        hasher.combine(nullability)
        hasher.combine(codecIdentity)
        hasher.combine(codingContext)
    }
}


/// Deterministic failures while declaring, encoding, or assembling invocation
/// bindings.
public enum XLInvocationBindingError: Error, Equatable, Sendable, LocalizedError {
    case invalidParameterIndex(slot: XLParameterSlot)
    case noncontiguousParameterIndex(
        slot: XLParameterSlot,
        expected: XLLogicalParameterIndex
    )
    case conflictingParameterIndex(
        index: XLLogicalParameterIndex,
        existing: XLParameterSlot,
        incoming: XLParameterSlot
    )
    case conflictingParameterKey(
        key: XLBindingKey,
        existing: XLParameterSlot,
        incoming: XLParameterSlot
    )
    case conflictingPhysicalParameterIndex(
        index: Int,
        existing: XLParameterSlot,
        incoming: XLParameterSlot
    )
    case codecValueTypeMismatch(
        slot: XLParameterSlot,
        codecValueTypeIdentifier: XLValueTypeIdentifier
    )
    case codecBindingRequiresPreparedParameter(
        slot: XLParameterSlot,
        codecIdentity: XLValueCodecIdentity
    )
    case preparedCodecUnavailable(
        slot: XLParameterSlot,
        codecIdentity: XLValueCodecIdentity
    )
    case preparedCodecIdentityMismatch(
        slot: XLParameterSlot,
        expected: XLValueCodecIdentity,
        actual: XLValueCodecIdentity
    )
    case preparedCodecDialectMismatch(
        slot: XLParameterSlot,
        codecIdentity: XLValueCodecIdentity,
        expectedDialectIdentifier: XLDialectIdentifier
    )
    case dialectValueStorageMismatch(
        slot: XLParameterSlot,
        expectedCodecIdentity: XLValueCodecIdentity,
        actualStorageIdentifier: XLValueStorageIdentifier
    )
    case packetLayoutMismatch(
        expected: XLParameterLayout,
        actual: XLParameterLayout
    )
    case parameterDeclarationNotInLayout(declaration: XLParameterDeclaration)
    case parameterNotInLayout(slot: XLParameterSlot)
    case parameterMetadataMismatch(
        expected: XLParameterSlot,
        actual: XLParameterSlot
    )
    case duplicateBinding(slot: XLParameterSlot)
    case missingBindings(slots: [XLParameterSlot])
    case nullForRequiredParameter(slot: XLParameterSlot)
    case codecEncodingFailed(
        slot: XLParameterSlot,
        codecIdentity: XLValueCodecIdentity,
        context: XLValueCodingContext,
        message: String
    )
    case driverBindingFailed(
        slot: XLParameterSlot,
        codecIdentity: XLValueCodecIdentity?,
        context: XLValueCodingContext,
        message: String
    )
    case driverArgumentValidationFailed(
        layout: XLParameterLayout,
        message: String
    )

    public var errorDescription: String? {
        switch self {
        case .invalidParameterIndex(let slot):
            return "Parameter \(slot.key) has invalid logical index \(slot.index)."
        case .noncontiguousParameterIndex(let slot, let expected):
            return "Parameter \(slot.key) has noncontiguous logical index \(slot.index); expected \(expected)."
        case .conflictingParameterIndex(let index, let existing, let incoming):
            return "Logical parameter index \(index) is declared by both \(existing.key) and \(incoming.key)."
        case .conflictingParameterKey(let key, let existing, let incoming):
            return "Parameter \(key) has conflicting declarations at logical indices \(existing.index) and \(incoming.index)."
        case .conflictingPhysicalParameterIndex(let index, let existing, let incoming):
            return "Dialect parameter index \(index) aliases distinct logical parameters \(existing.key) and \(incoming.key)."
        case .codecValueTypeMismatch(let slot, let codecValueTypeIdentifier):
            let codec = slot.codecIdentity?.key.description ?? "unknown"
            return "Parameter \(slot.key) declares value type \(slot.valueTypeIdentifier), but codec \(codec) targets \(codecValueTypeIdentifier)."
        case .codecBindingRequiresPreparedParameter(let slot, let codecIdentity):
            return "Parameter \(slot.key) selects codec \(codecIdentity.key) at \(slot.codingContext); encode it through its prepared parameter instead of supplying a raw dialect value."
        case .preparedCodecUnavailable(let slot, let codecIdentity):
            return "Prepared codec \(codecIdentity.key) is unavailable for parameter \(slot.key) at \(slot.codingContext)."
        case .preparedCodecIdentityMismatch(let slot, let expected, let actual):
            return "Parameter \(slot.key) expects prepared codec \(expected.key), but the registered codec is \(actual.key) at \(slot.codingContext)."
        case .preparedCodecDialectMismatch(let slot, let codecIdentity, let expectedDialectIdentifier):
            return "Prepared codec \(codecIdentity.key) for parameter \(slot.key) targets dialect \(codecIdentity.dialectIdentifier), not \(expectedDialectIdentifier), at \(slot.codingContext)."
        case .dialectValueStorageMismatch(let slot, let expectedCodecIdentity, let actualStorageIdentifier):
            return "Parameter \(slot.key) encoded by codec \(expectedCodecIdentity.key) expects storage \(expectedCodecIdentity.storageIdentifier), but the dialect value uses \(actualStorageIdentifier), at \(slot.codingContext)."
        case .packetLayoutMismatch(let expected, let actual):
            if actual.count != expected.count {
                return "Invocation parameter count \(actual.count) does not match prepared parameter count \(expected.count)."
            }
            return "Invocation parameter layout does not match the prepared layout; both contain the same number of parameters (\(expected.count))."
        case .parameterDeclarationNotInLayout(let declaration):
            let codec = declaration.codecIdentity?.key.description ?? "legacy/unselected"
            return "Parameter \(declaration.key) with codec \(codec) at \(declaration.codingContext) is not in the prepared layout."
        case .parameterNotInLayout(let slot):
            return "Parameter \(slot.key) at logical index \(slot.index) is not in the prepared layout."
        case .parameterMetadataMismatch(let expected, let actual):
            return "Parameter \(actual.key) does not match the prepared metadata for \(expected.key) at logical index \(expected.index)."
        case .duplicateBinding(let slot):
            return "Parameter \(slot.key) at logical index \(slot.index) is bound more than once."
        case .missingBindings(let slots):
            let parameters = slots.map { "\($0.key)@\($0.index)" }.joined(separator: ", ")
            return "Invocation is missing values for \(parameters)."
        case .nullForRequiredParameter(let slot):
            return "Required parameter \(slot.key) at \(slot.codingContext) cannot be SQL NULL."
        case .codecEncodingFailed(let slot, let codecIdentity, let context, let message):
            return "Codec \(codecIdentity.key) could not encode parameter \(slot.key) at \(context): \(message)"
        case .driverBindingFailed(let slot, let codecIdentity, let context, let message):
            let codec = codecIdentity?.key.description ?? "legacy/unselected"
            return "Driver could not bind parameter \(slot.key) with codec \(codec) at \(context): \(message)"
        case .driverArgumentValidationFailed(let layout, let message):
            return "Driver could not validate the physical argument table for the \(layout.count)-parameter layout: \(message)"
        }
    }
}


/// Canonical immutable metadata for every logical parameter in one statement.
public struct XLParameterLayout: Hashable, Sendable {

    public static let empty = Self(canonicalSlots: [])

    public let slots: [XLParameterSlot]

    public init(slots declarations: [XLParameterSlot] = []) throws {
        var slotsByIndex: [XLLogicalParameterIndex: XLParameterSlot] = [:]
        var slotsByKey: [XLBindingKey: XLParameterSlot] = [:]

        for slot in declarations {
            guard slot.index.rawValue >= 0 else {
                throw XLInvocationBindingError.invalidParameterIndex(slot: slot)
            }

            if let codecIdentity = slot.codecIdentity,
               codecIdentity.valueTypeIdentifier != slot.valueTypeIdentifier {
                throw XLInvocationBindingError.codecValueTypeMismatch(
                    slot: slot,
                    codecValueTypeIdentifier: codecIdentity.valueTypeIdentifier
                )
            }

            if let existing = slotsByIndex[slot.index] {
                guard existing == slot else {
                    throw XLInvocationBindingError.conflictingParameterIndex(
                        index: slot.index,
                        existing: existing,
                        incoming: slot
                    )
                }
                continue
            }

            if let existing = slotsByKey[slot.key] {
                guard existing == slot else {
                    throw XLInvocationBindingError.conflictingParameterKey(
                        key: slot.key,
                        existing: existing,
                        incoming: slot
                    )
                }
                continue
            }

            slotsByIndex[slot.index] = slot
            slotsByKey[slot.key] = slot
        }

        let canonicalSlots = slotsByIndex.values.sorted { lhs, rhs in
            lhs.index < rhs.index
        }
        for (offset, slot) in canonicalSlots.enumerated() {
            let expected = XLLogicalParameterIndex(offset)
            guard slot.index == expected else {
                throw XLInvocationBindingError.noncontiguousParameterIndex(
                    slot: slot,
                    expected: expected
                )
            }
        }
        slots = canonicalSlots
    }

    private init(canonicalSlots: [XLParameterSlot]) {
        self.slots = canonicalSlots
    }

    public var isEmpty: Bool {
        slots.isEmpty
    }

    public var count: Int {
        slots.count
    }

    public func slot(at index: XLLogicalParameterIndex) -> XLParameterSlot? {
        slots.first { $0.index == index }
    }

    public func slot(for key: XLBindingKey) -> XLParameterSlot? {
        slots.first { $0.key == key }
    }
}


/// One present, normalized dialect value for a static parameter slot.
///
/// A dialect's SQL `NULL` value is a present value here. Missing bindings are
/// represented only by the absence of an `XLInvocationBinding` from a packet.
public struct XLInvocationBinding<Value: XLDialectValue>: Hashable, Sendable {

    public let slot: XLParameterSlot

    public let value: Value

    public init(slot: XLParameterSlot, value: Value) throws {
        if let codecIdentity = slot.codecIdentity {
            throw XLInvocationBindingError.codecBindingRequiresPreparedParameter(
                slot: slot,
                codecIdentity: codecIdentity
            )
        }
        self.slot = slot
        self.value = value
    }

    package init(preparedCodecSlot slot: XLParameterSlot, value: Value) {
        self.slot = slot
        self.value = value
    }
}


/// Adapter-neutral metadata exposed by every immutable invocation packet.
///
/// Drivers downcast the packet to their dialect's concrete
/// `XLInvocationBindings` specialization before accessing normalized values.
public protocol XLInvocationBindingPacket: Sendable {

    var layout: XLParameterLayout { get }

    var bindingCount: Int { get }

    var isComplete: Bool { get }
}


/// Immutable per-call values paired with one prepared parameter layout.
///
/// `bindings` is always ordered by logical parameter index, regardless of the
/// order in which callers supplied values.
public struct XLInvocationBindings<Value: XLDialectValue>:
    Hashable,
    Sendable,
    XLInvocationBindingPacket
{

    public let layout: XLParameterLayout

    public let bindings: [XLInvocationBinding<Value>]

    public init(layout: XLParameterLayout) {
        self.layout = layout
        self.bindings = []
    }

    public init(
        layout: XLParameterLayout,
        bindings: [XLInvocationBinding<Value>]
    ) throws {
        var packet = Self(layout: layout)
        for binding in bindings {
            packet = try packet.binding(binding)
        }
        self = packet
    }

    private init(
        layout: XLParameterLayout,
        canonicalBindings: [XLInvocationBinding<Value>]
    ) {
        self.layout = layout
        self.bindings = canonicalBindings
    }

    public var isComplete: Bool {
        bindings.count == layout.count
    }

    public var bindingCount: Int {
        bindings.count
    }

    public var missingSlots: [XLParameterSlot] {
        layout.slots.filter { binding(at: $0.index) == nil }
    }

    public func binding(
        at index: XLLogicalParameterIndex
    ) -> XLInvocationBinding<Value>? {
        bindings.first { $0.slot.index == index }
    }

    public func binding(for key: XLBindingKey) -> XLInvocationBinding<Value>? {
        bindings.first { $0.slot.key == key }
    }

    /// Returns a new packet with `binding` appended after validating its static
    /// metadata against the prepared layout.
    public func binding(
        _ binding: XLInvocationBinding<Value>
    ) throws -> Self {
        let expected: XLParameterSlot
        if let indexedSlot = layout.slot(at: binding.slot.index) {
            expected = indexedSlot
        }
        else if let keyedSlot = layout.slot(for: binding.slot.key) {
            expected = keyedSlot
        }
        else {
            throw XLInvocationBindingError.parameterNotInLayout(slot: binding.slot)
        }

        guard expected == binding.slot else {
            throw XLInvocationBindingError.parameterMetadataMismatch(
                expected: expected,
                actual: binding.slot
            )
        }

        guard self.binding(at: binding.slot.index) == nil else {
            throw XLInvocationBindingError.duplicateBinding(slot: binding.slot)
        }

        let canonicalBindings = (bindings + [binding]).sorted { lhs, rhs in
            lhs.slot.index < rhs.slot.index
        }
        return Self(layout: layout, canonicalBindings: canonicalBindings)
    }

    public func binding(_ value: Value, to slot: XLParameterSlot) throws -> Self {
        try binding(try XLInvocationBinding(slot: slot, value: value))
    }

    /// Returns this packet when all declared slots are present, or throws a
    /// canonical missing-slot list.
    @discardableResult
    public func validatingComplete() throws -> Self {
        let missingSlots = missingSlots
        guard missingSlots.isEmpty else {
            throw XLInvocationBindingError.missingBindings(slots: missingSlots)
        }
        return self
    }
}


/// A statically resolved parameter codec reusable across independent calls.
///
/// `Source` deliberately has no `Sendable` requirement. Values are consumed by
/// `encode` and never retained; invocation packets store only normalized dialect
/// values, which are `Sendable` by contract.
public struct XLPreparedParameter<Source, Dialect>: Sendable
where Dialect: XLValueCodingDialect {

    public let slot: XLParameterSlot

    private let codec: XLResolvedValueCodec<Source, Dialect>

    public init(
        index: XLLogicalParameterIndex,
        key: XLBindingKey,
        nullability: XLParameterNullability,
        codec: XLResolvedValueCodec<Source, Dialect>
    ) {
        self.slot = XLParameterSlot(
            index: index,
            key: key,
            valueTypeIdentifier: codec.identity.valueTypeIdentifier,
            valueTypeName: String(reflecting: Source.self),
            nullability: nullability,
            codecIdentity: codec.identity,
            codingContext: codec.context
        )
        self.codec = codec
    }

    public var codecIdentity: XLValueCodecIdentity {
        codec.identity
    }

    public var codingContext: XLValueCodingContext {
        codec.context
    }

    public func encode(
        _ value: Source
    ) throws -> XLInvocationBinding<Dialect.Value> {
        do {
            return XLInvocationBinding(
                preparedCodecSlot: slot,
                value: try codec.encode(value)
            )
        }
        catch {
            throw encodingError(error)
        }
    }

    public func encodeOptional(
        _ value: Source?
    ) throws -> XLInvocationBinding<Dialect.Value> {
        guard value != nil || slot.nullability == .nullable else {
            throw XLInvocationBindingError.nullForRequiredParameter(slot: slot)
        }

        do {
            return XLInvocationBinding(
                preparedCodecSlot: slot,
                value: try codec.encodeOptional(value)
            )
        }
        catch {
            throw encodingError(error)
        }
    }

    private func encodingError(_ error: Error) -> XLInvocationBindingError {
        XLInvocationBindingError.codecEncodingFailed(
            slot: slot,
            codecIdentity: codec.identity,
            context: codec.context,
            message: _xlInvocationErrorMessage(error)
        )
    }
}


private func _xlInvocationErrorMessage(_ error: Error) -> String {
    if let localizedError = error as? LocalizedError,
       let description = localizedError.errorDescription {
        return description
    }
    return String(describing: error)
}
