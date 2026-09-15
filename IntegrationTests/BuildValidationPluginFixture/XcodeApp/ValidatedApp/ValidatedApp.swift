// A minimal macOS application target whose only purpose is to adopt
// SwiftQLSQLiteBuildValidationPlugin from an Xcode project rather than from a
// SwiftPM target (#666). Its manifest, snapshot, and plan-analysis opt-in are
// members of the target, in this folder. verify-xcode.sh builds it.
import SwiftUI

@main
struct ValidatedApp: App {
    var body: some Scene {
        WindowGroup {
            Text("SwiftQL build validation fixture")
        }
    }
}
