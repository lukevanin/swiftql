//
//  GRDBLegacyBindingSupport.swift
//  SwiftQL
//
//  The pieces the v1 mutable `set(parameter:value:)` facade needs, shared by
//  the read and write requests.
//
//  Split out of GRDBSQLDatabase.swift (issue #560): both request types use
//  them, and `private` is file-scoped, so they cannot sit inside either one.
//

extension XLParameterSlot {

    func acceptsLegacySet(_ declaration: XLParameterDeclaration) -> Bool {
        self.declaration == declaration || isRendererLegacyBindingWildcard
    }

    /// Whether this slot is the renderer's legacy binding sentinel.
    ///
    /// `XLBuilder.namedBinding` and `indexedBinding` predate typed parameter
    /// declarations. The renderer records this exact sentinel so the v1
    /// mutating `set` facade can still normalize a value for custom expressions
    /// that emit placeholders directly. Typed and contextual slots never take
    /// this path and continue to require an exact declaration match.
    ///
    /// One definition, module-wide. `SQLiteEncoding` carried a byte-identical
    /// private copy that had to stay in lockstep with this one or the legacy
    /// `set` facade would silently reject bindings the renderer had accepted
    /// (issue #560 surfaced the duplicate; #558 names it).
    var isRendererLegacyBindingWildcard: Bool {
        valueTypeIdentifier == XLValueTypeIdentifier(
            rawValue: "swiftql.legacy-binding-value"
        )
            && valueTypeName == "SwiftQL.XLBindable"
            && nullability == .nullable
            && codecIdentity == nil
    }
}


func replacingBinding(
    _ value: XLSQLiteValue,
    at slot: XLParameterSlot,
    in packet: XLInvocationBindings<XLSQLiteValue>
) throws -> XLInvocationBindings<XLSQLiteValue> {
    if value == .null, slot.nullability == .required {
        throw XLInvocationBindingError.nullForRequiredParameter(slot: slot)
    }
    return try XLInvocationBindings(
        layout: packet.layout,
        bindings: packet.bindings.filter { $0.slot.index != slot.index } + [
            XLInvocationBinding(slot: slot, value: value)
        ]
    )
}
