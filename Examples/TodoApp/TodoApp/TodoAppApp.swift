import SwiftUI

@main
struct TodoAppApp: App {

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS)
        .defaultSize(width: 420, height: 320)
        #endif
    }
}
