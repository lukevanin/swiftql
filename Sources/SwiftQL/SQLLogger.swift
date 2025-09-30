/**
 * © 2019 - 2023 SEG Solutions
 *
 * NOTICE: All information contained herein is, and remains
 * the property of SEG Solutions and its suppliers,
 * if any.  The intellectual and technical concepts contained
 * herein are proprietary to SEG Solutions and its suppliers.
 * Dissemination of this information or reproduction of this material
 * is strictly forbidden unless prior written permission is obtained
 * from SEG Solutions.
 */

import Foundation


public enum XLLogLevel {
    case information
    case debug
    case warning
    case error
}


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
