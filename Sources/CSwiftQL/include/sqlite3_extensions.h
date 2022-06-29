#ifndef sqlite3_extensions_h
#define sqlite3_extensions_h

#include <sqlite3.h>

typedef void(*errorLogCallback)(void *pArg, int iErrCode, const char *zMsg);

///
/// Wrapper around sqlite3_config(SQLITE_CONFIG_LOG, ...) which is a variadic
/// function that can't be used from Swift.
///
/// See: https://github.com/groue/GRDB.swift/blob/master/Support/grdb_config.h
///
static inline void registerErrorLogCallback(errorLogCallback callback) {
    sqlite3_config(SQLITE_CONFIG_LOG, callback, 0);
}

#endif
