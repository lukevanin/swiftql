import SwiftUI

import TodoKit

@main
struct TodoAppApp: App {

    @State private var store = TodoStoreEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView(store: store)
        }
        #if os(macOS)
        .defaultSize(width: 900, height: 600)
        #endif
    }
}

/// Opens the database once for the whole app.
@Observable
@MainActor
final class TodoStoreEnvironment {

    enum State {
        case opening
        case ready(TodoDatabase)
        case failed(String)
    }

    private(set) var state = State.opening

    func open() async {
        guard case .opening = state else {
            return
        }
        do {
            state = .ready(try await TodoDatabaseLoader.applicationDatabase())
        }
        catch {
            state = .failed(String(describing: error))
        }
    }
}
