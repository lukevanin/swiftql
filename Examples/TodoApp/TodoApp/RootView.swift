import SwiftUI

import TodoKit

/// Waits for the database, then hands it to the interface.
struct RootView: View {

    let store: TodoStoreEnvironment

    var body: some View {
        Group {
            switch store.state {
            case .opening:
                ProgressView("Opening the database…")
            case .ready(let database):
                TodoSplitView(database: database)
            case .failed(let description):
                ContentUnavailableView(
                    "Could not open the database",
                    systemImage: "exclamationmark.triangle",
                    description: Text(description)
                )
            }
        }
        .task { await store.open() }
    }
}
