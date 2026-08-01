import SwiftUI

import TodoKit

/// The scaffold's placeholder. It opens a database, writes a row, reads it
/// back through a declared query, and reports what happened.
struct ContentView: View {

    @State private var status = Status.opening

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checklist")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("SwiftQL to-do demo")
                .font(.title2.weight(.semibold))
            Text(status.message)
                .font(.callout)
                .foregroundStyle(status.isFailure ? .red : .secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { status = await Self.open() }
    }

    /// SwiftQL's request methods are synchronous, so the database work runs
    /// off the main actor and only the resulting status crosses back. Live
    /// queries replace this hand-rolled hop.
    private static func open() async -> Status {
        await Task.detached {
            do {
                let database = try TodoDatabase.ephemeral()
                try database.insertProbe()
                return .connected(rows: try database.launchProbeCount())
            }
            catch {
                return .failed(String(describing: error))
            }
        }
        .value
    }
}

private enum Status: Sendable {

    case opening
    case connected(rows: Int)
    case failed(String)

    var message: String {
        switch self {
        case .opening:
            return "Opening the database…"
        case .connected(let rows):
            return "Connected. A declared query read back \(rows) row(s)."
        case .failed(let description):
            return "Could not open the database.\n\(description)"
        }
    }

    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}

#Preview {
    ContentView()
}
