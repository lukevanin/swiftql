import SwiftUI

import TodoKit

/// One to-do, observed by identifier.
///
/// Completing it here writes and stops. The row this view shows, the row in
/// the list, and the sidebar counts are three separate observations of the
/// same commit, so all three update without anything asking them to.
struct TodoDetailPane: View {

    let database: TodoDatabase
    let todoID: TodoUUID

    @State private var model: TodoDetailModel?
    @State private var failure: String?
    @State private var writeFailure: String?

    @State private var title = ""
    @State private var notes = ""
    @State private var priority = TodoPriority.normal
    @State private var hasDueDate = false
    @State private var dueDate = Date()
    @State private var isEditing = false

    var body: some View {
        Group {
            if let model, let todo = model.todo.row {
                form(model: model, todo: todo)
            }
            else if let failure {
                ContentUnavailableView(
                    "Could not open the to-do",
                    systemImage: "exclamationmark.triangle",
                    description: Text(failure)
                )
            }
            else if model?.todo.isLoading == false {
                ContentUnavailableView(
                    "This to-do is gone",
                    systemImage: "trash"
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
            isEditing = false
        }
    }

    private func start() {
        guard model == nil else {
            return
        }
        do {
            model = try TodoDetailModel(database: database, todoID: todoID)
        }
        catch {
            failure = String(describing: error)
        }
    }

    @ViewBuilder
    private func form(model: TodoDetailModel, todo: Todo) -> some View {
        Form {
            Section {
                if isEditing {
                    TextField("Title", text: $title)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...)
                }
                else {
                    Text(todo.title)
                        .font(.headline)
                    if !todo.notes.isEmpty {
                        Text(todo.notes)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Due") {
                if isEditing {
                    Toggle("Has a due date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Due", selection: $dueDate)
                    }
                }
                else {
                    Text(
                        todo.dueAt.map {
                            $0.wrappedValue.formatted(date: .abbreviated, time: .shortened)
                        } ?? "No due date"
                    )
                }
            }

            Section("Priority") {
                if isEditing {
                    Picker("Priority", selection: $priority) {
                        Text("Low").tag(TodoPriority.low)
                        Text("Normal").tag(TodoPriority.normal)
                        Text("High").tag(TodoPriority.high)
                    }
                    .pickerStyle(.segmented)
                }
                else {
                    Text(name(of: todo.priority))
                }
            }

            if !model.tags.isEmpty {
                Section("Tags") {
                    Text(model.tags.map(\.name).joined(separator: " · "))
                }
            }

            Section {
                Toggle(
                    "Completed",
                    isOn: Binding(
                        get: { todo.isCompleted },
                        set: { isCompleted in
                            write {
                                try database.setCompleted(
                                    isCompleted,
                                    todoID: todo.id
                                )
                            }
                        }
                    )
                )
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
        .formStyle(.grouped)
        .navigationTitle(todo.title)
        .toolbar {
            ToolbarItem {
                Button(isEditing ? "Save" : "Edit") {
                    if isEditing {
                        save(todo)
                    }
                    else {
                        load(todo)
                    }
                    isEditing.toggle()
                }
            }
        }
    }

    private func load(_ todo: Todo) {
        title = todo.title
        notes = todo.notes
        priority = todo.priority
        hasDueDate = todo.dueAt != nil
        dueDate = todo.dueAt?.wrappedValue ?? Date()
    }

    private func save(_ todo: Todo) {
        write {
            try database.updateTodo(
                id: todo.id,
                title: title,
                notes: notes,
                dueAt: hasDueDate ? TodoDate(dueDate) : nil,
                priority: priority
            )
        }
    }

    /// Runs a write and surfaces anything it throws, rather than leaving a
    /// failed save looking like a successful one.
    private func write(_ operation: () throws -> Void) {
        do {
            try operation()
        }
        catch {
            writeFailure = error.localizedDescription
        }
    }

    private func name(of priority: TodoPriority) -> String {
        switch priority {
        case .low: return "Low"
        case .normal: return "Normal"
        case .high: return "High"
        }
    }
}
