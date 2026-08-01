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
        .onAppear(perform: open)
    }

    private func open() {
        do {
            let database = try TodoDatabase.ephemeral()
            try database.insertProbe()
            status = .connected(rows: try database.launchProbeCount())
        }
        catch {
            status = .failed(String(describing: error))
        }
    }
}

private enum Status {

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
