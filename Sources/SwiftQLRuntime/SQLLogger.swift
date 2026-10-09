//
//  SQLLogger.swift
//

import Foundation


///
/// Logging level using by XLLogger.
///
public enum XLLogLevel {
    case information
    case debug
    case warning
    case error
}


///
/// Logs SwiftQL events.
///
/// A logger is `Sendable` because SwiftQL writes to it from whichever thread
/// runs the statement. A pooled reader connection, a live-query observation,
/// and the calling thread can all log at the same time. An implementation must
/// therefore be safe for concurrent use.
///
public protocol XLLogger: Sendable {
    
    func log(level: XLLogLevel, message: String)
}

extension XLLogger {
    
    public func information(_ message: String) {
        log(level: .information, message: message)
    }

    public func debug(_ message: String) {
        log(level: .debug, message: message)
    }
    
    public func warning(_ message: String) {
        log(level: .warning, message: message)
    }
    
    public func error(_ message: String) {
        log(level: .error, message: message)
    }
}
