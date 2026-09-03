import SwiftUI

import TodoKit

/// One list's to-dos, with the filter, sort, and search bound to the query.
///
/// Changing any control rebinds the live query. Nothing is filtered, sorted,
/// or searched in Swift.
struct TodoListPane: View {

    let database: TodoDatabase

    @Binding var selection: TodoUUID?

    @State private var model: TodoListModel?
    @State private var failure: String?
    @State private var writeFailure: String?

    private let listID: TodoUUID

    init(database: TodoDatabase, listID: TodoUUID, selection: Binding<TodoUUID?>) {
        self.database = database
        self.listID = listID
        _selection = selection
    }

    var body: some View {
        Group {
            if let model {
                content(model)
            }
            else if let failure {
                ContentUnavailableView(
                    "Could not open the list",
                    systemImage: "exclamationmark.triangle",
                    description: Text(failure)
                )
            }
            else {
                ProgressView()
            }
        }
        .onAppear(perform: start)
        .onDisappear {
            // Clearing the model as well as stopping it is what lets the
            // observation restart if this view comes back. Keeping a stopped
            // one would leave the pane permanently frozen.
            model?.stop()
            model = nil
            // Clear the failure too, so a later appearance tries again
            // rather than rendering a stale error before start() runs.
            failure = nil
        }
    }

    private func start() {
        guard model == nil else {
            return
        }
        do {
            model = try TodoListModel(
                database: database,
                query: TodoQuery(listID: listID)
            )
        }
        catch {
            failure = String(describing: error)
        }
    }

    @ViewBuilder
    private func content(_ model: TodoListModel) -> some View {
        List(model.todos.rows, id: \.id, selection: $selection) { todo in
            TodoRow(
                todo: todo,
                tags: model.tags(for: todo),
                checklistItemCount: model.checklistItemCount(for: todo),
                hasLink: model.hasLink(todo)
            ) {
                toggle(todo)
            }
            .tag(todo.id)
        }
        .searchable(
            text: Binding(
                get: { model.searchText },
                set: { model.searchText = $0 }
            ),
            prompt: "Title or notes"
        )
        .navigationTitle("To-dos")
        .toolbar {
            ToolbarItem {
                Picker(
                    "Filter",
                    selection: Binding(
                        get: { model.filter },
                        set: { model.filter = $0 }
                    )
                ) {
                    ForEach(TodoFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue.capitalized).tag(filter)
                    }
                }
            }
            ToolbarItem {
                Picker(
                    "Sort",
                    selection: Binding(
                        get: { model.sort },
                        set: { model.sort = $0 }
                    )
                ) {
                    Text("Manual").tag(TodoSort.manual)
                    Text("Due date").tag(TodoSort.dueDate)
                    Text("Priority").tag(TodoSort.priority)
                }
            }
            ToolbarItem {
                Button {
                    add()
                } label: {
                    Label("New to-do", systemImage: "plus")
                }
            }
        }
        .alert(
            "The write failed",
            isPresented: Binding(
                get: { writeFailure != nil },
                set: { if !$0 { writeFailure = nil } }
            ),
            presenting: writeFailure
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { description in
            Text(description)
        }
        .overlay {
            if model.todos.rows.isEmpty, !model.todos.isLoading {
                ContentUnavailableView(
                    "Nothing here",
                    systemImage: "checkmark.circle",
                    description: Text("No to-do matches this filter.")
                )
            }
        }
    }

    /// A write, and then nothing. The list, the sidebar counts, and the
    /// detail pane all update from their own observations of this commit.
    private func toggle(_ todo: Todo) {
        write { try database.toggleCompleted(todoID: todo.id) }
    }

    private func add() {
        // No reloadRowDetails() here: a new to-do has no tags and no
        // sub-tasks yet, and the rows themselves arrive through the live
        // query.
        write { try database.createTodo(listID: listID, title: "New to-do") }
    }

    /// Runs a write and surfaces anything it throws.
    ///
    /// A demo that swallows write errors teaches the wrong habit, and a
    /// silent no-op is the hardest kind of failure to notice in a UI that
    /// otherwise updates itself.
    private func write(_ operation: () throws -> Void) {
        do {
            try operation()
        }
        catch {
            writeFailure = error.localizedDescription
        }
    }
}

private struct TodoRow: View {

    let todo: Todo
    let tags: [Tag]
    let checklistItemCount: Int

    /// Whether the note holds a web link, as SQLite decided with the compiled
    /// `Regex` in `TodoLinks.pattern`.
    let hasLink: Bool

    let toggle: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button(action: toggle) {
                Image(
                    systemName: todo.isCompleted
                        ? "checkmark.circle.fill"
                        : "circle"
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(todo.isCompleted ? "Mark as open" : "Complete")

            VStack(alignment: .leading, spacing: 2) {
                Text(todo.title)
                    .strikethrough(todo.isCompleted)
                if !tags.isEmpty {
                    Text(tags.map(\.name).joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if hasLink {
                Image(systemName: "link")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Notes contain a link")
            }

            if checklistItemCount > 0 {
                Label("\(checklistItemCount)", systemImage: "checklist")
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(
                        checklistItemCount == 1
                            ? "1 sub-task"
                            : "\(checklistItemCount) sub-tasks"
                    )
            }

            if let dueAt = todo.dueAt {
                Text(dueAt.wrappedValue, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
