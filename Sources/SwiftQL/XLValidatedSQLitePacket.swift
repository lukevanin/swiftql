//
//  XLValidatedSQLitePacket.swift
//  SwiftQL
//
//  A SQLite invocation packet that has been checked against the statement it is
//  about to be bound to (issue #561).
//
//  Validation used to be a step anyone could skip and anyone could repeat, and
//  it was repeated: an execution validated its packet, then handed it to
//  `boundStatement`, which validated it again -- two or three full passes over
//  every binding per call. Making the result a distinct type that only
//  validation can produce turns "already validated" into something the compiler
//  knows, so a second pass is not merely unnecessary but unrepresentable.
//

///
/// The outcome of checking one invocation packet against one prepared
/// statement's parameter layout.
///
/// The structural checks are enforced by construction: the only initializer
/// runs them and throws, so a value of this type cannot exist without a packet
/// that is SQLite's, was built for the statement being executed, and has a
/// value in every slot the layout declares.
///
/// The *semantic* checks -- codec identity, storage agreement, nullability, and
/// the NaN guard -- stay with ``GRDBInvocationExecutor/sqlitePacket(_:)``,
/// which is the only caller. Those need the driver's dialect and registry,
/// which this type deliberately knows nothing about. So the invariant this
/// carries is "structurally valid for its layout", and the reason a second
/// pass is unnecessary is that `sqlitePacket` runs the rest before returning.
///
struct XLValidatedSQLitePacket {

    /// The bindings, complete and in layout order.
    let bindings: [XLInvocationBinding<XLSQLiteValue>]

    /// The layout they were checked against.
    let layout: XLParameterLayout

    ///
    /// Checks `bindings` against `layout` and keeps the result.
    ///
    /// This is the only way to make one, and it cannot be handed something it
    /// has not checked -- which is what lets `boundStatement` execute a packet
    /// without validating it again.
    ///
    /// - Parameter requestType: Named in the mismatch error, so the message
    ///   says which execution path rejected the packet.
    ///
    init(
        validating bindings: any XLInvocationBindingPacket,
        matching layout: XLParameterLayout,
        requestType: Any.Type
    ) throws {
        let validated = try _xlSQLiteInvocationPacket(
            bindings,
            matching: layout,
            requestType: requestType
        )
        self.bindings = validated.bindings
        self.layout = validated.layout
    }
}


///
/// Narrows an invocation packet to SQLite's value type and confirms it is
/// complete against `layout`.
///
/// The shape checks any SQLite execution starts with, before anything
/// path-specific: that the packet is SQLite's at all, that it was built for the
/// statement being executed, and that every slot the layout declares has a
/// value. The driver's validation and the static query's descriptor validation
/// both begin here and then diverge -- one checks codec identity against the
/// database's registry, the other checks storage against the descriptor's own
/// declared parameters -- which is why only the opening is shared (issue #561).
///
/// - Parameter requestType: Named in the mismatch error, so the message says
///   which execution path rejected the packet.
///
func _xlSQLiteInvocationPacket(
    _ bindings: any XLInvocationBindingPacket,
    matching layout: XLParameterLayout,
    requestType: Any.Type
) throws -> XLInvocationBindings<XLSQLiteValue> {
    guard let packet = bindings as? XLInvocationBindings<XLSQLiteValue> else {
        throw XLRequestBindingError.incompatibleInvocationPacket(
            requestType: String(reflecting: requestType),
            expectedDialect: XLSQLiteDialect.identity,
            expectedValueType: String(reflecting: XLSQLiteValue.self),
            actualPacketType: String(reflecting: type(of: bindings))
        )
    }
    guard packet.layout == layout else {
        throw XLInvocationBindingError.packetLayoutMismatch(
            expected: layout,
            actual: packet.layout
        )
    }
    return try packet.validatingComplete()
}
