//
//  XLLogger.swift
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
public protocol XLLogger {
    
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
