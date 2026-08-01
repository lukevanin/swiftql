import SwiftUI

import TodoKit

/// The placeholder. It opens the durable database, seeding it on first
/// launch, and reports what the schema holds. The real interface replaces it.
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

            #if DEBUG
            Button("Reset to seeded state") {
                Task { await reset() }
            }
            .padding(.top, 8)
            #endif
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await open() }
    }

    private func open() async {
        do {
            status = .opened(try await TodoLaunchCheck.run())
        }
        catch {
            status = .failed(String(describing: error))
        }
    }

    #if DEBUG
    private func reset() async {
        do {
            status = .opened(try await TodoLaunchCheck.resetAndRun())
        }
        catch {
            status = .failed(String(describing: error))
        }
    }
    #endif
}

private enum Status: Sendable {

    case opening
    case opened(TodoLaunchSummary)
    case failed(String)

    var message: String {
        switch self {
        case .opening:
            return "Opening the database…"
        case .opened(let summary):
            let opening = summary.didSeed
                ? "Created and seeded the database."
                : "Opened the existing database."
            return """
                \(opening)
                \(summary.listCount) lists, \(summary.todoCount) to-dos, \
                \(summary.tagCount) tags.
                """
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
