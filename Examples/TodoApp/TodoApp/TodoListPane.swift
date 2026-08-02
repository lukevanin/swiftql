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
            TodoRow(todo: todo, tags: model.tags(for: todo)) {
                toggle(todo, in: model)
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
                    add(to: model)
                } label: {
                    Label("New to-do", systemImage: "plus")
                }
            }
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
    private func toggle(_ todo: Todo, in model: TodoListModel) {
        _ = try? database.toggleCompleted(todoID: todo.id)
    }

    private func add(to model: TodoListModel) {
        _ = try? database.createTodo(listID: listID, title: "New to-do")
        model.reloadTags()
    }
}

private struct TodoRow: View {

    let todo: Todo
    let tags: [Tag]
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

            if let dueAt = todo.dueAt {
                Text(dueAt.wrappedValue, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
