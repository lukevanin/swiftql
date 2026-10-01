//
//  SQLObservingDatabaseDriver.swift
//  SwiftQLCore
//
//  The optional live-query refinement of the driver contract (issue #684).
//


/// A driver that can observe what a statement reads, and re-run a fetch on
/// its own connection whenever that changes (issue #684).
///
/// A live query needs two things the base ``XLDatabaseDriver`` contract does
/// not say: when the data a statement reads has changed, and where to run the
/// statement again. A driver that knows both conforms to this refinement.
/// SwiftQL's live-query members build on it, so an adapter supplies its own
/// change notification here and needs neither Combine nor any other
/// observation framework to support live queries.
///
/// Conforming is optional. A driver without its own change notification
/// conforms to ``XLDatabaseDriver`` alone, and its requests observe however
/// their adapter chooses.
public protocol XLObservingDatabaseDriver: XLDatabaseDriver {

    /// Observes `statement`, yielding what `fetch` returns now and after
    /// every committed change to the entities the statement reads.
    ///
    /// `fetch` prepares, binds, and runs the statement on the connection the
    /// driver lends it, exactly as an operation passed to a scope method
    /// does. The driver runs it once for the initial value, and again after
    /// each committed transaction that changes one of those entities. It does
    /// not run it for a change to any other entity, or for a change that
    /// rolls back. ``XLLogicalPreparedStatement/entities`` names the entities
    /// the statement reads. A driver that can work out that set more exactly
    /// from the database itself, for example one that also tracks the base
    /// tables of a view the statement selects from, may observe that set
    /// instead, as long as it covers every entity the statement names.
    ///
    /// The returned stream follows the same contract as a request's live
    /// query stream:
    ///
    /// - Observation begins with iteration. Constructing the stream does no
    ///   work, and only its first `next()` call starts observing.
    /// - Each call returns one independent, single-consumer observation.
    /// - The stream buffers at most one undelivered value. A newer value
    ///   replaces one the consumer has not yet asked for, and never queues
    ///   behind it.
    /// - When `fetch` throws, or the driver cannot observe, iteration throws
    ///   that error and the stream ends. A driver may retry a failure it
    ///   knows to be transient before reporting it.
    /// - Cancelling the consuming task ends iteration with `nil`, never a
    ///   thrown error, and stops the observation, so `fetch` runs no more.
    ///
    /// A driver may run `fetch` more than once for one change, and so yield
    /// an equal value twice. The consumer compares values itself when it
    /// needs distinct ones.
    ///
    /// - Parameters:
    ///   - statement: The statement `fetch` runs. The driver observes the
    ///     entities it reads.
    ///   - fetch: Runs the statement on a connection the driver lends, and
    ///     returns the value to yield. It is `@Sendable` because the driver
    ///     may run it on its own executor.
    /// - Returns: A lazily started stream of fetched values.
    func observe<Value: Sendable>(
        _ statement: XLLogicalPreparedStatement,
        fetch: @escaping @Sendable (inout Connection) throws -> Value
    ) -> AsyncThrowingStream<Value, Error>
}
