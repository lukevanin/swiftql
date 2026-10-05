//
//  BlockingTaskSupport.swift
//  SwiftQLTestSupport
//
//  Running synchronous scope bodies on a dispatch thread, and blocking such a
//  body while a task created in it runs, for tests of what a task may do
//  while a scope is still open.
//

import Foundation


/// Runs `body` on a dispatch thread, outside any task, and resumes with its
/// result.
///
/// A test that blocks inside `body` -- for example while a task it created
/// runs -- blocks a dispatch thread rather than one of the cooperative pool's
/// threads, so it cannot starve the task it waits for.
public func onDispatchThread<Result: Sendable>(
    _ body: @escaping @Sendable () throws -> Result
) async throws -> Result {
    try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global().async {
            continuation.resume(with: Swift.Result { try body() })
        }
    }
}


/// Runs `operation` in a detached task and blocks the calling thread until it
/// finishes, so a scope body can hand work to another thread and still be
/// running when it does.
///
/// Call it from a dispatch thread, such as inside ``onDispatchThread(_:)``,
/// not from a task, so the blocked thread is not one the task needs.
///
/// - Throws: ``TaskTimedOut`` when `operation` has not finished after ten
///   seconds.
public func resultOfTaskBlockingThisThread<Result: Sendable>(
    _ operation: @escaping @Sendable () async -> Result
) throws -> Result {
    let finished = DispatchSemaphore(value: 0)
    let result = LockedValue<Result?>(nil)
    Task.detached {
        let value = await operation()
        result.withValue { $0 = value }
        finished.signal()
    }
    guard finished.wait(timeout: .now() + 10) == .success, let value = result.read() else {
        throw TaskTimedOut()
    }
    return value
}


/// A task a test waited for did not finish in time.
public struct TaskTimedOut: Error {

    public init() {}
}
