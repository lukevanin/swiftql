//
//  XLLegacyBindingSupport.swift
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
