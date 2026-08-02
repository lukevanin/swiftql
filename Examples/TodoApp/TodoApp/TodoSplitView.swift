import SwiftUI

import TodoKit

/// Sidebar of lists, to-dos for the selected one, and a detail pane.
///
/// One source per pane, and every one of them a live query. Nothing here
/// reloads after a write.
struct TodoSplitView: View {

    let database: TodoDatabase

    @State private var sidebar: TodoSidebarModel
    @State private var selectedListID: TodoUUID?
    @State private var selectedTodoID: TodoUUID?

    init(database: TodoDatabase) {
        self.database = database
        _sidebar = State(initialValue: TodoSidebarModel(database: database))
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(model: sidebar, selection: $selectedListID)
        } content: {
            if let selectedListID {
                TodoListPane(
                    database: database,
                    listID: selectedListID,
                    selection: $selectedTodoID
                )
                // A new list is a new observation, not a filter applied to
                // the old one, so the pane is rebuilt rather than mutated.
                .id(selectedListID)
            }
            else {
                ContentUnavailableView(
                    "No list selected",
                    systemImage: "sidebar.left"
                )
            }
        } detail: {
            if let selectedTodoID {
                TodoDetailPane(database: database, todoID: selectedTodoID)
                    .id(selectedTodoID)
            }
            else {
                ContentUnavailableView(
                    "No to-do selected",
                    systemImage: "checklist"
                )
            }
        }
        .onAppear {
            if selectedListID == nil {
                selectedListID = sidebar.lists.rows.first?.id
            }
        }
        .onChange(of: sidebar.lists.rows.count) {
            if selectedListID == nil {
                selectedListID = sidebar.lists.rows.first?.id
            }
        }
    }
}

/// Lists, with live open and total counts.
private struct SidebarView: View {

    let model: TodoSidebarModel

    @Binding var selection: TodoUUID?

    var body: some View {
        List(model.lists.rows, id: \.id, selection: $selection) { list in
            HStack {
                Text(list.name)
                Spacer()
                // These numbers come from the counts observation, not from
                // counting the rows the other pane happens to be showing.
                Text("\(model.counts(for: list.id).openCount)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Text("/ \(model.counts(for: list.id).totalCount)")
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
            .tag(list.id)
        }
        .navigationTitle("Lists")
        .overlay {
            if model.lists.isLoading {
                ProgressView()
            }
        }
    }
}
