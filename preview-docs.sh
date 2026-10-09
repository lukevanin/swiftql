#!/bin/sh

# Previews one module's documentation: SwiftQL by default, or the module named
# as the argument, such as SwiftQLSQLite. The plugin previews one target at a
# time; make-docs.sh builds the combined site (issue #790).
swift package --disable-sandbox preview-documentation --target "${1:-SwiftQL}"
