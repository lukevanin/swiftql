//
//  SQLConnection.swift
//  LINQTest (iOS)
//
//  Created by Luke Van In on 2022/05/11.
//

import Foundation
import SQLite3

let SQLITE_STATIC = unsafeBitCast(0, to: sqlite3_destructor_type.self)
let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)


enum SQLSuccess {
    case ok
    case row
    case done
}


protocol SQLBindingProtocol {
    func bind(variable: Int, value: Int) throws
    func bind(variable: Int, value: Double) throws
    func bind<T>(variable: Int, value: T) throws where T: StringProtocol
    func bind<T>(variable: Int, value: T) throws where T: DataProtocol
}


protocol SQLRowProtocol {
    func readInt(column: Int) -> Int
    func readDouble(column: Int) -> Double
    func readString(column: Int) -> String
    func readData(column: Int) -> Data
}

protocol SQLPreparedStatementProtocol {
    func sql() -> String
    func execute(bind: (SQLBindingProtocol) throws -> Void, read: (SQLRowProtocol) -> Void) throws -> Void
}


protocol SQLProviderProtocol {
    
    func prepare(sql: String) throws -> SQLPreparedStatementProtocol
    func perform(block: () -> Int32) throws -> SQLSuccess
}


enum SQLite {

    enum ResourceError: Error {
        case cannotOpenFile
    }


    struct ConnectionError: Error {
        let code: Int
        let message: String
        let errorCode: Int
        let extendedErrorCode: Int
        let errorCodeMessage: String
        let extendedErrorCodeMessage: String
    }
    
    
    struct QueryError: Error {
        let underlyingError: Error
        let sql: String
    }
    
    
    struct BindingError: Error {
        let underlyingError: Error
        let index: Int
        let kind: String
    }
    
    
    class Row: SQLRowProtocol {
        
        private let handle: OpaquePointer
        
        init(handle: OpaquePointer) {
            self.handle = handle
        }
        
        func readInt(column: Int) -> Int {
            Int(sqlite3_column_int64(handle, Int32(column)))
        }
        
        func readDouble(column: Int) -> Double {
            sqlite3_column_double(handle, Int32(column))
        }
        
        func readString(column: Int) -> String {
            let buffer = sqlite3_column_text(handle, Int32(column))
            return String(cString: buffer!)
        }
        
        func readData(column: Int) -> Data {
            let buffer = sqlite3_column_blob(handle, Int32(column))
            let count = sqlite3_column_bytes(handle, Int32(column))
            return Data(bytes: buffer!, count: Int(count))
        }
    }
    
    
    class PreparedStatement: SQLPreparedStatementProtocol, SQLBindingProtocol {
        

        fileprivate let handle: OpaquePointer
        fileprivate let connection: Connection
        private let rawSQL: String

        init(handle: OpaquePointer, sql: String, connection: Connection) {
            self.rawSQL = sql
            self.handle = handle
            self.connection = connection
        }
        
        func sql() -> String {
            return rawSQL
        }

        func bind(variable: Int, value: Int) throws {
            try performBinding(Int.self, index: variable) {
                sqlite3_bind_int64(handle, Int32(variable), Int64(value))
            }
        }

        func bind(variable: Int, value: Double) throws {
            try performBinding(Double.self, index: variable) {
                sqlite3_bind_double(handle, Int32(variable), value)
            }
        }

        func bind<T>(variable: Int, value: T) throws where T: StringProtocol {
            var buffer = value.cString(using: .utf8) ?? []
            try performBinding(T.self, index: variable) {
                sqlite3_bind_text(handle, Int32(variable), &buffer, Int32(buffer.count), SQLITE_TRANSIENT)
            }
        }
        
        func bind<T>(variable: Int, value: T) throws where T: DataProtocol {
            let _ = try value.withContiguousStorageIfAvailable { buffer in
                try performBinding(T.self, index: variable) {
                    sqlite3_bind_blob(handle, Int32(variable), buffer.baseAddress, Int32(buffer.count), SQLITE_TRANSIENT)
                }
            }
        }
        
        private func performBinding<I>(_ kind: I.Type, index: Int, block: () throws -> Void) throws -> Void {
            do {
                try block()
            }
            catch {
                throw BindingError(underlyingError: error, index: index, kind: String(describing: I.self))
            }
        }
        
        func execute(bind: (SQLBindingProtocol) throws -> Void, read: (SQLRowProtocol) -> Void) throws -> Void {
            defer {
                try! connection.perform {
                    sqlite3_reset(handle)
                }
            }
            let row = Row(handle: handle)
            do {
                try connection.perform {
                    sqlite3_clear_bindings(handle)
                }
                try bind(self)
                while true {
                    let result = try connection.perform() {
                        sqlite3_step(handle)
                    }
                    if result != .row {
                        break
                    }
                    read(row)
                }
            }
            catch {
                throw QueryError(underlyingError: error, sql: sql())
            }
        }
    }


    struct Resource {
        
        let fileURL: URL
        
        func connect() throws -> Connection {
            let filename = fileURL.path.cString(using: .utf8)
            var handle: OpaquePointer!
            let result = sqlite3_open(filename, &handle)
            guard result == SQLITE_OK else {
                throw ResourceError.cannotOpenFile
            }
            return Connection(db: handle)
        }
    }


    class Connection: SQLProviderProtocol {
        
        fileprivate let db: OpaquePointer
            
        init(db: OpaquePointer) {
            self.db = db
        }
        
        func prepare(sql: String) throws -> SQLPreparedStatementProtocol {
            var sqlCString = sql.cString(using: .utf8)!
            var handle: OpaquePointer!
            do {
                try perform() {
                    sqlite3_prepare_v2(db, &sqlCString, Int32(sqlCString.count), &handle, nil)
                }
            }
            catch {
                throw QueryError(underlyingError: error, sql: sql)
            }
            return PreparedStatement(handle: handle, sql: sql, connection: self)
        }
        
        @discardableResult func perform(block: () -> Int32) throws -> SQLSuccess {
            let result = block()
            if result == SQLITE_OK {
                return .ok
            }
            if result == SQLITE_DONE {
                return .done
            }
            if result == SQLITE_ROW {
                return .row
            }
            let message = String(cString: sqlite3_errmsg(db))
            let errorCode = sqlite3_errcode(db)
            let extendedErrorCode = sqlite3_extended_errcode(db)
            let errorCodeMessage = sqlite3_errstr(errorCode)!
            let extendedErrorCodeMessage = sqlite3_errstr(extendedErrorCode)!
            throw ConnectionError(
                code: Int(result),
                message: message,
                errorCode: Int(errorCode),
                extendedErrorCode: Int(extendedErrorCode),
                errorCodeMessage: String(cString: errorCodeMessage),
                extendedErrorCodeMessage: String(cString: extendedErrorCodeMessage)
            )
        }
        
        
        /*
         /// https://sqlite.org/rescode.html
        ** CAPI3REF: Result Codes
        ** KEYWORDS: {result code definitions}
        **
        ** Many SQLite functions return an integer result code from the set shown
        ** here in order to indicate success or failure.
        **
        ** New error codes may be added in future versions of SQLite.
        **
        ** See also: [extended result code definitions]
        */
        /*
        public var SQLITE_OK: Int32 { get } /* Successful result */
        /* beginning-of-error-codes */
        public var SQLITE_ERROR: Int32 { get } /* Generic error */
        public var SQLITE_INTERNAL: Int32 { get } /* Internal logic error in SQLite */
        public var SQLITE_PERM: Int32 { get } /* Access permission denied */
        public var SQLITE_ABORT: Int32 { get } /* Callback routine requested an abort */
        public var SQLITE_BUSY: Int32 { get } /* The database file is locked */
        public var SQLITE_LOCKED: Int32 { get } /* A table in the database is locked */
        public var SQLITE_NOMEM: Int32 { get } /* A malloc() failed */
        public var SQLITE_READONLY: Int32 { get } /* Attempt to write a readonly database */
        public var SQLITE_INTERRUPT: Int32 { get } /* Operation terminated by sqlite3_interrupt()*/
        public var SQLITE_IOERR: Int32 { get } /* Some kind of disk I/O error occurred */
        public var SQLITE_CORRUPT: Int32 { get } /* The database disk image is malformed */
        public var SQLITE_NOTFOUND: Int32 { get } /* Unknown opcode in sqlite3_file_control() */
        public var SQLITE_FULL: Int32 { get } /* Insertion failed because database is full */
        public var SQLITE_CANTOPEN: Int32 { get } /* Unable to open the database file */
        public var SQLITE_PROTOCOL: Int32 { get } /* Database lock protocol error */
        public var SQLITE_EMPTY: Int32 { get } /* Internal use only */
        public var SQLITE_SCHEMA: Int32 { get } /* The database schema changed */
        public var SQLITE_TOOBIG: Int32 { get } /* String or BLOB exceeds size limit */
        public var SQLITE_CONSTRAINT: Int32 { get } /* Abort due to constraint violation */
        public var SQLITE_MISMATCH: Int32 { get } /* Data type mismatch */
        public var SQLITE_MISUSE: Int32 { get } /* Library used incorrectly */
        public var SQLITE_NOLFS: Int32 { get } /* Uses OS features not supported on host */
        public var SQLITE_AUTH: Int32 { get } /* Authorization denied */
        public var SQLITE_FORMAT: Int32 { get } /* Not used */
        public var SQLITE_RANGE: Int32 { get } /* 2nd parameter to sqlite3_bind out of range */
        public var SQLITE_NOTADB: Int32 { get } /* File opened that is not a database file */
        public var SQLITE_NOTICE: Int32 { get } /* Notifications from sqlite3_log() */
        public var SQLITE_WARNING: Int32 { get } /* Warnings from sqlite3_log() */
        public var SQLITE_ROW: Int32 { get } /* sqlite3_step() has another row ready */
        public var SQLITE_DONE: Int32 { get } /* sqlite3_step() has finished executing */
        /* end-of-error-codes */
        */
    }
}
