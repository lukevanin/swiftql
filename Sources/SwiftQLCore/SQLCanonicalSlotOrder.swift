//
//  SQLCanonicalSlotOrder.swift
//  SwiftQLCore
//
//  The ordering and contiguity rule every canonical slot table ends with
//  (issue #558).
//

///
/// Sorts slots into canonical index order and confirms their indices are a
/// contiguous run from zero.
///
/// A slot table's index is a position, not a label: index 2 means "the third
/// value", so a table holding indices 0 and 2 describes a row with a hole in
/// it. Nothing downstream can represent that, which is why the check is here
/// rather than at whatever later point the hole would first be noticed.
///
/// Shared by ``XLParameterLayout`` and ``XLStaticQueryResultMetadata``, which
/// end identically. Their per-slot validation stays separate on purpose: it is
/// not the same rule in two error styles, it is two different rules. A
/// parameter layout accepts a slot declared twice when both declarations agree
/// -- one parameter referenced from two places in a query is normal -- while a
/// result table refuses any duplicate, because two values cannot occupy one
/// column of a row.
///
/// - Parameters:
///   - slots: The deduplicated slots, in any order.
///   - index: The slot's position.
///   - expectedIndex: The position a slot at a given offset must have.
///   - noncontiguous: Builds the error for a slot whose index is not the
///     expected one.
///
package func _xlCanonicalSlotOrder<Slot, Index: Comparable>(
    _ slots: [Slot],
    index: (Slot) -> Index,
    expectedIndex: (Int) -> Index,
    noncontiguous: (Slot, Index) -> Error
) throws -> [Slot] {
    let ordered = slots.sorted { index($0) < index($1) }
    for (offset, slot) in ordered.enumerated() {
        let expected = expectedIndex(offset)
        guard index(slot) == expected else {
            throw noncontiguous(slot, expected)
        }
    }
    return ordered
}
